import 'package:cloud_firestore/cloud_firestore.dart';

/// Returns the locally cached copy of a query if there is one (instant),
/// otherwise falls back to the server.
Future<QuerySnapshot<Map<String, dynamic>>> getCacheFirst(
    Query<Map<String, dynamic>> query) async {
  try {
    final cached = await query.get(const GetOptions(source: Source.cache));
    if (cached.docs.isNotEmpty) return cached;
  } catch (_) {
    // Not cached yet, fall through to the server.
  }
  return query.get();
}

/// Same idea for a single document.
Future<DocumentSnapshot<Map<String, dynamic>>> getDocCacheFirst(
    DocumentReference<Map<String, dynamic>> ref) async {
  try {
    final cached = await ref.get(const GetOptions(source: Source.cache));
    if (cached.exists) return cached;
  } catch (_) {
    // Not cached yet, fall through to the server.
  }
  return ref.get();
}