import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'student_email.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false, _busy = false, _obscure = true;
  String? _message;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final client = Supabase.instance.client;
      final email = _email.text.trim().toLowerCase();
      if (_signUp) {
        final response = await client.auth.signUp(
          email: email,
          password: _password.text,
        );
        if (mounted && response.session == null) {
          setState(() {
            _signUp = false;
            _message =
                'Account created. Instant sign-in is unavailable because email confirmation is enabled in the account service.';
          });
        }
      } else {
        await client.auth.signInWithPassword(
          email: email,
          password: _password.text,
        );
      }
      _password.clear();
    } on AuthException catch (error) {
      if (mounted) {
        setState(() => _message = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Unable to reach the account service. Try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _form,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'UTRGV-GO',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _signUp
                          ? 'Create an account with your .edu email.'
                          : 'Sign in with your .edu email.',
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _email,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'School email',
                        hintText: 'example@utrgv.edu',
                      ),
                      validator: (v) => StudentEmail.isEligible(v ?? '')
                          ? null
                          : 'Use a valid email address ending in .edu.',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: _obscure,
                      autofillHints: [
                        _signUp
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure ? Icons.visibility : Icons.visibility_off,
                          ),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Enter your password.';
                        }
                        if (_signUp && v.length < 8) {
                          return 'Use at least 8 characters.';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) {
                        _submit();
                      },
                    ),
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(_message!),
                        ),
                      ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(
                        _busy
                            ? 'Please wait...'
                            : _signUp
                            ? 'Create account'
                            : 'Sign in',
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _signUp = !_signUp;
                              _message = null;
                              _password.clear();
                            }),
                      child: Text(
                        _signUp
                            ? 'Already have an account? Sign in'
                            : 'Create an account',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
