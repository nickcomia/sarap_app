import 'dart:math';
import '../models.dart';

/// Computes a live "match %" between a user's profile and a restaurant —
/// this is the app's AI/ML-assisted recommendation layer referenced in
/// the manuscript. It's a transparent, explainable weighted-scoring
/// model (not a black-box trained network): each factor below is scored
/// independently against real profile + restaurant/menu data, then
/// combined into a single percentage. This keeps recommendations
/// auditable — useful both for demoing to a panel and for debugging why
/// a place did or didn't rank highly.
///
/// Weights (sum to 100):
///   Cuisine preference match      — 25
///   Establishment type match      — 15
///   Budget fit                    — 20
///   Dietary restriction compliance — 20
///   Rating quality                — 10
///   Distance convenience          — 10
class MatchingEngine {
  static const _priceRankMap = {'₱': 1, '₱₱': 2, '₱₱₱': 3};

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
    } else if (profile.cuisines.contains(restaurant.cuisine)) {
      score += 25;
    }

    // --- Establishment type (15 pts) ---
    if (profile.establishmentTypes.isEmpty) {
      score += 9;
    } else if (profile.establishmentTypes.contains(restaurant.type)) {
      score += 15;
    }

    // --- Budget fit (20 pts) ---
    final userBudgetRank = _budgetRankFor(profile.maxBudget);
    final placeRank = _priceRankMap[restaurant.priceRange] ?? 2;
    if (placeRank <= userBudgetRank) {
      // Comfortably within budget — full marks, with a small bonus for
      // being noticeably cheaper than the user's ceiling.
      score += 20;
    } else {
      // Over budget — partial credit that shrinks the further over it is.
      final overBy = placeRank - userBudgetRank;
      score += (20 - overBy * 8).clamp(0, 20).toDouble();
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

    return score.round().clamp(0, 100);
  }

  /// Maps the user's max-budget slider (₱30-₱500+) onto the same 1-3
  /// scale used for restaurant price ranges (₱ / ₱₱ / ₱₱₱).
  static int _budgetRankFor(double maxBudget) {
    if (maxBudget <= 100) return 1;
    if (maxBudget <= 250) return 2;
    return 3;
  }

  /// Hard requirements for putting a dish in the meal plan at all.
  /// Unlike scoring, these are pass/fail:
  ///   - the dish must not cost more than the user's per-meal budget
  ///   - the dish must carry a dietary tag for EVERY restriction the user
  ///     picked (an untagged dish can't be verified, so it is excluded)
  static bool _fitsProfile(UserProfile profile, MenuItem item) {
    if (item.price > profile.maxBudget) return false;

    if (profile.dietaryRestrictions.isNotEmpty) {
      final tags = item.dietaryTags.map((t) => t.toLowerCase().trim()).toSet();
      for (final restriction in profile.dietaryRestrictions) {
        if (!tags.contains(restriction.toLowerCase().trim())) return false;
      }
    }
    return true;
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
    if (item.price <= profile.maxBudget) {
      score += 30;
    } else {
      final overRatio = (item.price - profile.maxBudget) / profile.maxBudget;
      score += (30 - overRatio * 30).clamp(0, 30);
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

  /// Builds a full 7-day meal plan from real menu items, picking — for
  /// each day/slot — randomly among the top 3 highest-scoring items
  /// tagged for that slot (scored via [scoreMenuItem]). Dishes that break
  /// the user's dietary restrictions or budget are filtered out first
  /// (see [_fitsProfile]). Slots with no qualifying dish are left empty
  /// so the user can log manually.
  static List<DayPlan> buildMealPlan(
    UserProfile profile,
    List<MenuItem> allItems,
    Map<String, String> restaurantNamesById,
  ) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final rand = Random();
    final target = profile.dailyCalorieTarget.clamp(1200, 4000);

    return days.map((day) {
      final meals = MealSlot.values.map((slot) {
        final calTarget = (target * _slotCalorieFraction[slot]!).round();
        final candidates = allItems
            .where((i) => i.mealTypes
                .map((m) => m.toLowerCase())
                .contains(slot.label.toLowerCase()))
            .where((i) => _fitsProfile(profile, i))
            .toList();

        if (candidates.isEmpty) {
          return MealEntry(slot: slot);
        }

        candidates.sort((a, b) => scoreMenuItem(profile, b, calTarget)
            .compareTo(scoreMenuItem(profile, a, calTarget)));
        final topPicks = candidates.take(3).toList();
        final chosen = topPicks[rand.nextInt(topPicks.length)];

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