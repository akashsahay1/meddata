import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../widgets/adaptive_layout.dart';
import '../../widgets/ui_kit.dart';

/// Shared header for the auth screens: Medikabiz brand mark + wordmark, a bold
/// title and a muted subtitle, in the green/orange design language.
class AuthHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const AuthHeader({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    // Brand green only reads on the light canvas; on dark the wordmark/title
    // switch to the theme's onSurface and the subtitle to a light muted tone.
    final Color wordmarkColor =
        isDark ? theme.colorScheme.onSurface : AppColors.navy;
    final Color subtitleColor = isDark ? AppColors.onDarkMuted : AppColors.muted;
    // On a computer the navy panel beside the form carries the logo.
    final bool wide = MediaQuery.sizeOf(context).width >= AdaptiveLayout.desktopBreakpoint;
    return Column(
      children: <Widget>[
        if (!wide) ...<Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const BrandMark(size: 40),
              const SizedBox(width: 12),
              Text(
                'Medikabiz',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: wordmarkColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
        ],
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTheme.display(size: 26, weight: FontWeight.w800, color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: subtitleColor,
          ),
        ),
      ],
    );
  }
}

/// Page for log in, sign up and forgot password. On a computer a navy panel
/// on the left says what Medikabiz is (the screen was mostly empty); the
/// form sits on the right. On a phone the form alone, centred.
class AuthScaffold extends StatelessWidget {
  final Widget child;
  const AuthScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final Widget form = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: child,
        ),
      ),
    );
    final bool wide = MediaQuery.sizeOf(context).width >= AdaptiveLayout.desktopBreakpoint;
    return Scaffold(
      body: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Expanded(flex: 5, child: _AuthPitch()),
                Expanded(flex: 6, child: SafeArea(child: form)),
              ],
            )
          : SafeArea(child: form),
    );
  }
}

class _AuthPitch extends StatelessWidget {
  const _AuthPitch();

  @override
  Widget build(BuildContext context) {
    const TextStyle point = TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white);
    // Logo at the top, the pitch in the middle; scrolls when the window is short.
    return ColoredBox(
      color: AppColors.navy,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(48, 40, 40, 40),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight - 80),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const BrandMark(size: 34),
                      const SizedBox(width: 10),
                      Text.rich(
                        TextSpan(children: const <TextSpan>[
                          TextSpan(text: 'Medika'),
                          TextSpan(text: 'biz', style: TextStyle(color: AppColors.primaryBright)),
                        ]),
                        style: AppTheme.display(size: 22, weight: FontWeight.w800, color: Colors.white),
                      ),
                    ],
                  ),
                  const Spacer(),
                  const SizedBox(height: 40),
                  Text('Your medical shop,\nin order.',
                      style: AppTheme.display(size: 34, weight: FontWeight.w800, color: Colors.white, height: 1.15)),
                  const SizedBox(height: 12),
                  const Text('Bills, stock and expiry on this computer and your phone.',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.onDarkMuted)),
                  const SizedBox(height: 28),
                  for (final String p in const <String>[
                    'GST bills at the counter',
                    'Expiry and low-stock alerts',
                    'Works without internet, syncs later',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.check_circle_outline, size: 20, color: AppColors.primaryBright),
                          const SizedBox(width: 10),
                          Flexible(child: Text(p, style: point)),
                        ],
                      ),
                    ),
                  const Spacer(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The white card the auth forms sit in.
class AuthCard extends StatelessWidget {
  final Widget child;
  const AuthCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.cardLg),
        border: Border.all(color: theme.dividerColor),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x14071D3B), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: child,
    );
  }
}

/// Reusable form validators for the auth screens.
class AuthValidators {
  AuthValidators._();

  static String? required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return 'Enter your email';
    final RegExp re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return re.hasMatch(v.trim()) ? null : 'Enter a valid email';
  }

  static String? password(String? v) {
    if (v == null || v.isEmpty) return 'Enter a password';
    if (v.length < 8) return 'At least 8 characters';
    return null;
  }
}
