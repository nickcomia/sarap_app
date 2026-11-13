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

/// Waits for [work] for at most [limit]. If it is slower (slow or no
/// internet) or fails, start-up simply carries on; the work keeps running
/// in the background and the screens update when it finishes.
Future<void> _bestEffort(Future<dynamic> work, Duration limit) async {
  try {
    await work.timeout(limit);
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Local set-up only: does not wait for the internet.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // App Check proves to Firebase AI Logic that requests come from the real
  // app. The debug provider is for development builds only; switch to
  // AndroidProvider.playIntegrity before releasing. Skipped on web, which
  // needs a separate reCAPTCHA setup.
  // Run together, and never wait more than 2 seconds for them.
  await _bestEffort(
    Future.wait(<Future<dynamic>>[
      if (!kIsWeb)
        FirebaseAppCheck.instance.activate(androidProvider: AndroidProvider.debug),
      NotificationService.initialize(),
    ]),
    const Duration(seconds: 2),
  );

  var onboardingDone = true;
  var emailVerified = true;

  if (FirebaseService.currentUid != null) {
    // Firebase keeps the user signed in on the device, so this needs no
    // internet. Only an account that looks unverified is re-checked online
    // (the user may have just tapped the link), and only for a few seconds.
    emailVerified = FirebaseService.isEmailVerified;
    if (!emailVerified) {
      await _bestEffort(
        FirebaseAuth.instance.currentUser?.reload() ?? Future<void>.value(),
        const Duration(seconds: 3),
      );
      emailVerified = FirebaseService.isEmailVerified;
    }

    if (emailVerified) {
      // Whether onboarding is finished was saved on this device last time,
      // so the first screen can be chosen instantly, even offline.
      final saved = await FirebaseService.cachedOnboardingComplete();
      if (saved != null) {
        onboardingDone = saved;
        // Re-check quietly; the answer is stored for the next start.
        FirebaseService.isOnboardingComplete().catchError((_) => true);
      } else {
        // Nothing saved yet (first start after an update): ask the server,
        // but give up after 3 seconds and let the user in (TC-034 resume
        // still works once the answer is known).
        try {
          onboardingDone =
              await FirebaseService.isOnboardingComplete().timeout(const Duration(seconds: 3));
        } catch (_) {
          onboardingDone = true;
        }
      }

      // Re-download the saved profile, restaurants, saved places and meal
      // plan (cache-first). Wait at most 1.5 seconds; whatever is not ready
      // by then keeps loading and the screens update by themselves.
      await _bestEffort(
        AppState.instance.loadCurrentUserIfLoggedIn(),
        const Duration(milliseconds: 1500),
      );
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