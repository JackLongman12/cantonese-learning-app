import 'dart:io';

import 'package:duk/app_services.dart';
import 'package:duk/data/content_db.dart';
import 'package:duk/engine/learner_model.dart';
import 'package:duk/engine/memory.dart';
import 'package:duk/events/event.dart';
import 'package:duk/events/event_logger.dart';
import 'package:duk/events/event_store.dart';
import 'package:duk/ui/paste_reader_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const dbPath = 'assets/content/content.db';
  final hasDb = File(dbPath).existsSync();

  testWidgets('pasted text gets readings only where the learner needs them', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final db = ContentDb.open(dbPath);
    addTearDown(db.close);
    final now = DateTime.utc(2026, 11, 15, 9);
    final memory = Memory();
    // the learner already knows 唔 and 該 well (two years of good reviews)
    final history = <Event>[];
    var at = now.subtract(const Duration(days: 700));
    for (var i = 0; i < 10; i++) {
      for (final id in ['cr:yue:唔:m4', 'cr:yue:該:goi1']) {
        history.add(
          Event(
            id: 'h$i$id',
            tsUtc: at,
            tzOffsetMin: 0,
            monoMs: 0,
            deviceId: 'd',
            deviceKind: 'test',
            sessionId: 's',
            appVersion: 't',
            contentVersion: 'c',
            type: 'review.applied',
            payload: {'item_id': id, 'grade': 'good'},
          ),
        );
      }
      at = at.add(Duration(days: [1, 3, 8, 20, 40, 60, 90, 120, 150, 200][i]));
    }
    final store = MemoryEventStore();
    final services = AppServices(
      content: db,
      memory: memory,
      learner: LearnerModel.replay(history, memory),
      logger: EventLogger(
        store: store,
        deviceId: 'test',
        deviceKind: 'windows',
        appVersion: 'test',
        contentVersion: db.contentVersion,
        clock: () => now,
      ),
      playAudio: (_) async {},
    );
    await t.pumpWidget(
      MaterialApp(
        home: PasteReaderScreen(services: services, lang: 'yue'),
      ),
    );
    await t.enterText(find.byKey(const ValueKey('paste-input')), '唔該，我去銀行。');
    await t.tap(find.byKey(const ValueKey('read-text')));
    await t.pumpAndSettle();

    String ruby(String surface) {
      // ruby-N keys are per line; the text is one line, so N is the token index
      final idx = '唔該，我去銀行。'.split('').indexOf(surface);
      return t.widget<Text>(find.byKey(ValueKey('ruby-$idx'))).data ?? '';
    }

    expect(ruby('唔'), ''); // known well: no help
    expect(ruby('該'), '');
    expect(ruby('銀'), 'ngan4'); // new: full reading
    expect(ruby('行'), 'hong4'); // context word 銀行, not the default hang4
    expect(t.widget<Text>(find.byKey(const ValueKey('coverage'))).data, '33%');

    final open = store.events.firstWhere((e) => e.type == 'reader.open');
    expect(open.payload['chars'], 6);
    // the pasted text itself is never logged
    expect(store.events.any((e) => e.toLine().contains('銀行')), isFalse);
  }, skip: !hasDb);
}
