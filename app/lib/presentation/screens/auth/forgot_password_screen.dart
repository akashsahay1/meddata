import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../services/auth_service.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/ui_kit.dart';
import 'auth_widgets.dart';

/// Two-step reset: 1) enter email → get a 6-digit code, 2) enter code + new
/// password. Matches the backend /auth/forgot-password + /auth/reset-password.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _busy = false;
  bool _codeSent = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (AuthValidators.email(_email.text) != null) {
      _formKey.currentState!.validate();
      return;
    }
    setState(() => _busy = true);
    final String? error =
        await context.read<AuthService>().forgotPassword(_email.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error == null) _codeSent = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error ??
          'If that email exists, a 6-digit reset code has been sent.'),
    ));
  }

  Future<void> _reset() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final String? error = await context.read<AuthService>().resetPassword(
          email: _email.text.trim(),
          code: _code.text.trim(),
          password: _password.text,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Password reset. Please log in.')));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  AuthHeader(
                    title: 'Forgot password',
                    subtitle: _codeSent
                        ? 'Enter the code we emailed you and pick a new password'
                        : 'We will email you a 6-digit reset code',
                  ),
                  const SizedBox(height: 30),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(AppRadii.cardLg),
                      border: Border.all(color: theme.dividerColor),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x140A302E),
                          blurRadius: 24,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        LabeledField(
                          label: 'Email',
                          hint: 'you@example.com',
                          controller: _email,
                          enabled: !_codeSent,
                          keyboardType: TextInputType.emailAddress,
                          validator: AuthValidators.email,
                        ),
                        if (_codeSent) ...<Widget>[
                          const SizedBox(height: 16),
                          _LabeledCodeField(controller: _code),
                          const SizedBox(height: 16),
                          _PasswordField(
                            controller: _password,
                            obscure: _obscure,
                            onToggle: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ],
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed:
                              _busy ? null : (_codeSent ? _reset : _sendCode),
                          child: _busy
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  // Dark on the disabled (light grey)
                                  // button; white would not show.
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.ink,
                                  ),
                                )
                              : Text(_codeSent
                                  ? 'Reset password'
                                  : 'Send reset code'),
                        ),
                        if (_codeSent) ...<Widget>[
                          const SizedBox(height: 4),
                          Center(
                            child: TextButton(
                              onPressed: _busy ? null : _sendCode,
                              child: const Text('Resend code'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Back to log in',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.orange,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The 6-digit reset code, styled to match [LabeledField] but with a numeric
/// keyboard and a 6-character cap.
class _LabeledCodeField extends StatelessWidget {
  final TextEditingController controller;

  const _LabeledCodeField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.only(bottom: 7, left: 2),
          child: Text(
            '6-digit code',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 6,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          decoration: const InputDecoration(
            hintText: '000000',
            counterText: '',
          ),
          validator: (String? v) => (v == null || v.trim().length != 6)
              ? 'Enter the 6-digit code'
              : null,
        ),
      ],
    );
  }
}

/// A labeled new-password field with a show/hide toggle, matching
/// [LabeledField]'s look while adding obscure-text handling that the kit widget
/// does not expose.
class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggle;

  const _PasswordField({
    required this.controller,
    required this.obscure,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.only(bottom: 7, left: 2),
          child: Text(
            'New password',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          decoration: InputDecoration(
            hintText: 'At least 6 characters',
            suffixIcon: IconButton(
              icon: Icon(
                obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AppColors.muted,
                size: 20,
              ),
              onPressed: onToggle,
              tooltip: obscure ? 'Show password' : 'Hide password',
            ),
          ),
          validator: AuthValidators.password,
        ),
      ],
    );
  }
}
