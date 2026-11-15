/// One topic: practise its sentences, or read one of its conversations.
library;

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../data/content_db.dart';
import 'mascot.dart';
import 'reader_screen.dart';
import 'speak_drill_screen.dart';

class TopicScreen extends StatefulWidget {
  const TopicScreen({
    super.key,
    required this.services,
    required this.scenario,
    required this.lang,
  });

  final AppServices services;
  final ScenarioRow scenario;
  final String lang;

  @override
  State<TopicScreen> createState() => _TopicScreenState();
}

class _TopicScreenState extends State<TopicScreen> {
  AppServices get _s => widget.services;

  Future<void> _open(Widget screen, Map<String, Object?> log) async {
    _s.logger.log('nav.screen', log);
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sc = widget.scenario;
    final dialogues = _s.content.dialogues(sc.id, widget.lang);
    return Scaffold(
      appBar: AppBar(title: Text(sc.title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  color: theme.colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sentences',
                                style: theme.textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${sc.sentenceCount} real-life lines. The app picks the '
                                'ones that help you most right now.',
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                key: const ValueKey('practise'),
                                onPressed: () => _open(
                                  ReaderScreen(
                                    services: _s,
                                    title: sc.title,
                                    sentences: _s.content.sentences(
                                      sc.id,
                                      widget.lang,
                                    ),
                                    lang: widget.lang,
                                    scenarioId: sc.id,
                                  ),
                                  {
                                    'screen': 'reader',
                                    'mode': 'topic',
                                    'scenario_id': sc.id,
                                  },
                                ),
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('Practise sentences'),
                              ),
                              const SizedBox(height: 8),
                              // rapid speaking: the mic runs by itself, line after line
                              FilledButton.tonalIcon(
                                key: const ValueKey('speak-topic'),
                                onPressed: () => _open(
                                  SpeakDrillScreen(
                                    services: _s,
                                    title: 'Speak: ${sc.title}',
                                    sentences: pickSpeakLines(
                                      _s,
                                      _s.content.sentences(sc.id, widget.lang),
                                    ),
                                  ),
                                  {'screen': 'speak', 'scenario_id': sc.id},
                                ),
                                icon: const Icon(
                                  Icons.record_voice_over_rounded,
                                ),
                                label: const Text('Speak'),
                              ),
                            ],
                          ),
                        ),
                        const DuckMascot(size: 84),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Conversations', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'The same situation, different ways it can go. Read your lines and theirs.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                if (dialogues.isEmpty)
                  const Text('No conversations for this topic yet.'),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'All lines are drafts until you have checked them by ear.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final (i, d) in dialogues.indexed)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      key: ValueKey('dlg-${d.id}'),
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.secondaryContainer,
                        foregroundColor: theme.colorScheme.onSecondaryContainer,
                        child: Text('${i + 1}'),
                      ),
                      title: Text(d.title),
                      subtitle: Text(
                        d.level >= 3
                            ? '${d.lines} lines · Advanced'
                            : '${d.lines} lines',
                      ),
                      trailing: const Icon(Icons.forum_rounded),
                      onTap: () => _open(
                        ReaderScreen(
                          services: _s,
                          title: d.title,
                          sentences: _s.content.dialogueLines(
                            d.id,
                            widget.lang,
                          ),
                          lang: widget.lang,
                          mode: 'conversation',
                          scenarioId: sc.id,
                          conversation: true,
                        ),
                        {
                          'screen': 'reader',
                          'mode': 'conversation',
                          'dialogue_id': d.id,
                        },
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
