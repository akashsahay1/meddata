import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../widgets/ui_kit.dart';

/// Shared header for the auth screens: Meddata brand mark + wordmark, a bold
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
        isDark ? theme.colorScheme.onSurface : AppColors.green;
    final Color subtitleColor = isDark ? AppColors.onDarkMuted : AppColors.muted;
    return Column(
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const BrandMark(size: 40),
            const SizedBox(width: 12),
            Text(
              'Meddata',
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
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: theme.colorScheme.onSurface,
          ),
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
    if (v.length < 6) return 'At least 6 characters';
    return null;
  }
}
