import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Admin authentication for the web dashboard.
///
/// An account is an admin only if a document exists at admins/{uid}.
/// Those documents are created by hand in the Firebase console, never by
/// the app, so nobody can promote themselves.
class AdminService {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

  static Stream<User?> get authChanges => _auth.authStateChanges();
  static User? get currentUser => _auth.currentUser;

  /// Asks the server (never the local cache) whether the signed-in user is
  /// an admin. Fails closed: any error, including being offline, means
  /// "not an admin".
  static Future<bool> isCurrentUserAdmin() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      final doc = await _db
          .collection('admins')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server));
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  static Future<void> signIn(String email, String password) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
  }

  static Future<void> signOut() => _auth.signOut();

  /// One generic message for wrong email and wrong password, so the page
  /// doesn't reveal which accounts exist.
  static String friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Enter a valid email address';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password';
      case 'too-many-requests':
        return 'Too many attempts. Wait a few minutes and try again.';
      case 'network-request-failed':
        return 'Could not reach Firebase. Check your internet connection.';
      default:
        return e.message ?? 'Sign-in failed';
    }
  }

  // ------------------------------------------------------------------
  // Reviews & moderation
  // ------------------------------------------------------------------

  static int _int(dynamic v) => v is num ? v.toInt() : 0;

  static DateTime _old(dynamic d) => d is DateTime ? d : DateTime(2000);

  /// Copies a document's fields, turns Timestamps into DateTime and adds
  /// the document id under 'id'.
  static Map<String, dynamic> _plain(String id, Map<String, dynamic> m) => {
        for (final e in m.entries)
          e.key: e.value is Timestamp
              ? (e.value as Timestamp).toDate()
              : e.value,
        'id': id,
      };

  /// Best-effort audit trail. Never blocks the admin action.
  static Future<void> _log(
    String userId,
    String action, {
    int? strikes,
    String? reason,
    String? reviewId,
  }) async {
    try {
      await _db.collection('moderationActions').add({
        'userId': userId,
        'action': action,
        if (strikes != null) 'strikes': strikes,
        if (reason != null) 'reason': reason,
        if (reviewId != null) 'reviewId': reviewId,
        'source': 'admin',
        'adminId': _auth.currentUser?.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Pending reviews, oldest first (sorted here so no index is needed).
  static Future<List<Map<String, dynamic>>> fetchPendingReviews() async {
    final snap = await _db
        .collection('reviews')
        .where('status', isEqualTo: 'pending')
        .get();
    final list = snap.docs.map((d) => _plain(d.id, d.data())).toList();
    list.sort((a, b) => _old(a['createdAt']).compareTo(_old(b['createdAt'])));
    return list;
  }

  static Future<void> approveReview(String reviewId) {
    return _db.collection('reviews').doc(reviewId).update({
      'status': 'approved',
      'rejectReason': FieldValue.delete(),
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': _auth.currentUser?.uid,
    });
  }

  /// Rejects a review without penalising the author.
  static Future<void> rejectReview(String reviewId, String reason) {
    return _db.collection('reviews').doc(reviewId).update({
      'status': 'rejected',
      'rejectReason': reason.isEmpty ? 'Rejected by admin' : reason,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': _auth.currentUser?.uid,
    });
  }

  /// Rejects a review AND adds a strike to its author, using the same
  /// ladder as the app: 1 = warning, 2 = 3-day ban, 3 = 7-day ban,
  /// 4+ = account disabled. Returns a short summary for the admin.
  static Future<String> rejectForViolation({
    required String reviewId,
    required String userId,
    required String reason,
  }) async {
    final reviewRef = _db.collection('reviews').doc(reviewId);
    final userRef = _db.collection('users').doc(userId);
    late String summary;
    late String action;
    late int strikes;
    final why = reason.isEmpty ? 'Violation of community rules' : reason;

    await _db.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      strikes = _int(snap.data()?['strikes']) + 1;
      DateTime? until;
      var disabled = false;

      if (strikes == 1) {
        action = 'warning';
        summary = 'Strike 1: the user received a warning.';
      } else if (strikes == 2) {
        until = DateTime.now().add(const Duration(days: 3));
        action = 'temporary_ban';
        summary = 'Strike 2: the user is banned from posting for 3 days.';
      } else if (strikes == 3) {
        until = DateTime.now().add(const Duration(days: 7));
        action = 'temporary_ban';
        summary = 'Strike 3: the user is banned from posting for 7 days.';
      } else {
        disabled = true;
        action = 'disabled';
        summary = 'Strike $strikes: the account has been disabled.';
      }

      tx.update(reviewRef, {
        'status': 'rejected',
        'rejectReason': why,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': _auth.currentUser?.uid,
      });
      tx.set(
        userRef,
        {
          'strikes': strikes,
          if (until != null) 'bannedUntil': Timestamp.fromDate(until),
          if (disabled) 'status': 'disabled',
          if (disabled)
            'disabledReason': 'Repeated use of hateful or abusive language.',
          'lastViolationAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });

    await _log(userId, action,
        strikes: strikes, reason: why, reviewId: reviewId);
    return summary;
  }

  // ------------------------------------------------------------------
  // Users
  // ------------------------------------------------------------------

  /// All user documents with their id, newest first.
  static Future<List<Map<String, dynamic>>> listUsers() async {
    final snap = await _db.collection('users').get();
    final list = snap.docs.map((d) => _plain(d.id, d.data())).toList();
    list.sort((a, b) => _old(b['createdAt']).compareTo(_old(a['createdAt'])));
    return list;
  }

  /// Bans a user from posting reviews for [days] days. Strikes unchanged.
  static Future<void> banUser(String userId, int days) async {
    final until = DateTime.now().add(Duration(days: days));
    await _db.collection('users').doc(userId).set({
      'bannedUntil': Timestamp.fromDate(until),
    }, SetOptions(merge: true));
    await _log(userId, 'temporary_ban', reason: 'Banned by admin for $days days');
  }

  /// Disables an account completely. The user sees the disabled screen the
  /// next time the app starts.
  static Future<void> disableUser(String userId, String reason) async {
    final why = reason.isEmpty ? 'Disabled by an administrator.' : reason;
    await _db.collection('users').doc(userId).set({
      'status': 'disabled',
      'disabledReason': why,
    }, SetOptions(merge: true));
    await _log(userId, 'disabled', reason: why);
  }

  /// Lifts a ban and/or re-enables a disabled account. Strikes go back to 0
  /// so the next violation starts again at a warning.
  static Future<void> restoreUser(String userId) async {
    await _db.collection('users').doc(userId).update({
      'strikes': 0,
      'bannedUntil': FieldValue.delete(),
      'status': FieldValue.delete(),
      'disabledReason': FieldValue.delete(),
    });
    await _log(userId, 'restored', reason: 'Ban lifted / account re-enabled');
  }
}