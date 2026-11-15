/// Visual-novel pieces for conversations: a stage with the two people talking (the one
/// speaking is lit, the other dimmed), name plates, a backlog of earlier lines, and the
/// "what do you say?" choice on the learner's turns.
///
/// Characters are Irasutoya illustrations the app downloads on first launch
/// (platform/character_pictures.dart; never bundled or committed, see
/// content/characters.yaml). When a picture is missing (offline so far, tests, the
/// swearing topic) a coloured initial is drawn instead.
library;

import 'package:material_ui/material_ui.dart';

import '../data/content_db.dart';
import '../platform/character_pictures.dart';
import 'ruby_text.dart';

/// English role for each speaker name used in the conversations.
const speakerRoles = {
  '你': 'You',
  '司機': 'Driver',
  '伙計': 'Waiter',
  '店員': 'Shop assistant',
  '檔主': 'Stall owner',
  '路人': 'Passer-by',
  '朋友': 'Friend',
  '醫生': 'Doctor',
  '姑娘': 'Nurse',
  '老細': 'Boss',
  '職員': 'Staff',
  '經紀': 'Agent',
  '業主': 'Landlord',
  '鄰居': 'Neighbor',
  '速遞員': 'Courier',
  '室友': 'Flatmate',
  '同事': 'Colleague',
  '警員': 'Police officer',
  '保安': 'Security guard',
  '經理': 'Manager',
  '同學': 'Classmate',
  '遊客': 'Tourist',
  '阿明': 'Ah Ming',
  '嫲嫲': 'Grandma',
};

/// The downloaded pictures (set at start-up; null in tests and previews, so Irasutoya
/// pictures never end up in committed snapshots).
CharacterPictures? characterPictures;

/// Colours that tell the two sides apart everywhere: stage, name plate, dialogue box.
({Color bg, Color fg, Color edge}) speakerColors(
  ColorScheme s, {
  required bool mine,
}) => mine
    ? (bg: s.primaryContainer, fg: s.onPrimaryContainer, edge: s.primary)
    : (bg: s.secondaryContainer, fg: s.onSecondaryContainer, edge: s.secondary);

class CharacterSprite extends StatelessWidget {
  const CharacterSprite({
    super.key,
    required this.speaker,
    required this.active,
    required this.mine,
    this.height = 170,
    this.showPicture = true,
  });
  final String speaker;
  final bool active;
  final bool mine;
  final double height;
  final bool showPicture;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = speakerColors(scheme, mine: mine);
    final fallback = Center(
      child: CircleAvatar(
        radius: height * 0.28,
        backgroundColor: c.edge,
        foregroundColor: mine ? scheme.onPrimary : scheme.onSecondary,
        child: mine
            ? Icon(Icons.person_rounded, size: height * 0.3)
            : Text(
                speaker.isEmpty ? '?' : speaker.characters.first,
                style: chineseStyle(
                  'yue',
                  fontSize: height * 0.22,
                  color: scheme.onSecondary,
                ),
              ),
      ),
    );
    final file = showPicture ? characterPictures?.fileFor(speaker) : null;
    final picture = file != null && file.existsSync()
        ? Image.file(
            file,
            height: height,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => fallback,
          )
        : fallback;
    return AnimatedScale(
      scale: active ? 1.0 : 0.86,
      duration: const Duration(milliseconds: 220),
      alignment: Alignment.bottomCenter,
      child: AnimatedOpacity(
        opacity: active ? 1 : 0.38,
        duration: const Duration(milliseconds: 220),
        child: SizedBox(height: height, width: height * 0.8, child: picture),
      ),
    );
  }
}

/// Name plate: "伙計 Waiter" in the speaker's color, with a small triangle pointing up
/// at the person on stage.
class NamePlate extends StatelessWidget {
  const NamePlate({super.key, required this.speaker, required this.mine});
  final String speaker;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = speakerColors(theme.colorScheme, mine: mine);
    return Container(
      key: const ValueKey('name-plate'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: c.edge,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            if (!mine)
              TextSpan(
                text: '$speaker ',
                style: chineseStyle('yue', fontSize: 15, color: Colors.white),
              ),
            TextSpan(text: mine ? 'You' : (speakerRoles[speaker] ?? '')),
          ],
        ),
        style: theme.textTheme.labelLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The stage: the other person on the left, you on the right; the speaker is lit.
class ConversationStage extends StatelessWidget {
  const ConversationStage({
    super.key,
    required this.other,
    required this.youSpeaking,
    this.showPictures = true,
    this.icon,
  });
  final String other;
  final bool youSpeaking;
  final bool showPictures;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('stage'),
      height: 190,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [scheme.surfaceContainerLow, scheme.surfaceContainerHighest],
        ),
      ),
      child: Stack(
        children: [
          if (icon != null)
            Positioned(
              right: 0,
              left: 0,
              top: 14,
              child: Icon(
                icon,
                size: 64,
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          // floor line
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: Container(height: 2, color: scheme.outlineVariant),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                CharacterSprite(
                  key: const ValueKey('sprite-other'),
                  speaker: other,
                  active: !youSpeaking,
                  mine: false,
                  showPicture: showPictures,
                ),
                const Spacer(),
                CharacterSprite(
                  key: const ValueKey('sprite-you'),
                  speaker: '你',
                  active: youSpeaking,
                  mine: true,
                  showPicture: showPictures,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "What do you say?": the line you are about to say among plausible wrong ones.
class ChoicePanel extends StatelessWidget {
  const ChoicePanel({
    super.key,
    required this.options,
    required this.wrong,
    required this.onPick,
    this.prompt,
  });
  final List<String> options;
  final Set<String> wrong;
  final ValueChanged<String> onPick;

  /// The English of what the other person just said, as context.
  final String? prompt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('What do you say?', style: theme.textTheme.titleMedium),
        if (prompt != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'They said: $prompt',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 10),
        for (var i = 0; i < options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              key: ValueKey('choice-$i'),
              onPressed: wrong.contains(options[i])
                  ? null
                  : () => onPick(options[i]),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                side: BorderSide(
                  color: wrong.contains(options[i])
                      ? scheme.error
                      : scheme.primary,
                ),
              ),
              child: Text(
                options[i],
                style:
                    chineseStyle(
                      'yue',
                      fontSize: 20,
                      color: wrong.contains(options[i])
                          ? scheme.error
                          : scheme.onSurface,
                    ).copyWith(
                      decoration: wrong.contains(options[i])
                          ? TextDecoration.lineThrough
                          : null,
                    ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The backlog: every line so far, coloured by who said it.
Future<void> showBacklog(BuildContext context, List<SentenceRow> lines) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text('So far', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final l in lines)
              Builder(
                builder: (_) {
                  final mine = l.speaker == '你';
                  final c = speakerColors(theme.colorScheme, mine: mine);
                  return Align(
                    alignment: mine
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      constraints: const BoxConstraints(maxWidth: 320),
                      decoration: BoxDecoration(
                        color: c.bg,
                        border: Border.all(color: c.edge, width: 1.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            mine
                                ? 'You'
                                : '${l.speaker} ${speakerRoles[l.speaker] ?? ''}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: c.edge,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            l.text,
                            style: chineseStyle(
                              'yue',
                              fontSize: 18,
                              color: c.fg,
                            ),
                          ),
                          Text(
                            l.en,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: c.fg,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      );
    },
  );
}
