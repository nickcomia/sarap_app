import 'dart:async';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../services/firebase_service.dart';
import '../theme.dart';
import 'auth_screen.dart';
import 'home_shell.dart';
import 'onboarding/onboarding_flow.dart';

/// Shown after sign-up and whenever a signed-in account is not verified yet,
/// BEFORE the preference set-up. The user taps the link in the email; this
/// screen notices on its own and moves on.
class VerifyEmailScreen extends StatefulWidget {
  final String email;

  /// true right after registering: go straight to onboarding.
  final bool isNewAccount;
  const VerifyEmailScreen({
    super.key,
    required this.email,
    this.isNewAccount = false,
  });

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  static const _cooldownSeconds = 60;

  Timer? _poll;
  Timer? _tick;
  int _cooldown = _cooldownSeconds; // an email was just sent
  bool _checking = false;
  bool _done = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _startCooldown();
    // Check quietly every few seconds so the screen moves on by itself.
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _check(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _tick?.cancel();
    setState(() => _cooldown = _cooldownSeconds);
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_cooldown <= 1) {
        t.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking || _done) return;
    setState(() => _checking = true);
    var ok = false;
    try {
      ok = await FirebaseService.checkEmailVerified();
    } catch (_) {}
    if (!mounted) return;
    if (ok) {
      _done = true;
      _poll?.cancel();
      _tick?.cancel();
      await _goNext();
      return;
    }
    setState(() {
      _checking = false;
      if (!silent) {
        _message = 'Not verified yet. Tap the link in the email first, '
            'then try again.';
      }
    });
  }

  /// Verified: continue to onboarding (new / unfinished accounts) or Home.
  Future<void> _goNext() async {
    final state = AppState.instance;

    if (widget.isNewAccount) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OnboardingFlow()),
        (route) => false,
      );
      return;
    }

    try {
      await state.loadCurrentUserIfLoggedIn();
    } catch (_) {}
    var done = true;
    try {
      done = await FirebaseService.isOnboardingComplete();
    } catch (_) {}
    if (!mounted) return;

    if (!done) {
      // Nothing real is saved yet, so placeholder defaults must not count.
      state.missingHealthFields = ['age', 'height', 'weight'];
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OnboardingFlow()),
        (route) => false,
      );
      return;
    }

    if (state.mealPlan.isEmpty) {
      try {
        await state.generateMealPlan();
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeShell()),
      (route) => false,
    );
  }

  Future<void> _resend() async {
    if (_cooldown > 0) return;
    try {
      await FirebaseService.resendVerificationEmail();
      if (!mounted) return;
      setState(() => _message = 'A new email is on its way. Check spam too.');
      _startCooldown();
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = e.toString());
    }
  }

  Future<void> _useDifferentAccount() async {
    _poll?.cancel();
    _tick?.cancel();
    await FirebaseService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.mark_email_unread_outlined, size: 64),
                  const SizedBox(height: 16),
                  const Text('Verify your email',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Text(
                    'We sent a verification link to\n${widget.email}\n\n'
                    'Open the email and tap the link. This page will continue '
                    'automatically once you are verified.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 14, height: 1.4, color: AppColors.muted),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _checking ? null : () => _check(),
                      child: _checking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text("I've verified my email"),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _cooldown > 0 ? null : _resend,
                    child: Text(_cooldown > 0
                        ? 'Resend email in ${_cooldown}s'
                        : 'Resend email'),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 6),
                    Text(_message!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12.5)),
                  ],
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _useDifferentAccount,
                    child: const Text('Use a different account'),
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