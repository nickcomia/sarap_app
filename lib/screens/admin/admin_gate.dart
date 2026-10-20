import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/admin_service.dart';
import '../../theme.dart';
import 'admin_home_screen.dart';
import 'admin_login_screen.dart';

/// Decides what the admin site shows:
///   signed out            -> login
///   signed in, not admin  -> "not authorized" with a sign-out button
///   signed in, admin      -> dashboard
class AdminGate extends StatelessWidget {
  const AdminGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AdminService.authChanges,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Loading();
        }
        final user = snap.data;
        if (user == null) return const AdminLoginScreen();
        // Keyed by uid so switching accounts re-runs the admin check.
        return _AdminCheck(key: ValueKey(user.uid), email: user.email ?? '');
      },
    );
  }
}

class _AdminCheck extends StatefulWidget {
  final String email;
  const _AdminCheck({super.key, required this.email});

  @override
  State<_AdminCheck> createState() => _AdminCheckState();
}

class _AdminCheckState extends State<_AdminCheck> {
  late final Future<bool> _isAdmin = AdminService.isCurrentUserAdmin();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isAdmin,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _Loading();
        }
        if (snap.data == true) return const AdminHomeScreen();
        return _NotAuthorized(email: widget.email);
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _NotAuthorized extends StatelessWidget {
  final String email;
  const _NotAuthorized({required this.email});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 54, color: AppColors.muted),
                const SizedBox(height: 14),
                Text('Not authorized',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  '$email is not an administrator account.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, fontSize: 13.5),
                ),
                const SizedBox(height: 22),
                const ElevatedButton(
                  onPressed: AdminService.signOut,
                  child: Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
