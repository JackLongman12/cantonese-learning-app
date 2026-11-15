/// Reading skills beyond sound families: meaning components (radicals), sentence
/// particles and measure words. Each item has a picture, so the shape sticks to the
/// meaning, and an example sentence with Jyutping that you can hear.
library;

import 'voice_picker.dart';

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../data/content_db.dart';
import '../engine/scaffold.dart';
import '../platform/sfx.dart';
import 'ruby_text.dart';
import 'tiles.dart';
import 'word_sheet.dart';

/// A picture (emoji) for a meaning-component hint. Pictures only: the meanings come
/// from Make Me a Hanzi.
const _hintPictures = {
  'water': '💧',
  'mouth': '👄',
  'hand': '✋',
  'plant': '🌿',
  'grass': '🌿',
  'tree': '🌳',
  'wood': '🪵',
  'metal': '⚙️',
  'gold': '🪙',
  'earth': '🟫',
  'person': '🧑',
  'heart': '❤️',
  'speech': '💬',
  'words': '💬',
  'woman': '👩',
  'sun': '☀️',
  'fire': '🔥',
  'silk': '🧵',
  'foot': '🦶',
  'eye': '👁️',
  'food': '🍚',
  'eat': '🍚',
  'walk': '🚶',
  'rain': '🌧️',
  'roof': '🏠',
  'house': '🏠',
  'shell': '🐚',
  'money': '💰',
  'knife': '🔪',
  'grain': '🌾',
  'jade': '💎',
  'vehicle': '🚗',
  'cart': '🛒',
  'moon': '🌙',
  'flesh': '🍖',
  'meat': '🍖',
  'dog': '🐕',
  'insect': '🐛',
  'bird': '🐦',
  'fish': '🐟',
  'horse': '🐎',
  'bamboo': '🎋',
  'door': '🚪',
  'gate': '⛩️',
  'stone': '🪨',
  'clothes': '👕',
  'clothing': '👕',
  'sickness': '🤒',
  'illness': '🤒',
  'ice': '🧊',
  'strength': '💪',
  'child': '👶',
  'field': '🌾',
  'cow': '🐄',
  'boat': '⛵',
  'spirit': '✨',
  'step': '👣',
  'hill': '⛰️',
  'mountain': '⛰️',
  'cloth': '🧶',
  'wine': '🍶',
  'mound': '⛰️',
  'city': '🏙️',
  'net': '🕸️',
  'ear': '👂',
  'head': '🗣️',
  'hair': '💇',
  'claw': '🐾',
  'tooth': '🦷',
  'bone': '🦴',
  'leather': '👜',
  'thread': '🧵',
  'axe': '🪓',
  'bow': '🏹',
  'arrow': '🏹',
  'dish': '🍽️',
  'vessel': '🏺',
  'pig': '🐖',
  'sheep': '🐑',
  'wind': '🌬️',
  'old': '👴',
  'ghost': '👻',
  'cave': '🕳️',
  'hole': '🕳️',
  'show': '🔔',
  'altar': '🛐',
  'wheat': '🌾',
  'rice': '🍚',
  'cover': '⛺',
  'enclosure': '🔲',
  'building': '🏢',
  'shelter': '🛖',
  'stop': '✋',
};

String pictureFor(String hint) =>
    _hintPictures[hint.toLowerCase()] ??
    _hintPictures[hint.toLowerCase().split(RegExp(r'[ ,/]')).first] ??
    '🔤';

/// Tiles for the Practice tab, after sound families and spoken vs written.
List<Widget> extraSkillTiles(
  BuildContext context,
  AppServices s,
  Future<void> Function(Widget) push,
) => [
  _Tile(
    key: const ValueKey('open-radicals'),
    icon: Icons.account_tree_rounded,
    title: 'Radicals',
    subtitle: '氵 → 河 海 洗',
    onTap: () => push(RadicalsScreen(services: s)),
  ),
  for (final sk in s.content.skills())
    _Tile(
      key: ValueKey('open-skill-${sk.id}'),
      icon: switch (sk.id) {
        'particles' => Icons.chat_bubble_outline_rounded,
        'measure-words' => Icons.straighten_rounded,
        _ => Icons.menu_book_rounded,
      },
      title: sk.title,
      subtitle: sk.subtitle,
      onTap: () => push(SkillScreen(services: s, skill: sk)),
    ),
];

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppTile(
    icon: icon,
    title: title,
    subtitle: subtitle,
    subtitleStyle: chineseStyle('yue', fontSize: 14),
    onTap: onTap,
  );
}

/// Meaning components: the part of a character that hints at what it is about.
class RadicalsScreen extends StatelessWidget {
  const RadicalsScreen({super.key, required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final groups = services.content.radicals();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Radicals'),
        actions: [VoiceButton(services)],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              'Most characters have a part that hints at the meaning (氵 water in 河 '
              'river) and a part that hints at the sound. Spot the meaning part and a '
              'new character is half read.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Meanings: Make Me a Hanzi. Most used in the app first.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            for (final g in groups)
              Card(
                key: ValueKey('radical-${g.component}'),
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            pictureFor(g.hint),
                            style: const TextStyle(fontSize: 32),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            g.component,
                            style: chineseStyle('yue', fontSize: 34),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              g.hint,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final c in g.chars)
                            Tooltip(
                              message: c.definition,
                              child: ActionChip(
                                onPressed: () => sayOrExplain(
                                  context,
                                  services,
                                  c.char,
                                  'yue',
                                ),
                                label: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      c.reading,
                                      style: theme.textTheme.labelSmall,
                                    ),
                                    Text(
                                      c.char,
                                      style: chineseStyle('yue', fontSize: 22),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A list skill (particles, measure words): picture, the word with Jyutping, what it
/// does, and an example sentence you can hear.
class SkillScreen extends StatelessWidget {
  const SkillScreen({super.key, required this.services, required this.skill});
  final AppServices services;
  final SkillRow skill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entries = services.content.skillEntries(skill.id);
    final annotator = services.content.annotator('yue');
    return Scaffold(
      appBar: AppBar(
        title: Text(skill.title),
        actions: [VoiceButton(services)],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              'Drafts until checked by a native speaker. Tap an example to hear it.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            for (final e in entries)
              Card(
                key: ValueKey('skill-entry-${e.id}'),
                margin: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  onTap: () {
                    services.sound(Sfx.tap);
                    sayOrExplain(context, services, e.example, 'yue');
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.emoji, style: const TextStyle(fontSize: 36)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    e.zh,
                                    style: chineseStyle('yue', fontSize: 30),
                                  ),
                                  const SizedBox(width: 8),
                                  if (e.reading != null)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        e.reading!,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(color: scheme.primary),
                                      ),
                                    ),
                                ],
                              ),
                              Text(
                                e.meaning,
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 8),
                              RubyText(
                                lang: 'yue',
                                fontSize: 22,
                                tokens: [
                                  for (final t in annotator.annotate(e.example))
                                    RubyToken(
                                      surface: t.surface,
                                      kind: t.kind,
                                      reading: t.reading,
                                      level: ScaffoldLevel.full,
                                    ),
                                ],
                              ),
                              Text(
                                e.exampleEn,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
