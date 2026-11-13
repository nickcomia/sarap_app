import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';
import 'theme.dart';
import 'screens/splash_screen.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding/onboarding_flow.dart';
import 'screens/verify_email_screen.dart';
import 'services/notification_service.dart';
import 'services/firebase_service.dart';
import 'app_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // These two do not depend on each other, so run them at the same time.
  // App Check proves to Firebase AI Logic that requests come from the real
  // app. The debug provider is for development builds only; switch to
  // AndroidProvider.playIntegrity before releasing. Skipped on web, which
  // needs a separate reCAPTCHA setup.
  await Future.wait(<Future<dynamic>>[
    if (!kIsWeb)
      FirebaseAppCheck.instance.activate(androidProvider: AndroidProvider.debug),
    NotificationService.initialize(),
  ]);

  var onboardingDone = true;
  var emailVerified = true;

  if (FirebaseService.currentUid != null) {
    // Only ask the server again when the saved state says "not verified"
    // (the user may have just tapped the link). Verified users skip this.
    emailVerified = FirebaseService.isEmailVerified;
    if (!emailVerified) {
      try {
        await FirebaseAuth.instance.currentUser?.reload();
      } catch (_) {}
      emailVerified = FirebaseService.isEmailVerified;
    }

    if (emailVerified) {
      // Load the user's data and check onboarding at the same time.
      // loadCurrentUserIfLoggedIn() only waits for quick cache-first reads;
      // the slow work continues in the background after the first screen.
      final results = await Future.wait<dynamic>([
        AppState.instance.loadCurrentUserIfLoggedIn(),
        // A logged-in user who closed the app mid-onboarding must resume
        // it rather than land on Home (TC-034). If the check fails
        // (e.g. offline), let them in rather than lock them out.
        FirebaseService.isOnboardingComplete().catchError((_) => true),
      ]);
      onboardingDone = results[1] as bool;
    }
  } else {
    AppState.instance.loadRestaurantsFromServer();
  }

  runApp(SarapApp(onboardingDone: onboardingDone, emailVerified: emailVerified));
}

// Built once. AppState notifies many times while data loads, and rebuilding
// the whole theme on every notification was wasted work.
final ThemeData _lightTheme = AppTheme.light();
final ThemeData _darkTheme = AppTheme.dark();

class SarapApp extends StatelessWidget {
  final bool onboardingDone;
  final bool emailVerified;
  const SarapApp({
    super.key,
    this.onboardingDone = true,
    this.emailVerified = true,
  });

  @override
  Widget build(BuildContext context) {
    final Widget startScreen;
    if (FirebaseService.currentUid == null) {
      startScreen = const SplashScreen();
    } else if (!emailVerified) {
      // Signed in but the email is not verified yet: verify first.
      startScreen = VerifyEmailScreen(email: FirebaseService.currentEmail ?? '');
    } else if (!onboardingDone) {
      startScreen = const OnboardingFlow();
    } else {
      startScreen = const HomeShell();
    }

    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'SARAP',
          debugShowCheckedModeBanner: false,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          themeMode: AppState.instance.themeMode,
          home: startScreen,
        );
      },
    );
  }
}