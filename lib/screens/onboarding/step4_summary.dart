import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../app_state.dart';
import '../../models.dart';

class Step4Summary extends StatelessWidget {
  const Step4Summary({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = AppState.instance.profile;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _stat('BMI', profile.bmi.toStringAsFixed(1), profile.bmiCategory),
                    _divider(),
                    _stat('Daily calorie target', '${profile.dailyCalorieTarget}', 'kcal / day'),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _stat(
                      'Calorie deficit/surplus',
                      profile.calorieDeficitOrSurplus > 0
                          ? '+${profile.calorieDeficitOrSurplus}'
                          : '${profile.calorieDeficitOrSurplus}',
                      'kcal / day',
                    ),
                    _divider(),
                    _stat('Goal BMI', profile.goalBmi.toStringAsFixed(1), 'target'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _summaryTile(
            'Establishments',
            profile.establishmentTypes.isEmpty
                ? 'No preference'
                : profile.establishmentTypes.join(', '),
          ),
          _summaryTile(
            'Cuisines',
            profile.cuisines.isEmpty ? 'No preference' : profile.cuisines.join(', '),
          ),
          _summaryTile(
            'Meal times',
            profile.mealTypes.isEmpty ? 'No preference' : profile.mealTypes.join(', '),
          ),
          _summaryTile(
            'Budget per meal',
            profile.maxBudget >= 500 ? 'Up to ₱500+' : 'Up to ₱${profile.maxBudget.round()}',
          ),
          _summaryTile(
            'Dietary restrictions',
            profile.dietaryRestrictions.isEmpty
                ? 'None'
                : profile.dietaryRestrictions.join(', '),
          ),
          _summaryTile('Health goal', profile.healthGoal.label),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 46,
        color: Colors.white24,
        margin: const EdgeInsets.symmetric(horizontal: 12),
      );

  Widget _stat(String label, String value, String sub) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 11.5)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          Text(sub, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _summaryTile(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.chipBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
