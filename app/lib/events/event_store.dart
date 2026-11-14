/// Append-only storage. One JSONL file per device per month, which is also the sync unit:
/// a device only ever writes its own files, so merging can never conflict.
library;

import 'dart:convert';
import 'dart:io';

import 'event.dart';

abstract interface class EventStore {
  void append(Event e);

  /// Every event from every device, unordered.
  Iterable<Event> readAll();
}

class MemoryEventStore implements EventStore {
  final List<Event> events = [];

  @override
  void append(Event e) => events.add(e);

  @override
  Iterable<Event> readAll() => events;
}

class JsonlEventStore implements EventStore {
  JsonlEventStore(this.root, this.deviceId);

  /// `<root>/<deviceId>/<yyyy-mm>.jsonl`
  final Directory root;
  final String deviceId;

  File _fileFor(DateTime tsUtc) {
    final month = '${tsUtc.year}-${tsUtc.month.toString().padLeft(2, '0')}';
    return File('${root.path}/$deviceId/$month.jsonl');
  }

  @override
  void append(Event e) {
    final f = _fileFor(e.tsUtc);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync('${e.toLine()}\n', mode: FileMode.append, flush: true);
  }

  @override
  Iterable<Event> readAll() sync* {
    if (!root.existsSync()) return;
    final files =
        root
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.jsonl'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      for (final line in const LineSplitter().convert(f.readAsStringSync())) {
        final e = Event.tryParseLine(line);
        if (e != null) yield e;
      }
    }
  }
}
