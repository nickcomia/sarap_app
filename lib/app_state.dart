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

  /// Explains to the user why the meal plan is empty or partly empty
  /// (no matches for budget/diet, incomplete health profile, etc.).
  String? planMessage;

  /// Required health fields (age, height, weight) that are missing from the
  /// saved profile. Empty when everything needed is present.
  List<String> missingHealthFields = [];

  /// True once we have either loaded the saved profile from Firestore or
  /// written the current profile to it. While false, the age/height/weight
  /// on [profile] are just placeholder defaults and must not be trusted.
  bool _healthProfileLoaded = false;

  bool get hasRequiredHealthData =>
      missingHealthFields.isEmpty && profile.hasValidHealthData;

  bool get hasAnyMeal =>
      mealPlan.any((d) => d.meals.any((m) => m.isFilled));

  // Tanauan City centre, used to decide which restaurants are "local".
  static const _tanauanLat = 14.0863;
  static const _tanauanLng = 121.1497;
  static const _localRadiusKm = 15.0;

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
    // Brand-new account: nothing has been entered yet, so the placeholder
    // defaults must not count as real health data.
    missingHealthFields = ['age', 'height', 'weight'];
    _healthProfileLoaded = false;
    notifyListeners();
    await NotificationService.registerTokenForCurrentUser();
  }

  Future<void> login({required String email, required String password}) async {
    final result = await FirebaseService.login(email: email, password: password);
    // Never let a previous account's plan linger while this one loads.
    mealPlan = [];
    planMessage = null;
    profile.name = result['name'];
    profile.email = result['email'];
    notifyListeners();
    await NotificationService.registerTokenForCurrentUser();

    // Load this account's own saved health/preference profile, so the
    // calorie target shown belongs to the signed-in account and not to the
    // placeholder defaults.
    await loadProfileFromServer();

    // Pull down whatever this account already has saved.
    await loadSavedFromServer();
    await loadMealPlanFromServer();
  }

  /// Downloads users/{uid} and profiles/{uid} into [profile]. Also records
  /// which required health fields are missing, so the app can ask for them
  /// instead of calculating a target from placeholder defaults.
  Future<void> loadProfileFromServer() async {
    if (!isLoggedIn) return;
    try {
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
        missingHealthFields = _findMissingHealthFields(profileData);
        _healthProfileLoaded = true;
      } else {
        missingHealthFields = ['age', 'height', 'weight'];
        _healthProfileLoaded = true;
      }
      notifyListeners();
    } catch (_) {
      // Offline or Firebase unreachable. If we never managed to load the
      // saved profile, the age/height/weight are only placeholder defaults,
      // so never let them pass as real health data.
      if (!_healthProfileLoaded) {
        missingHealthFields = ['age', 'height', 'weight'];
        notifyListeners();
      }
    }
  }

  List<String> _findMissingHealthFields(Map<String, dynamic> data) {
    bool bad(dynamic v) => v is! num || v <= 0;
    return [
      if (bad(data['age'])) 'age',
      if (bad(data['heightCm'])) 'height',
      if (bad(data['weightKg'])) 'weight',
    ];
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

      await loadProfileFromServer();

      await loadRestaurantsFromServer();
      await loadSavedFromServer();
      await loadMealPlanFromServer();
      if (!hasAnyMeal) await generateMealPlan();
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
      // updateProfile writes every health field, so nothing is missing now.
      missingHealthFields = [];
      _healthProfileLoaded = true;
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

  bool _isLocal(Restaurant r) =>
      LocationService.distanceKm(_tanauanLat, _tanauanLng, r.latitude, r.longitude) <=
      _localRadiusKm;

  /// Every network step of the meal planner gives up after this long, so a
  /// dead connection ends in a visible, recoverable message instead of an
  /// endless spinner.
  static const _networkTimeout = Duration(seconds: 15);

  /// Fresh from Firestore: only restaurants that are visible AND local,
  /// and only their menu items that are available AND have a usable price
  /// and calorie value. Returns null if the data could not be loaded.
  Future<_EligibleMenu?> _loadEligibleMenu() async {
    try {
      return await _fetchEligibleMenu().timeout(_networkTimeout);
    } catch (_) {
      return null;
    }
  }

  Future<_EligibleMenu> _fetchEligibleMenu() async {
    // Prefer the server copy so a restaurant the admin just hid can't slip
    // through from a stale cache; fall back to the cache offline.
    List<Restaurant> fetched;
    try {
      fetched = await FirebaseService.fetchRestaurants(forceServer: true);
    } catch (_) {
      fetched = await FirebaseService.fetchRestaurants();
    }
    final local = fetched.where(_isLocal).toList();
    final localIds = {for (final r in local) r.id};

    // fetchAllMenuItems already drops items marked unavailable.
    final items = await FirebaseService.fetchAllMenuItems();
    final localItems =
        items.where((i) => localIds.contains(i.restaurantId)).toList();
    final usable = localItems.where(MatchingEngine.isUsable).toList();
    return _EligibleMenu(
      usable,
      {for (final r in local) r.id: r.name},
      localItems.length - usable.length,
    );
  }

  static String _skippedNote(int skipped) => skipped == 0
      ? ''
      : ' $skipped menu item(s) were skipped because their price or calories '
          'are missing or invalid.';

  // --- Meal plan generation ---------------------------------------------

  bool _generating = false;
  bool get isGenerating => _generating;

  /// Builds the 7-day meal plan from real Firestore menu items. Repeated
  /// calls while one is already running are ignored, so tapping "generate"
  /// several times can never create duplicate or interleaved plans.
  Future<void> generateMealPlan() async {
    if (_generating) return;
    _generating = true;
    notifyListeners();
    final watch = Stopwatch()..start();
    try {
      await _generateMealPlan();
    } finally {
      _generating = false;
      debugPrint('PLAN GENERATION: ${watch.elapsedMilliseconds} ms');
      notifyListeners();
    }
  }

  Future<void> _generateMealPlan() async {
    planMessage = null;

    if (!hasRequiredHealthData) {
      final what = missingHealthFields.isEmpty
          ? 'age, height and weight'
          : missingHealthFields.join(', ');
      planMessage = 'Complete your health profile ($what) so SARAP can '
          'calculate your calorie target.';
      ensureEmptyMealPlanIfNeeded();
      notifyListeners();
      return;
    }

    final menu = await _loadEligibleMenu();
    if (menu == null) {
      planMessage = 'Could not load menus. Check your connection and try again.';
      ensureEmptyMealPlanIfNeeded();
      notifyListeners();
      return;
    }

    final built =
        MatchingEngine.buildMealPlan(profile, menu.items, menu.namesById);
    final filled =
        built.fold<int>(0, (n, d) => n + d.meals.where((m) => m.isFilled).length);

    if (filled == 0) {
      final hadPlan = hasAnyMeal;
      planMessage = MatchingEngine.explainNoMatches(profile, menu.items) +
          (hadPlan ? ' Your previous plan was kept.' : '') +
          _skippedNote(menu.skipped);
      ensureEmptyMealPlanIfNeeded();
      notifyListeners();
      return; // do NOT overwrite the saved plan
    }

    // Save first, show second: a plan that failed to save is never
    // presented as the user's plan.
    if (isLoggedIn) {
      try {
        await FirebaseService.saveMealPlan(built).timeout(_networkTimeout);
      } catch (_) {
        planMessage = 'Could not save the new plan. Check your connection and '
            'try again — your previous plan was kept.';
        ensureEmptyMealPlanIfNeeded();
        notifyListeners();
        return;
      }
    }

    mealPlan = built;
    final emptySlots = built.length * MealSlot.values.length - filled;
    final note = _skippedNote(menu.skipped);
    if (emptySlots > 0) {
      planMessage = '$emptySlots meal slot(s) have no dish that fits your budget '
          'and dietary restrictions, so they were left empty.$note';
    } else if (note.isNotEmpty) {
      planMessage = note.trim();
    }
    notifyListeners();
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

  // --- Calorie arithmetic -------------------------------------------------

  int get dailyTarget => hasRequiredHealthData ? profile.dailyCalorieTarget : 0;

  /// Target minus what the day already holds. Deliberately NOT clamped at
  /// zero: a negative value means the user is over target by that many kcal.
  int remainingFor(DayPlan day) => dailyTarget - day.totalCalories;

  static const _maxMealCalories = 10000;
  static bool _validCalories(int? c) =>
      c != null && c > 0 && c <= _maxMealCalories;

  // --- Writing one slot ---------------------------------------------------

  /// The single place a slot changes. The write goes to Firestore first and
  /// the on-screen state only changes after it succeeded, so a failed write
  /// never shows an unsaved meal as saved, and a retry can never count the
  /// calories twice (a slot is overwritten, never appended to).
  Future<bool> _commitSlot(
    int dayIndex,
    MealSlot slot, {
    required String? dishName,
    required String? restaurantName,
    required int? calories,
  }) async {
    if (dayIndex < 0 || dayIndex >= mealPlan.length) return false;
    final day = mealPlan[dayIndex];
    final entry = day.meals.firstWhere((m) => m.slot == slot);
    final watch = Stopwatch()..start();

    if (isLoggedIn) {
      try {
        await FirebaseService.replaceMeal(
          dayLabel: day.dayLabel,
          slot: slot,
          dishName: dishName,
          restaurantName: restaurantName,
          calories: calories,
        ).timeout(_networkTimeout);
      } catch (_) {
        planMessage = 'Could not save your change. Check your connection and '
            'try again — nothing was changed.';
        notifyListeners();
        return false;
      }
    }

    entry.dishName = dishName;
    entry.restaurantName = restaurantName;
    entry.calories = calories;
    planMessage = null;
    debugPrint('SLOT COMMIT: ${watch.elapsedMilliseconds} ms');
    notifyListeners();
    return true;
  }

  /// Swaps one slot for another random eligible dish. If nothing else
  /// qualifies the slot is left as it was.
  Future<void> replaceMeal(int dayIndex, MealSlot slot) async {
    if (!hasRequiredHealthData) {
      planMessage = 'Complete your health profile so SARAP can calculate '
          'your calorie target.';
      notifyListeners();
      return;
    }

    final menu = await _loadEligibleMenu();
    if (menu == null) {
      planMessage = 'Could not load menus. Check your connection and try again.';
      notifyListeners();
      return;
    }

    final day = mealPlan[dayIndex];
    final entry = day.meals.firstWhere((m) => m.slot == slot);
    final alt = MatchingEngine.pickForSlot(
      profile,
      menu.items,
      menu.namesById,
      slot,
      excludeDish: entry.dishName,
    );

    if (alt == null) {
      planMessage = 'No other dish fits your budget and dietary restrictions '
          'for ${slot.label.toLowerCase()}.';
      notifyListeners();
      return;
    }

    await _commitSlot(dayIndex, slot,
        dishName: alt.dishName,
        restaurantName: alt.restaurantName,
        calories: alt.calories);
  }

  /// Manually sets a meal slot's contents — used by the "log what I ate"
  /// edit sheet, for both restaurant meals and home-cooked meals.
  /// Returns false (with [planMessage] set) if the input is invalid or the
  /// save failed.
  Future<bool> setMeal(
    int dayIndex,
    MealSlot slot, {
    required String dishName,
    required String restaurantName,
    required int calories,
  }) async {
    if (dishName.trim().isEmpty || !_validCalories(calories)) {
      planMessage = 'Enter a dish name and calories between 1 and '
          '$_maxMealCalories.';
      notifyListeners();
      return false;
    }
    return _commitSlot(dayIndex, slot,
        dishName: dishName.trim(),
        restaurantName: restaurantName,
        calories: calories);
  }

  /// Clears a meal slot back to empty.
  Future<bool> clearMeal(int dayIndex, MealSlot slot) =>
      _commitSlot(dayIndex, slot,
          dishName: null, restaurantName: null, calories: null);

  // --- Swap / empty-slot pickers -------------------------------------------

  /// Assumption pending clarification MP-CL-01: a swap candidate may differ
  /// from the current dish by at most this fraction of its calories
  /// (400 kcal lunch -> 450 kcal replacement is +12.5%, so it qualifies).
  /// The value lives in MatchingEngine.swapCalorieTolerance.

  /// Dishes the user may pick for [slot] on [dayIndex].
  ///  - Filled slot  -> swap: other eligible dishes within the calorie range.
  ///  - Empty slot   -> only dishes that fit the day's remaining calories
  ///                    (a dish equal to the allowance is accepted).
  /// Always uses fresh menu data: local, visible, available, budget- and
  /// diet-compliant, with a valid price and calorie value.
  Future<OptionResult> loadOptions(int dayIndex, MealSlot slot) async {
    if (!hasRequiredHealthData) {
      return OptionResult(const [],
          'Complete your health profile first so SARAP can calculate your '
          'calorie target.',
          failed: true);
    }
    if (dayIndex < 0 || dayIndex >= mealPlan.length) {
      return OptionResult(const [], 'The meal plan is not ready yet.',
          failed: true);
    }

    final menu = await _loadEligibleMenu();
    if (menu == null) {
      return OptionResult(const [],
          'Could not load menus. Check your connection and try again.',
          failed: true);
    }

    final day = mealPlan[dayIndex];
    final entry = day.meals.firstWhere((m) => m.slot == slot);
    final slotName = slot.label.toLowerCase();
    final isSwap = entry.isFilled;
    final skipped = _skippedNote(menu.skipped);

    List<MenuItem> found;
    String? emptyMsg;
    int? allowance;
    int reference;

    if (isSwap) {
      final current = entry.calories ?? 0;
      reference = current;
      final tol = (current * MatchingEngine.swapCalorieTolerance).round();
      found = MatchingEngine.eligibleForSlot(
        profile,
        menu.items,
        slot,
        minCalories: current - tol,
        maxCalories: current + tol,
        excludeDish: entry.dishName,
      );
      emptyMsg = 'No other dish fits your budget, dietary restrictions and '
          'calorie range for $slotName. Your current meal was kept.$skipped';
    } else {
      allowance = remainingFor(day);
      reference = allowance;
      if (allowance <= 0) {
        return OptionResult(
          const [],
          'No calories left for ${day.dayLabel} ($allowance kcal remaining), '
          'so no $slotName dish can be suggested without going over your target.',
          allowance: allowance,
        );
      }
      found = MatchingEngine.eligibleForSlot(profile, menu.items, slot,
          maxCalories: allowance);
      if (found.isEmpty) {
        final anyFit = MatchingEngine.eligibleForSlot(profile, menu.items, slot);
        emptyMsg = anyFit.isEmpty
            ? MatchingEngine.explainNoMatches(profile, menu.items) + skipped
            : 'No $slotName dish fits within your remaining $allowance kcal.'
                '$skipped';
      }
    }

    found.sort((a, b) => (a.calories - reference)
        .abs()
        .compareTo((b.calories - reference).abs()));

    final options = [
      for (final i in found)
        MealOption(i, menu.namesById[i.restaurantId] ?? 'Unknown')
    ];
    return OptionResult(options, options.isEmpty ? emptyMsg : null,
        isSwap: isSwap, allowance: allowance);
  }

  /// Commits the user's pick. The options are re-checked against fresh data
  /// first, so a dish that was hidden or changed while the picker was open
  /// is rejected and the original meal stays untouched.
  /// Returns null on success, otherwise a message to show.
  Future<String?> chooseOption(
      int dayIndex, MealSlot slot, MealOption option) async {
    final fresh = await loadOptions(dayIndex, slot);
    if (fresh.failed) return fresh.message;

    final match = fresh.options.where((o) => o.item.id == option.item.id);
    if (match.isEmpty) {
      return 'That dish is no longer available or no longer fits. '
          'The list was refreshed — please choose again.';
    }
    final chosen = match.first;
    final ok = await _commitSlot(dayIndex, slot,
        dishName: chosen.item.name,
        restaurantName: chosen.restaurantName,
        calories: chosen.item.calories);
    return ok ? null : planMessage;
  }

  /// Adds a dish discovered on a restaurant page to a chosen day and slot.
  /// Applies the same rules as the planner: local, valid price/calories,
  /// budget, dietary restrictions, and the day's remaining calories.
  /// Returns null on success, otherwise a message to show.
  Future<String?> addMenuItemToPlan(
    MenuItem item,
    Restaurant restaurant,
    int dayIndex,
    MealSlot slot,
  ) async {
    if (!hasRequiredHealthData) {
      return 'Complete your health profile first so SARAP can calculate '
          'your calorie target.';
    }
    ensureEmptyMealPlanIfNeeded();
    if (dayIndex < 0 || dayIndex >= mealPlan.length) {
      return 'The meal plan is not ready yet.';
    }
    if (!_isLocal(restaurant)) {
      return 'Only restaurants in Tanauan City can be added to your plan.';
    }
    if (!MatchingEngine.isUsable(item)) {
      return 'This dish has no valid price or calories, so it cannot be planned.';
    }
    if (!MatchingEngine.fitsProfile(profile, item)) {
      return 'This dish does not fit your budget or dietary restrictions.';
    }

    final day = mealPlan[dayIndex];
    final entry = day.meals.firstWhere((m) => m.slot == slot);
    final allowance = remainingFor(day) + (entry.calories ?? 0);
    if (item.calories > allowance) {
      return 'This dish (${item.calories} kcal) is more than the '
          '${allowance < 0 ? 0 : allowance} kcal left for ${day.dayLabel}.';
    }

    final ok = await _commitSlot(dayIndex, slot,
        dishName: item.name,
        restaurantName: restaurant.name,
        calories: item.calories);
    return ok ? null : planMessage;
  }

  void resetForSignOut() {
    profile = UserProfile();
    mealPlan = [];
    planMessage = null;
    missingHealthFields = [];
    _healthProfileLoaded = false;
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

/// Menu items that are allowed in a plan (active, available, from visible
/// local restaurants, with a valid price and calories) plus the restaurant
/// names to display for them. [skipped] counts local items that were left
/// out because their price or calories were missing or invalid.
class _EligibleMenu {
  final List<MenuItem> items;
  final Map<String, String> namesById;
  final int skipped;
  _EligibleMenu(this.items, this.namesById, this.skipped);
}

/// One dish the user can pick for a slot, with its restaurant's name.
class MealOption {
  final MenuItem item;
  final String restaurantName;
  MealOption(this.item, this.restaurantName);
}

/// What the swap / empty-slot picker should show.
class OptionResult {
  final List<MealOption> options;

  /// Why [options] is empty (or why loading failed). Null when there are options.
  final String? message;

  /// True when the options could not be loaded at all (offline, incomplete
  /// profile) as opposed to "loaded fine, nothing fits".
  final bool failed;

  /// True when the slot already had a meal (swap), false for an empty slot.
  final bool isSwap;

  /// Calories left for the day (empty-slot mode only).
  final int? allowance;

  OptionResult(this.options, this.message,
      {this.failed = false, this.isSwap = false, this.allowance});
}