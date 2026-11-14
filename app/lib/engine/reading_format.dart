/// How a stored reading is shown to the learner (Jyutping, e.g. `hong4`).
library;

/// Full reading as shown above a character.
String displayReading(String lang, String reading) => reading;

/// Tone-only hint: the Jyutping tone number.
String displayToneHint(String lang, String reading) =>
    RegExp(r'[1-6]$').firstMatch(reading)?.group(0) ?? '';
