import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../app_state.dart';
import '../../widgets/common.dart';
import '../home_shell.dart';
import 'step1_food_preferences.dart';
import 'step2_taste_budget.dart';
import 'step3_health_profile.dart';
import 'step4_summary.dart';

/// Hosts onboarding Steps 1-4 (Figures 9, 10, 11, 12) inside a single
/// PageView, with a shared step-progress header and a pinned bottom
/// "Continue" button that advances the flow.
class OnboardingFlow extends StatefulWidget {
  final int initialStep; // 0-based, lets Profile deep-link into a step
  const OnboardingFlow({super.key, this.initialStep = 0});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  late final _pageController = PageController(initialPage: widget.initialStep);
  late int _step = widget.initialStep; // 0-based

  static const _titles = [
    'What do you like to eat?',
    'Taste & budget',
    'Tell us about your health',
    'You\'re all set!',
  ];
  static const _subtitles = [
    'Pick the establishments, cuisines, and meal times you\'re most interested in.',
    'Fine-tune spice, sweetness, and how much you like to spend per meal.',
    'This helps SARAP calculate your calorie needs accurately.',
    'Review your profile before we find food near you.',
  ];

  void _next() {
    if (_step < 3) {
      setState(() => _step += 1);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _finish();
    }
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _step -= 1);
    _pageController.previousPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _finish() async {
    final state = AppState.instance;
    await state.syncProfileToServer();
    state.generateMealPlan();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeShell()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _back,
                    icon: const Icon(Icons.arrow_back, color: AppColors.navy),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: StepProgress(
                step: _step + 1,
                totalSteps: 4,
                title: _titles[_step],
                subtitle: _subtitles[_step],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: const [
                  Step1FoodPreferences(),
                  Step2TasteBudget(),
                  Step3HealthProfile(),
                  Step4Summary(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: ElevatedButton(
                onPressed: _next,
                child: Text(_step < 3 ? 'Continue' : 'Find food near me'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

