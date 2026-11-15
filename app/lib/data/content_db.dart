/// Read-only access to content.db, the database the pipeline builds. Nothing here writes.
library;

import 'package:sqlite3/sqlite3.dart';

import '../engine/annotator.dart';
import '../engine/planner.dart';

class TokenRow {
  const TokenRow(
    this.surface,
    this.kind,
    this.reading,
    this.itemId,
    this.flagged,
  );
  final String surface;
  final String kind;
  final String? reading;
  final String? itemId;
  final bool flagged;
}

class SentenceRow {
  const SentenceRow({
    required this.id,
    required this.pairId,
    required this.lang,
    required this.text,
    required this.en,
    required this.register,
    required this.region,
    required this.notes,
    required this.reviewed,
    required this.tokens,
    this.pattern,
    this.dialogue,
    this.speaker,
    this.turn,
    this.words = const [],
  });

  final String id;
  final String pairId;
  final String lang;
  final String text;
  final String en;
  final String register;
  final String region;
  final String notes;
  final bool reviewed;
  final List<TokenRow> tokens;
  final String? pattern;

  /// Set on conversation lines.
  final String? dialogue;
  final String? speaker;
  final int? turn;

  /// Multi-character words as (first token index, token count), from the pipeline's
  /// context segmentation checked against the dictionary.
  final List<(int, int)> words;

  /// Word number for each token: tokens of one word share it (for underlining).
  List<int> get wordOf {
    final out = List<int>.generate(tokens.length, (i) => i);
    for (final (start, len) in words) {
      for (var k = start; k < start + len && k < out.length; k++) {
        out[k] = start;
      }
    }
    return out;
  }

  /// The token range (start, end) of the word containing token [i].
  (int, int) wordRange(int i) {
    for (final (start, len) in words) {
      if (i >= start && i < start + len) return (start, start + len);
    }
    return (i, i + 1);
  }

  Set<String> get itemIds => {
    for (final t in tokens)
      if (t.itemId != null) t.itemId!,
  };

  Candidate toCandidate() =>
      Candidate(id: id, itemIds: itemIds, region: region, pattern: pattern);
}

/// A phonetic component and the characters built on it.
class SoundFamily {
  const SoundFamily(this.component, this.reading, this.members);
  final String component;
  final String reading;
  final List<({String char, String reading})> members;
}

class DialogueRow {
  const DialogueRow(
    this.id,
    this.title,
    this.lines, {
    this.level = 0,
    this.pair,
  });
  final String id;
  final String title;
  final int lines;

  /// Stories only.
  final int level;
  final String? pair;
}

class ScenarioRow {
  const ScenarioRow(this.id, this.title, this.region, this.sentenceCount);
  final String id;
  final String title;
  final String region;
  final int sentenceCount;
}

class DictEntry {
  const DictEntry({
    required this.trad,
    required this.simp,
    required this.pinyin,
    required this.jyutping,
    required this.en,
    required this.source,
  });
  final String trad;
  final String simp;

  /// Numbered Pinyin / Jyutping, space separated ('jyutping' may be empty).
  final String pinyin;
  final String jyutping;
  final String en;

  /// cccanto | cedict
  final String source;
}

class ContentDb {
  ContentDb.open(String path)
    : _db = sqlite3.open(path, mode: OpenMode.readOnly);

  final Database _db;

  void close() => _db.close();

  String meta(String key) {
    final rows = _db.select('SELECT value FROM meta WHERE key = ?', [key]);
    return rows.isEmpty ? '' : rows.first['value'] as String;
  }

  String get contentVersion => meta('content_version');

  /// Dictionary entries written exactly [text] (Traditional).
  /// Cantonese meanings (CC-Canto) come first. Empty on old databases.
  List<DictEntry> lookup(String text, String lang) {
    try {
      return [
        for (final r in _db.select(
          'SELECT trad, simp, pinyin, jyutping, en, source FROM dict_entry '
          "WHERE trad = ? ORDER BY source = 'cccanto' DESC, rowid LIMIT 8",
          [text],
        ))
          DictEntry(
            trad: r['trad'] as String,
            simp: r['simp'] as String,
            pinyin: r['pinyin'] as String,
            jyutping: r['jyutping'] as String,
            en: r['en'] as String,
            source: r['source'] as String,
          ),
      ];
    } on SqliteException {
      return const [];
    }
  }

  /// Dictionary words inside [text] that cover character [pos], longest first: tapping
  /// 銀 in 行路去銀行 offers 銀行 "bank" before 銀 "silver".
  List<({int start, int end, List<DictEntry> entries})> wordsAt(
    String text,
    int pos,
    String lang, {
    int maxLen = 6,
  }) {
    final out = <({int start, int end, List<DictEntry> entries})>[];
    for (var len = maxLen; len >= 1; len--) {
      for (var start = pos - len + 1; start <= pos; start++) {
        final end = start + len;
        if (start < 0 || end > text.length) continue;
        final w = text.substring(start, end);
        if (!_hanOnly.hasMatch(w)) continue;
        final e = lookup(w, lang);
        if (e.isNotEmpty) out.add((start: start, end: end, entries: e));
      }
    }
    return out;
  }

  List<ScenarioRow> scenarios(String lang) => [
    for (final r in _db.select(
      'SELECT s.id, s.title, s.region, '
      '(SELECT COUNT(*) FROM sentence x WHERE x.scenario_id = s.id AND x.lang = ? '
      'AND x.dialogue IS NULL) AS n '
      'FROM scenario s ORDER BY s.region = \'macau\' DESC, s.title',
      [lang],
    ))
      ScenarioRow(
        r['id'] as String,
        r['title'] as String,
        r['region'] as String,
        r['n'] as int,
      ),
  ];

  final Map<String, Annotator> _annotators = {};

  /// Reading lookup for arbitrary text (paste, OCR). Loaded once per language.
  Annotator annotator(String lang) => _annotators.putIfAbsent(lang, () {
    final chars = {
      for (final r in _db.select(
        'SELECT char, reading, n_readings FROM lex_char WHERE lang = ?',
        [lang],
      ))
        r['char'] as String: LexChar(
          r['reading'] as String,
          r['n_readings'] as int,
        ),
    };
    final words = {
      for (final r in _db.select(
        'SELECT word, reading FROM lex_word WHERE lang = ?',
        [lang],
      ))
        r['word'] as String: r['reading'] as String,
    };
    return Annotator(chars: chars, words: words);
  });

  Map<String, String>? _toTrad;

  /// Simplified -> traditional by character (Unihan), for recogniser output, which is
  /// written in simplified characters. Ambiguous mappings keep the first variant; the
  /// readings compared afterwards are what matter, not the exact character.
  String toTraditional(String text) {
    _toTrad ??= {
      for (final r in _db.select(
        "SELECT char, traditional FROM char_info WHERE traditional IS NOT NULL AND traditional != ''",
      ))
        r['char'] as String: String.fromCharCode(
          (r['traditional'] as String).runes.first,
        ),
    };
    return String.fromCharCodes(
      text.runes.expand((c) {
        final t = _toTrad![String.fromCharCode(c)];
        return t == null ? [c] : t.runes;
      }),
    );
  }

  /// Character-reading items per scenario, for progress bars.
  Map<String, Set<String>> charItemsByScenario(String lang) {
    final out = <String, Set<String>>{};
    for (final r in _db.select(
      'SELECT DISTINCT s.scenario_id, t.item_id FROM token t '
      'JOIN sentence s ON s.id = t.sentence_id '
      'WHERE s.lang = ? AND t.item_id IS NOT NULL',
      [lang],
    )) {
      out
          .putIfAbsent(r['scenario_id'] as String, () => {})
          .add(r['item_id'] as String);
    }
    return out;
  }

  /// Every sentence of a language, for mixed review sessions.
  /// Conversation lines are excluded: they are read in order, as conversations.
  List<SentenceRow> allSentences(String lang) =>
      _sentences('s.lang = ? AND s.dialogue IS NULL', [lang]);

  List<SentenceRow> sentences(String scenarioId, String lang) => _sentences(
    's.scenario_id = ? AND s.lang = ? AND s.dialogue IS NULL',
    [scenarioId, lang],
  );

  List<DialogueRow> dialogues(String scenarioId, String lang) => [
    for (final r in _db.select(
      'SELECT d.id, d.title, COUNT(s.id) AS n FROM dialogue d '
      'JOIN sentence s ON s.dialogue = d.id AND s.lang = ? '
      "WHERE d.scenario_id = ? AND d.kind = 'conversation' GROUP BY d.id ORDER BY d.id",
      [lang, scenarioId],
    ))
      DialogueRow(r['id'] as String, r['title'] as String, r['n'] as int),
  ];

  /// Sound families (characters sharing a phonetic component, from Make Me a Hanzi) that
  /// matter for this content: members that appear in the sentences, with their readings.
  List<SoundFamily> soundFamilies(String lang) {
    final reading = {
      for (final r in _db.select(
        'SELECT char, reading FROM lex_char WHERE lang = ?',
        [lang],
      ))
        r['char'] as String: r['reading'] as String,
    };
    final used = {
      for (final r in _db.select(
        "SELECT DISTINCT t.surface FROM token t JOIN sentence s ON s.id = t.sentence_id "
        "WHERE s.lang = ? AND t.kind = 'han'",
        [lang],
      ))
        r['surface'] as String,
    };
    final byComponent = <String, List<String>>{};
    for (final r in _db.select('SELECT component, member FROM family')) {
      final m = r['member'] as String;
      if (used.contains(m) && reading.containsKey(m)) {
        byComponent.putIfAbsent(r['component'] as String, () => []).add(m);
      }
    }
    return [
      for (final e in byComponent.entries)
        if (e.value.length >= 2 && reading.containsKey(e.key))
          SoundFamily(e.key, reading[e.key]!, [
            for (final m in e.value) (char: m, reading: reading[m]!),
          ]),
    ]..sort((a, b) => b.members.length.compareTo(a.members.length));
  }

  /// Sentences by id, in the order given (resuming a session).
  List<SentenceRow> sentencesByIds(List<String> ids) {
    if (ids.isEmpty) return const [];
    final marks = List.filled(ids.length, '?').join(',');
    final byId = {for (final s in _sentences('s.id IN ($marks)', ids)) s.id: s};
    return [for (final id in ids) ?byId[id]];
  }

  /// Graded stories in a language, easiest first.
  List<DialogueRow> stories(String lang) => [
    for (final r in _db.select(
      "SELECT id, title, lines, level, pair_id FROM dialogue WHERE kind = 'story' AND lang = ? "
      'ORDER BY level, id',
      [lang],
    ))
      DialogueRow(
        r['id'] as String,
        r['title'] as String,
        r['lines'] as int,
        level: r['level'] as int,
        pair: r['pair_id'] as String?,
      ),
  ];

  /// What the learner (你) says in the other conversations of a topic: plausible but
  /// wrong answers for the "what do you say?" choice.
  List<String> learnerLines(String scenarioId, {String? exceptDialogue}) => [
    for (final r in _db.select(
      "SELECT text FROM sentence WHERE scenario_id = ? AND speaker = '你' "
      'AND dialogue IS NOT NULL AND dialogue != ? ORDER BY id',
      [scenarioId, exceptDialogue ?? ''],
    ))
      r['text'] as String,
  ];

  /// The lines of one conversation, in speaking order.
  List<SentenceRow> dialogueLines(String dialogueId, String lang) =>
      _sentences('s.dialogue = ? AND s.lang = ?', [dialogueId, lang])
        ..sort((a, b) => (a.turn ?? 0).compareTo(b.turn ?? 0));

  List<SentenceRow> _sentences(String where, List<Object?> args) {
    final tokens = <String, List<TokenRow>>{};
    for (final r in _db.select(
      'SELECT t.sentence_id, t.surface, t.kind, t.reading, t.item_id, t.flagged '
      'FROM token t JOIN sentence s ON s.id = t.sentence_id '
      'WHERE $where ORDER BY t.sentence_id, t.idx',
      args,
    )) {
      tokens
          .putIfAbsent(r['sentence_id'] as String, () => [])
          .add(
            TokenRow(
              r['surface'] as String,
              r['kind'] as String,
              r['reading'] as String?,
              r['item_id'] as String?,
              (r['flagged'] as int) != 0,
            ),
          );
    }
    final words = <String, List<(int, int)>>{};
    for (final r in _db.select(
      'SELECT w.sentence_id, w.start_idx, w.length '
      'FROM sentence_word w JOIN sentence s ON s.id = w.sentence_id '
      'WHERE $where ORDER BY w.sentence_id, w.start_idx',
      args,
    )) {
      words.putIfAbsent(r['sentence_id'] as String, () => []).add((
        r['start_idx'] as int,
        r['length'] as int,
      ));
    }
    return [
      for (final r in _db.select(
        'SELECT s.id, s.pair_id, s.lang, s.text, s.en, s.register, s.region, s.notes, '
        's.reviewed, s.pattern, s.dialogue, s.speaker, s.turn '
        'FROM sentence s WHERE $where ORDER BY s.id',
        args,
      ))
        SentenceRow(
          id: r['id'] as String,
          pairId: r['pair_id'] as String,
          lang: r['lang'] as String,
          text: r['text'] as String,
          en: r['en'] as String,
          register: r['register'] as String,
          region: r['region'] as String,
          notes: r['notes'] as String,
          reviewed: (r['reviewed'] as int) != 0,
          tokens: tokens[r['id'] as String] ?? const [],
          pattern: r['pattern'] as String?,
          dialogue: r['dialogue'] as String?,
          speaker: r['speaker'] as String?,
          turn: r['turn'] as int?,
          words: words[r['id'] as String] ?? const [],
        ),
    ];
  }

  /// Asset-relative path of pre-generated audio, or null if none was built.
  String? audioPath(String lang, String text, {bool slow = false}) {
    final rows = _db.select(
      'SELECT path FROM audio WHERE lang = ? AND text = ? AND rate = ? ORDER BY voice LIMIT 1',
      [lang, text, slow ? 'slow' : 'normal'],
    );
    return rows.isEmpty ? null : rows.first['path'] as String;
  }
}

final _hanOnly = RegExp(r'^[㐀-鿿豈-﫿]+$');

class DeckRow {
  const DeckRow(this.id, this.title, this.region, this.description, this.count);
  final String id;
  final String title;
  final String region;
  final String description;
  final int count;
}

class CardRow {
  const CardRow({
    required this.id,
    required this.deckId,
    required this.zh,
    required this.alt,
    required this.note,
    required this.flagged,
    required this.tokens,
    this.image,
    this.credit = '',
  });
  final String id;
  final String deckId;

  /// Photo file in assets/cards/ (food deck), and its licence credit.
  final String? image;
  final String credit;
  final String zh;

  /// Portuguese (Macau) or English (Hong Kong) name, as on the sign.
  final String alt;
  final String note;
  final bool flagged;
  final List<TokenRow> tokens;

  List<String> get itemIds => [
    for (final t in tokens)
      if (t.itemId != null) t.itemId!,
  ];
}

extension DeckQueries on ContentDb {
  /// Flashcard decks of real names (OpenStreetMap); empty on older databases.
  List<DeckRow> decks() {
    try {
      return [
        for (final r in _db.select(
          'SELECT d.id, d.title, d.region, d.description, COUNT(c.id) AS n '
          'FROM deck d JOIN card c ON c.deck_id = d.id GROUP BY d.id '
          "ORDER BY d.id = 'food' DESC, d.region = 'macau' DESC, d.rowid",
        ))
          DeckRow(
            r['id'] as String,
            r['title'] as String,
            r['region'] as String,
            r['description'] as String,
            r['n'] as int,
          ),
      ];
    } on SqliteException {
      return const [];
    }
  }

  /// Cards of a deck in rank order (most important first).
  List<CardRow> cards(String deckId) {
    final tokens = <String, List<TokenRow>>{};
    for (final r in _db.select(
      'SELECT t.card_id, t.surface, t.kind, t.reading, t.item_id, t.flagged '
      'FROM card_token t JOIN card c ON c.id = t.card_id WHERE c.deck_id = ? '
      'ORDER BY t.card_id, t.idx',
      [deckId],
    )) {
      (tokens[r['card_id'] as String] ??= []).add(
        TokenRow(
          r['surface'] as String,
          r['kind'] as String,
          r['reading'] as String?,
          r['item_id'] as String?,
          (r['flagged'] as int) == 1,
        ),
      );
    }
    return [
      for (final r in _db.select(
        'SELECT id, zh, alt, note, flagged, image, credit FROM card '
        'WHERE deck_id = ? ORDER BY rank',
        [deckId],
      ))
        CardRow(
          id: r['id'] as String,
          deckId: deckId,
          zh: r['zh'] as String,
          alt: r['alt'] as String,
          note: r['note'] as String,
          flagged: (r['flagged'] as int) == 1,
          tokens: tokens[r['id'] as String] ?? const [],
          image: r['image'] as String?,
          credit: r['credit'] as String? ?? '',
        ),
    ];
  }

  /// "街 → Rua (122 of 123)": street-name endings and the word that goes with them,
  /// counted from the map data.
  List<({String zh, String word, int n, int total})> streetPatterns(
    String region,
  ) {
    try {
      return [
        for (final r in _db.select(
          'SELECT zh, word, n, total FROM street_pattern WHERE region = ? ORDER BY total DESC',
          [region],
        ))
          (
            zh: r['zh'] as String,
            word: r['word'] as String,
            n: r['n'] as int,
            total: r['total'] as int,
          ),
      ];
    } on SqliteException {
      return const [];
    }
  }
}
