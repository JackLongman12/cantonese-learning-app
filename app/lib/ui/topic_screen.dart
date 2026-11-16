/// One topic: practice its sentences, or read one of its conversations.
library;

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import 'finish.dart' show pushOnce;
import '../data/content_db.dart';
import 'critters.dart';
import 'reader_screen.dart';
import 'speak_drill_screen.dart';
import 'tiles.dart';

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
    await pushOnce(context, MaterialPageRoute<void>(builder: (_) => screen));
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
                              if (sc.description.isNotEmpty) ...[
                                Text(
                                  sc.description,
                                  key: const ValueKey('topic-description'),
                                  style: theme.textTheme.bodyLarge,
                                ),
                                const SizedBox(height: 8),
                              ],
                              Text(
                                '${sc.sentenceCount} real-life lines. The app picks the '
                                'ones that help you most right now.',
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                key: const ValueKey('practice'),
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
                                label: const Text('Practice sentences'),
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
                        const Chick(mood: ChickMood.curious, size: 84),
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
                const SizedBox(height: 4),
                TileGrid(
                  children: [
                    for (final d in dialogues)
                      AppTile(
                        key: ValueKey('dlg-${d.id}'),
                        icon: Icons.forum_rounded,
                        title: d.title,
                        subtitle: '${d.lines} lines',
                        badge: d.level >= 3 ? 'Advanced' : null,
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
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
