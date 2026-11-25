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

  /// What this user has chosen or logged before (not saved in the profile doc).
  final TasteHistory taste = TasteHistory();

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

  /// One or more establishment types separated by commas, for example
  /// "Café", "Fast food", or "Restaurant, Bar".
  final String type;
  final String cuisine;
  double distanceKm; // live-updated from GPS once location is available
  int matchPercent; // computed live by MatchingEngine against the user's profile

  /// Calories of this restaurant's usable menu dishes. Filled in by
  /// AppState once the menus are loaded; empty means "no menu data yet".
  /// Used by MatchingEngine to judge how well the restaurant fits the
  /// user's health goal.
  List<int> menuCalories = [];

  /// Price level ₱, ₱₱ or ₱₱₱. Worked out from [priceMin] and [priceMax]
  /// whenever the administrator enters them.
  final String priceRange;

  /// Lowest and highest dish price in pesos, entered by the administrator.
  final double? priceMin;
  final double? priceMax;
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
    this.priceMin,
    this.priceMax,
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

  /// True when a usable lowest and highest price are stored.
  bool get hasPriceRange =>
      priceMin != null && priceMax != null && priceMin! > 0 && priceMax! >= priceMin!;

  /// A middle price that one expensive dish cannot pull up
  /// (the geometric mean of the lowest and highest price).
  double? get typicalPrice => hasPriceRange ? sqrt(priceMin! * priceMax!) : null;

  /// "₱200 – ₱1,240" when a range is known, otherwise the ₱ level.
  String get priceLabel {
    if (!hasPriceRange) return priceRange;
    if (priceMin == priceMax) return _peso(priceMin!);
    return '${_peso(priceMin!)} – ${_peso(priceMax!)}';
  }

  /// Each establishment type of this restaurant, e.g. ['Restaurant', 'Bar'].
  List<String> get types =>
      type.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

  static String _peso(double v) {
    final digits = v.round().toString();
    final withCommas = digits.replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    return '₱$withCommas';
  }

  /// Price level from the typical price. The cut-offs match the budget
  /// slider: up to ₱100, up to ₱250, and above.
  static String priceTierFor(double min, double max) {
    final typical = sqrt(min * max);
    if (typical <= 100) return '₱';
    if (typical <= 250) return '₱₱';
    return '₱₱₱';
  }
}

/// A single dish/product on a restaurant's menu — added via the in-app
/// admin screen, including a real photo taken on-site.
class MenuItem {
  final String id;
  final String restaurantId;
  final String name;
  final double price;

  /// Estimated calories for ONE serving of this dish, as entered by the
  /// administrator. [servingSize] says what that serving is.
  final int calories;
  final List<String> mealTypes; // e.g. ['Breakfast', 'Lunch']
  final List<String> dietaryTags; // e.g. ['No pork', 'Halal']

  /// What one serving is, for example "1 slice", "16 oz cup" or
  /// "1 plate (about 250 g)". Null means the administrator has not said.
  final String? servingSize;
  final String? imageUrl;

  MenuItem({
    required this.id,
    required this.restaurantId,
    required this.name,
    required this.price,
    required this.calories,
    required this.mealTypes,
    required this.dietaryTags,
    this.servingSize,
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

  /// True once the diner marks this planned meal as eaten.
  bool eaten;

  bool get isFilled => dishName != null;

  MealEntry({
    required this.slot,
    this.dishName,
    this.restaurantName,
    this.calories,
    this.eaten = false,
  });
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

enum ReviewStatus { pending, approved, rejected }

/// A user's written review of a restaurant. New reviews are saved as
/// [ReviewStatus.pending] and only show to other users once an admin
/// approves them.
class Review {
  final String id;
  final String restaurantId;
  final String userId;
  final String userName;
  final int rating; // 1..5
  final String text;
  final String? dish; // what the reviewer ate (optional)
  final ReviewStatus status;
  final String? rejectReason;
  final DateTime? createdAt;

  const Review({
    required this.id,
    required this.restaurantId,
    required this.userId,
    required this.userName,
    required this.rating,
    required this.text,
    this.dish,
    this.status = ReviewStatus.pending,
    this.rejectReason,
    this.createdAt,
  });
}
/// One meal the user deliberately chose or logged in the meal plan.
/// Saved at users/{uid}/mealLog/{id}.
class MealChoice {
  final String dishName;
  final String? restaurantId;
  final String? restaurantName;
  final String? cuisine;
  final List<String> dietaryTags;
  final int calories;
  final MealSlot slot;
  final String dayLabel;

  /// 'picked' (swap/fill picker), 'manual' (log sheet) or 'restaurant_page'.
  final String source;
  final bool homeCooked;

  const MealChoice({
    required this.dishName,
    this.restaurantId,
    this.restaurantName,
    this.cuisine,
    this.dietaryTags = const <String>[],
    required this.calories,
    required this.slot,
    required this.dayLabel,
    required this.source,
    this.homeCooked = false,
  });

  Map<String, dynamic> toMap() => {
        'dishName': dishName,
        'restaurantId': restaurantId,
        'restaurantName': restaurantName,
        'cuisine': cuisine,
        'dietaryTags': dietaryTags,
        'calories': calories,
        'slot': slot.name,
        'dayLabel': dayLabel,
        'source': source,
        'homeCooked': homeCooked,
      };

  factory MealChoice.fromMap(Map<String, dynamic> m) {
    final tags = m['dietaryTags'];
    return MealChoice(
      dishName: (m['dishName'] ?? '').toString(),
      restaurantId: m['restaurantId'] as String?,
      restaurantName: m['restaurantName'] as String?,
      cuisine: m['cuisine'] as String?,
      dietaryTags: tags is List
          ? tags.map((e) => e.toString()).toList()
          : const <String>[],
      calories: (m['calories'] as num?)?.toInt() ?? 0,
      slot: MealSlot.values.firstWhere(
        (s) => s.name == m['slot'],
        orElse: () => MealSlot.lunch,
      ),
      dayLabel: (m['dayLabel'] ?? '').toString(),
      source: (m['source'] ?? 'manual').toString(),
      homeCooked: m['homeCooked'] == true,
    );
  }
}

/// Counts of what one user has chosen before. Used to nudge the match score,
/// the meal planner and the AI prompt toward foods the user really picks.
class TasteHistory {
  final Map<String, int> dishCounts = {};
  final Map<String, int> cuisineCounts = {};
  final Map<String, int> restaurantCounts = {}; // by restaurant id
  final Map<String, String> _dishLabels = {};
  final Map<String, String> _cuisineLabels = {};
  int total = 0;
  int _cuisineTotal = 0;

  static String dishKey(String name) => name.toLowerCase().trim();
  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  void clear() {
    dishCounts.clear();
    cuisineCounts.clear();
    restaurantCounts.clear();
    _dishLabels.clear();
    _cuisineLabels.clear();
    total = 0;
    _cuisineTotal = 0;
  }

  void add(MealChoice c) {
    final dish = c.dishName.trim();
    if (dish.isEmpty) return;
    total++;
    final k = dishKey(dish);
    dishCounts[k] = (dishCounts[k] ?? 0) + 1;
    _dishLabels.putIfAbsent(k, () => dish);

    final cuisine = c.cuisine?.trim() ?? '';
    if (cuisine.isNotEmpty) {
      final ck = _norm(cuisine);
      cuisineCounts[ck] = (cuisineCounts[ck] ?? 0) + 1;
      _cuisineLabels.putIfAbsent(ck, () => cuisine);
      _cuisineTotal++;
    }

    final rid = c.restaurantId;
    if (rid != null && rid.isNotEmpty) {
      restaurantCounts[rid] = (restaurantCounts[rid] ?? 0) + 1;
    }
  }

  /// Too little history makes the numbers noise, so it is ignored below 3.
  bool get isUseful => total >= 3;

  int cuisineCount(String cuisine) => cuisineCounts[_norm(cuisine)] ?? 0;

  /// Share (0..1) of this user's choices that were this cuisine.
  double cuisineShare(String cuisine) =>
      _cuisineTotal == 0 ? 0 : cuisineCount(cuisine) / _cuisineTotal;

  List<String> topDishes(int n) => _top(dishCounts, _dishLabels, n);
  List<String> topCuisines(int n) => _top(cuisineCounts, _cuisineLabels, n);

  static List<String> _top(
      Map<String, int> counts, Map<String, String> labels, int n) {
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(n).map((e) {
      // Dish names can be typed by the user, so keep them short and one line.
      var t = (labels[e.key] ?? e.key).replaceAll(RegExp(r'[\r\n"]'), ' ').trim();
      if (t.length > 40) t = t.substring(0, 40);
      return t;
    }).toList();
  }
}