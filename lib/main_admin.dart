import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'screens/admin/admin_gate.dart';
import 'theme.dart';

/// Entry point for the web admin dashboard. Run it with:
///   flutter run -d chrome -t lib/main_admin.dart
/// and build it with:
///   flutter build web -t lib/main_admin.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (kIsWeb) {
    // The admin login lasts only for this browser tab: closing the tab or
    // the browser signs the admin out. A page refresh keeps them signed in.
    await FirebaseAuth.instance.setPersistence(Persistence.SESSION);
  }

  runApp(const SarapAdminApp());
}

class SarapAdminApp extends StatelessWidget {
  const SarapAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SARAP Admin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const AdminGate(),
    );
  }
}