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
}
