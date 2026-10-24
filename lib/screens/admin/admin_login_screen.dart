import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/admin_service.dart';
import '../../theme.dart';

/// Email/password sign-in for administrators. There is deliberately no
/// register button and no Google sign-in here.
///
/// Wide screens show a branded panel beside the form; narrow screens show
/// the form on its own. The sign-in logic is unchanged.
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AdminService.signIn(_emailController.text, _passwordController.text);
      // AdminGate listens to auth changes and takes over from here.
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = AdminService.friendlyError(e));
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        if (!wide) {
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: AppShadows.card,
                  ),
                  child: _form(context, showLogo: true),
                ),
              ),
            ),
          );
        }

        return Row(
          children: [
            Expanded(flex: 11, child: _brandPanel()),
            Expanded(
              flex: 9,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(40),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: _form(context, showLogo: false),
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  // -------------------------------------------------------------------------
  // Left brand panel (wide screens)
  // -------------------------------------------------------------------------

  Widget _brandPanel() {
    return Container(
      decoration: const BoxDecoration(gradient: AppGradients.hero),
      child: Stack(
        children: [
          // Soft decorative circles
          Positioned(
            right: -90,
            top: -90,
            child: _circle(300, AppColors.primary.withValues(alpha: 0.18)),
          ),
          Positioned(
            left: -70,
            bottom: -70,
            child: _circle(240, Colors.white.withValues(alpha: 0.05)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: AppGradients.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.restaurant_menu,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    const Text('SARAP',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2)),
                  ],
                ),
                const Spacer(),
                const Text('Admin console',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6)),
                const SizedBox(height: 12),
                const Text(
                  'Manage restaurants,\nmenus and your community.',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      height: 1.2,
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Keep Tanauan City listings accurate so every SARAP '
                  'recommendation and meal plan is built on real, up-to-date data.',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 15, height: 1.55),
                ),
                const SizedBox(height: 32),
                _point(Icons.storefront_outlined, 'Restaurants and menu items'),
                const SizedBox(height: 14),
                _point(Icons.insights_outlined, 'Engagement reports and PDFs'),
                const SizedBox(height: 14),
                _point(Icons.verified_user_outlined, 'Moderation and user accounts'),
                const Spacer(),
                const Text('Authorized administrators only.',
                    style: TextStyle(color: Colors.white38, fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _circle(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );

  Widget _point(IconData icon, String text) => Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Text(text,
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      );

  // -------------------------------------------------------------------------
  // Sign-in form (shared by both layouts)
  // -------------------------------------------------------------------------

  Widget _form(BuildContext context, {required bool showLogo}) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showLogo) ...[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: AppGradients.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.admin_panel_settings_outlined,
                  color: Colors.white),
            ),
            const SizedBox(height: 18),
          ],
          Text('Welcome back',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          const Text('Sign in with your administrator account',
              style: TextStyle(color: AppColors.muted, fontSize: 14)),
          const SizedBox(height: 28),
          const Text('Email address',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              hintText: 'admin@example.com',
              prefixIcon: Icon(Icons.mail_outline, color: AppColors.muted),
            ),
            validator: (v) {
              final value = v?.trim() ?? '';
              if (value.isEmpty) return 'Enter your email';
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
                return 'Enter a valid email address';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          const Text('Password',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscure,
            autofillHints: const [AutofillHints.password],
            onFieldSubmitted: (_) => _loading ? null : _submit(),
            decoration: InputDecoration(
              hintText: 'Enter your password',
              prefixIcon:
                  const Icon(Icons.lock_outline, color: AppColors.muted),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppColors.muted,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Enter your password' : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline,
                      color: AppColors.danger, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!,
                        style: const TextStyle(
                            color: AppColors.danger, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white),
                  )
                : const Text('Sign in'),
          ),
          const SizedBox(height: 18),
          const Center(
            child: Text('Access is limited to approved administrators.',
                style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}