import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/settings_service.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  static const List<_Slide> _slides = <_Slide>[
    _Slide(
      icon: Icons.medication_outlined,
      title: 'Track every medicine',
      body: 'Add your stock once and keep quantities, batches and prices in '
          'one place — works fully offline.',
    ),
    _Slide(
      icon: Icons.notifications_none,
      title: 'Never miss an expiry',
      body: 'Get reminders before medicines expire and when stock runs low, '
          'so you avoid losses.',
    ),
    _Slide(
      icon: Icons.search,
      title: 'Find & update fast',
      body: 'Search by name, batch or barcode and update stock in seconds. '
          'Simple, clean, made for busy shops.',
    ),
  ];

  void _finish() {
    context.read<SettingsService>().setOnboarded(true);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool last = _page == _slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (int i) => setState(() => _page = i),
                itemCount: _slides.length,
                itemBuilder: (_, int i) => _slides[i].build(context),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(_slides.length, (int i) {
                final bool active = i == _page;
                return Container(
                  width: active ? 22 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface,
                    borderRadius: BorderRadius.circular(4),
                    shape: BoxShape.rectangle,
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: ElevatedButton(
                onPressed: () {
                  if (last) {
                    _finish();
                  } else {
                    _controller.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  }
                },
                child: Text(last ? 'Get Started' : 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  final IconData icon;
  final String title;
  final String body;
  const _Slide({required this.icon, required this.title, required this.body});

  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              border: Border.all(
                  color: Theme.of(context).colorScheme.onSurface, width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 56),
          ),
          const SizedBox(height: 32),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
