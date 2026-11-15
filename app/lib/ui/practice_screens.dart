/// Two short reference lessons that make reading easier to learn:
/// - Sound families: one phonetic component often gives a whole group its sound.
/// - Spoken vs written: written Cantonese next to standard written Chinese.
library;

import 'voice_picker.dart';

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../engine/reading_format.dart';
import 'ruby_text.dart';

String _syllable(String r) => r.replaceAll(RegExp(r'[1-6]$'), '');

/// How useful the component is as a hint for this member's sound.
enum SoundFit { same, toneOnly, different }

SoundFit soundFit(String component, String member) => component == member
    ? SoundFit.same
    : _syllable(component) == _syllable(member)
    ? SoundFit.toneOnly
    : SoundFit.different;

class SoundFamiliesScreen extends StatelessWidget {
  const SoundFamiliesScreen({
    super.key,
    required this.services,
    required this.lang,
  });
  final AppServices services;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final families = services.content.soundFamilies(lang);
    bool known(String char, String reading) =>
        !services.learner.stateOf('cr:$lang:$char:$reading').isNew;
    // families with something already known come first: that's where the hint pays off
    families.sort(
      (a, b) => b.members
          .where((m) => known(m.char, m.reading))
          .length
          .compareTo(a.members.where((m) => known(m.char, m.reading)).length),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sound families'),
        actions: [VoiceButton(services)],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(
                  'Many characters borrow their sound from one part of them. Know the part, '
                  'and you can often guess the sound of a character you have never seen.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  children: [
                    _Legend(color: scheme.secondary, text: 'same sound'),
                    _Legend(color: scheme.tertiary, text: 'tone differs'),
                    _Legend(color: scheme.outline, text: 'different'),
                  ],
                ),
                const SizedBox(height: 12),
                if (families.isEmpty)
                  const Text('No families found in this content yet.'),
                for (final f in families.take(60))
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 64,
                            child: Column(
                              children: [
                                Text(
                                  f.component,
                                  style: chineseStyle(lang, fontSize: 36),
                                ),
                                Text(
                                  displayReading(lang, f.reading),
                                  style: theme.textTheme.labelMedium,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                for (final m in f.members)
                                  _Member(
                                    char: m.char,
                                    reading: displayReading(lang, m.reading),
                                    lang: lang,
                                    known: known(m.char, m.reading),
                                    color: switch (soundFit(
                                      f.reading,
                                      m.reading,
                                    )) {
                                      SoundFit.same => scheme.secondary,
                                      SoundFit.toneOnly => scheme.tertiary,
                                      SoundFit.different => scheme.outline,
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 12, height: 4, color: color),
      const SizedBox(width: 4),
      Text(text, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

class _Member extends StatelessWidget {
  const _Member({
    required this.char,
    required this.reading,
    required this.lang,
    required this.known,
    required this.color,
  });
  final String char;
  final String reading;
  final String lang;
  final bool known;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(reading, style: Theme.of(context).textTheme.labelSmall),
      Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: color, width: 3)),
        ),
        child: Text(
          char,
          style: chineseStyle(
            lang,
            fontSize: 26,
          ).copyWith(fontWeight: known ? FontWeight.w700 : FontWeight.w400),
        ),
      ),
      if (known) Icon(Icons.check_rounded, size: 14, color: color),
    ],
  );
}

/// Written Cantonese (chats, ads) vs standard written Chinese (signs, forms, news), which
/// Cantonese speakers read aloud in Cantonese. Same meaning, different characters.
const spokenWrittenPairs = [
  ('佢', '他／她', 'he, she'),
  ('係', '是', 'is'),
  ('唔', '不', 'not'),
  ('冇', '沒有', "don't have"),
  ('嘅', '的', "possessive 's"),
  ('咗', '了', 'done (past)'),
  ('喺', '在', 'at, in'),
  ('睇', '看', 'look, read'),
  ('嘢', '東西', 'thing'),
  ('俾', '給', 'give'),
  ('啲', '些', 'some'),
  ('嚟', '來', 'come'),
  ('咁', '這麼', 'so (this much)'),
  ('呢個', '這個', 'this one'),
  ('嗰個', '那個', 'that one'),
  ('邊度', '哪裡', 'where'),
  ('乜嘢', '甚麼', 'what'),
  ('點解', '為甚麼', 'why'),
  ('幾多', '多少', 'how many'),
  ('我哋', '我們', 'we'),
  ('佢哋', '他們', 'they'),
  ('同', '和', 'and'),
  ('食', '吃', 'eat'),
  ('飲', '喝', 'drink'),
  ('瞓覺', '睡覺', 'sleep'),
  ('返工', '上班', 'go to work'),
];

class SpokenWrittenScreen extends StatelessWidget {
  const SpokenWrittenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Spoken vs written')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(
                  'Chats and ads are written the way you speak. Signs, forms and news use '
                  'standard written Chinese, which you read aloud in Cantonese. Same meaning, '
                  'different characters:',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'As spoken',
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'On signs and news',
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    Expanded(
                      child: Text('Meaning', style: theme.textTheme.labelLarge),
                    ),
                  ],
                ),
                const Divider(),
                for (final (spoken, written, en) in spokenWrittenPairs)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            spoken,
                            style: chineseStyle('yue', fontSize: 24),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            written,
                            style: chineseStyle('yue', fontSize: 24),
                          ),
                        ),
                        Expanded(
                          child: Text(en, style: theme.textTheme.bodyMedium),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
