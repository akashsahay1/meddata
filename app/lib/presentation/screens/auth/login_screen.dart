import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/auth_service.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/ui_kit.dart';
import 'forgot_password_screen.dart';
import 'signup_screen.dart';
import 'auth_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final String? error = await context.read<AuthService>().login(
          email: _email.text.trim(),
          password: _password.text,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
    // On success the AuthService notifies → the root gate rebuilds to the app.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const AuthHeader(
                    title: 'Welcome back',
                    subtitle: 'Log in to your Meddata account',
                  ),
                  const SizedBox(height: 30),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(AppRadii.cardLg),
                      border: Border.all(color: AppColors.border),
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
                          keyboardType: TextInputType.emailAddress,
                          validator: AuthValidators.email,
                        ),
                        const SizedBox(height: 16),
                        _PasswordField(
                          controller: _password,
                          obscure: _obscure,
                          onToggle: () =>
                              setState(() => _obscure = !_obscure),
                          onSubmitted: (_) => _login(),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 8),
                              minimumSize: const Size(0, 0),
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const ForgotPasswordScreen(),
                              ),
                            ),
                            child: const Text('Forgot password?'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: _busy ? null : _login,
                          child: _busy
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : const Text('Log in'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const Text(
                        "Don't have an account? ",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.muted,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SignupScreen(),
                          ),
                        ),
                        child: const Text(
                          'Sign up',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.orange,
                          ),
                        ),
                      ),
                    ],
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

/// A labeled password field with a show/hide toggle, matching [LabeledField]'s
/// look while adding obscure-text and submit handling that the kit widget does
/// not expose.
class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggle;
  final ValueChanged<String> onSubmitted;

  const _PasswordField({
    required this.controller,
    required this.obscure,
    required this.onToggle,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.only(bottom: 7, left: 2),
          child: Text(
            'Password',
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
          textInputAction: TextInputAction.done,
          onFieldSubmitted: onSubmitted,
          validator: AuthValidators.required,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
          decoration: InputDecoration(
            hintText: 'Your password',
            suffixIcon: IconButton(
              icon: Icon(
                obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AppColors.muted,
                size: 20,
              ),
              onPressed: onToggle,
            ),
          ),
        ),
      ],
    );
  }
}
