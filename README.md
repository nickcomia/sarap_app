# SARAP — AI-Assisted Restaurant Finder with Personalized Meal Planning

SARAP is a Flutter mobile app that helps people in **Tanauan City, Batangas** find restaurants and plan meals that fit their health profile, food preferences, and budget. It was developed as a capstone project.

## Download (Android)

Get the latest APK from the **[Releases page](https://github.com/nickcomia/sarap_app/releases/latest)**.

1. Download `SARAP.apk` on your Android phone.
2. Allow **Install unknown apps** when Android asks.
3. Tap **Install**. If Play Protect warns you, tap **Install anyway**.

Requires Android 6.0 or newer.

## Features

- **Restaurant discovery:** browse nearby restaurants and menus, with map and location support.
- **Personalized onboarding:** food preferences, taste and budget, and health profile.
- **Meal planning:** daily calorie target computed on-device (BMI, BMR, TDEE using the Mifflin-St Jeor equation) and a 7-day meal plan built from it.
- **AI-assisted picks:** menu recommendations generated with Gemini through Firebase AI Logic.
- **Saved places and profile:** save favorite restaurants and manage your account.
- **Sign-in:** email/password and Google sign-in through Firebase Authentication.
- **Admin dashboard (web):** manage restaurants and menu items, import menu items from CSV, view users, and manage content.

## Tech stack

| Area | Technology |
|---|---|
| App | Flutter (Dart), Material 3 |
| Backend | Firebase Authentication, Cloud Firestore, Firebase Storage, Firebase App Check |
| AI | Firebase AI Logic (Gemini) |
| Maps and location | Google Maps, Geolocator |
| Admin dashboard | Flutter Web, hosted on Vercel |

## Project structure

    lib/
      main.dart               # Mobile app entry point
      main_admin.dart         # Admin dashboard entry point (web)
      theme.dart              # Colors and ThemeData
      models.dart             # Data models
      app_state.dart          # App-wide state
      services/               # Firebase and location services
      screens/                # Mobile screens (splash, auth, onboarding, home, detail, plan, profile)
      screens/admin/          # Admin dashboard screens
      widgets/                # Reusable widgets
    assets/
      icons/                  # App icon
      photos/                 # Bundled images

The output in `build/web` is deployed to Vercel.

## Notes

- This project is for academic purposes.

## Author

Nick Aeron Comia, Sto. Tomas City, Batangas