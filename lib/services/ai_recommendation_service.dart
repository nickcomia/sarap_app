import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import '../models.dart';

/// Calls Gemini (via Firebase AI Logic — free Gemini Developer API tier,
/// no Cloud Function or Blaze plan needed) to pick and explain the best
/// restaurant matches for a user, on top of the app's existing rule-based
/// MatchingEngine scoring.
///
/// The existing MatchingEngine already narrows/scores the full list —
/// this only re-ranks and explains the top candidates it's handed, so a
/// slow/failed AI call never blocks the app from showing recommendations.
class AiRecommendationService {
  static GenerativeModel? _model;

  static GenerativeModel _getModel() {
    _model ??= FirebaseAI.googleAI(appCheck: FirebaseAppCheck.instance).generativeModel(
      model: 'gemini-2.0-flash',
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        temperature: 0.7,
      ),
    );
    return _model!;
  }

  /// Takes the user's profile and a pre-scored shortlist of restaurants
  /// (pass in state.sortedByMatch.take(8) or similar — keep this list
  /// small so the prompt stays fast and cheap), and returns up to
  /// [maxPicks] AI-reasoned recommendations, each referencing one of the
  /// restaurant IDs given.
  static Future<List<AiPick>> getRecommendations({
    required UserProfile profile,
    required List<Restaurant> shortlist,
    int maxPicks = 4,
  }) async {
    if (shortlist.isEmpty) return [];

    final restaurantLines = shortlist.map((r) {
      return '- id: ${r.id}, name: "${r.name}", type: ${r.type}, '
          'cuisine: ${r.cuisine}, price: ${r.priceRange}, rating: ${r.rating}, '
          'distanceKm: ${r.distanceKm}, tags: ${r.tags.join(", ")}, '
          'matchPercent: ${r.matchPercent}';
    }).join('\n');

    final prompt = '''
You are a friendly food recommendation assistant inside a Filipino restaurant-finder app called SARAP.

User profile:
- Daily calorie target: ${profile.dailyCalorieTarget} kcal
- Health goal: ${profile.healthGoal.label}
- BMI: ${profile.bmi.toStringAsFixed(1)} (${profile.bmiCategory})
- Max budget preference: ₱${profile.maxBudget}
- Preferred cuisines: ${profile.cuisines.isEmpty ? "no strong preference" : profile.cuisines.join(", ")}
- Dietary restrictions: ${profile.dietaryRestrictions.isEmpty ? "none" : profile.dietaryRestrictions.join(", ")}

Candidate restaurants (already pre-scored by an internal matching algorithm — matchPercent is that score):
$restaurantLines

Pick the best $maxPicks restaurants from the candidates above for this user. For each pick, write one short reason (max 20 words) that blends a warm, casual tone with a concrete data point (e.g. calorie fit, budget, distance, or dietary match) — do not just repeat the matchPercent number.

Respond ONLY with a raw JSON array, no markdown, no code fences, in this exact shape:
[
  {"restaurantId": "r1", "reason": "..."},
  {"restaurantId": "r2", "reason": "..."}
]

Only use restaurantId values from the candidate list above. Do not invent restaurants.
''';

    try {
      final model = _getModel();
      final response = await model.generateContent([Content.text(prompt)]);
      final text = response.text;
      if (text == null || text.trim().isEmpty) return [];

      final decoded = jsonDecode(text.trim()) as List<dynamic>;
      final validIds = shortlist.map((r) => r.id).toSet();

      return decoded
          .map((e) => AiPick.fromJson(e as Map<String, dynamic>))
          .where((pick) => validIds.contains(pick.restaurantId))
          .take(maxPicks)
          .toList();
    } catch (e, stack) {
      debugPrint('AI RECOMMENDATION ERROR: $e');
      debugPrint('STACK: $stack');
      return [];
    }
  }
}