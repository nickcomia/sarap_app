import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/firebase_service.dart';

/// Opens the "Change email" bottom sheet.
/// Usage: showChangeEmailSheet(context, currentEmail: state.profile.email);
Future<void> showChangeEmailSheet(BuildContext context, {required String currentEmail}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ChangeEmailSheet(currentEmail: currentEmail),
  );
}

class _ChangeEmailSheet extends StatefulWidget {
  final String currentEmail;
  const _ChangeEmailSheet({required this.currentEmail});

  @override
  State<_ChangeEmailSheet> createState() => _ChangeEmailSheetState();
}

class _ChangeEmailSheetState extends State<_ChangeEmailSheet> {
  final _newEmail = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _newEmail.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _newEmail.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    if (email.toLowerCase() == widget.currentEmail.toLowerCase()) {
      setState(() => _error = 'That is already your email.');
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your current password to confirm.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await FirebaseService.requestEmailChange(
        newEmail: email,
        currentPassword: _password.text,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _sent = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException
            ? e.message
            : 'Could not start the email change. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    InputDecoration field(String hint, IconData icon, {Widget? suffix}) {
      return InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: colors.muted),
        prefixIcon: Icon(icon, color: colors.muted),
        suffixIcon: suffix,
        filled: true,
        fillColor: colors.chipBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      );
    }

    Widget gradientButton(String label, VoidCallback? onPressed, {bool busy = false}) {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppGradients.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                  )
                : Text(label,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: colors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: AppGradients.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: colors.primary.withValues(alpha: 0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(
                      _sent ? Icons.mark_email_read_outlined : Icons.alternate_email_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _sent ? 'Verify your new email' : 'Change email address',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _sent
                        ? 'We sent a verification link to ${_newEmail.text.trim()}. '
                            'Your email only changes after you open that link. '
                            'Until then, keep signing in with ${widget.currentEmail}.'
                        : 'Current: ${widget.currentEmail}\n'
                            "We'll send a verification link to your new address.",
                    style: TextStyle(color: colors.muted, fontSize: 13.5, height: 1.45),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 22),
                  if (!_sent) ...[
                    TextField(
                      controller: _newEmail,
                      keyboardType: TextInputType.emailAddress,
                      style: TextStyle(color: colors.navy),
                      decoration: field('New email address', Icons.mail_outline_rounded),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: _hidePassword,
                      style: TextStyle(color: colors.navy),
                      onSubmitted: (_) => _submit(),
                      decoration: field(
                        'Current password',
                        Icons.lock_outline_rounded,
                        suffix: IconButton(
                          icon: Icon(
                            _hidePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: colors.muted,
                          ),
                          onPressed: () => setState(() => _hidePassword = !_hidePassword),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(_error!,
                            style: TextStyle(color: colors.danger, fontSize: 12.5)),
                      ),
                    ],
                    const SizedBox(height: 18),
                    gradientButton('Send verification link', _loading ? null : _submit,
                        busy: _loading),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Cancel', style: TextStyle(color: colors.muted)),
                    ),
                  ] else
                    gradientButton('Done', () => Navigator.of(context).pop()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}