/// The first-run walkthrough (2026-11-17): what DuckLearn is, its two modes, the drill,
/// search, why tones matter, and that it teaches spoken Cantonese, not formal written
/// Chinese. Shown before the setup questions, and on Settings → Replay onboarding.
library;

import 'package:material_ui/material_ui.dart';

import 'logo.dart';
import 'ruby_text.dart' show chineseStyle;

class IntroPages extends StatefulWidget {
  const IntroPages({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<IntroPages> createState() => _IntroPagesState();
}

class _IntroPagesState extends State<IntroPages> {
  final _pager = PageController();
  int _page = 0;

  static const _count = 6;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _next() {
    if (_page + 1 >= _count) return widget.onDone();
    _pager.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey('intro-skip'),
                onPressed: widget.onDone,
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pager,
                onPageChanged: (i) => setState(() => _page = i),
                children: const [
                  _Welcome(),
                  _Modes(),
                  _Drill(),
                  _Search(),
                  _Tones(),
                  _Spoken(),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _count; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? scheme.primary
                          : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('intro-next'),
                  onPressed: _next,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                  child: Text(_page + 1 >= _count ? 'Set up' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One walkthrough page: a picture on top, a title, a few lines.
class _Page extends StatelessWidget {
  const _Page({required this.picture, required this.title, required this.body});
  final Widget picture;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: picture),
          const SizedBox(height: 24),
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 10),
          Text(body, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

/// A small rounded panel used to draw the pictures.
class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.color, this.width});
  final Widget child;
  final Color? color;
  final double? width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color ?? Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
}

/// Characters with their Jyutping above (static: the walkthrough's examples).
class _Word extends StatelessWidget {
  const _Word(this.zh, this.jyutping, {this.size = 28});
  final String zh;
  final String jyutping;
  final double size;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        jyutping,
        style: TextStyle(
          fontSize: size * 0.4,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      Text(zh, style: chineseStyle('yue', fontSize: size)),
    ],
  );
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) => const _Page(
    picture: DuckLogo(size: 120, tile: true),
    title: 'Welcome to DuckLearn',
    body:
        'The Cantonese you need for everyday life in Hong Kong and Macau: the key '
        'words to get your point across, said out loud, with your pronunciation '
        'checked on your phone. A short walkthrough, then a few questions.',
  );
}

class _Modes extends StatelessWidget {
  const _Modes();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget mode(IconData icon, String title, String lines, Color color) =>
        Expanded(
          child: _Panel(
            color: color,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 30),
                const SizedBox(height: 8),
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(lines, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        );
    return _Page(
      picture: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          mode(
            Icons.record_voice_over_outlined,
            'New to Cantonese',
            'Situations, a daily drill, search for the word you need.',
            scheme.secondaryContainer,
          ),
          const SizedBox(width: 10),
          mode(
            Icons.menu_book_outlined,
            'Speak it, can\'t read',
            'Topics, read then check, flashcards out loud.',
            scheme.primaryContainer,
          ),
        ],
      ),
      title: 'Two ways to use it',
      body:
          'If you\'re new to Cantonese or know a little, you learn key words for daily '
          'situations and say them out loud. If you already speak it but can\'t read, '
          'you learn the characters for words you know. You choose next, and can '
          'switch any time in Settings.',
    );
  }
}

class _Drill extends StatelessWidget {
  const _Drill();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const arrow = Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Icon(Icons.arrow_forward_rounded, size: 18),
    );
    return _Page(
      picture: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Panel(child: Text('"the bill"', style: theme.textTheme.titleMedium)),
          arrow,
          CircleAvatar(
            radius: 24,
            backgroundColor: scheme.primary,
            child: Icon(Icons.mic_rounded, color: scheme.onPrimary),
          ),
          arrow,
          const _Panel(child: _Word('埋單', 'maai4 daan1', size: 26)),
        ],
      ),
      title: 'The daily drill',
      body:
          'See the English, say it in Cantonese, then hear and see the word. The mic '
          'checks how you said it. Words you know come back just before you\'d forget '
          'them, so a few minutes a day is enough.',
    );
  }
}

class _Search extends StatelessWidget {
  const _Search();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _Page(
      picture: _Panel(
        width: 280,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.search_rounded, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text('toilet', style: theme.textTheme.bodyLarge),
              ],
            ),
            const Divider(),
            Row(
              children: [
                const _Word('洗手間', 'sai2 sau2 gaan1', size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('toilet', style: theme.textTheme.bodyMedium),
                ),
                const Icon(Icons.volume_up_outlined),
              ],
            ),
          ],
        ),
      ),
      title: 'Find the word you need',
      body:
          'On Home, "What do you want to say?" finds the word or a short line to say, '
          'with its sound. Situations group the words for each part of daily life: '
          'getting around, eating out, paying, the doctor, emergencies and more.',
    );
  }
}

class _Tones extends StatelessWidget {
  const _Tones();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget row(String zh, String jp, String meaning, {bool rude = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              _Word(zh, jp, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  meaning,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: rude ? scheme.error : null,
                  ),
                ),
              ),
            ],
          ),
        );
    return _Page(
      picture: _Panel(
        width: 300,
        child: Column(
          children: [
            row('係', 'hai6', '"is, am" (low and level)'),
            row('喺', 'hai2', '"at, in" (rising)'),
            row('閪', 'hai1', 'a vulgar insult (high)', rude: true),
          ],
        ),
      ),
      title: 'Tones change the meaning',
      body:
          'Cantonese has six tones, and the same sound with a different tone is a '
          'different word. 我係 ("I am") with the wrong tone can come out rude, and '
          '買 (buy) and 賣 (sell) differ only by tone. Listen closely and let the mic '
          'check you. Reading skills has a short lesson on tones.',
    );
  }
}

class _Spoken extends StatelessWidget {
  const _Spoken();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget col(String label, String zh, Color color) => Expanded(
      child: _Panel(
        color: color,
        child: Column(
          children: [
            Text(label, style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            Text(zh, style: chineseStyle('yue', fontSize: 22)),
          ],
        ),
      ),
    );
    return _Page(
      picture: Row(
        children: [
          col('Spoken (this app)', '佢哋唔係', scheme.secondaryContainer),
          const SizedBox(width: 10),
          col('Formal written', '他們不是', scheme.surfaceContainerHigh),
        ],
      ),
      title: 'Good to know: spoken Cantonese',
      body:
          'DuckLearn is about spoken Cantonese. The Chinese you see here is Cantonese '
          'written the way people talk and text (佢哋 "they", 唔係 "isn\'t"). Formal '
          'written Chinese, used in news, forms and contracts, looks different and '
          'isn\'t covered. Signs and notices are the one exception the app touches on.',
    );
  }
}
