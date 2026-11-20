import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../models.dart';

/// Asks Gemini to pick and explain the best restaurant matches for a user,
/// on top of the app's existing rule-based MatchingEngine scoring.
///
/// The request goes through a small serverless proxy (see the sarap-ai-proxy
/// folder) instead of calling Gemini from inside the app. That keeps the API
/// key out of the APK, works for apps installed from a downloaded APK, and
/// lets the model name be changed on the server without a new app release.
///
/// The existing MatchingEngine already narrows/scores the full list —
/// this only re-ranks and explains the top candidates it's handed, so a
/// slow/failed AI call never blocks the app from showing recommendations.
class AiRecommendationService {
  /// Replace with your deployed Vercel URL, e.g.
  /// 'https://sarap-ai-proxy.vercel.app/api/ai-picks'
  static const String _endpoint =
      'https://sarap-ai-proxy.vercel.app/api/ai-picks';

  static const Duration _timeout = Duration(seconds: 30);

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
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('AI PICKS: not signed in, skipping');
        return [];
      }
      final idToken = await user.getIdToken();

      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({'prompt': prompt}),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint(
            'AI RECOMMENDATION ERROR: proxy returned ${response.statusCode}: ${response.body}');
        return [];
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final text = body['text'] as String?;
      if (text == null || text.trim().isEmpty) {
        debugPrint('AI PICKS: empty response from model');
        return [];
      }

      final decoded = jsonDecode(text.trim()) as List<dynamic>;
      final validIds = shortlist.map((r) => r.id).toSet();

      final picks = decoded
          .map((e) => AiPick.fromJson(e as Map<String, dynamic>))
          .where((pick) => validIds.contains(pick.restaurantId))
          .take(maxPicks)
          .toList();
      debugPrint('AI PICKS OK: ${picks.length}');
      return picks;
    } catch (e, stack) {
      debugPrint('AI RECOMMENDATION ERROR: $e');
      debugPrint('STACK: $stack');
      return [];
    }
  }
}