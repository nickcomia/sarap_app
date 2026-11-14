import 'dart:math';
import '../models.dart';

/// A short note shown on a restaurant card about how it fits the user's
/// health goal, for example "High calorie for your goal".
class GoalNote {
  final String text;
  final bool positive;
  const GoalNote(this.text, this.positive);
}

/// Computes a live "match %" between a user's profile and a restaurant —
/// this is the app's AI/ML-assisted recommendation layer referenced in
/// the manuscript. It's a transparent, explainable weighted-scoring
/// model (not a black-box trained network): each factor below is scored
/// independently against real profile + restaurant/menu data, then
/// combined into a single percentage. This keeps recommendations
/// auditable — useful both for demoing to a panel and for debugging why
/// a place did or didn't rank highly.
///
/// Base weights (sum to 100):
///   Cuisine preference match      — 25
///   Establishment type match      — 15
///   Budget fit                    — 20
///   Dietary restriction compliance — 20
///   Rating quality                — 10
///   Distance convenience          — 10
///
/// Health-goal fit: when the restaurant's menu calories are known, the base
/// score is blended with a "health fit" score (see [healthFit]). The share
/// of the final score decided by health fit depends on the goal: 45% for
/// Lose weight, 15% for Gain weight, 10% for Maintain weight. Restaurants
/// with no menu data keep their base score unchanged.
class MatchingEngine {
  static const _priceRankMap = {'₱': 1, '₱₱': 2, '₱₱₱': 3};

  /// Assumption pending clarification MP-CL-01: a swapped-in dish may differ
  /// from the dish it replaces by at most this fraction of that dish's
  /// calories (e.g. 400 kcal -> 300..500 kcal). Change here if the approved
  /// swap policy is different.
  static const double swapCalorieTolerance = 0.25;

  /// Recomputes matchPercent for every restaurant in [restaurants] against
  /// [profile], mutating each Restaurant.matchPercent in place. Call this
  /// after onboarding, after a profile edit, or after loading new
  /// restaurant data.
  static void recomputeAll(UserProfile profile, List<Restaurant> restaurants) {
    for (final r in restaurants) {
      r.matchPercent = computeMatchPercent(profile, r);
    }
  }

  static int computeMatchPercent(UserProfile profile, Restaurant restaurant) {
    double score = 0;

    // --- Cuisine preference (25 pts) ---
    if (profile.cuisines.isEmpty) {
      score += 15; // neutral credit — no stated preference to violate
    } else if (profile.cuisines.map(_key).contains(_key(restaurant.cuisine))) {
      score += 25;
    }

    // --- Establishment type (15 pts) ---
    if (profile.establishmentTypes.isEmpty) {
      score += 9;
    } else if (profile.establishmentTypes
        .map(_key)
        .toSet()
        .intersection(_typeKeys(restaurant.type))
        .isNotEmpty) {
      score += 15;
    }

    // --- Budget fit (20 pts) ---
    // With a real price range (set by the administrator) the score follows
    // the numbers; older records fall back to the three ₱ levels.
    final typical = restaurant.typicalPrice;
    final lowest = restaurant.priceMin;
    if (typical != null && lowest != null) {
      final budget = profile.maxBudget >= 500 ? double.infinity : profile.maxBudget;
      if (budget >= typical) {
        score += 20; // the usual dish is affordable
      } else if (budget >= lowest) {
        // Some dishes fit: 10 points rising to 20 as the budget nears the typical price.
        score += 10 + 10 * ((budget - lowest) / (typical - lowest));
      } else {
        // Even the cheapest dish is above the budget.
        score += 10 * (budget / lowest);
      }
    } else {
      final userBudgetRank = _budgetRankFor(profile.maxBudget);
      final placeRank = _priceRankMap[restaurant.priceRange] ?? 2;
      if (placeRank <= userBudgetRank) {
        score += 20;
      } else {
        final overBy = placeRank - userBudgetRank;
        score += (20 - overBy * 8).clamp(0, 20).toDouble();
      }
    }

    // --- Dietary restriction compliance (20 pts) ---
    if (profile.dietaryRestrictions.isEmpty) {
      score += 20;
    } else {
      final tagsLower = restaurant.tags.map((t) => t.toLowerCase()).toSet();
      final satisfied = profile.dietaryRestrictions
          .where((d) => tagsLower.contains(d.toLowerCase()))
          .length;
      score += 20 * (satisfied / profile.dietaryRestrictions.length);
    }

    // --- Rating quality (10 pts) ---
    score += (restaurant.rating / 5).clamp(0, 1) * 10;

    // --- Distance convenience (10 pts) ---
    // Full marks within 1km, tapering to 0 by 5km+.
    final distanceScore = (1 - (restaurant.distanceKm / 5)).clamp(0.0, 1.0);
    score += distanceScore * 10;

    final base = score.clamp(0.0, 100.0);

    // --- Health-goal fit ---
    // Blend in how well the restaurant's dishes suit the user's calorie
    // goal. Without menu data the base score is used as it is.
    final fit = healthFit(profile, restaurant);
    if (fit == null) return base.round().clamp(0, 100);
    final w = _healthWeight(profile.healthGoal);
    return (base * (1 - w) + fit * 100 * w).round().clamp(0, 100);
  }

  // ------------------------------------------------------------------
  // Health-goal fit
  // ------------------------------------------------------------------

  /// Share of the final match score decided by health fit.
  static double _healthWeight(HealthGoal goal) {
    switch (goal) {
      case HealthGoal.lose:
        return 0.45;
      case HealthGoal.gain:
        return 0.15;
      case HealthGoal.maintain:
        return 0.10;
    }
  }

  /// Calories one meal should roughly hold: a third of the daily target.
  /// Null when the health profile is incomplete, so no health score is
  /// calculated from placeholder defaults.
  static int? mealCalorieBudget(UserProfile profile) {
    if (!profile.hasValidHealthData) return null;
    final target = profile.dailyCalorieTarget.clamp(1200, 4000);
    return (target / 3).round();
  }

  /// 1.0 up to [limit] kcal, then falling in a straight line to 0 at twice
  /// the limit.
  static double _overLimitScore(int calories, double limit) {
    if (calories <= limit) return 1.0;
    return (1 - (calories - limit) / limit).clamp(0.0, 1.0);
  }

  /// How well one dish suits the goal, from 0 (not at all) to 1 (fully).
  ///   Lose weight     — up to one meal budget is fine, heavier dishes score less
  ///   Maintain weight — up to 1.2 meal budgets is fine
  ///   Gain weight     — dishes of at least 0.7 of a meal budget are fine
  static double _dishHealthScore(HealthGoal goal, int calories, int budget) {
    switch (goal) {
      case HealthGoal.lose:
        return _overLimitScore(calories, budget.toDouble());
      case HealthGoal.maintain:
        return _overLimitScore(calories, budget * 1.2);
      case HealthGoal.gain:
        final floor = budget * 0.7;
        return calories >= floor ? 1.0 : calories / floor;
    }
  }

  /// All-you-can-eat style places (unli, buffet, eat-all-you-can, samgyup)
  /// have no calorie limit per person, so they count as high calorie even
  /// when no menu item says so. Matches whole words for the general terms,
  /// so "sunlight" does not count. Remove "samgyup|samgyeopsal" below if
  /// some of your samgyup places are not unlimited.
  static final _unlimitedPattern = RegExp(
    r'\bunli\b|\bunlimited\b|all[\s-]*you[\s-]*can[\s-]*eat|'
    r'eat[\s-]*all[\s-]*you[\s-]*can|\bbuffet\b|samgyup|samgyeopsal',
  );

  static bool _isUnlimited(Restaurant r) {
    final text = '${r.name} ${r.tags.join(' ')}'.toLowerCase();
    return _unlimitedPattern.hasMatch(text);
  }

  /// How well a restaurant suits the user's calorie goal, from 0 to 1, or
  /// null when it cannot be judged (incomplete health profile, or the
  /// restaurant has no menu with calories and is not an all-you-can-eat).
  static double? healthFit(UserProfile profile, Restaurant restaurant) {
    final budget = mealCalorieBudget(profile);
    if (budget == null) return null;
    final goal = profile.healthGoal;

    double? fit;
    if (restaurant.menuCalories.isNotEmpty) {
      var sum = 0.0;
      for (final c in restaurant.menuCalories) {
        sum += _dishHealthScore(goal, c, budget);
      }
      fit = sum / restaurant.menuCalories.length;
    }

    if (goal != HealthGoal.gain && _isUnlimited(restaurant)) {
      // Never better than "mostly too heavy", whatever the menu lists.
      return min(fit ?? 0.3, 0.3);
    }
    return fit;
  }

  /// A short label for the restaurant card, or null when there is nothing
  /// clear to say.
  static GoalNote? goalNote(UserProfile profile, Restaurant restaurant) {
    final fit = healthFit(profile, restaurant);
    if (fit == null) return null;
    switch (profile.healthGoal) {
      case HealthGoal.lose:
        if (fit >= 0.75) return const GoalNote('Light options for your goal', true);
        if (fit <= 0.35) return const GoalNote('High calorie for your goal', false);
        return null;
      case HealthGoal.gain:
        if (fit >= 0.75) return const GoalNote('Hearty meals for your goal', true);
        return null;
      case HealthGoal.maintain:
        return null;
    }
  }

  /// Comparison key that ignores case, accents, spaces and punctuation, so
  /// "Karinderyá", "Karinderya", "Fast food" and "Fastfood" all match.
  static String _key(String text) {
    const from = 'áàâäãéèêëíìîïóòôöõúùûüñ';
    const to = 'aaaaaeeeeiiiiooooouuuun';
    final buffer = StringBuffer();
    for (final ch in text.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      buffer.write(i >= 0 ? to[i] : ch);
    }
    return buffer.toString().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// A restaurant may carry several types, e.g. "Restaurant, Bar".
  static Set<String> _typeKeys(String type) =>
      type.split(',').map(_key).where((k) => k.isNotEmpty).toSet();

  /// Maps the user's max-budget slider (₱30-₱500+) onto the same 1-3
  /// scale used for restaurant price ranges (₱ / ₱₱ / ₱₱₱).
  static int _budgetRankFor(double maxBudget) {
    if (maxBudget <= 100) return 1;
    if (maxBudget <= 250) return 2;
    return 3;
  }

  // ------------------------------------------------------------------
  // Hard eligibility rules for the meal plan (pass/fail, not scored)
  // ------------------------------------------------------------------

  /// The per-meal price ceiling. The slider's top value means "₱500+",
  /// i.e. no ceiling at all.
  static double? _budgetCap(UserProfile profile) =>
      profile.maxBudget >= 500 ? null : profile.maxBudget;

  /// A dish needs a real price and calorie figure to be plannable. A
  /// missing price (read as 0) must never turn into a "free" meal, and a
  /// missing, zero, negative or absurd calorie value must never reach the
  /// calorie arithmetic.
  static bool _isUsable(MenuItem item) =>
      item.price.isFinite &&
      item.price > 0 &&
      item.calories > 0 &&
      item.calories <= 10000;

  static bool isUsable(MenuItem item) => _isUsable(item);

  static bool _withinBudget(UserProfile profile, MenuItem item) {
    final cap = _budgetCap(profile);
    return cap == null || item.price <= cap;
  }

  /// Every restriction the user picked must appear as a dietary tag on the
  /// dish. An untagged dish can't be verified, so it is excluded.
  static bool _meetsDiet(UserProfile profile, MenuItem item) {
    if (profile.dietaryRestrictions.isEmpty) return true;
    final tags = item.dietaryTags.map((t) => t.toLowerCase().trim()).toSet();
    for (final restriction in profile.dietaryRestrictions) {
      if (!tags.contains(restriction.toLowerCase().trim())) return false;
    }
    return true;
  }

  static bool _fitsProfile(UserProfile profile, MenuItem item) =>
      _isUsable(item) && _withinBudget(profile, item) && _meetsDiet(profile, item);

  /// True when the dish has a valid price/calories and satisfies the
  /// user's budget and dietary restrictions.
  static bool fitsProfile(UserProfile profile, MenuItem item) =>
      _fitsProfile(profile, item);

  static bool _tagsSlot(MenuItem item, MealSlot slot) => item.mealTypes
      .map((m) => m.toLowerCase().trim())
      .contains(slot.label.toLowerCase());

  /// Dishes that may be offered for [slot]: tagged for that meal time,
  /// valid, within budget and diet, and — when given — inside a calorie
  /// range. Both bounds are INCLUSIVE, so a 600 kcal dish fits a 600 kcal
  /// allowance and a 601 kcal dish does not.
  static List<MenuItem> eligibleForSlot(
    UserProfile profile,
    List<MenuItem> items,
    MealSlot slot, {
    int? minCalories,
    int? maxCalories,
    String? excludeDish,
  }) {
    return items.where((i) {
      if (!_tagsSlot(i, slot)) return false;
      if (!_fitsProfile(profile, i)) return false;
      if (minCalories != null && i.calories < minCalories) return false;
      if (maxCalories != null && i.calories > maxCalories) return false;
      if (excludeDish != null && i.name == excludeDish) return false;
      return true;
    }).toList();
  }

  /// Plain-language reason why nothing could be planned. Shown on the
  /// Meal Plan screen so the user can fix the cause (budget, restrictions).
  static String explainNoMatches(UserProfile profile, List<MenuItem> items) {
    final usable = items.where(_isUsable).toList();
    if (usable.isEmpty) {
      return 'No local menu items with a price and calories are available yet.';
    }

    final tagged = usable
        .where((i) => MealSlot.values.any((s) => _tagsSlot(i, s)))
        .toList();
    if (tagged.isEmpty) {
      return 'Menu items are not tagged with meal times yet, so no plan can be built.';
    }

    final inBudget = tagged.where((i) => _withinBudget(profile, i)).toList();
    if (inBudget.isEmpty) {
      return 'No meals fit your budget of ₱${profile.maxBudget.round()} per meal. '
          'Try raising your budget in your profile.';
    }

    if (profile.dietaryRestrictions.isNotEmpty) {
      final dietOk = tagged.where((i) => _meetsDiet(profile, i)).toList();
      if (dietOk.isEmpty) {
        return 'No meals are verified for your dietary restrictions '
            '(${profile.dietaryRestrictions.join(', ')}). '
            'Try changing your restrictions in your profile.';
      }
    }

    return 'No meals match your budget and dietary restrictions together. '
        'Try relaxing one of them.';
  }

  /// Scores an individual menu item against the profile — used when
  /// generating the meal plan, so real dishes get picked based on how
  /// well they fit calories, budget, and dietary restrictions rather
  /// than at random.
  static double scoreMenuItem(UserProfile profile, MenuItem item, int calorieTargetForSlot) {
    double score = 0;

    // Calorie closeness (0-50): how close is this dish to the slot's
    // target calorie allowance?
    final calorieDiff = (item.calories - calorieTargetForSlot).abs();
    score += (50 - (calorieDiff / calorieTargetForSlot * 50)).clamp(0, 50);

    // Budget fit (0-30)
    if (_withinBudget(profile, item)) {
      score += 30;
    }

    // Dietary compliance (0-20)
    if (profile.dietaryRestrictions.isEmpty) {
      score += 20;
    } else {
      final tagsLower = item.dietaryTags.map((t) => t.toLowerCase()).toSet();
      final satisfied = profile.dietaryRestrictions
          .where((d) => tagsLower.contains(d.toLowerCase()))
          .length;
      score += 20 * (satisfied / profile.dietaryRestrictions.length);
    }

    return score;
  }

  static const _slotCalorieFraction = {
    MealSlot.breakfast: 0.25,
    MealSlot.lunch: 0.35,
    MealSlot.merienda: 0.10,
    MealSlot.dinner: 0.30,
  };

  /// The (up to) three best-scoring dishes, best first. Each dish is scored
  /// exactly once. (The old code re-scored dishes inside the sort, which
  /// made building a plan slow when a menu has many items.)
  static List<MenuItem> _topThree(
      UserProfile profile, List<MenuItem> candidates, int calTarget) {
    final scored = [
      for (final i in candidates)
        MapEntry(i, scoreMenuItem(profile, i, calTarget)),
    ];
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(3).map((e) => e.key).toList();
  }

  /// Picks one dish for [slot] — randomly among the top 3 highest-scoring
  /// eligible items tagged for that slot. Returns null when nothing
  /// qualifies, so the caller can leave the slot empty instead of
  /// inventing a meal. [excludeDish] avoids repeating the current dish
  /// when the user asks for a replacement.
  static MealEntry? pickForSlot(
    UserProfile profile,
    List<MenuItem> allItems,
    Map<String, String> restaurantNamesById,
    MealSlot slot, {
    String? excludeDish,
    Random? random,
  }) {
    final rand = random ?? Random();
    final target = profile.dailyCalorieTarget.clamp(1200, 4000);
    final calTarget = (target * _slotCalorieFraction[slot]!).round();

    var candidates = allItems
        .where((i) => _tagsSlot(i, slot))
        .where((i) => _fitsProfile(profile, i))
        .toList();

    if (excludeDish != null) {
      final others = candidates.where((i) => i.name != excludeDish).toList();
      if (others.isEmpty) return null;
      candidates = others;
    }
    if (candidates.isEmpty) return null;

    final topPicks = _topThree(profile, candidates, calTarget);
    final chosen = topPicks[rand.nextInt(topPicks.length)];

    return MealEntry(
      slot: slot,
      dishName: chosen.name,
      restaurantName: restaurantNamesById[chosen.restaurantId] ?? 'Unknown',
      calories: chosen.calories,
    );
  }

  /// Builds a full 7-day meal plan from real menu items. Dishes that
  /// break the user's dietary restrictions or budget are filtered out
  /// first (see [_fitsProfile]). Slots with no qualifying dish are left
  /// empty so the user can log manually.
  ///
  /// The eligible dishes and their top 3 are worked out ONCE per meal slot,
  /// then each day just picks one of them at random (the same behaviour as
  /// before, but 7 times less work).
  static List<DayPlan> buildMealPlan(
    UserProfile profile,
    List<MenuItem> allItems,
    Map<String, String> restaurantNamesById,
  ) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final rand = Random();
    final target = profile.dailyCalorieTarget.clamp(1200, 4000);

    final fitting = allItems.where((i) => _fitsProfile(profile, i)).toList();
    final topBySlot = <MealSlot, List<MenuItem>>{};
    for (final slot in MealSlot.values) {
      final calTarget = (target * _slotCalorieFraction[slot]!).round();
      final candidates = fitting.where((i) => _tagsSlot(i, slot)).toList();
      topBySlot[slot] = _topThree(profile, candidates, calTarget);
    }

    return days.map((day) {
      final meals = MealSlot.values.map((slot) {
        final top = topBySlot[slot]!;
        if (top.isEmpty) return MealEntry(slot: slot);
        final chosen = top[rand.nextInt(top.length)];
        return MealEntry(
          slot: slot,
          dishName: chosen.name,
          restaurantName: restaurantNamesById[chosen.restaurantId] ?? 'Unknown',
          calories: chosen.calories,
        );
      }).toList();
      return DayPlan(dayLabel: day, meals: meals);
    }).toList();
  }
}