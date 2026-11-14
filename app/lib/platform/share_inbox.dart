/// Text shared into DuckLearn from other apps (Android "Share" and the text-selection
/// menu). See MainActivity.kt. On other platforms nothing ever arrives.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class ShareInbox {
  ShareInbox() {
    if (Platform.isAndroid) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'sharedText' && call.arguments is String) {
          _incoming.add(call.arguments as String);
        }
      });
    }
  }

  static const _channel = MethodChannel('ducklearn/share');
  final _incoming = StreamController<String>.broadcast();

  /// Text shared while the app was already open.
  Stream<String> get incoming => _incoming.stream;

  /// Text that launched the app, if any (returned once).
  Future<String?> takeLaunchText() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('takeSharedText');
    } on MissingPluginException {
      return null;
    }
  }
}
