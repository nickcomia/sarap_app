import 'dart:math';

enum HealthGoal { lose, maintain, gain }

extension HealthGoalLabel on HealthGoal {
  String get label {
    switch (this) {
      case HealthGoal.lose:
        return 'Lose weight';
      case HealthGoal.maintain:
        return 'Maintain weight';
      case HealthGoal.gain:
        return 'Gain weight';
    }
  }
}

enum ActivityLevel { sedentary, light, moderate, active }

extension ActivityLevelData on ActivityLevel {
  String get label {
    switch (this) {
      case ActivityLevel.sedentary:
        return 'Sedentary';
      case ActivityLevel.light:
        return 'Light';
      case ActivityLevel.moderate:
        return 'Moderate';
      case ActivityLevel.active:
        return 'Active';
    }
  }

  // Standard activity multipliers used to convert BMR into daily energy
  // expenditure (TDEE).
  double get multiplier {
    switch (this) {
      case ActivityLevel.sedentary:
        return 1.2;
      case ActivityLevel.light:
        return 1.375;
      case ActivityLevel.moderate:
        return 1.55;
      case ActivityLevel.active:
        return 1.725;
    }
  }
}

enum BiologicalSex { female, male, notSaid }

extension BiologicalSexLabel on BiologicalSex {
  String get label {
    switch (this) {
      case BiologicalSex.female:
        return 'Female';
      case BiologicalSex.male:
        return 'Male';
      case BiologicalSex.notSaid:
        return 'Prefer not to say';
    }
  }
}

/// Holds every preference collected across the 4-step onboarding flow
/// (Figures 9-12) plus the derived health metrics used throughout the app.
class UserProfile {
  String name;
  String email;

  // Step 1 — Food Preferences
  Set<String> establishmentTypes = {};
  Set<String> cuisines = {};
  Set<String> mealTypes = {};

  // Step 2 — Taste & Budget
  double spiciness = 1; // 0..4 (None..Very Spicy)
  double sweetness = 1; // 0..4 (None..Very Sweet)
  double maxBudget = 150; // PHP, 30..500+
  Set<String> dietaryRestrictions = {};

  // Step 3 — Health Profile
  int age = 21;
  double heightCm = 165;
  double weightKg = 60;
  BiologicalSex sex = BiologicalSex.notSaid;
  ActivityLevel activityLevel = ActivityLevel.moderate;
  HealthGoal healthGoal = HealthGoal.maintain;

  /// Target body weight for Lose/Gain goals, set by the user in onboarding.
  /// Null means "unset" — callers fall back to a generic estimate.
  double? goalWeightKg;

  UserProfile({this.name = 'Juan Dela Cruz', this.email = ''});

  /// True only when age, height and weight are all within believable ranges.
  /// Used by AppState to decide whether a calorie target can be trusted.
  bool get hasValidHealthData =>
      age >= 10 && age <= 100 &&
      heightCm >= 100 && heightCm <= 250 &&
      weightKg >= 25 && weightKg <= 300;

  double get bmi {
    final heightM = heightCm / 100;
    if (heightM <= 0) return 0;
    return weightKg / (heightM * heightM);
  }

  /// WHO BMI classification standard (World Health Organization,
  /// international cutoffs: <18.5 Underweight, 18.5-24.9 Normal,
  /// 25-29.9 Overweight, ≥30 Obese).
  String get bmiCategory {
    final b = bmi;
    if (b < 18.5) return 'Underweight';
    if (b < 25) return 'Normal';
    if (b < 30) return 'Overweight';
    return 'Obese';
  }

  /// Mifflin-St Jeor equation, as referenced in the manuscript's glossary.
  double get bmr {
    final base = (10 * weightKg) + (6.25 * heightCm) - (5 * age);
    switch (sex) {
      case BiologicalSex.male:
        return base + 5;
      case BiologicalSex.female:
        return base - 161;
      case BiologicalSex.notSaid:
        return base - 78; // neutral midpoint
    }
  }

  double get tdee => bmr * activityLevel.multiplier;

  /// Default horizon (in weeks) used to translate a total weight goal into
  /// a daily calorie adjustment, when the user hasn't picked their own pace.
  static const int _defaultGoalTimeframeWeeks = 12;

  /// 1 kg of body fat ≈ 7700 kcal — the standard conversion used to turn a
  /// weekly weight-change rate into a daily calorie deficit/surplus.
  static const double _kcalPerKg = 7700;

  /// Safe weekly rate bounds (kg/week), per standard nutrition guidance:
  /// up to ~0.75 kg/week for loss, ~0.5 kg/week for gain. Below the low end,
  /// we still apply a sensible minimum so the plan has *some* effect.
  static const double _minLossRateKgPerWeek = 0.25;
  static const double _maxLossRateKgPerWeek = 0.75;
  static const double _minGainRateKgPerWeek = 0.15;
  static const double _maxGainRateKgPerWeek = 0.5;

  /// The weight actually being targeted. Falls back to a generic ±5kg
  /// guess if the user picked Lose/Gain but hasn't entered a goal weight
  /// yet, so the app still behaves sensibly before that field is filled.
  double get _effectiveGoalWeightKg {
    if (goalWeightKg != null) return goalWeightKg!;
    switch (healthGoal) {
      case HealthGoal.lose:
        return weightKg - 5;
      case HealthGoal.gain:
        return weightKg + 5;
      case HealthGoal.maintain:
        return weightKg;
    }
  }

  int get calorieDeficitOrSurplus {
    switch (healthGoal) {
      case HealthGoal.maintain:
        return 0;
      case HealthGoal.lose:
        final totalLossKg = (weightKg - _effectiveGoalWeightKg).clamp(0, 999);
        if (totalLossKg <= 0) return -500; // goal weight isn't actually lower — fall back
        var ratePerWeek = totalLossKg / _defaultGoalTimeframeWeeks;
        ratePerWeek = ratePerWeek.clamp(_minLossRateKgPerWeek, _maxLossRateKgPerWeek);
        final dailyDeficit = (ratePerWeek * _kcalPerKg) / 7;
        return -dailyDeficit.round();
      case HealthGoal.gain:
        final totalGainKg = (_effectiveGoalWeightKg - weightKg).clamp(0, 999);
        if (totalGainKg <= 0) return 300; // goal weight isn't actually higher — fall back
        var ratePerWeek = totalGainKg / _defaultGoalTimeframeWeeks;
        ratePerWeek = ratePerWeek.clamp(_minGainRateKgPerWeek, _maxGainRateKgPerWeek);
        final dailySurplus = (ratePerWeek * _kcalPerKg) / 7;
        return dailySurplus.round();
    }
  }

  int get dailyCalorieTarget => (tdee + calorieDeficitOrSurplus).round();

  /// Estimated weeks to reach the goal weight at the calculated safe rate —
  /// useful to show the user a realistic timeframe instead of just a number.
  int? get estimatedWeeksToGoal {
    if (healthGoal == HealthGoal.maintain || goalWeightKg == null) return null;
    final diffKg = (weightKg - goalWeightKg!).abs();
    if (diffKg <= 0) return 0;
    final dailyAdjustment = calorieDeficitOrSurplus.abs();
    if (dailyAdjustment == 0) return null;
    final weeklyKgChange = (dailyAdjustment * 7) / _kcalPerKg;
    return (diffKg / weeklyKgChange).ceil();
  }

  double get goalBmi {
    final heightM = heightCm / 100;
    if (heightM <= 0) return 22.0;
    final target = healthGoal == HealthGoal.maintain ? weightKg : _effectiveGoalWeightKg;
    final rawBmi = target / (heightM * heightM);
    return max(18.5, min(24.9, rawBmi));
  }
}

class Restaurant {
  final String id;
  final String name;
  final String type; // Café, Restaurant, Karinderyá, Street food
  final String cuisine;
  double distanceKm; // live-updated from GPS once location is available
  int matchPercent; // computed live by MatchingEngine against the user's profile
  final String priceRange; // ₱, ₱₱, ₱₱₱
  final double rating;
  final String address;
  final String description;
  final List<String> tags;
  final int accentColorValue; // fallback color swatch used until a real photo exists
  final double latitude;
  final double longitude;
  final String? imageUrl; // real cover photo, uploaded via the admin screen
  bool isSaved;

  Restaurant({
    required this.id,
    required this.name,
    required this.type,
    required this.cuisine,
    required this.distanceKm,
    required this.matchPercent,
    required this.priceRange,
    required this.rating,
    required this.address,
    required this.description,
    required this.tags,
    required this.accentColorValue,
    this.latitude = 14.0863, // defaults to roughly Tanauan City center
    this.longitude = 121.1497,
    this.imageUrl,
    this.isSaved = false,
  });
}

/// A single dish/product on a restaurant's menu — added via the in-app
/// admin screen, including a real photo taken on-site.
class MenuItem {
  final String id;
  final String restaurantId;
  final String name;
  final double price;
  final int calories;
  final List<String> mealTypes; // e.g. ['Breakfast', 'Lunch']
  final List<String> dietaryTags; // e.g. ['No pork', 'Halal']
  final String? imageUrl;

  MenuItem({
    required this.id,
    required this.restaurantId,
    required this.name,
    required this.price,
    required this.calories,
    required this.mealTypes,
    required this.dietaryTags,
    this.imageUrl,
  });
}

enum MealSlot { breakfast, lunch, merienda, dinner }

extension MealSlotLabel on MealSlot {
  String get label {
    switch (this) {
      case MealSlot.breakfast:
        return 'Breakfast';
      case MealSlot.lunch:
        return 'Lunch';
      case MealSlot.merienda:
        return 'Merienda';
      case MealSlot.dinner:
        return 'Dinner';
    }
  }
}

class MealEntry {
  final MealSlot slot;
  String? dishName;
  String? restaurantName;
  int? calories;
  bool get isFilled => dishName != null;

  MealEntry({required this.slot, this.dishName, this.restaurantName, this.calories});
}

class DayPlan {
  final String dayLabel; // Mon, Tue, ...
  final List<MealEntry> meals;
  DayPlan({required this.dayLabel, required this.meals});

  int get totalCalories =>
      meals.fold(0, (sum, m) => sum + (m.calories ?? 0));
}

/// One AI-generated restaurant recommendation with a short explanation.
class AiPick {
  final String restaurantId;
  final String reason;

  AiPick({required this.restaurantId, required this.reason});

  factory AiPick.fromJson(Map<String, dynamic> json) {
    return AiPick(
      restaurantId: json['restaurantId'] ?? '',
      reason: json['reason'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'restaurantId': restaurantId,
        'reason': reason,
      };
}