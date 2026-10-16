import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme.dart';
import '../app_state.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../widgets/forgot_password_sheet.dart';
import '../widgets/change_email_sheet.dart';
import '../services/report_service.dart';
import 'onboarding/onboarding_flow.dart';
import 'splash_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final profile = state.profile;
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                    border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
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
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12.5)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _badge('BMI ${profile.bmi.toStringAsFixed(1)} — ${profile.bmiCategory}',
                              Colors.white, AppColors.primaryDark),
                          _badge('Goal: ${profile.healthGoal.label}',
                              Colors.white.withValues(alpha: 0.9), const Color(0xFF1E9E6B)),
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
              _countCard(context, 'Places saved', '${state.savedRestaurants.length}'),
              const SizedBox(width: 12),
              _countCard(context, 'Meal plans', state.mealPlan.isEmpty ? '0' : '1'),
            ],
          ),
          const SizedBox(height: 22),
          Text('Health Stats', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(18),
              boxShadow: isDark ? null : AppShadows.card,
              border: isDark ? Border.all(color: colors.border, width: 1) : null,
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

          ProfileMenuTile(
            icon: Icons.tune,
            label: 'My preferences',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OnboardingFlow(initialStep: 0)),
            ),
          ),
          ProfileMenuTile(
            icon: Icons.calendar_month_outlined,
            label: 'My meal plans',
            onTap: () => state.setHomeTab(1),
          ),
          ProfileMenuTile(
            icon: Icons.favorite_border,
            label: 'Saved places',
            onTap: () => state.setHomeTab(2),
          ),
          ProfileMenuTile(
            icon: Icons.monitor_weight_outlined,
            label: 'Update BMI & health info',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OnboardingFlow(initialStep: 2)),
            ),
          ),
          const SizedBox(height: 10),
          Divider(color: colors.border),
          ProfileMenuTile(
            icon: Icons.email_outlined,
            label: 'Email my report',
            onTap: () => _emailReport(context, state),
          ),
          const SizedBox(height: 10),
          Divider(color: colors.border),
          ProfileMenuTile(
            icon: Icons.alternate_email_rounded,
            label: 'Change email',
            onTap: () => showChangeEmailSheet(
              context,
              currentEmail: state.profile.email,
            ),
          ),
          ProfileMenuTile(
            icon: Icons.lock_reset_outlined,
            label: 'Reset password',
            onTap: () => showForgotPasswordSheet(
              context,
              initialEmail: state.profile.email,
            ),
          ),
          const SizedBox(height: 10),
          Divider(color: colors.border),
          // Dark mode toggle
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(16),
              boxShadow: isDark ? null : AppShadows.soft,
              border: isDark ? Border.all(color: colors.border, width: 1) : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.chipSelectedBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.dark_mode_outlined, size: 19, color: colors.primaryDark),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text('Dark mode',
                      style: TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w600, color: colors.navy)),
                ),
                Switch(
                  value: state.isDarkMode,
                  activeThumbColor: colors.primary,
                  onChanged: (_) => state.toggleTheme(),
                ),
              ],
            ),
          ),
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

  Widget _countCard(BuildContext context, String label, String value) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: isDark ? null : AppShadows.card,
          border: isDark ? Border.all(color: colors.border, width: 1) : null,
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: colors.navy)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: colors.muted)),
          ],
        ),
      ),
    );
  }

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
}