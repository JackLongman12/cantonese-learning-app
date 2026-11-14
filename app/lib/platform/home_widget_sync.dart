/// Keeps the Android home-screen widget (DuckWidgetProvider.kt) in step with the app.
library;

import 'dart:io';

import 'package:home_widget/home_widget.dart';

int? _lastDue;
int? _lastKnown;

/// Pushes the numbers the widget shows; cheap to call on every home rebuild.
Future<void> syncHomeWidget({required int due, required int known}) async {
  if (!Platform.isAndroid || (due == _lastDue && known == _lastKnown)) return;
  _lastDue = due;
  _lastKnown = known;
  try {
    await HomeWidget.saveWidgetData<int>('due', due);
    await HomeWidget.saveWidgetData<int>('known', known);
    await HomeWidget.updateWidget(androidName: 'DuckWidgetProvider');
  } on Object {
    // the widget is a convenience; never let it break the app
  }
}
