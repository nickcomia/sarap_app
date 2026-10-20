import 'dart:io';
import 'dart:typed_data';
import 'cache_first.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
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

/// Wraps Firebase Authentication + Cloud Firestore. Data layout:
///
///   users/{uid}                 -> { name, email, createdAt }
///   profiles/{uid}               -> onboarding + health profile fields
///   restaurants/{restaurantId}   -> sample Tanauan City restaurants
///   users/{uid}/saved/{restaurantId}     -> bookmark marker docs
///   users/{uid}/mealPlan/{day_slot}      -> one doc per meal slot
class FirebaseService {
  static final _auth = fb_auth.FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;
  static final _storage = FirebaseStorage.instance;

  static String? get currentUid => _auth.currentUser?.uid;

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

      if (!cred.user!.emailVerified) {
        await cred.user!.sendEmailVerification();
        await _auth.signOut();
        throw ApiException(
          'Please verify your email first — we just sent you a new link.',
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
  }

  /// Whether the currently signed-in user's email is verified. Returns
  /// true for providers that don't need this check (e.g. there's no
  /// signed-in user at all — caller should check isLoggedIn separately).
  static bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  /// Resends Firebase's built-in email verification link to the current
  /// user. No-op if already verified or not logged in.
  static Future<void> resendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user == null || user.emailVerified) return;
    await user.sendEmailVerification();
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
      };

  // ------------------------------------------------------------------
  // Restaurants
  // ------------------------------------------------------------------

  static Future<List<Restaurant>> fetchRestaurants({
    bool forceServer = false,
    bool includeUnavailable = false,
  }) async {
    final query = _db.collection('restaurants');
    final snap = forceServer ? await query.get() : await getCacheFirst(query);

    if (snap.docs.isEmpty) {
      // First run — nobody has seeded the "restaurants" collection yet.
      // Push the bundled sample data up so the app has something to show,
      // then read it back the same way as any other run.
      await _seedRestaurants();
      final reseeded = await _db.collection('restaurants').get();
      return reseeded.docs.map(_restaurantFromDoc).toList();
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
    required String priceRange,
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
      'priceRange': priceRange,
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
  static Future<List<MenuItem>> fetchAllMenuItems() async {
    final snap = await _db.collectionGroup('menuItems').get();
    return snap.docs
        .where((d) => d.data()['available'] != false)
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
    required String priceRange,
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
      'priceRange': priceRange,
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

  static Future<void> saveMealPlan(List<DayPlan> plan) async {
    final uid = currentUid;
    if (uid == null) return;
    final col = _db.collection('users').doc(uid).collection('mealPlan');

    final batch = _db.batch();
    final existing = await col.get();
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
    await _db.collection('users').doc(uid).collection('mealPlan').doc(id).set({
      'dayLabel': dayLabel,
      'slot': slot.name,
      'dishName': dishName,
      'restaurantName': restaurantName,
      'calories': calories,
    });
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
      default:
        return e.message ?? 'Authentication failed';
    }
  }
}