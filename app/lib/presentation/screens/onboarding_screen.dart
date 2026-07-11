import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';

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
          'one place, works fully offline.',
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
          'Simple, clean, made for busy homes and small stores.',
    ),
  ];

  void _finish() {
    // _RootGate rebuilds and routes to Home (trial active) or the paywall.
    context.read<SettingsService>().setOnboarded(true);
  }

  @override
  Widget build(BuildContext context) {
    final bool last = _page == _slides.length - 1;
    return Scaffold(
      backgroundColor: AppColors.greenDarkest,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            children: <Widget>[
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: TextButton(
                    onPressed: _finish,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.onDarkFaint,
                    ),
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onDarkFaint,
                      ),
                    ),
                  ),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(30, 0, 30, 46),
                child: Column(
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List<Widget>.generate(_slides.length, (int i) {
                        final bool active = i == _page;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                          width: active ? 26 : 7,
                          height: 7,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.orange
                                : Colors.white.withValues(alpha: 0.14),
                            borderRadius:
                                BorderRadius.circular(AppRadii.pill),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(AppRadii.button),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: AppColors.orange.withValues(alpha: 0.4),
                              blurRadius: 28,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
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
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.orange,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadii.button),
                            ),
                          ),
                          child: Text(
                            last ? 'Get started' : 'Next',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 34),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 184,
            height: 184,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                color: AppColors.green,
                borderRadius: BorderRadius.circular(34),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 56, color: AppColors.orange),
            ),
          ),
          const SizedBox(height: 38),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              height: 1.6,
              fontWeight: FontWeight.w500,
              color: AppColors.onDarkMuted,
            ),
          ),
        ],
      ),
    );
  }
}
