import 'package:flutter/material.dart';

/// Shared header for the auth screens (monochrome).
class AuthHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const AuthHeader({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final Color fg = Theme.of(context).colorScheme.onSurface;
    return Column(
      children: <Widget>[
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            border: Border.all(color: fg, width: 2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.medical_services_outlined, size: 34),
        ),
        const SizedBox(height: 16),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: fg)),
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
