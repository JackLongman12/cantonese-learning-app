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

  Set<String> get itemIds => {
    for (final t in tokens)
      if (t.itemId != null) t.itemId!,
  };

  Candidate toCandidate() =>
      Candidate(id: id, itemIds: itemIds, region: region, pattern: pattern);
}

class ScenarioRow {
  const ScenarioRow(this.id, this.title, this.region, this.sentenceCount);
  final String id;
  final String title;
  final String region;
  final int sentenceCount;
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

  List<ScenarioRow> scenarios(String lang) => [
    for (final r in _db.select(
      'SELECT s.id, s.title, s.region, '
      '(SELECT COUNT(*) FROM sentence x WHERE x.scenario_id = s.id AND x.lang = ?) AS n '
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
  List<SentenceRow> allSentences(String lang) =>
      _sentences('s.lang = ?', [lang]);

  List<SentenceRow> sentences(String scenarioId, String lang) =>
      _sentences('s.scenario_id = ? AND s.lang = ?', [scenarioId, lang]);

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
    return [
      for (final r in _db.select(
        'SELECT s.id, s.pair_id, s.lang, s.text, s.en, s.register, s.region, s.notes, '
        's.reviewed, s.pattern FROM sentence s WHERE $where ORDER BY s.id',
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
