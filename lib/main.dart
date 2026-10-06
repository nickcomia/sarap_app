import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';
import 'theme.dart';
import 'screens/splash_screen.dart';
import 'screens/home_shell.dart';
import 'services/notification_service.dart';
import 'services/firebase_service.dart';
import 'app_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // App Check proves to Firebase AI Logic that requests come from the real
  // app. The debug provider is for development builds only; switch to
  // AndroidProvider.playIntegrity before releasing. Skipped on web, which
  // needs a separate reCAPTCHA setup.
  if (!kIsWeb) {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.debug,
    );
  }

  await NotificationService.initialize();

  // Firebase Auth silently keeps the user logged in across app restarts,
  // but AppState.profile always starts as a fresh UserProfile() with
  // placeholder defaults — nothing re-downloads the real saved profile
  // unless this runs. Without it, a returning logged-in user sees demo
  // data ("Juan Dela Cruz", default BMI) instead of their own every time
  // they reopen the app.
  if (FirebaseService.currentUid != null) {
    await AppState.instance.loadCurrentUserIfLoggedIn();
  } else {
    AppState.instance.loadRestaurantsFromServer();
  }

  runApp(const SarapApp());
}

class SarapApp extends StatelessWidget {
  const SarapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'SARAP',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: AppState.instance.themeMode,
          home: FirebaseService.currentUid != null
              ? const HomeShell()
              : const SplashScreen(),
        );
      },
    );
  }
}