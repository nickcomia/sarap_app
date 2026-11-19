import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_state.dart';
import '../theme.dart';
import 'splash_screen.dart';

/// Shown instead of the app when an account has been disabled by the
/// moderation system or by an administrator.
class DisabledAccountScreen extends StatelessWidget {
  const DisabledAccountScreen({super.key});

  /// Replace with your own appeal form (a Google Form works) or a mailto: link.
  static const appealUrl = 'https://forms.gle/REPLACE_WITH_YOUR_FORM';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reason = AppState.instance.disabledReason;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
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
                const SizedBox(height: 8),
                Text(
                  'If you think this was a mistake, you can appeal the decision.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.muted, height: 1.5),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => launchUrl(Uri.parse(appealUrl),
                      mode: LaunchMode.externalApplication),
                  child: const Text('Appeal this decision'),
                ),
                TextButton(
                  onPressed: () async {
                    await AppState.instance.logoutFromServer();
                    if (!context.mounted) return;
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const SplashScreen()),
                      (_) => false,
                    );
                  },
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}