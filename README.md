# SARAP — Smart Food Finder (Flutter App)

A working Flutter implementation of the UI designs from the SARAP capstone
manuscript's **User Design Interface** section (Figures 7–16): splash
screen, sign in/register, the 4-step onboarding flow (food preferences,
taste & budget, health profile, summary), the Home/Discovery feed, the
restaurant detail screen, the 7-day meal plan, Saved places, and Profile.

It's a self-contained, **local-data prototype** — no backend server is
required to run it. Restaurant data is bundled as sample Tanauan City
listings, and BMI / BMR / TDEE / calorie-target math is computed on-device
from what the user enters in onboarding (Mifflin-St Jeor equation). The
7-day meal plan is generated from that calorie target using sample dishes.
This lets you run the whole app end-to-end immediately, then swap the
mocked pieces (`lib/mock_data.dart`) for real API/GIS/AI calls later.

## Project structure

```
lib/
  main.dart                     # App entry point
  theme.dart                    # Colors & ThemeData (matches the mockups)
  models.dart                   # UserProfile, Restaurant, MealEntry, DayPlan
  app_state.dart                # Single app-wide ChangeNotifier (no extra packages)
  mock_data.dart                # Sample Tanauan City restaurants + meal-plan generator
  widgets/common.dart           # Reusable chip, card, badge, menu-tile widgets
  screens/
    splash_screen.dart          # Figure 7
    auth_screen.dart            # Figure 8
    onboarding/
      onboarding_flow.dart      # Step controller (progress bar + PageView)
      step1_food_preferences.dart   # Figure 9
      step2_taste_budget.dart       # Figure 10
      step3_health_profile.dart     # Figure 11
      step4_summary.dart            # Figure 12
    home_shell.dart             # Bottom nav shell (Figure 13, item 4)
    discovery_feed.dart         # Figure 13
    restaurant_detail_screen.dart   # Figure 14
    meal_plan_screen.dart       # Figure 15
    saved_screen.dart           # Saved tab
    profile_screen.dart         # Figure 16
```

## Running it in VS Code

1. **Install prerequisites** (skip any you already have):
   - [Flutter SDK](https://docs.flutter.dev/get-started/install) — run `flutter doctor` afterward and fix anything it flags.
   - VS Code extensions: **Flutter** and **Dart** (from the Extensions panel).
   - A target device: an Android emulator, iOS simulator (Mac only), or just
     run it in Chrome — no emulator needed for that.

2. **Open the project**
   - Unzip this project, then in VS Code: `File → Open Folder…` → select the `sarap_app` folder.

3. **Get packages**
   - Open a terminal in VS Code (`` Ctrl+` ``) and run:
     ```
     flutter pub get
     ```

4. **Run the app**
   - Press `F5`, or use the terminal:
     ```
     flutter run
     ```
   - If no device is attached, `flutter run -d chrome` runs it straight in
     a browser tab — the fastest way to see it working.

That's it — no API keys, no backend, no extra setup. Every screen is
wired together with real navigation and shared state, so you can
register → complete onboarding → get a generated meal plan → browse
restaurants → save places → edit your profile, all in one flow.

## Where to plug in the real backend later

- `lib/mock_data.dart` → replace `MockData.restaurants()` with your GIS/API
  restaurant fetch, and `generateMealPlan()` with your real AI meal-plan
  generation call.
- `lib/screens/auth_screen.dart` → swap the local `_submit()` logic for
  real Firebase/REST authentication.
- `lib/app_state.dart` → this is the single place that holds app state;
  point its methods at real services instead of the in-memory data without
  touching any screen code.
