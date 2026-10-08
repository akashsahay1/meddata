import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/platform.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

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
      image: 'assets/images/onboarding_stock.png',
      title: 'Track every medicine',
      body:
          'Add your stock once and keep quantities, batches and prices in '
          'one place, works fully offline.',
    ),
    _Slide(
      image: 'assets/images/onboarding_alerts.png',
      title: 'Never miss an expiry',
      body:
          'Get reminders before medicines expire and when stock runs low, '
          'so you avoid losses.',
    ),
    _Slide(
      image: 'assets/images/onboarding_search.png',
      title: 'Find & update fast',
      body:
          'Search by name, batch or barcode and update stock in seconds. '
          'Simple, clean, made for busy homes and small stores.',
    ),
  ];

  void _finish() {
    // _RootGate rebuilds and routes to Home (trial active) or the paywall.
    context.read<SettingsService>().setOnboarded(true);
  }

  void _next() {
    if (_page == _slides.length - 1) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AppPlatform.isWindows || MediaQuery.sizeOf(context).width >= 900) {
      return _buildDesktop();
    }
    return _buildPhone();
  }

  Widget _buildDesktop() {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960, maxHeight: 650),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x160A302E),
                      blurRadius: 44,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Row(
                  children: <Widget>[
                    const SizedBox(width: 310, child: _DesktopBrandPanel()),
                    Expanded(
                      child: Column(
                        children: <Widget>[
                          Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(0, 8, 16, 0),
                              child: TextButton(
                                onPressed: _finish,
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.muted,
                                ),
                                child: const Text('Skip'),
                              ),
                            ),
                          ),
                          Expanded(
                            child: PageView.builder(
                              controller: _controller,
                              onPageChanged: (int i) =>
                                  setState(() => _page = i),
                              itemCount: _slides.length,
                              itemBuilder: (_, int i) =>
                                  _slides[i].buildDesktop(context),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                            child: Row(
                              children: <Widget>[
                                SizedBox(
                                  width: 48,
                                  child: _page == 0
                                      ? const SizedBox.shrink()
                                      : IconButton(
                                          tooltip: 'Previous',
                                          onPressed: () =>
                                              _controller.previousPage(
                                                duration: const Duration(
                                                  milliseconds: 250,
                                                ),
                                                curve: Curves.easeOut,
                                              ),
                                          icon: const Icon(
                                            Icons.arrow_back_rounded,
                                          ),
                                        ),
                                ),
                                Expanded(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: List<Widget>.generate(
                                      _slides.length,
                                      (int i) {
                                        final bool active = i == _page;
                                        return AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 300,
                                          ),
                                          curve: Curves.easeOut,
                                          width: active ? 26 : 7,
                                          height: 7,
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: active
                                                ? AppColors.orange
                                                : AppColors.border,
                                            borderRadius: BorderRadius.circular(
                                              AppRadii.pill,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 156,
                                  height: 48,
                                  child: ElevatedButton(
                                    onPressed: _next,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.orange,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          AppRadii.button,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      _page == _slides.length - 1
                                          ? 'Get started'
                                          : 'Next',
                                    ),
                                  ),
                                ),
                              ],
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
        ),
      ),
    );
  }

  Widget _buildPhone() {
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
                  itemBuilder: (_, int i) => _slides[i].buildPhone(context),
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
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 26),
                    SizedBox(
                      width: 220,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadii.button),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: AppColors.orange.withValues(alpha: 0.4),
                              blurRadius: 28,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: _next,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.orange,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadii.button,
                              ),
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

class _DesktopBrandPanel extends StatelessWidget {
  const _DesktopBrandPanel();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.greenDarkest,
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Row(
              children: <Widget>[
                BrandMark(size: 38),
                SizedBox(width: 12),
                Text(
                  'Meddata',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0x1FFF6B2C),
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: const Text(
                'MADE FOR YOUR MEDICINE SHOP',
                style: TextStyle(
                  color: AppColors.orangeLight,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Your stock,\nunder control.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                height: 1.12,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.7,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Keep batches, prices and expiry dates together in one simple place.',
              style: TextStyle(
                color: AppColors.onDarkMuted,
                fontSize: 14,
                height: 1.55,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            const Row(
              children: <Widget>[
                Icon(
                  Icons.cloud_off_outlined,
                  color: AppColors.orangeLight,
                  size: 18,
                ),
                SizedBox(width: 9),
                Text(
                  'Works offline. Syncs across your devices.',
                  style: TextStyle(
                    color: AppColors.onDarkFaint,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  final String image;
  final String title;
  final String body;
  const _Slide({required this.image, required this.title, required this.body});

  Widget buildPhone(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 34),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 230,
            height: 230,
            child: Image.asset(
              image,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
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

  Widget buildDesktop(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double imageSize = (constraints.maxHeight * 0.48)
            .clamp(180.0, 250.0)
            .toDouble();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                width: imageSize,
                height: imageSize,
                child: Image.asset(
                  image,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  color: AppColors.greenDarkest,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.6,
                    fontWeight: FontWeight.w500,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
