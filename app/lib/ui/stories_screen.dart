/// Graded stories. Each shows how much of it this learner can already read, and the best
/// next read is the one that is mostly familiar but not yet easy (extensive reading).
library;

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import 'finish.dart' show pushOnce;
import '../data/content_db.dart';
import '../engine/scaffold.dart';
import 'reader_screen.dart';
import 'tiles.dart';

/// Share of a story's characters the learner reads without full help.
double storyCoverage(AppServices s, List<SentenceRow> lines) {
  final now = s.logger.now();
  final ids = {for (final l in lines) ...l.itemIds};
  if (ids.isEmpty) return 0;
  final known = ids.where(
    (id) =>
        s.scaffold.levelFor(s.learner.stateOf(id), s.memory, now) !=
        ScaffoldLevel.full,
  );
  return known.length / ids.length;
}

class StoriesScreen extends StatefulWidget {
  const StoriesScreen({super.key, required this.services, required this.lang});
  final AppServices services;
  final String lang;

  @override
  State<StoriesScreen> createState() => _StoriesScreenState();
}

class _StoriesScreenState extends State<StoriesScreen> {
  AppServices get _s => widget.services;

  Future<void> _open(DialogueRow story, String lang) async {
    _s.logger.log('nav.screen', {
      'screen': 'reader',
      'mode': 'story',
      'dialogue_id': story.id,
    });
    await pushOnce(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          services: _s,
          title: story.title,
          sentences: _s.content.dialogueLines(story.id, lang),
          lang: lang,
          mode: 'story',
          story: true,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stories = _s.content.stories(widget.lang);
    final coverage = {
      for (final st in stories)
        st.id: storyCoverage(_s, _s.content.dialogueLines(st.id, widget.lang)),
    };
    // Best next read: mostly familiar but still something to learn.
    final next = stories
        .where((st) => coverage[st.id]! < 0.97)
        .fold<DialogueRow?>(
          null,
          (best, st) =>
              best == null || coverage[st.id]! > coverage[best.id]! ? st : best,
        );
    final levels = {for (final st in stories) st.level}.toList()..sort();
    Widget tile(DialogueRow st) => AppTile(
      key: ValueKey('story-${st.id}'),
      icon: Icons.auto_stories_rounded,
      title: st.title,
      subtitle:
          '${st.lines} lines · you know ${(100 * coverage[st.id]!).round()}%',
      progress: coverage[st.id],
      onTap: () => _open(st, widget.lang),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Text('Stories', style: theme.textTheme.titleLarge),
            if (stories.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('No stories yet.'),
              ),
            if (next != null) ...[
              const SizedBox(height: 12),
              Card(
                key: const ValueKey('story-next'),
                margin: EdgeInsets.zero,
                color: theme.colorScheme.primaryContainer,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  leading: const Icon(Icons.auto_stories_rounded, size: 32),
                  title: Text('Read next: ${next.title}'),
                  subtitle: Text(
                    'Level ${next.level} · you know '
                    '${(100 * coverage[next.id]!).round()}% of it',
                  ),
                  trailing: const Icon(Icons.play_arrow_rounded),
                  onTap: () => _open(next, widget.lang),
                ),
              ),
            ],
            for (final lv in levels) ...[
              Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 10),
                child: Text(switch (lv) {
                  1 => 'Level 1 · short and easy',
                  2 => 'Level 2',
                  _ => 'Level $lv · longer',
                }, style: theme.textTheme.titleMedium),
              ),
              TileGrid(
                children: [
                  for (final st in stories)
                    if (st.level == lv) tile(st),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
