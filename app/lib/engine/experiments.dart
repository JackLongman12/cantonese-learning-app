/// A/B tests across installs. Each install is put into one arm of each experiment,
/// fixed for good, from a hash of its anonymous telemetry id: no server round trip,
/// and the same arm on every launch. Arms are logged (`experiment.assigned`) so the
/// analysis (`duk telemetry report`) can compare them. docs/TELEMETRY.md lists what
/// each experiment measures.
library;

class Experiment {
  const Experiment(this.id, this.arms, {this.what = ''});
  final String id;

  /// The first arm is the control (what the app did before).
  final List<String> arms;
  final String what;
}

/// Running experiments. Never reuse an id: old logs carry it. To end one, remove it
/// here and hard-code the winning arm; record the result in docs/CHANGELOG.md.
const experiments = [
  Experiment(
    'meaning_after_check',
    ['shown', 'hidden'],
    what:
        'Speakers: after checking a sentence, does showing the English meaning '
        'help, or is it noise for someone who understood it by ear?',
  ),
  Experiment(
    'first_session',
    ['short', 'longer'],
    what:
        'The very first session: 5 sentences with 4 new characters, or 8 with 6. '
        'Which brings more people back for a second session?',
  ),
];

/// The arm of [e] for this install. Stable: FNV-1a over the id and the experiment.
String armFor(String installId, Experiment e) =>
    e.arms[_fnv1a('$installId/${e.id}') % e.arms.length];

/// Every experiment's arm for this install.
Map<String, String> armsFor(String installId) => {
  for (final e in experiments) e.id: armFor(installId, e),
};

int _fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}
