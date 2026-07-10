import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/auth_service.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const AuthHeader(
                  title: 'Forgot password',
                  subtitle: 'We will email you a 6-digit reset code',
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _email,
                  enabled: !_codeSent,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                  validator: AuthValidators.email,
                ),
                if (_codeSent) ...<Widget>[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: '6-digit code',
                      prefixIcon: Icon(Icons.pin_outlined),
                      counterText: '',
                    ),
                    validator: (String? v) =>
                        (v == null || v.trim().length != 6)
                            ? 'Enter the 6-digit code'
                            : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'New password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: AuthValidators.password,
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _busy ? null : (_codeSent ? _reset : _sendCode),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_codeSent ? 'Reset password' : 'Send reset code'),
                ),
                if (_codeSent) ...<Widget>[
                  const SizedBox(height: 8),
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
        ),
      ),
    );
  }
}
