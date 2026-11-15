/// Graded stories. Each shows how much of it this learner can already read, and the best
/// next read is the one that is mostly familiar but not yet easy (extensive reading).
library;

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../data/content_db.dart';
import '../engine/scaffold.dart';
import 'reader_screen.dart';

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
    await Navigator.of(context).push(
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
    final scheme = theme.colorScheme;
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
    return Scaffold(
      appBar: AppBar(title: const Text('Stories')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(
                  'Read whole stories, a line at a time. Reading lots of mostly-familiar '
                  'text is how reading gets fast.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                if (stories.isEmpty)
                  const Text('No stories in this language yet.'),
                for (final st in stories)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      key: ValueKey('story-${st.id}'),
                      onTap: () => _open(st, widget.lang),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    st.title,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                                if (st.id == next?.id)
                                  Chip(
                                    label: const Text('Good next read'),
                                    backgroundColor: scheme.primaryContainer,
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: coverage[st.id],
                                minHeight: 6,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Level ${st.level} · ${st.lines} lines · '
                              'you can read ${(100 * coverage[st.id]!).round()}%',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
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
        ),
      ),
    );
  }
}
