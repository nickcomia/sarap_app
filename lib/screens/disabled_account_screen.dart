import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../theme.dart';
import 'splash_screen.dart';

/// Shown instead of the app when an account has been disabled by the
/// moderation system or by an administrator. The user can send an appeal
/// from here; it is saved in the `appeals` collection (one document per
/// user) for an administrator to review.
class DisabledAccountScreen extends StatefulWidget {
  const DisabledAccountScreen({super.key});

  @override
  State<DisabledAccountScreen> createState() => _DisabledAccountScreenState();
}

class _DisabledAccountScreenState extends State<DisabledAccountScreen> {
  final _message = TextEditingController();
  bool _loading = true; // checking whether an appeal already exists
  bool _sending = false;
  String? _existingStatus; // pending / approved / rejected, if one was sent
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadExistingAppeal();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _loadExistingAppeal() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final doc =
          await FirebaseFirestore.instance.collection('appeals').doc(uid).get();
      if (!mounted) return;
      setState(() {
        _existingStatus = doc.exists ? (doc.data()?['status'] as String?) : null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendAppeal() async {
    if (_sending) return;
    final text = _message.text.trim();
    if (text.length < 20) {
      setState(() => _error =
          'Please explain in at least 20 characters why this was a mistake.');
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _error = 'You are not signed in.');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final app = AppState.instance;
      await FirebaseFirestore.instance.collection('appeals').doc(uid).set({
        'userId': uid,
        'email': app.profile.email,
        'name': app.profile.name,
        'message': text,
        'disabledReason': app.disabledReason,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() {
        _sending = false;
        _existingStatus = 'pending';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'Could not send your appeal. Check your connection and try again.';
      });
    }
  }

  Future<void> _signOut() async {
    await AppState.instance.logoutFromServer();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SplashScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reason = AppState.instance.disabledReason;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.block, size: 72, color: AppColors.primary),
                  const SizedBox(height: 20),
                  Text('Your account has been disabled',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  Text(
                    reason ??
                        'Your account was disabled because of something that '
                            'broke the SARAP community rules.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.muted, height: 1.5),
                  ),
                  const SizedBox(height: 22),
                  if (_loading)
                    const CircularProgressIndicator(strokeWidth: 2.4)
                  else if (_existingStatus == 'pending')
                    _statusBox(
                      colors,
                      'Your appeal was sent and is waiting for review. '
                      'You will be able to use SARAP again if it is approved.',
                    )
                  else if (_existingStatus == 'rejected')
                    _statusBox(
                      colors,
                      'Your appeal was reviewed and the decision stays. '
                      'If you have new information, you can send another appeal below.',
                    ),
                  if (!_loading && _existingStatus != 'pending') ...[
                    const SizedBox(height: 16),
                    Text(
                      'If you think this was a mistake, tell us what happened.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.muted, height: 1.5),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _message,
                      enabled: !_sending,
                      maxLength: 1000,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Write your appeal here…',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 6),
                      Text(_error!,
                          style: TextStyle(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _sending ? null : _sendAppeal,
                        child: _sending
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Send appeal'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _signOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusBox(dynamic colors, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.chipBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.navy, fontSize: 13.5, height: 1.5)),
    );
  }
}