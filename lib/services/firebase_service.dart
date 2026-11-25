import 'dart:io';
import 'dart:typed_data';
import 'cache_first.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import '../mock_data.dart';

/// Thrown on any auth/database failure with a message safe to show the
/// user directly (kept as the same name/shape the app previously used
/// for the PHP backend, so screens didn't need to change).
class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

/// Result of recording a moderation violation for the signed-in user.
class ViolationOutcome {
  final int strikes;
  final DateTime? bannedUntil;
  final bool disabled;
  final String message; // safe to show the user

  ViolationOutcome({
    required this.strikes,
    required this.bannedUntil,
    required this.disabled,
    required this.message,
  });
}

/// Wraps Firebase Authentication + Cloud Firestore. Data layout:
///
///   users/{uid}                 -> { name, email, createdAt,
///                                    strikes, bannedUntil, status, ... }
///   profiles/{uid}               -> onboarding + health profile fields
///   restaurants/{restaurantId}   -> sample Tanauan City restaurants
///   reviews/{uid_restaurantId}   -> user reviews (pending/approved/rejected)
///   moderationActions/{id}       -> audit trail of warnings, bans, disables
///   users/{uid}/saved/{restaurantId}     -> bookmark marker docs
///   users/{uid}/mealPlan/{day_slot}      -> one doc per meal slot
class FirebaseService {
  static final _auth = fb_auth.FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;
  static final _storage = FirebaseStorage.instance;

  static String? get currentUid => _auth.currentUser?.uid;
  static String? get currentEmail => _auth.currentUser?.email;

  // ------------------------------------------------------------------
  // Auth
  // ------------------------------------------------------------------

  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      final uid = cred.user!.uid;
      await cred.user!.updateDisplayName(name);
      await cred.user!.sendEmailVerification();

      await _db.collection('users').doc(uid).set({
        'name': name,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
      });
      // Default profile row the app fills in as onboarding progresses.
      await _db.collection('profiles').doc(uid).set(_defaultProfileMap());
      _cacheOnboarding(uid, false);

      return {'userId': uid, 'name': name, 'email': email};
    } on fb_auth.FirebaseAuthException catch (e) {
      throw ApiException(_friendlyAuthError(e));
    }
  }

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(email: email, password: password);

      // Do NOT resend the email or sign out here: the app shows the Verify
      // screen, which has its own resend button with a cool-down. Sending a
      // new email on every login attempt is what triggers Firebase's
      // "blocked all requests from this device" error.
      if (!isEmailVerified) {
        throw ApiException(
          'Please verify your email first. Check your inbox and spam folder.',
        );
      }

      final uid = cred.user!.uid;
      final doc = await _db.collection('users').doc(uid).get();
      final data = doc.data() ?? {};
      return {
        'userId': uid,
        'name': data['name'] ?? cred.user!.displayName ?? '',
        'email': data['email'] ?? email,
      };
    } on fb_auth.FirebaseAuthException catch (e) {
      throw ApiException(_friendlyAuthError(e));
    }
  }

  static Future<void> logout() async => _auth.signOut();

  /// Writes/updates the users/{uid} doc for a Google Sign-In account.
  /// Google's flow never calls register(), so without this, cold-start
  /// rehydration (fetchUserDoc) finds nothing and falls back to defaults.
  /// Safe to call on every Google sign-in (new or returning) — merge:true
  /// means it won't clobber anything else already there.
  ///
  /// Also creates the profiles/{uid} doc for first-time Google users, with
  /// onboardingCompleted = false, so onboarding is enforced for them.
  static Future<void> syncGoogleUserDoc({
    required String name,
    required String email,
  }) async {
    final uid = currentUid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).set({
      'name': name,
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final profileRef = _db.collection('profiles').doc(uid);
    if (!(await profileRef.get()).exists) {
      await profileRef.set(_defaultProfileMap());
    }
  }

  /// Whether the currently signed-in user's email is verified. Returns
  /// true for providers that don't need this check (e.g. there's no
  /// signed-in user at all — caller should check isLoggedIn separately).
  static bool get isEmailVerified {
    final user = _auth.currentUser;
    if (user == null) return false;
    // Only email/password accounts need email verification. Google and
    // Facebook accounts are already verified by the provider (Facebook
    // users otherwise show emailVerified == false and would be signed
    // out on every app start).
    final usesPassword =
        user.providerData.any((p) => p.providerId == 'password');
    return !usesPassword || user.emailVerified;
  }

  /// Resends Firebase's built-in email verification link to the current
  /// user. No-op if already verified or not logged in.
  static Future<void> resendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user == null || user.emailVerified) return;
    try {
      await user.sendEmailVerification();
    } on fb_auth.FirebaseAuthException catch (e) {
      throw ApiException(_friendlyAuthError(e));
    }
  }

  /// Refreshes the account from the server and says whether the email is
  /// verified now. Used by the Verify screen.
  static Future<bool> checkEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  /// Sends Firebase's built-in password reset email. Throws [ApiException]
  /// only for a malformed email address — deliberately does NOT distinguish
  /// "no account found" from "email sent", so the UI can show one generic
  /// message and avoid revealing whether an email is registered.
  static Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on fb_auth.FirebaseAuthException catch (e) {
      if (e.code == 'invalid-email') {
        throw ApiException('Enter a valid email address');
      }
      // user-not-found, etc. — silently succeed from the caller's view.
    }
  }

  /// Starts an email change. Re-checks the current password first (Firebase
  /// requires a recent sign-in for this), then sends a verification link to
  /// the NEW address. The account's email only changes once that link is
  /// opened. Throws [ApiException] with a message safe to show the user.
  static Future<void> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) async {
    final user = _auth.currentUser;
    final oldEmail = user?.email;
    if (user == null || oldEmail == null) {
      throw ApiException('You are not signed in');
    }
    try {
      final cred = fb_auth.EmailAuthProvider.credential(
        email: oldEmail,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(cred);
      await user.verifyBeforeUpdateEmail(newEmail);
    } on fb_auth.FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        throw ApiException('Your current password is incorrect');
      }
      if (e.code == 'too-many-requests') {
        throw ApiException('Too many attempts — please try again later');
      }
      throw ApiException(_friendlyAuthError(e));
    }
  }

  /// Call on app start: if the user opened the verification link, Firebase
  /// Auth now has the new email but users/{uid} still has the old one. This
  /// refreshes the auth user and copies the new email into Firestore.
  /// Returns the new email if it changed, otherwise null. Never throws.
  static Future<String?> syncEmailFromAuth() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;
      await user.reload();
      final fresh = _auth.currentUser?.email;
      if (fresh == null) return null;
      final doc = await _db.collection('users').doc(user.uid).get();
      if (doc.data()?['email'] == fresh) return null;
      await _db
          .collection('users')
          .doc(user.uid)
          .set({'email': fresh}, SetOptions(merge: true));
      return fresh;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------
  // Profile
  // ------------------------------------------------------------------

  static Future<void> updateProfile(UserProfile profile) async {
    final uid = currentUid;
    if (uid == null) return;
    await _db.collection('profiles').doc(uid).set({
      'establishmentTypes': profile.establishmentTypes.toList(),
      'cuisines': profile.cuisines.toList(),
      'mealTypes': profile.mealTypes.toList(),
      'spiciness': profile.spiciness,
      'sweetness': profile.sweetness,
      'maxBudget': profile.maxBudget,
      'dietaryRestrictions': profile.dietaryRestrictions.toList(),
      'age': profile.age,
      'heightCm': profile.heightCm,
      'weightKg': profile.weightKg,
      'sex': profile.sex.name,
      'activityLevel': profile.activityLevel.name,
      'healthGoal': profile.healthGoal.name,
      'goalWeightKg': profile.goalWeightKg,
    }, SetOptions(merge: true));
  }

  /// Fetches the users/{uid} doc (name, email) for the currently logged-in
  /// account — used on cold app start to rehydrate the real profile instead
  /// of showing UserProfile()'s placeholder defaults.
  static Future<Map<String, dynamic>?> fetchUserDoc() async {
    final uid = currentUid;
    if (uid == null) return null;
    final doc = await getDocCacheFirst(_db.collection('users').doc(uid));
    return doc.data();
  }

  /// Fetches the profiles/{uid} doc (onboarding + health fields) for the
  /// currently logged-in account — same cold-start rehydration purpose.
  static Future<Map<String, dynamic>?> fetchProfileDoc() async {
    final uid = currentUid;
    if (uid == null) return null;
    final doc = await getDocCacheFirst(_db.collection('profiles').doc(uid));
    return doc.data();
  }

  /// Whether the signed-in user has finished the onboarding flow.
  /// Reads straight from the server (not the cache) so the answer is
  /// always current. Accounts created before this flag existed have no
  /// 'onboardingCompleted' field and count as completed.
  static Future<bool> isOnboardingComplete() async {
    final uid = currentUid;
    if (uid == null) return false;
    final doc = await _db.collection('profiles').doc(uid).get();
    // A missing doc means a brand-new account.
    final done = doc.exists && doc.data()?['onboardingCompleted'] != false;
    _cacheOnboarding(uid, done);
    return done;
  }

  /// The onboarding answer saved on THIS device the last time it was known,
  /// or null if never saved. Instant and works without internet, so the app
  /// can pick its first screen without waiting for the network.
  static Future<bool?> cachedOnboardingComplete() async {
    final uid = currentUid;
    if (uid == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('onboarding_done_$uid');
    } catch (_) {
      return null;
    }
  }

  static Future<void> _cacheOnboarding(String uid, bool done) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_done_$uid', done);
    } catch (_) {}
  }

  /// Call when the user finishes the last onboarding step.
  static Future<void> markOnboardingComplete() async {
    final uid = currentUid;
    if (uid == null) return;
    await _db
        .collection('profiles')
        .doc(uid)
        .set({'onboardingCompleted': true}, SetOptions(merge: true));
    _cacheOnboarding(uid, true);
  }

  static Map<String, dynamic> _defaultProfileMap() => {
        'establishmentTypes': [],
        'cuisines': [],
        'mealTypes': [],
        'spiciness': 1,
        'sweetness': 1,
        'maxBudget': 150,
        'dietaryRestrictions': [],
        'age': 21,
        'heightCm': 165,
        'weightKg': 60,
        'sex': 'notSaid',
        'activityLevel': 'moderate',
        'healthGoal': 'maintain',
        'onboardingCompleted': false,
      };

  // ------------------------------------------------------------------
  // Restaurants
  // ------------------------------------------------------------------

  static Future<List<Restaurant>> fetchRestaurants({
    bool forceServer = false, // kept so existing callers still compile
    bool includeUnavailable = false,
  }) async {
    // Cache-first unless the caller asks for the server copy: the first
    // paint is instant, and AppState refreshes from the server afterwards.
    // (forceServer used to be ignored, so every call waited on the network.)
    if (!forceServer) {
      try {
        final cached = await _db
            .collection('restaurants')
            .get(const GetOptions(source: Source.cache));
        if (cached.docs.isNotEmpty) {
          return cached.docs
              .where((d) => includeUnavailable || d.data()['available'] != false)
              .map(_restaurantFromDoc)
              .toList();
        }
      } catch (_) {
        // Nothing cached yet (first launch): fall through to the server.
      }
    }

    final snap = await _db.collection('restaurants').get();

    if (snap.docs.isEmpty) {
      // First run: seed the bundled sample data, then read it back.
      await _seedRestaurants();
      final reseeded = await _db.collection('restaurants').get();
      return reseeded.docs
          .where((d) => includeUnavailable || d.data()['available'] != false)
          .map(_restaurantFromDoc)
          .toList();
    }

    return snap.docs
        .where((d) => includeUnavailable || d.data()['available'] != false)
        .map(_restaurantFromDoc)
        .toList();
  }

  static Restaurant _restaurantFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final r = d.data();
    return Restaurant(
      id: d.id,
      name: r['name'] ?? '',
      type: r['type'] ?? '',
      cuisine: r['cuisine'] ?? '',
      distanceKm: (r['distanceKm'] as num?)?.toDouble() ?? 0,
      matchPercent: (r['matchPercent'] as num?)?.toInt() ?? 0,
      priceRange: r['priceRange'] ?? '₱',
      priceMin: (r['priceMin'] as num?)?.toDouble(),
      priceMax: (r['priceMax'] as num?)?.toDouble(),
      rating: (r['rating'] as num?)?.toDouble() ?? 0,
      address: r['address'] ?? '',
      description: r['description'] ?? '',
      tags: List<String>.from(r['tags'] ?? []),
      accentColorValue: (r['accentColorValue'] as num?)?.toInt() ?? 0xFFFFB199,
      latitude: (r['latitude'] as num?)?.toDouble() ?? 14.0863,
      longitude: (r['longitude'] as num?)?.toDouble() ?? 121.1497,
      imageUrl: r['imageUrl'],
    );
  }

  static Future<void> _seedRestaurants() async {
    final batch = _db.batch();
    for (final r in MockData.restaurants()) {
      batch.set(_db.collection('restaurants').doc(r.id), {
        'name': r.name,
        'type': r.type,
        'cuisine': r.cuisine,
        'distanceKm': r.distanceKm,
        'matchPercent': r.matchPercent,
        'priceRange': r.priceRange,
        'priceMin': r.priceMin,
        'priceMax': r.priceMax,
        'rating': r.rating,
        'address': r.address,
        'description': r.description,
        'tags': r.tags,
        'accentColorValue': r.accentColorValue,
        'latitude': r.latitude,
        'longitude': r.longitude,
        'imageUrl': r.imageUrl,
      });
    }
    await batch.commit();
  }

  // ------------------------------------------------------------------
  // Admin: add real restaurants & menu items (with photos)
  // ------------------------------------------------------------------

  /// Uploads a photo file to Firebase Storage under [folder] and returns
  /// its public download URL. Used for both restaurant cover photos and
  /// individual menu item photos.
  static Future<String> uploadImage(File file, String folder) async {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = _storage.ref().child('$folder/$fileName');
    await ref.putFile(file);
    return await ref.getDownloadURL();
  }

  /// Same as uploadImage, but takes raw bytes so it also works on web
  /// (dart:io File is not available in browsers).
  static Future<String> uploadImageBytes(Uint8List bytes, String folder) async {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = _storage.ref().child('$folder/$fileName');
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return await ref.getDownloadURL();
  }

  /// Creates a brand-new restaurant document (used by the in-app admin
  /// "Add restaurant" screen). Returns the new restaurant's id.
  static Future<String> addRestaurant({
    required String name,
    required String type,
    required String cuisine,
    String? priceRange, // optional: derived from priceMin/priceMax when given
    num? priceMin, // lowest dish price in PHP (int or double)
    num? priceMax, // highest dish price in PHP (int or double)
    required double rating,
    required String address,
    required String description,
    required List<String> tags,
    required double latitude,
    required double longitude,
    String? imageUrl,
  }) async {
    final doc = _db.collection('restaurants').doc();
    await doc.set({
      'name': name,
      'type': type,
      'cuisine': cuisine,
      'distanceKm': 0.0,
      'matchPercent': 80, // placeholder until the matching algorithm runs
      ..._priceFields(priceRange, priceMin, priceMax),
      'rating': rating,
      'address': address,
      'description': description,
      'tags': tags,
      'accentColorValue': 0xFFFFB199,
      'latitude': latitude,
      'longitude': longitude,
      'imageUrl': imageUrl,
    });
    return doc.id;
  }

  /// Turns the admin's price inputs into the fields stored on a restaurant.
  /// With a lowest and highest price, the tier shown in the app (₱, ₱₱, ₱₱₱)
  /// is derived automatically, so the two can never disagree. Without them
  /// (old forms), the tier passed in is kept.
  static Map<String, dynamic> _priceFields(String? tier, num? min, num? max) {
    if (min != null || max != null) {
      if (min == null || max == null) {
        throw ApiException('Enter both the lowest and the highest price');
      }
      final lo = min.toDouble();
      final hi = max.toDouble();
      if (!lo.isFinite || !hi.isFinite || lo <= 0) {
        throw ApiException('The lowest price must be greater than 0');
      }
      if (hi < lo) {
        throw ApiException('The highest price cannot be lower than the lowest price');
      }
      if (hi > 100000) {
        throw ApiException('The highest price looks too large — check the amount');
      }
      return {
        'priceRange': Restaurant.priceTierFor(lo, hi),
        'priceMin': lo,
        'priceMax': hi,
      };
    }
    return {'priceRange': tier ?? '₱₱', 'priceMin': null, 'priceMax': null};
  }

  /// Rejects menu values that would break calorie arithmetic or create a
  /// "free" meal. Throws [ApiException] with a message safe to show.
  static void _validateMenuValues({double? price, int? calories}) {
    if (price != null && (!price.isFinite || price <= 0)) {
      throw ApiException('Enter a price greater than 0');
    }
    if (calories != null && (calories <= 0 || calories > 10000)) {
      throw ApiException('Enter calories between 1 and 10000');
    }
  }

  /// Adds a menu item (dish/product) under a restaurant, with its own
  /// photo. Stored at restaurants/{restaurantId}/menuItems/{itemId}.
  static Future<void> addMenuItem({
    required String restaurantId,
    required String name,
    required double price,
    required int calories,
    required List<String> mealTypes,
    required List<String> dietaryTags,
    String? imageUrl,
  }) async {
    _validateMenuValues(price: price, calories: calories);
    await _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('menuItems')
        .add({
      'name': name,
      'price': price,
      'calories': calories,
      'mealTypes': mealTypes,
      'dietaryTags': dietaryTags,
      'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<List<MenuItem>> fetchMenuItems(
    String restaurantId, {
    bool includeUnavailable = false,
  }) async {
    final snap = await _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('menuItems')
        .get();
    return snap.docs
        .where((d) => includeUnavailable || d.data()['available'] != false)
        .map((d) {
      final m = d.data();
      return MenuItem(
        id: d.id,
        restaurantId: restaurantId,
        name: m['name'] ?? '',
        price: _asDouble(m['price']),
        calories: _asInt(m['calories']),
        mealTypes: _asStringList(m['mealTypes']),
        dietaryTags: _asStringList(m['dietaryTags']),
        imageUrl: m['imageUrl'],
      );
    }).toList();
  }

  /// Fetches every restaurant's menu items in a single Firestore round
  /// trip using a collection group query, instead of one .get() call
  /// per restaurant (what fetchMenuItems() does one at a time). Each
  /// MenuItem already carries its own restaurantId, so callers can group
  /// them locally if needed.
  static Future<List<MenuItem>> fetchAllMenuItems({bool includeUnavailable = false}) async {
    final snap = await _db.collectionGroup('menuItems').get();
    return snap.docs
        .where((d) => includeUnavailable || d.data()['available'] != false)
        .map((d) {
      final m = d.data();
      final restaurantId = d.reference.parent.parent!.id;
      return MenuItem(
        id: d.id,
        restaurantId: restaurantId,
        name: m['name'] ?? '',
        price: _asDouble(m['price']),
        calories: _asInt(m['calories']),
        mealTypes: _asStringList(m['mealTypes']),
        dietaryTags: _asStringList(m['dietaryTags']),
        imageUrl: m['imageUrl'],
      );
    }).toList();
  }

  // ---- Admin: availability, edit, delete ----

  /// restaurantId -> visible in the app? (missing field counts as visible)
  static Future<Map<String, bool>> fetchRestaurantAvailability() async {
    final snap = await _db.collection('restaurants').get();
    return {for (final d in snap.docs) d.id: d.data()['available'] != false};
  }

  /// menuItemId -> visible in the app? (missing field counts as visible)
  static Future<Map<String, bool>> fetchMenuItemAvailability(
      String restaurantId) async {
    final snap = await _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('menuItems')
        .get();
    return {for (final d in snap.docs) d.id: d.data()['available'] != false};
  }

  static Future<void> setRestaurantAvailable(String id, bool available) async {
    await _db.collection('restaurants').doc(id).update({'available': available});
  }

  static Future<void> setMenuItemAvailable(
      String restaurantId, String itemId, bool available) async {
    await _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('menuItems')
        .doc(itemId)
        .update({'available': available});
  }

  static Future<void> updateRestaurant({
    required String id,
    required String name,
    required String type,
    required String cuisine,
    String? priceRange, // optional: derived from priceMin/priceMax when given
    num? priceMin, // lowest dish price in PHP (int or double)
    num? priceMax, // highest dish price in PHP (int or double)
    required double rating,
    required String address,
    required String description,
    required List<String> tags,
    required double latitude,
    required double longitude,
    String? imageUrl,
  }) async {
    await _db.collection('restaurants').doc(id).update({
      'name': name,
      'type': type,
      'cuisine': cuisine,
      ..._priceFields(priceRange, priceMin, priceMax),
      'rating': rating,
      'address': address,
      'description': description,
      'tags': tags,
      'latitude': latitude,
      'longitude': longitude,
      'imageUrl': imageUrl,
    });
  }

  /// Deletes a restaurant AND its menu items (Firestore does not delete
  /// sub-collections automatically).
  static Future<void> deleteRestaurant(String id) async {
    final ref = _db.collection('restaurants').doc(id);
    final items = await ref.collection('menuItems').get();
    final batch = _db.batch();
    for (final d in items.docs) {
      batch.delete(d.reference);
    }
    batch.delete(ref);
    await batch.commit();
  }

  static Future<void> updateMenuItem({
    required String restaurantId,
    required String itemId,
    required String name,
    required double price,
    required int calories,
    required List<String> mealTypes,
    required List<String> dietaryTags,
    String? imageUrl,
  }) async {
    _validateMenuValues(price: price, calories: calories);
    await _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('menuItems')
        .doc(itemId)
        .update({
      'name': name,
      'price': price,
      'calories': calories,
      'mealTypes': mealTypes,
      'dietaryTags': dietaryTags,
      'imageUrl': imageUrl,
    });
  }

  static Future<void> deleteMenuItem(String restaurantId, String itemId) async {
    await _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('menuItems')
        .doc(itemId)
        .delete();
  }

  // ---- Admin: dashboard, users, reports, content ----

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  static String _shortDate(DateTime d) => '${_monthNames[d.month - 1]} ${d.day}';

  /// Counts map -> list of {name, count}, biggest first.
  static List<Map<String, dynamic>> _ranked(Map<String, int> m, {int? take}) {
    final list = m.entries
        .map((e) => <String, dynamic>{'name': e.key, 'count': e.value})
        .toList()
      ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
    return take == null ? list : list.take(take).toList();
  }

  /// Numbers for the admin dashboard: growth, coverage, popularity, diner
  /// demand, reviews and moderation. Only counts and totals are produced,
  /// never one diner's details. Every extended part is best effort: if a
  /// Firestore rule blocks it, that part is reported as unavailable and the
  /// rest of the dashboard still loads.
  static Future<Map<String, dynamic>> fetchDashboardStats() async {
    final now = DateTime.now();

    // ---- Users: growth and moderation state ----
    final usersSnap = await _db.collection('users').get();
    var newUsers = 0;
    final weekCounts = List<int>.filled(8, 0);
    var withStrikes = 0, bannedNow = 0, disabledUsers = 0, totalStrikes = 0;
    for (final d in usersSnap.docs) {
      final m = d.data();
      final ts = m['createdAt'];
      if (ts is Timestamp) {
        final days = now.difference(ts.toDate()).inDays;
        if (days < 7) newUsers++;
        final w = days ~/ 7;
        if (w >= 0 && w < 8) weekCounts[w]++;
      }
      final strikes = _asInt(m['strikes']);
      if (strikes > 0) {
        withStrikes++;
        totalStrikes += strikes;
      }
      final b = m['bannedUntil'];
      if (b is Timestamp && b.toDate().isAfter(now)) bannedNow++;
      if (m['status'] == 'disabled') disabledUsers++;
    }
    final signups = [
      for (var i = 7; i >= 0; i--)
        <String, dynamic>{
          'name': _shortDate(now.subtract(Duration(days: 7 * i + 6))),
          'count': weekCounts[i],
        }
    ];

    // ---- Restaurants and menus ----
    final restSnap = await _db.collection('restaurants').get();
    final itemsSnap = await _db.collectionGroup('menuItems').get();
    final itemsPer = <String, int>{};
    for (final d in itemsSnap.docs) {
      final rid = d.reference.parent.parent!.id;
      itemsPer[rid] = (itemsPer[rid] ?? 0) + 1;
    }

    final names = <String, String>{};
    final cuisineOf = <String, String>{};
    final typeCounts = <String, int>{};
    final cuisineCounts = <String, int>{};
    final tagSupply = <String, int>{};
    final rated = <Map<String, dynamic>>[];
    final noMenuNames = <String>[];
    final buckets = <String, int>{
      '4.5 and above': 0,
      '4.0 to 4.4': 0,
      '3.0 to 3.9': 0,
      'Below 3.0': 0,
      'Not rated': 0,
    };
    var ratingSum = 0.0, ratingN = 0, hidden = 0;
    for (final d in restSnap.docs) {
      final m = d.data();
      final name = (m['name'] ?? '').toString();
      names[d.id] = name;
      final type = (m['type'] ?? 'Other').toString();
      typeCounts[type] = (typeCounts[type] ?? 0) + 1;
      final cuisine = (m['cuisine'] ?? 'Other').toString();
      cuisineOf[d.id] = cuisine;
      cuisineCounts[cuisine] = (cuisineCounts[cuisine] ?? 0) + 1;
      for (final t in _asStringList(m['tags'])) {
        final k = t.toLowerCase().trim();
        if (k.isNotEmpty) tagSupply[k] = (tagSupply[k] ?? 0) + 1;
      }
      final rating = (m['rating'] as num?)?.toDouble() ?? 0;
      if (rating > 0) {
        ratingSum += rating;
        ratingN++;
        rated.add({'name': name, 'rating': rating});
        if (rating >= 4.5) {
          buckets['4.5 and above'] = buckets['4.5 and above']! + 1;
        } else if (rating >= 4.0) {
          buckets['4.0 to 4.4'] = buckets['4.0 to 4.4']! + 1;
        } else if (rating >= 3.0) {
          buckets['3.0 to 3.9'] = buckets['3.0 to 3.9']! + 1;
        } else {
          buckets['Below 3.0'] = buckets['Below 3.0']! + 1;
        }
      } else {
        buckets['Not rated'] = buckets['Not rated']! + 1;
      }
      if (m['available'] == false) hidden++;
      if ((itemsPer[d.id] ?? 0) == 0) noMenuNames.add(name);
    }
    rated.sort((a, b) => (b['rating'] as double).compareTo(a['rating'] as double));
    final topRated = rated.take(5).toList();
    final lowRated = rated.reversed.take(5).toList();

    // ---- Saved places (needs the admin read rule for "saved") ----
    final saved = <String, int>{};
    var savedOk = true;
    try {
      final s = await _db.collectionGroup('saved').get();
      for (final d in s.docs) {
        saved[d.id] = (saved[d.id] ?? 0) + 1;
      }
    } catch (_) {
      savedOk = false;
    }
    final savesByCuisine = <String, int>{};
    final mostSaved = <String, int>{};
    final noSaveNames = <String>[];
    if (savedOk) {
      saved.forEach((id, n) {
        final c = cuisineOf[id];
        if (c != null) savesByCuisine[c] = (savesByCuisine[c] ?? 0) + n;
        mostSaved[names[id] ?? id] = n;
      });
      for (final id in names.keys) {
        if (!saved.containsKey(id)) noSaveNames.add(names[id]!);
      }
    }

    // ---- Diner profiles: demand (best effort) ----
    var profilesOk = true;
    var profileCount = 0, onboarded = 0;
    var budgetSum = 0.0, budgetN = 0;
    final goalMix = <String, int>{};
    final demandCuisines = <String, int>{};
    final demandDiets = <String, int>{};
    try {
      final ps = await _db.collection('profiles').get();
      profileCount = ps.docs.length;
      const goalLabels = {
        'lose': 'Lose weight',
        'maintain': 'Maintain weight',
        'gain': 'Gain weight',
      };
      for (final d in ps.docs) {
        final m = d.data();
        if (m['onboardingCompleted'] == false) continue;
        onboarded++;
        final g = goalLabels[m['healthGoal']];
        if (g != null) goalMix[g] = (goalMix[g] ?? 0) + 1;
        for (final c in _asStringList(m['cuisines'])) {
          demandCuisines[c] = (demandCuisines[c] ?? 0) + 1;
        }
        for (final c in _asStringList(m['dietaryRestrictions'])) {
          demandDiets[c] = (demandDiets[c] ?? 0) + 1;
        }
        final b = (m['maxBudget'] as num?)?.toDouble();
        if (b != null && b > 0) {
          budgetSum += b;
          budgetN++;
        }
      }
    } catch (_) {
      profilesOk = false;
    }

    // ---- Meal plans (best effort) ----
    var plansOk = true;
    final planUsers = <String>{};
    try {
      final mp = await _db.collectionGroup('mealPlan').get();
      for (final d in mp.docs) {
        if (d.data()['dishName'] != null) {
          planUsers.add(d.reference.parent.parent!.id);
        }
      }
    } catch (_) {
      plansOk = false;
    }

    // ---- Reviews (best effort) ----
    var reviewsOk = true;
    var rApproved = 0, rPending = 0, rRejected = 0;
    var rSum = 0.0;
    final reviewers = <String>{};
    final reviewedCounts = <String, int>{};
    try {
      final rs = await _db.collection('reviews').get();
      for (final d in rs.docs) {
        final m = d.data();
        reviewers.add((m['userId'] ?? '').toString());
        final st = m['status'];
        if (st == 'approved') {
          rApproved++;
          rSum += _asInt(m['rating']).toDouble();
          final n = names[m['restaurantId']] ?? (m['restaurantName'] ?? '').toString();
          if (n.isNotEmpty) reviewedCounts[n] = (reviewedCounts[n] ?? 0) + 1;
        } else if (st == 'rejected') {
          rRejected++;
        } else {
          rPending++;
        }
      }
    } catch (_) {
      reviewsOk = false;
    }

    // ---- Appeals and moderation actions (best effort) ----
    var appealsOk = true;
    var aPending = 0, aApproved = 0, aRejected = 0;
    try {
      final as = await _db.collection('appeals').get();
      for (final d in as.docs) {
        final st = d.data()['status'];
        if (st == 'approved') {
          aApproved++;
        } else if (st == 'rejected') {
          aRejected++;
        } else {
          aPending++;
        }
      }
    } catch (_) {
      appealsOk = false;
    }
    var actionsOk = true;
    final actionCounts = <String, int>{};
    try {
      final ms = await _db.collection('moderationActions').get();
      const actionLabels = {
        'warning': 'Warnings',
        'temporary_ban': 'Temporary bans',
        'disabled': 'Accounts disabled',
      };
      for (final d in ms.docs) {
        final a = d.data()['action']?.toString() ?? 'other';
        final label = actionLabels[a] ?? 'Other actions';
        actionCounts[label] = (actionCounts[label] ?? 0) + 1;
      }
    } catch (_) {
      actionsOk = false;
    }

    return {
      // headline numbers (used by the Overview page too)
      'users': usersSnap.docs.length,
      'newUsers': newUsers,
      'restaurants': restSnap.docs.length,
      'hiddenRestaurants': hidden,
      'menuItems': itemsSnap.docs.length,
      'avgRating': ratingN == 0 ? 0.0 : ratingSum / ratingN,
      'byType': _ranked(typeCounts),
      'mostSaved': _ranked(mostSaved, take: 10),
      'totalSaves': saved.values.fold<int>(0, (a, b) => a + b),
      'savedOk': savedOk,
      // growth and coverage
      'signups': signups,
      'byCuisine': _ranked(cuisineCounts),
      'ratingBuckets': buckets.entries
          .map((e) => <String, dynamic>{'name': e.key, 'count': e.value})
          .toList(),
      'topRated': topRated,
      'lowRated': lowRated,
      'noMenuCount': noMenuNames.length,
      'noMenuNames': noMenuNames.take(6).toList(),
      'noSaveCount': noSaveNames.length,
      'noSaveNames': noSaveNames.take(6).toList(),
      'savesByCuisine': _ranked(savesByCuisine),
      'tagSupply': tagSupply,
      // diner demand
      'profilesOk': profilesOk,
      'profileCount': profileCount,
      'onboardedCount': onboarded,
      'goalMix': _ranked(goalMix),
      'demandCuisines': _ranked(demandCuisines, take: 8),
      'demandDiets': _ranked(demandDiets, take: 8),
      'avgBudget': budgetN == 0 ? null : budgetSum / budgetN,
      'plansOk': plansOk,
      'usersWithPlan': planUsers.length,
      // reviews and moderation
      'reviewsOk': reviewsOk,
      'reviewsApproved': rApproved,
      'reviewsPending': rPending,
      'reviewsRejected': rRejected,
      'avgReviewRating': rApproved == 0 ? null : rSum / rApproved,
      'reviewers': reviewers.where((e) => e.isNotEmpty).length,
      'mostReviewed': _ranked(reviewedCounts, take: 5),
      'usersWithStrikes': withStrikes,
      'totalStrikes': totalStrikes,
      'bannedNow': bannedNow,
      'disabledUsers': disabledUsers,
      'appealsOk': appealsOk,
      'appealsPending': aPending,
      'appealsApproved': aApproved,
      'appealsRejected': aRejected,
      'actionsOk': actionsOk,
      'actionsByType': _ranked(actionCounts),
    };
  }

  /// Every document of [collection] as a map (with its id). Timestamps are
  /// converted to DateTime; newest createdAt first.
  static Future<List<Map<String, dynamic>>> adminListDocs(String collection) async {
    final snap = await _db.collection(collection).get();
    final list = snap.docs.map((d) {
      final m = <String, dynamic>{'id': d.id};
      d.data().forEach((k, v) {
        m[k] = v is Timestamp ? v.toDate() : v;
      });
      return m;
    }).toList();
    list.sort((a, b) {
      final x = a['createdAt'];
      final y = b['createdAt'];
      if (x is DateTime && y is DateTime) return y.compareTo(x);
      if (x is DateTime) return -1;
      if (y is DateTime) return 1;
      return 0;
    });
    return list;
  }

  /// Creates (id == null) or merges into (id given) a document.
  static Future<void> adminSaveDoc(
      String collection, String? id, Map<String, dynamic> data) async {
    if (id == null) {
      await _db
          .collection(collection)
          .add({...data, 'createdAt': FieldValue.serverTimestamp()});
    } else {
      await _db.collection(collection).doc(id).set(data, SetOptions(merge: true));
    }
  }

  static Future<void> adminDeleteDoc(String collection, String id) async {
    await _db.collection(collection).doc(id).delete();
  }

  /// Removes everything the app stores for one user: users/{uid} with its
  /// saved + mealPlan subcollections, and profiles/{uid}.
  /// This does NOT delete the login itself (Firebase Authentication);
  /// that has to be done in the Firebase console.
  static Future<void> adminDeleteUserData(String uid) async {
    final userRef = _db.collection('users').doc(uid);

    // Subcollections first: deleting a document does not delete them.
    for (final sub in const ['saved', 'mealPlan']) {
      final snap = await userRef.collection(sub).get();
      if (snap.docs.isEmpty) continue;
      final subBatch = _db.batch();
      for (final d in snap.docs) {
        subBatch.delete(d.reference);
      }
      await subBatch.commit();
    }

    final batch = _db.batch();
    batch.delete(_db.collection('profiles').doc(uid));
    batch.delete(userRef);
    await batch.commit();
  }

  /// '<restaurantId>/<itemId>' -> { proteinG, carbsG, fatG } for every menu item.
  static Future<Map<String, Map<String, dynamic>>> fetchNutritionExtras() async {
    final snap = await _db.collectionGroup('menuItems').get();
    return {
      for (final d in snap.docs)
        '${d.reference.parent.parent!.id}/${d.id}': {
          'proteinG': d.data()['proteinG'],
          'carbsG': d.data()['carbsG'],
          'fatG': d.data()['fatG'],
        }
    };
  }

  static Future<void> updateMenuItemNutrition({
    required String restaurantId,
    required String itemId,
    required int calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
  }) async {
    _validateMenuValues(calories: calories);
    await _db
        .collection('restaurants')
        .doc(restaurantId)
        .collection('menuItems')
        .doc(itemId)
        .update({
      'calories': calories,
      'proteinG': proteinG,
      'carbsG': carbsG,
      'fatG': fatG,
    });
  }

  /// Numeric Firestore fields sometimes get entered as strings (e.g. via
  /// the console). Handle both shapes safely.
  static double _asDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  /// Firestore fields that should be arrays sometimes get entered as a
  /// plain string (e.g. via the console). Handle both shapes safely.
  static List<String> _asStringList(dynamic value) {
    if (value == null) return [];
    if (value is List) return List<String>.from(value);
    if (value is String) return [value];
    return [];
  }

  // ------------------------------------------------------------------
  // Saved places
  // ------------------------------------------------------------------

  static Future<List<String>> fetchSavedIds() async {
    final uid = currentUid;
    if (uid == null) return [];
    final snap = await getCacheFirst(
        _db.collection('users').doc(uid).collection('saved'));
    return snap.docs.map((d) => d.id).toList();
  }

  static Future<bool> toggleSaved(String restaurantId) async {
    final uid = currentUid;
    if (uid == null) return false;
    final ref = _db.collection('users').doc(uid).collection('saved').doc(restaurantId);
    final doc = await ref.get();
    if (doc.exists) {
      await ref.delete();
      return false;
    } else {
      await ref.set({'savedAt': FieldValue.serverTimestamp()});
      return true;
    }
  }

  // ------------------------------------------------------------------
  // Meal plan
  // ------------------------------------------------------------------

  /// Replaces the whole saved plan in one atomic batch. Slot documents have
  /// fixed ids (day_slot), so running this twice can never leave duplicates.
  /// The existing docs are read from the SERVER on purpose: offline this
  /// throws instead of silently queuing a write that would land later.
  static Future<void> saveMealPlan(List<DayPlan> plan) async {
    final uid = currentUid;
    if (uid == null) return;
    final col = _db.collection('users').doc(uid).collection('mealPlan');

    final batch = _db.batch();
    final existing = await col.get(const GetOptions(source: Source.server));
    for (final d in existing.docs) {
      batch.delete(d.reference);
    }
    for (final day in plan) {
      for (final meal in day.meals) {
        final id = '${day.dayLabel}_${meal.slot.name}';
        batch.set(col.doc(id), {
          'dayLabel': day.dayLabel,
          'slot': meal.slot.name,
          'dishName': meal.dishName,
          'restaurantName': meal.restaurantName,
          'calories': meal.calories,
        });
      }
    }
    await batch.commit();
  }

  static Future<List<Map<String, dynamic>>> fetchMealPlanEntries() async {
    final uid = currentUid;
    if (uid == null) return [];
    final snap = await getCacheFirst(
        _db.collection('users').doc(uid).collection('mealPlan'));
    return snap.docs.map((d) => d.data()).toList();
  }

  /// Writes one slot. Done as a transaction so it only succeeds when the
  /// server actually accepted it: offline or on timeout it throws, and the
  /// app then leaves the on-screen meal unchanged. The doc id is fixed
  /// (day_slot), so a retry overwrites the same slot — never adds a second.
  static Future<void> replaceMeal({
    required String dayLabel,
    required MealSlot slot,
    String? dishName,
    String? restaurantName,
    int? calories,
  }) async {
    final uid = currentUid;
    if (uid == null) return;
    final id = '${dayLabel}_${slot.name}';
    final ref = _db.collection('users').doc(uid).collection('mealPlan').doc(id);
    await _db.runTransaction((tx) async {
      tx.set(ref, {
        'dayLabel': dayLabel,
        'slot': slot.name,
        'dishName': dishName,
        'restaurantName': restaurantName,
        'calories': calories,
      });
    }, timeout: const Duration(seconds: 10));
  }

  // ------------------------------------------------------------------
  // Reviews & moderation
  // ------------------------------------------------------------------

  static Review _reviewFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final ts = m['createdAt'];
    final dish = (m['dish'] as String?)?.trim();
    return Review(
      id: d.id,
      restaurantId: m['restaurantId'] ?? '',
      userId: m['userId'] ?? '',
      userName: m['userName'] ?? 'SARAP user',
      rating: _asInt(m['rating']).clamp(1, 5).toInt(),
      text: m['text'] ?? '',
      dish: (dish == null || dish.isEmpty) ? null : dish,
      status: ReviewStatus.values.firstWhere(
        (s) => s.name == m['status'],
        orElse: () => ReviewStatus.pending,
      ),
      rejectReason: m['rejectReason'],
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }

  /// Approved reviews of one restaurant, newest first. Sorted here so no
  /// composite index is needed.
  static Future<List<Review>> fetchApprovedReviews(String restaurantId) async {
    final snap = await _db
        .collection('reviews')
        .where('restaurantId', isEqualTo: restaurantId)
        .where('status', isEqualTo: 'approved')
        .get();
    final list = snap.docs.map(_reviewFromDoc).toList();
    list.sort((a, b) => (b.createdAt ?? DateTime(2000))
        .compareTo(a.createdAt ?? DateTime(2000)));
    return list;
  }

  /// The signed-in user's own review(s) of one restaurant (any status).
  /// Normally at most one; older data saved before the one-review rule can
  /// have more.
  static Future<List<Review>> fetchMyReviews(String restaurantId) async {
    final uid = currentUid;
    if (uid == null) return [];
    final snap = await _db
        .collection('reviews')
        .where('userId', isEqualTo: uid)
        .where('restaurantId', isEqualTo: restaurantId)
        .get();
    return snap.docs.map(_reviewFromDoc).toList();
  }

  /// Saves a review. Each user may write ONE review per restaurant: a new
  /// review is stored under the id '<uid>_<restaurantId>', so a second one
  /// for the same place cannot exist (the database rules enforce this too).
  /// If the user already has a review of this place, it is edited instead:
  /// it goes back to 'pending' so the admin checks the new text, and its
  /// createdAt is kept. [reviewId] is the review being edited, if known.
  static Future<void> submitReview({
    required Restaurant restaurant,
    required String userName,
    required int rating,
    required String text,
    String? dish,
    String? reviewId,
  }) async {
    final uid = currentUid;
    if (uid == null) throw ApiException('You are not signed in');
    if (rating < 1 || rating > 5) {
      throw ApiException('Choose a rating from 1 to 5');
    }

    final cleanDish =
        (dish == null || dish.trim().isEmpty) ? null : dish.trim();

    try {
      // A review saved before the one-review rule has a random id. Edit it
      // instead of creating a second review of the same place.
      var editId = reviewId;
      if (editId == null) {
        final mine = await fetchMyReviews(restaurant.id);
        if (mine.isNotEmpty) editId = mine.first.id;
      }

      if (editId != null) {
        // Edit: same record, back to pending. createdAt is kept.
        await _db.collection('reviews').doc(editId).update({
          'restaurantName': restaurant.name,
          'userName': userName,
          'rating': rating,
          'text': text.trim(),
          'dish': cleanDish,
          'status': 'pending',
          'rejectReason': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await _db.collection('reviews').doc('${uid}_${restaurant.id}').set({
          'restaurantId': restaurant.id,
          'restaurantName': restaurant.name,
          'userId': uid,
          'userName': userName,
          'rating': rating,
          'text': text.trim(),
          'dish': cleanDish,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw ApiException(
            'You cannot post or edit reviews right now. Please try again later.');
      }
      rethrow;
    }
  }

  /// strikes / bannedUntil / disabled state of the signed-in user.
  static Future<Map<String, dynamic>> fetchModerationState() async {
    final uid = currentUid;
    if (uid == null) return {};
    final doc = await _db.collection('users').doc(uid).get();
    final d = doc.data() ?? {};
    final ts = d['bannedUntil'];
    return {
      'strikes': _asInt(d['strikes']),
      'bannedUntil': ts is Timestamp ? ts.toDate() : null,
      'disabled': d['status'] == 'disabled',
      'disabledReason': d['disabledReason'],
    };
  }

  /// Adds one strike to the signed-in user and applies the penalty ladder:
  /// 1 = warning, 2 = 3-day ban, 3 = 7-day ban, 4+ = account disabled.
  static Future<ViolationOutcome> recordViolation({required String reason}) async {
    final uid = currentUid;
    if (uid == null) throw ApiException('You are not signed in');
    final ref = _db.collection('users').doc(uid);
    late ViolationOutcome outcome;

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final strikes = _asInt(snap.data()?['strikes']) + 1;
      DateTime? until;
      var disabled = false;
      String message;

      if (strikes == 1) {
        message = 'Warning: hateful or abusive language is not allowed in '
            'SARAP. Your review was not submitted. Another violation will '
            'lead to a temporary ban.';
      } else if (strikes == 2) {
        until = DateTime.now().add(const Duration(days: 3));
        message = 'Your review was not submitted. You are banned from '
            'posting reviews for 3 days because of repeated violations.';
      } else if (strikes == 3) {
        until = DateTime.now().add(const Duration(days: 7));
        message = 'Your review was not submitted. You are banned from '
            'posting reviews for 7 days because of repeated violations.';
      } else {
        disabled = true;
        message = 'Your account has been disabled because of repeated '
            'violations.';
      }

      tx.set(ref, {
        'strikes': strikes,
        if (until != null) 'bannedUntil': Timestamp.fromDate(until),
        if (disabled) 'status': 'disabled',
        if (disabled)
          'disabledReason': 'Repeated use of hateful or abusive language.',
        'lastViolationAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      outcome = ViolationOutcome(
        strikes: strikes,
        bannedUntil: until,
        disabled: disabled,
        message: message,
      );
    }, timeout: const Duration(seconds: 10));

    // Audit trail for the admin console. Best effort only.
    try {
      await _db.collection('moderationActions').add({
        'userId': uid,
        'action': outcome.disabled
            ? 'disabled'
            : (outcome.bannedUntil != null ? 'temporary_ban' : 'warning'),
        'strikes': outcome.strikes,
        'reason': reason,
        'source': 'word_filter',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}

    return outcome;
  }

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  static String _friendlyAuthError(fb_auth.FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'An account with this email already exists';
      case 'invalid-email':
        return 'Enter a valid email address';
      case 'weak-password':
        return 'Password is too weak — use at least 6 characters';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password';
      case 'network-request-failed':
        return 'Could not reach Firebase — check your internet connection';
      case 'too-many-requests':
        return 'Too many attempts from this device. Please wait a while and try again.';
      default:
        return e.message ?? 'Authentication failed';
    }
  }
}