import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'student_email.dart';
import 'field_notes.dart';

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
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(
          context,
        ).textTheme.apply(fontFamily: 'Inter', bodyColor: journalInk),
        colorScheme: ColorScheme.fromSeed(
          seedColor: journalInk,
          brightness: Brightness.light,
          primary: journalInk,
          secondary: journalOrange,
          surface: journalPaper,
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: journalInk,
          selectionColor: Color(0x44E85C08),
          selectionHandleColor: journalInk,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8F5EB),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          hintStyle: const TextStyle(color: Color(0xFF73786F), fontSize: 15),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: journalInk),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: journalInk),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: journalInk, width: 2),
          ),
          errorMaxLines: 3,
        ),
      ),
      child: Scaffold(
        backgroundColor: journalPaper,
        body: JournalPaper(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, viewport) => SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: viewport.maxHeight),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 10, 22, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const JournalMasthead(),
                            const SizedBox(height: 14),
                            Stack(
                              clipBehavior: Clip.hardEdge,
                              children: [
                                if (scale <= 1.3)
                                  const Positioned(
                                    right: -16,
                                    top: 0,
                                    child: JournalMapStrip(),
                                  ),
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    LayoutBuilder(
                                      builder: (context, bounds) => Padding(
                                        padding: const EdgeInsets.only(
                                          top: 20,
                                          bottom: 26,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            ConstrainedBox(
                                              constraints: BoxConstraints(
                                                maxWidth: scale > 1.3
                                                    ? bounds.maxWidth
                                                    : bounds.maxWidth * .86,
                                              ),
                                              child: Text(
                                                'Every walk,\na new story.',
                                                style: journalType(
                                                  bounds.maxWidth < 330
                                                      ? 43
                                                      : 48,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 18),
                                            const Text(
                                              'SAME CAMPUS.\nMORE TO EXPLORE.',
                                              style: TextStyle(
                                                fontSize: 10,
                                                letterSpacing: 2.6,
                                                height: 1.7,
                                                color: journalInk,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Transform.rotate(
                                              angle: -.06,
                                              child: Container(
                                                width: 55,
                                                height: 2,
                                                color: journalOrange,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: journalOrange,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 15,
                                            vertical: 7,
                                          ),
                                          child: Text(
                                            _signUp
                                                ? 'JOIN THE ADVENTURE'
                                                : 'SIGN IN',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 3,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    Form(
                                      key: _form,
                                      child: AutofillGroup(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Text(
                                              'School email',
                                              style: journalType(19),
                                            ),
                                            const SizedBox(height: 7),
                                            Semantics(
                                              label: 'School email',
                                              child: TextFormField(
                                                controller: _email,
                                                enabled: !_busy,
                                                keyboardType:
                                                    TextInputType.emailAddress,
                                                textInputAction:
                                                    TextInputAction.next,
                                                autocorrect: false,
                                                style: const TextStyle(
                                                  color: journalInk,
                                                  fontSize: 16,
                                                ),
                                                autofillHints: const [
                                                  AutofillHints.email,
                                                ],
                                                decoration:
                                                    const InputDecoration(
                                                      hintText:
                                                          'name@school.edu',
                                                    ),
                                                validator: (v) =>
                                                    StudentEmail.isEligible(
                                                      v ?? '',
                                                    )
                                                    ? null
                                                    : 'Use a valid email address ending in .edu.',
                                              ),
                                            ),
                                            const SizedBox(height: 17),
                                            Text(
                                              'Password',
                                              style: journalType(19),
                                            ),
                                            const SizedBox(height: 7),
                                            Semantics(
                                              label: 'Password',
                                              child: TextFormField(
                                                controller: _password,
                                                enabled: !_busy,
                                                obscureText: _obscure,
                                                textInputAction:
                                                    TextInputAction.done,
                                                style: const TextStyle(
                                                  color: journalInk,
                                                  fontSize: 16,
                                                ),
                                                autofillHints: [
                                                  _signUp
                                                      ? AutofillHints
                                                            .newPassword
                                                      : AutofillHints.password,
                                                ],
                                                decoration: InputDecoration(
                                                  hintText: _signUp
                                                      ? 'At least 8 characters'
                                                      : 'Enter your password',
                                                  suffixIcon: IconButton(
                                                    tooltip: _obscure
                                                        ? 'Show password'
                                                        : 'Hide password',
                                                    onPressed: _busy
                                                        ? null
                                                        : () => setState(
                                                            () => _obscure =
                                                                !_obscure,
                                                          ),
                                                    icon: Icon(
                                                      _obscure
                                                          ? Icons
                                                                .visibility_outlined
                                                          : Icons
                                                                .visibility_off_outlined,
                                                      color: journalInk,
                                                      size: 22,
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
                                                onFieldSubmitted: (_) =>
                                                    _submit(),
                                              ),
                                            ),
                                            if (_message != null)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 14,
                                                ),
                                                child: Semantics(
                                                  liveRegion: true,
                                                  child: Text(
                                                    _message!,
                                                    style: const TextStyle(
                                                      color: journalInk,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            const SizedBox(height: 20),
                                            FilledButton(
                                              style: FilledButton.styleFrom(
                                                backgroundColor: journalInk,
                                                foregroundColor: journalPaper,
                                                minimumSize:
                                                    const Size.fromHeight(54),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 10,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(5),
                                                ),
                                              ),
                                              onPressed: _busy ? null : _submit,
                                              child: Row(
                                                children: [
                                                  const SizedBox(width: 30),
                                                  Expanded(
                                                    child: Text(
                                                      _busy
                                                          ? 'Please wait...'
                                                          : _signUp
                                                          ? 'Create account'
                                                          : 'Sign in',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: journalType(
                                                        24,
                                                        color: journalPaper,
                                                      ),
                                                    ),
                                                  ),
                                                  Container(
                                                    width: 32,
                                                    height: 32,
                                                    decoration:
                                                        const BoxDecoration(
                                                          color: journalOrange,
                                                          shape:
                                                              BoxShape.circle,
                                                        ),
                                                    child: _busy
                                                        ? const Padding(
                                                            padding:
                                                                EdgeInsets.all(
                                                                  8,
                                                                ),
                                                            child:
                                                                CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2,
                                                                  color: Colors
                                                                      .white,
                                                                ),
                                                          )
                                                        : const Icon(
                                                            Icons.arrow_forward,
                                                            color: Colors.white,
                                                            size: 23,
                                                          ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Wrap(
                                              alignment: WrapAlignment.center,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                Text(
                                                  _signUp
                                                      ? 'Already exploring?'
                                                      : 'New here?',
                                                  style: journalType(16),
                                                ),
                                                TextButton(
                                                  style: TextButton.styleFrom(
                                                    foregroundColor:
                                                        const Color(0xFFB74300),
                                                    minimumSize: const Size(
                                                      48,
                                                      48,
                                                    ),
                                                  ),
                                                  onPressed: _busy
                                                      ? null
                                                      : () => setState(() {
                                                          _signUp = !_signUp;
                                                          _message = null;
                                                          _password.clear();
                                                          _form.currentState
                                                              ?.reset();
                                                        }),
                                                  child: Text(
                                                    _signUp
                                                        ? 'Sign in'
                                                        : 'Create an account',
                                                    style:
                                                        journalType(
                                                          16,
                                                          color: const Color(
                                                            0xFFB74300,
                                                          ),
                                                        ).copyWith(
                                                          decoration:
                                                              TextDecoration
                                                                  .underline,
                                                          decorationColor:
                                                              journalOrange,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Divider(
                              height: 1,
                              color: journalInk.withValues(alpha: .4),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(top: 14),
                              child: Text(
                                'All .edu emails welcome.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: journalInk,
                                  fontSize: 10,
                                  letterSpacing: 2,
                                ),
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
          ),
        ),
      ),
    );
  }
}
