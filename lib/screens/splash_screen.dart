import 'package:flutter/material.dart';
import '../theme.dart';
import 'auth_screen.dart';

/// Figure 7: Splash / Welcome Screen — introduces the app and its key
/// features with two entry points: "Create free account" and "Log in".
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 3),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Image.asset(
                    'assets/icons/icon.jpg',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 26),
              Text('SARAP',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontSize: 34)),
              const SizedBox(height: 10),
              const Text(
                'Discover restaurants that match your\ntaste, budget, and health goals.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 14.5, height: 1.5),
              ),
              const SizedBox(height: 34),
              const _FeatureRow(
                icon: Icons.location_on_outlined,
                text: 'Find nearby food spots around Tanauan City',
              ),
              const SizedBox(height: 14),
              const _FeatureRow(
                icon: Icons.favorite_border,
                text: 'Get restaurant matches personalized to you',
              ),
              const SizedBox(height: 14),
              const _FeatureRow(
                icon: Icons.calendar_month_outlined,
                text: 'Follow an AI-generated 7-day meal plan',
              ),
              const Spacer(flex: 4),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AuthScreen(startOnRegister: true),
                    ),
                  ),
                  child: const Text('Create free account'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AuthScreen(startOnRegister: false),
                    ),
                  ),
                  child: const Text('Log in'),
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.chipSelectedBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.primaryDark, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 13.5, color: AppColors.navy, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}
