/// Read-only access to content.db, the database the pipeline builds. Nothing here writes.
library;

import 'package:sqlite3/sqlite3.dart';

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

  List<SentenceRow> sentences(String scenarioId, String lang) {
    final tokens = <String, List<TokenRow>>{};
    for (final r in _db.select(
      'SELECT t.sentence_id, t.surface, t.kind, t.reading, t.item_id, t.flagged '
      'FROM token t JOIN sentence s ON s.id = t.sentence_id '
      'WHERE s.scenario_id = ? AND s.lang = ? ORDER BY t.sentence_id, t.idx',
      [scenarioId, lang],
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
        'SELECT id, pair_id, lang, text, en, register, region, notes, reviewed, pattern '
        'FROM sentence WHERE scenario_id = ? AND lang = ? ORDER BY id',
        [scenarioId, lang],
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
