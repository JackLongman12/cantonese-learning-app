library;

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import 'reader_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.services});
  final AppServices services;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _lang = 'yue';

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    final scenarios = s.content
        .scenarios(_lang)
        .where((x) => x.sentenceCount > 0)
        .toList();
    final known = s.learner.known.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('讀 Duk'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'yue', label: Text('粵語')),
                ButtonSegment(value: 'cmn', label: Text('普通话')),
              ],
              selected: {_lang},
              onSelectionChanged: (v) {
                s.logger.log('settings.change', {
                  'key': 'lang',
                  'from': _lang,
                  'to': v.first,
                });
                setState(() => _lang = v.first);
              },
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '$known characters met so far',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (scenarios.isEmpty)
            const Text('No content for this language yet.'),
          for (final sc in scenarios)
            Card(
              child: ListTile(
                title: Text(sc.title),
                subtitle: Text('${sc.region} · ${sc.sentenceCount} sentences'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  s.logger.log('nav.screen', {
                    'screen': 'reader',
                    'scenario_id': sc.id,
                  });
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ReaderScreen(services: s, scenario: sc, lang: _lang),
                    ),
                  );
                  if (mounted) setState(() {});
                },
              ),
            ),
        ],
      ),
    );
  }
}
