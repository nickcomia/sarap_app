import 'package:flutter/material.dart';
import 'models.dart';
import 'mock_data.dart';
import 'services/firebase_service.dart';
import 'services/location_service.dart';
import 'services/matching_engine.dart';
import 'services/notification_service.dart';
import 'services/ai_recommendation_service.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// A single, app-wide source of truth. Plain ChangeNotifier singleton —
/// simple to reason about, no extra state-management package needed.
///
/// Talks to Firebase Authentication + Cloud Firestore for anything that
/// needs to persist per-account (profile, saved places, meal plan), but
/// always keeps working locally (bundled mock restaurant data) if a
/// network call fails — so the app never gets stuck without internet.
class AppState extends ChangeNotifier {
  AppState._internal();
  static final AppState instance = AppState._internal();

  UserProfile profile = UserProfile();
  List<Restaurant> restaurants = MockData.restaurants();
  List<DayPlan> mealPlan = [];

  // --- AI recommendations ---------------------------------------------
  List<AiPick> aiPicks = [];
  bool loadingAiPicks = false;

  static const _aiCacheKey = 'ai_picks_cache_v1';
  static const _aiCacheMaxAge = Duration(hours: 2);

  /// Checks a local cache first (instant, no network/LLM call) before
  /// falling back to a real Gemini request. Pass forceRefresh: true after
  /// preferences change, since a stale cache would show outdated reasoning.
  Future<void> loadAiRecommendations({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await _loadCachedAiPicks();
      if (cached != null) {
        aiPicks = cached;
        notifyListeners();
        return;
      }
    }

    loadingAiPicks = true;
    notifyListeners();
    aiPicks = await AiRecommendationService.getRecommendations(
      profile: profile,
      shortlist: sortedByMatch.take(8).toList(),
    );
    loadingAiPicks = false;
    notifyListeners();

    if (aiPicks.isNotEmpty) {
      await _saveAiPicksToCache(aiPicks);
    }
  }

  Future<List<AiPick>?> _loadCachedAiPicks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_aiCacheKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = DateTime.tryParse(decoded['cachedAt'] ?? '');
      if (cachedAt == null) return null;
      if (DateTime.now().difference(cachedAt) > _aiCacheMaxAge) return null;
      return (decoded['picks'] as List)
          .map((e) => AiPick.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveAiPicksToCache(List<AiPick> picks) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'cachedAt': DateTime.now().toIso8601String(),
        'picks': picks.map((p) => p.toJson()).toList(),
      };
      await prefs.setString(_aiCacheKey, jsonEncode(data));
    } catch (_) {
      // Non-fatal — picks just won't be cached for next time.
    }
  }

  Future<void> _clearAiPicksCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_aiCacheKey);
    } catch (_) {}
  }

  int homeTabIndex = 0; // For You, Meal Plan, Saved, Profile

  // --- Appearance -----------------------------------------------------
  ThemeMode themeMode = ThemeMode.light;
  bool get isDarkMode => themeMode == ThemeMode.dark;

  void toggleTheme() {
    themeMode = isDarkMode ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }

  // --- Live location ------------------------------------------------
  double? userLat;
  double? userLng;
  bool locationDenied = false;

  /// Fetches the device's current GPS position (asking for permission
  /// if needed) and recomputes every restaurant's distance from it. If
  /// location can't be obtained for any reason, the existing estimated
  /// distances are left untouched.
  Future<void> refreshLocation() async {
    final pos = await LocationService.getCurrentLocation();
    if (pos == null) {
      locationDenied = true;
      notifyListeners();
      return;
    }
    userLat = pos.latitude;
    userLng = pos.longitude;
    locationDenied = false;
    for (final r in restaurants) {
      r.distanceKm = double.parse(
        LocationService.distanceKm(pos.latitude, pos.longitude, r.latitude, r.longitude)
            .toStringAsFixed(1),
      );
    }
    notifyListeners();
  }

  bool get isLoggedIn => FirebaseService.currentUid != null;

  void setHomeTab(int index) {
    homeTabIndex = index;
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Auth
  // ------------------------------------------------------------------

  /// Registers a new account via Firebase. Throws [ApiException] on
  /// failure (e.g. email already used, weak password, no internet) so
  /// the UI can show the message.
  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final result = await FirebaseService.register(name: name, email: email, password: password);
    profile.name = result['name'];
    profile.email = result['email'];
    notifyListeners();
    await NotificationService.registerTokenForCurrentUser();
  }

  Future<void> login({required String email, required String password}) async {
    final result = await FirebaseService.login(email: email, password: password);
    profile.name = result['name'];
    profile.email = result['email'];
    notifyListeners();
    await NotificationService.registerTokenForCurrentUser();

    // Pull down whatever this account already has saved.
    await loadSavedFromServer();
    await loadMealPlanFromServer();
  }

  /// Called once at app startup. Firebase Auth silently keeps the user
  /// logged in across app restarts, but AppState.profile always starts as
  /// a fresh UserProfile() with placeholder defaults ("Juan Dela Cruz",
  /// default BMI, etc.) — nothing re-downloads the real saved profile
  /// unless this runs. Without it, a returning logged-in user sees the
  /// demo/placeholder data instead of their own, every time they reopen
  /// the app.
  Future<void> loadCurrentUserIfLoggedIn() async {
    if (!isLoggedIn) return;
    if (!FirebaseService.isEmailVerified) {
      // Shouldn't normally happen (login() already blocks unverified
      // accounts), but guards against an edge case — e.g. the user
      // registered, closed the app before verifying, and reopened it.
      await logoutFromServer();
      return;
    }
    try {
      // If the user opened an email-change verification link, copy the
      // new address from Firebase Auth into their Firestore user doc
      // before the profile is loaded below.
      await FirebaseService.syncEmailFromAuth();

      final userData = await FirebaseService.fetchUserDoc();
      if (userData != null) {
        profile.name = userData['name'] ?? profile.name;
        profile.email = userData['email'] ?? profile.email;
      }

      final profileData = await FirebaseService.fetchProfileDoc();
      if (profileData != null) {
        profile.establishmentTypes =
            Set<String>.from(profileData['establishmentTypes'] ?? []);
        profile.cuisines = Set<String>.from(profileData['cuisines'] ?? []);
        profile.mealTypes = Set<String>.from(profileData['mealTypes'] ?? []);
        profile.spiciness =
            (profileData['spiciness'] as num?)?.toDouble() ?? profile.spiciness;
        profile.sweetness =
            (profileData['sweetness'] as num?)?.toDouble() ?? profile.sweetness;
        profile.maxBudget =
            (profileData['maxBudget'] as num?)?.toDouble() ?? profile.maxBudget;
        profile.dietaryRestrictions =
            Set<String>.from(profileData['dietaryRestrictions'] ?? []);
        profile.age = (profileData['age'] as num?)?.toInt() ?? profile.age;
        profile.heightCm =
            (profileData['heightCm'] as num?)?.toDouble() ?? profile.heightCm;
        profile.weightKg =
            (profileData['weightKg'] as num?)?.toDouble() ?? profile.weightKg;
        profile.sex = BiologicalSex.values.firstWhere(
          (e) => e.name == profileData['sex'],
          orElse: () => profile.sex,
        );
        profile.activityLevel = ActivityLevel.values.firstWhere(
          (e) => e.name == profileData['activityLevel'],
          orElse: () => profile.activityLevel,
        );
        profile.healthGoal = HealthGoal.values.firstWhere(
          (e) => e.name == profileData['healthGoal'],
          orElse: () => profile.healthGoal,
        );
        profile.goalWeightKg = (profileData['goalWeightKg'] as num?)?.toDouble();
      }
      notifyListeners();

      await loadRestaurantsFromServer();
      await loadSavedFromServer();
      await loadMealPlanFromServer();
      if (mealPlan.isEmpty) await generateMealPlan();
      loadAiRecommendations();
    } catch (_) {
      // Offline or Firebase unreachable — keep whatever local state exists
      // rather than blocking app startup.
    }
  }

  Future<void> logoutFromServer() async {
    try {
      await FirebaseService.logout();
    } catch (_) {
      // Not fatal — we're resetting local state regardless.
    }
    resetForSignOut();
  }

  // ------------------------------------------------------------------
  // Profile sync — call after onboarding steps change profile fields.
  // ------------------------------------------------------------------

  Future<void> syncProfileToServer() async {
    if (!isLoggedIn) return;
    try {
      await FirebaseService.updateProfile(profile);
    } catch (_) {
      // Offline/Firebase unreachable — profile still lives locally.
    }
    // Preferences changed — recompute how well each restaurant fits.
    MatchingEngine.recomputeAll(profile, restaurants);
    notifyListeners();

    // Preferences changed — cached AI reasoning is now stale.
    await _clearAiPicksCache();
    loadAiRecommendations(forceRefresh: true);
  }

  // ------------------------------------------------------------------
  // Restaurants
  // ------------------------------------------------------------------

  /// Tries to load restaurants from Firestore; falls back to the
  /// bundled sample data if that fails or the collection is empty
  /// (e.g. you haven't run the seed script yet).
  Future<void> loadRestaurantsFromServer() async {
    try {
      // Cache-first: instant on every launch after the first.
      final cached = await FirebaseService.fetchRestaurants();
      debugPrint('FETCHED COUNT: ${cached.length}');
      if (cached.isNotEmpty) _applyRestaurants(cached);
    } catch (e) {
      debugPrint('FETCH ERROR: $e');
    }
    MatchingEngine.recomputeAll(profile, restaurants);
    notifyListeners();

    // Not awaited on purpose: refresh from the server without blocking.
    _refreshRestaurantsInBackground();
  }

  Future<void> _refreshRestaurantsInBackground() async {
    try {
      final fresh = await FirebaseService.fetchRestaurants(forceServer: true);
      if (fresh.isEmpty) return;
      _applyRestaurants(fresh);
      MatchingEngine.recomputeAll(profile, restaurants);
      notifyListeners();
    } catch (e) {
      debugPrint('BACKGROUND REFRESH ERROR: $e');
    }
  }

  /// Swaps in a new restaurant list while keeping what the app already
  /// knows locally (saved hearts and GPS distances), so a background
  /// refresh doesn't visibly reset them.
  void _applyRestaurants(List<Restaurant> incoming) {
    final savedIds = {for (final r in restaurants) if (r.isSaved) r.id};
    final distanceById = {for (final r in restaurants) r.id: r.distanceKm};
    for (final r in incoming) {
      r.isSaved = savedIds.contains(r.id);
      if (userLat != null) {
        final d = distanceById[r.id];
        if (d != null) r.distanceKm = d;
      }
    }
    restaurants = incoming;
  }

  void toggleSaved(String restaurantId) {
    final r = restaurants.firstWhere((r) => r.id == restaurantId);
    r.isSaved = !r.isSaved;
    notifyListeners();

    if (isLoggedIn) {
      FirebaseService.toggleSaved(restaurantId).catchError((_) => false);
    }
  }

  Future<void> loadSavedFromServer() async {
    if (!isLoggedIn) return;
    try {
      final ids = await FirebaseService.fetchSavedIds();
      for (final r in restaurants) {
        r.isSaved = ids.contains(r.id);
      }
      notifyListeners();
    } catch (_) {
      // Keep whatever local saved-state already exists.
    }
  }

  List<Restaurant> get savedRestaurants =>
      restaurants.where((r) => r.isSaved).toList();

  List<Restaurant> get sortedByMatch {
    final list = [...restaurants];
    list.sort((a, b) => b.matchPercent.compareTo(a.matchPercent));
    return list;
  }

  // ------------------------------------------------------------------
  // Meal plan
  // ------------------------------------------------------------------

  /// Builds the 7-day meal plan from real Firestore menu items when
  /// available (scored by MatchingEngine — calorie fit, budget, dietary
  /// restrictions). Falls back to the bundled sample generator only if
  /// no restaurant has any menu items yet (e.g. brand-new setup).
  Future<void> generateMealPlan() async {
    final allItems = await FirebaseService.fetchAllMenuItems().catchError((_) => <MenuItem>[]);

    if (allItems.isEmpty) {
      // No real menu data yet: leave every slot empty rather than
      // inventing dishes that can't be checked against diet or budget.
      mealPlan = [];
      ensureEmptyMealPlanIfNeeded();
    } else {
      final namesById = {for (final r in restaurants) r.id: r.name};
      mealPlan = MatchingEngine.buildMealPlan(profile, allItems, namesById);
    }
    notifyListeners();

    if (isLoggedIn) {
      FirebaseService.saveMealPlan(mealPlan).catchError((_) {});
    }
  }

  /// Rebuilds the full 7-day × 4-slot grid every time — any slot that
  /// doesn't have a saved doc in Firestore just stays empty ("Tap to
  /// log..."), instead of the whole day/slot silently disappearing.
  Future<void> loadMealPlanFromServer() async {
    if (!isLoggedIn) return;
    try {
      final entries = await FirebaseService.fetchMealPlanEntries();
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

      final byDay = <String, Map<MealSlot, MealEntry>>{
        for (final d in days)
          d: {for (final s in MealSlot.values) s: MealEntry(slot: s)}
      };

      for (final e in entries) {
        final slot = MealSlot.values.byName(e['slot']);
        final dayLabel = e['dayLabel'] as String?;
        if (dayLabel == null || !byDay.containsKey(dayLabel)) continue;
        byDay[dayLabel]![slot] = MealEntry(
          slot: slot,
          dishName: e['dishName'],
          restaurantName: e['restaurantName'],
          calories: e['calories'] == null ? null : int.parse(e['calories'].toString()),
        );
      }

      mealPlan = days
          .map((d) => DayPlan(
                dayLabel: d,
                meals: MealSlot.values.map((s) => byDay[d]![s]!).toList(),
              ))
          .toList();
      notifyListeners();
    } catch (_) {
      // Keep whatever local meal plan already exists.
    }
  }

  /// Local-only empty 7-day × 4-slot skeleton — no Firestore write.
  /// Used as a safety net if the meal plan tab is opened before/without
  /// being logged in, so the user still sees "Tap to log..." for every
  /// slot instead of a blank loading spinner.
  void ensureEmptyMealPlanIfNeeded() {
    if (mealPlan.isNotEmpty) return;
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    mealPlan = days
        .map((d) => DayPlan(
              dayLabel: d,
              meals: MealSlot.values.map((s) => MealEntry(slot: s)).toList(),
            ))
        .toList();
    notifyListeners();
  }

  void replaceMeal(int dayIndex, MealSlot slot) {
    final alt = MockData.randomMealFor(slot, profile, restaurants);
    final day = mealPlan[dayIndex];
    final entry = day.meals.firstWhere((m) => m.slot == slot);
    entry.dishName = alt.dishName;
    entry.restaurantName = alt.restaurantName;
    entry.calories = alt.calories;
    notifyListeners();

    if (isLoggedIn) {
      FirebaseService.replaceMeal(
        dayLabel: day.dayLabel,
        slot: slot,
        dishName: entry.dishName,
        restaurantName: entry.restaurantName,
        calories: entry.calories,
      ).catchError((_) {});
    }
  }

  /// Manually sets a meal slot's contents — used by the "log what I ate"
  /// edit sheet, for both restaurant meals and home-cooked meals.
  void setMeal(
    int dayIndex,
    MealSlot slot, {
    required String dishName,
    required String restaurantName,
    required int calories,
  }) {
    final day = mealPlan[dayIndex];
    final entry = day.meals.firstWhere((m) => m.slot == slot);
    entry.dishName = dishName;
    entry.restaurantName = restaurantName;
    entry.calories = calories;
    notifyListeners();

    if (isLoggedIn) {
      FirebaseService.replaceMeal(
        dayLabel: day.dayLabel,
        slot: slot,
        dishName: entry.dishName,
        restaurantName: entry.restaurantName,
        calories: entry.calories,
      ).catchError((_) {});
    }
  }

  /// Clears a meal slot back to empty ("Tap to pick a ... option").
  void clearMeal(int dayIndex, MealSlot slot) {
    final day = mealPlan[dayIndex];
    final entry = day.meals.firstWhere((m) => m.slot == slot);
    entry.dishName = null;
    entry.restaurantName = null;
    entry.calories = null;
    notifyListeners();

    if (isLoggedIn) {
      FirebaseService.replaceMeal(
        dayLabel: day.dayLabel,
        slot: slot,
        dishName: null,
        restaurantName: null,
        calories: null,
      ).catchError((_) {});
    }
  }

  void resetForSignOut() {
    profile = UserProfile();
    mealPlan = [];
    aiPicks = [];
    homeTabIndex = 0;
    for (final r in restaurants) {
      r.isSaved = false;
    }
    notifyListeners();
    _clearAiPicksCache();
  }

  void refresh() => notifyListeners();
}