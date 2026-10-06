import '../models.dart';

/// Builds a plain-text report summarizing the user's health profile and
/// current 7-day meal plan — used for the "Email my report" feature.
class ReportService {
  static String buildReport(UserProfile profile, List<DayPlan> mealPlan) {
    final buffer = StringBuffer();

    buffer.writeln('SARAP — Personalized Meal Plan Report');
    buffer.writeln('Generated for: ${profile.name}');
    buffer.writeln('=' * 40);
    buffer.writeln();

    buffer.writeln('HEALTH PROFILE');
    buffer.writeln('BMI: ${profile.bmi.toStringAsFixed(1)} (${profile.bmiCategory})');
    buffer.writeln('Goal: ${profile.healthGoal.label}');
    buffer.writeln('Daily calorie target: ${profile.dailyCalorieTarget} kcal');
    buffer.writeln('Target BMI: ${profile.goalBmi.toStringAsFixed(1)}');
    buffer.writeln();

    buffer.writeln('PREFERENCES');
    buffer.writeln('Cuisines: ${profile.cuisines.isEmpty ? "No preference" : profile.cuisines.join(", ")}');
    buffer.writeln(
        'Dietary restrictions: ${profile.dietaryRestrictions.isEmpty ? "None" : profile.dietaryRestrictions.join(", ")}');
    buffer.writeln('Budget per meal: up to ₱${profile.maxBudget.round()}');
    buffer.writeln();

    if (mealPlan.isNotEmpty) {
      buffer.writeln('7-DAY MEAL PLAN');
      for (final day in mealPlan) {
        buffer.writeln('-' * 30);
        buffer.writeln(day.dayLabel);
        for (final meal in day.meals) {
          if (meal.isFilled) {
            buffer.writeln(
                '  ${meal.slot.label}: ${meal.dishName} (${meal.restaurantName}) — ${meal.calories} kcal');
          } else {
            buffer.writeln('  ${meal.slot.label}: not yet picked');
          }
        }
        buffer.writeln('  Total: ${day.totalCalories} kcal');
      }
    }

    buffer.writeln();
    buffer.writeln('Sent from the SARAP app.');
    return buffer.toString();
  }
}
