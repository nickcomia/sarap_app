import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../theme.dart';
import '../app_state.dart';
import '../services/firebase_service.dart';
import 'onboarding/onboarding_flow.dart';
import 'home_shell.dart';
import 'verify_email_screen.dart';

/// Figure 8: Sign In / Register Screen.
/// Tabs switch between the login view and account-creation view; includes
/// email/password fields, a show/hide password toggle, and "Continue with
/// Google".
class AuthScreen extends StatefulWidget {
  final bool startOnRegister;
  const AuthScreen({super.key, this.startOnRegister = false});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late bool isRegister = widget.startOnRegister;
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  final _formKey = GlobalKey<FormState>();

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'Enter your email';
    if (!_emailPattern.hasMatch(value)) return 'Enter a valid email address';
    return null;
  }

  String? _validatePassword(String? v) {
    final value = v ?? '';
    if (value.length < 6) return 'At least 6 characters';
    if (value.length > 20) return 'Max 20 characters';
    if (value != value.trim()) return 'No leading/trailing spaces';
    if (isRegister) {
      final hasLetter = RegExp(r'[A-Za-z]').hasMatch(value);
      final hasNumber = RegExp(r'[0-9]').hasMatch(value);
      if (!hasLetter || !hasNumber) {
        return 'Use at least one letter and one number';
      }
    }
    return null;
  }

  String? _validateConfirmPassword(String? v) {
    if (!isRegister) return null;
    final value = v ?? '';
    if (value.isEmpty) return 'Re-enter your password';
    if (value != _passwordController.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final state = AppState.instance;
    final email = _emailController.text.trim().toLowerCase();
    setState(() => _loading = true);

    try {
      if (isRegister) {
        await state.register(
          name: _nameController.text.trim(),
          email: email,
          password: _passwordController.text,
        );
        if (!mounted) return;
        // The account exists, but the email must be verified BEFORE the
        // preference set-up. The auth screen is removed so Back can't
        // return to it (TC-033).
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => VerifyEmailScreen(email: email, isNewAccount: true),
          ),
          (route) => false,
        );
      } else {
        await state.login(
          email: email,
          password: _passwordController.text,
        );
        if (!mounted) return;

        // Accounts that haven't finished onboarding go back to it (TC-033/034).
        final done = await FirebaseService.isOnboardingComplete();
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

        // Returning users skip straight to the Home / Discovery feed.
        if (state.mealPlan.isEmpty) await state.generateMealPlan();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeShell()),
          (route) => false,
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      // Signed in but not verified yet: show the verify screen instead of
      // sending yet another email from here.
      if (e.message.contains('verify your email') &&
          FirebaseService.currentUid != null) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => VerifyEmailScreen(
                email: FirebaseService.currentEmail ?? email),
          ),
          (route) => false,
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Something went wrong: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty || !_emailPattern.hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid email above first')),
      );
      return;
    }
    try {
      await FirebaseService.sendPasswordResetEmail(email);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    } catch (_) {
      // Ignore other errors — show the same generic message either way.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('If an account exists for that email, a reset link has been sent.'),
      ),
    );
  }

  /// Used by Google sign-in once Firebase has accepted the credential:
  /// saves name/email, loads THIS account's saved profile (so the calorie
  /// target never uses placeholder defaults), then routes to onboarding or
  /// Home depending on the saved onboarding flag.
  Future<void> _finishSocialSignIn({
    required String? displayName,
    required String? email,
  }) async {
    final state = AppState.instance;

    // Never let a previous account's plan linger while this one loads.
    state.mealPlan = [];
    state.planMessage = null;

    // Always reflect the real account details.
    final name = (displayName != null && displayName.trim().isNotEmpty)
        ? displayName.trim()
        : state.profile.name;
    state.profile.name = name;
    state.profile.email = email ?? '';
    state.refresh();

    // Persist name/email (and create the profile doc for new users).
    await FirebaseService.syncGoogleUserDoc(
      name: state.profile.name,
      email: state.profile.email,
    );

    // Load this account's saved health data and preferences first.
    await state.loadProfileFromServer();

    // Decide by the saved onboarding flag, not "is new user" (TC-028/034).
    final done = await FirebaseService.isOnboardingComplete();
    if (!mounted) return;

    if (!done) {
      // Unfinished account: nothing real is saved yet.
      state.missingHealthFields = ['age', 'height', 'weight'];
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OnboardingFlow()),
        (route) => false,
      );
    } else {
      await state.loadSavedFromServer();
      await state.loadMealPlanFromServer();
      if (state.mealPlan.isEmpty) await state.generateMealPlan();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (route) => false,
      );
    }
  }

  String _socialErrorMessage(FirebaseAuthException e, String provider) {
    if (e.code == 'account-exists-with-different-credential') {
      return 'This email already has an account. Please sign in with your '
          'email and password, or the method you used before.';
    }
    if (e.code == 'network-request-failed') {
      return 'Could not reach the internet — check your connection.';
    }
    return '$provider sign-in failed: ${e.message ?? e.code}';
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);
    try {
      final google = GoogleSignIn();
      // Forget the remembered account so Google always shows the account
      // picker (TC-028, TC-029, TC-031).
      await google.signOut();

      final googleUser = await google.signIn();
      if (googleUser == null) return; // cancelled: stay on this screen (TC-029)

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
      if (!mounted) return;

      await _finishSocialSignIn(
        displayName: googleUser.displayName,
        email: googleUser.email,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_socialErrorMessage(e, 'Google'))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Google sign-in failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                const SizedBox(height: 24),
                Text('Welcome to SARAP',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 6),
                const Text('Sign in or create an account to continue',
                    style: TextStyle(color: AppColors.muted, fontSize: 13.5)),
                const SizedBox(height: 26),

                // (1) Sign In tab / (2) Register tab
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.chipBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: _tabButton('Sign In', !isRegister)),
                      Expanded(child: _tabButton('Register', isRegister)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Name field — only needed for account creation.
                if (isRegister) ...[
                  const Text('Full name',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(hintText: 'Juan Dela Cruz'),
                    validator: (v) =>
                        (isRegister && (v == null || v.trim().isEmpty)) ? 'Enter your name' : null,
                  ),
                  const SizedBox(height: 16),
                ],

                // (3) Email address textbox
                const Text('Email address',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  maxLength: 254, // RFC 5321 max email length
                  decoration: const InputDecoration(
                    hintText: 'you@example.com',
                    counterText: '', // hide the 0/254 counter — not useful here
                  ),
                  validator: _validateEmail,
                ),
                const SizedBox(height: 16),

                // (4) Password textbox + (5) show/hide toggle
                const Text('Password',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscure,
                  maxLength: 20,
                  decoration: InputDecoration(
                    hintText: 'Enter your password',
                    counterText: '', // hide the 0/20 counter — not useful here
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: AppColors.muted,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: _validatePassword,
                ),

                // (New) Confirm password — only needed for account creation.
                if (isRegister) ...[
                  const SizedBox(height: 16),
                  const Text('Confirm password',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirm,
                    maxLength: 20,
                    decoration: InputDecoration(
                      hintText: 'Re-enter your password',
                      counterText: '',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: AppColors.muted,
                        ),
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    validator: _validateConfirmPassword,
                  ),
                ],

                if (!isRegister) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _sendPasswordReset,
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      ),
                      child: const Text('Forgot password?'),
                    ),
                  ),
                ],
                const SizedBox(height: 26),

                // (6) Sign in button
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        )
                      : Text(isRegister ? 'Create account' : 'Sign in'),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Expanded(child: Divider(color: AppColors.border)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text('or', style: TextStyle(color: AppColors.muted)),
                    ),
                    Expanded(child: Divider(color: AppColors.border)),
                  ],
                ),
                const SizedBox(height: 16),

                // (7) Continue with Google button
                OutlinedButton.icon(
                  onPressed: _loading ? null : _signInWithGoogle,
                  icon: const Icon(Icons.g_mobiledata, size: 26),
                  label: const Text('Continue with Google'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabButton(String label, bool active) {
    return GestureDetector(
      onTap: () => setState(() => isRegister = label == 'Register'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          boxShadow: active
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6)]
              : [],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: active ? AppColors.primaryDark : AppColors.muted,
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }
}