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





## Run from source

Requirements: Flutter SDK, an Android device or emulator, and your own Firebase project.

```bash
git clone https://github.com/nickcomia/sarap_app.git
cd sarap_app
flutter pub get
flutter run
```

You need to add your own Firebase configuration (`android/app/google-services.json`) and API keys. These are not included in the repository.

### Build a release APK

```bash
flutter build apk --release --split-per-abi
```

Release signing uses `android/key.properties` and a keystore. Both are kept out of version control.

### Build the admin dashboard (web)

```bash
flutter build web --release -t lib/main_admin.dart
```

The output in `build/web` is deployed to Vercel.

## Notes

- The Facebook login option was removed; Google and email sign-in are supported.
- This project is for academic purposes.

## Author

Nick Aeron Comia, Sto. Tomas City, Batangas
