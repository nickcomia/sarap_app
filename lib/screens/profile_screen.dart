import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../app_state.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../services/firebase_service.dart';
import '../services/report_service.dart';
import 'onboarding/onboarding_flow.dart';
import 'splash_screen.dart';

/// Figure 16: Profile Screen.
/// Shows name/location/BMI badge/goal, saved & meal-plan counts, a Health
/// Stats card, and the account menu: (1) My preferences, (2) My meal
/// plans, (3) Saved places, (4) Update BMI & health info, (5) Sign out.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final profile = state.profile;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gradient profile header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppGradients.hero,
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppShadows.card,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white,
                    child: Text(
                      profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                      style: const TextStyle(
                          color: AppColors.primaryDark, fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile.name,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text('Tanauan City, Batangas',
                          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12.5)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _badge('BMI ${profile.bmi.toStringAsFixed(1)} — ${profile.bmiCategory}',
                              Colors.white, AppColors.primaryDark),
                          _badge('Goal: ${profile.healthGoal.label}',
                              Colors.white.withOpacity(0.9), const Color(0xFF1E9E6B)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _countCard('Places saved', '${state.savedRestaurants.length}'),
              const SizedBox(width: 12),
              _countCard('Meal plans', state.mealPlan.isEmpty ? '0' : '1'),
            ],
          ),
          const SizedBox(height: 22),
          Text('Health Stats', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(18),
              boxShadow: AppShadows.card,
            ),
            child: Row(
              children: [
                StatPill(label: 'Current BMI', value: profile.bmi.toStringAsFixed(1)),
                const SizedBox(width: 10),
                StatPill(label: 'Target BMI', value: profile.goalBmi.toStringAsFixed(1)),
                const SizedBox(width: 10),
                StatPill(label: 'Daily kcal target', value: '${profile.dailyCalorieTarget}'),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text('Account', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),

          // (1) My preferences
          ProfileMenuTile(
            icon: Icons.tune,
            label: 'My preferences',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OnboardingFlow(initialStep: 0)),
            ),
          ),
          // (2) My meal plans
          ProfileMenuTile(
            icon: Icons.calendar_month_outlined,
            label: 'My meal plans',
            onTap: () => state.setHomeTab(1),
          ),
          // (3) Saved places
          ProfileMenuTile(
            icon: Icons.favorite_border,
            label: 'Saved places',
            onTap: () => state.setHomeTab(2),
          ),
          // (4) Update BMI & health info
          ProfileMenuTile(
            icon: Icons.monitor_weight_outlined,
            label: 'Update BMI & health info',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OnboardingFlow(initialStep: 2)),
            ),
          ),
          const SizedBox(height: 10),
          const Divider(color: AppColors.border),
          ProfileMenuTile(
            icon: Icons.email_outlined,
            label: 'Email my report',
            onTap: () => _emailReport(context, state),
          ),
          const SizedBox(height: 10),
          const Divider(color: AppColors.border),
          ProfileMenuTile(
            icon: Icons.lock_reset_outlined,
            label: 'Reset password',
            onTap: () => _resetPassword(context, state),
          ),
          const SizedBox(height: 10),
          const Divider(color: AppColors.border),
          // Dark mode toggle
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppShadows.soft,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.chipSelectedBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.dark_mode_outlined,
                      size: 19, color: AppColors.primaryDark),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text('Dark mode',
                      style: TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.navy)),
                ),
                Switch(
                  value: state.isDarkMode,
                  activeColor: AppColors.primary,
                  onChanged: (_) => state.toggleTheme(),
                ),
              ],
            ),
          ),
          // (5) Sign out button
          ProfileMenuTile(
            icon: Icons.logout,
            label: 'Sign out',
            danger: true,
            onTap: () async {
              await state.logoutFromServer();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const SplashScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 11)),
    );
  }

  Widget _countCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.navy)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }

  // Builds a plain-text report of the profile + meal plan and opens it
  // in the device's own email app via a mailto: link, pre-filled and
  // ready to send. (This composes through the user's own mail client
  // rather than a server-triggered send — no SMTP/email-provider account
  // needed for the app itself.)
  Future<void> _emailReport(BuildContext context, AppState state) async {
    final report = ReportService.buildReport(state.profile, state.mealPlan);
    final uri = Uri(
      scheme: 'mailto',
      path: state.profile.email,
      query: 'subject=${Uri.encodeComponent('My SARAP Meal Plan Report')}'
          '&body=${Uri.encodeComponent(report)}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No email app found on this device')),
      );
    }
  }

  Future<void> _resetPassword(BuildContext context, AppState state) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset password'),
        content: Text(
          'Send a password reset link to ${state.profile.email}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Send link'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await FirebaseService.sendPasswordResetEmail(state.profile.email);
    } catch (_) {
      // Ignore — show the same message either way.
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Password reset email sent — check your inbox.')),
    );
  }
}