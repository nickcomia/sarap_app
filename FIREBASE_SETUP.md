# SARAP — Firebase Setup

The app now uses **Firebase Authentication** (email/password accounts)
and **Cloud Firestore** (cloud database) instead of a self-hosted
MySQL/PHP backend. This satisfies the "cloud-based data storage"
requirement without you needing to host or maintain a server.

## 1. Create the Firebase project

1. Go to https://console.firebase.google.com → **Add project**
2. Name it (e.g. `sarap-app`) → skip Google Analytics if you're not
   sure you need it → **Create project**

## 2. Enable Email/Password sign-in

**Build → Authentication → Get started** → **Sign-in method** tab →
enable **Email/Password**.

## 3. Create the Firestore database

**Build → Firestore Database → Create database** → choose a location
close to you → start in **test mode** (open read/write for 30 days —
fine for development; see the security rules note below before you
actually demo/submit).
java
## 4. Install the FlutterFire CLI

```
dart pub global activate flutterfire_cli
```

If `flutterfire` isn't found afterward, make sure Dart's global pub
bin folder is on your PATH (the activate command prints the exact
folder path on your OS).

You also need the Firebase CLI itself:
```
npm install -g firebase-tools
firebase login
```
(This needs Node.js — https://nodejs.org — if you don't have it.)

## 5. Connect this project to your Firebase project

From inside the `sarap_app` folder:
```
flutterfire configure
```
- Pick the Firebase project you created in step 1
- Select platforms: at minimum **android**; add **web** too if you
  also want to test in Chrome
- This overwrites `lib/firebase_options.dart` with your real config —
  that's expected, don't hand-edit that file.

## 6. Run it

```
flutter pub get
flutter run
```

Register a new account on the splash screen → complete onboarding →
you should see your account appear under **Authentication → Users** in
the Firebase console, and a `profiles/{uid}` document appear under
**Firestore Database**.

The **first time** any user reaches the Home/Discovery feed, the app
automatically pushes the 8 sample Tanauan City restaurants into a
`restaurants` collection in Firestore (no manual data entry needed) —
after that, everyone reads from that same collection.

## Data layout (Firestore)

```
users/{uid}                        { name, email, createdAt }
profiles/{uid}                     { establishmentTypes, cuisines, mealTypes,
                                      spiciness, sweetness, maxBudget,
                                      dietaryRestrictions, age, heightCm,
                                      weightKg, sex, activityLevel, healthGoal }
restaurants/{restaurantId}         { name, type, cuisine, distanceKm,
                                      matchPercent, priceRange, rating,
                                      address, description, tags, accentColorValue }
users/{uid}/saved/{restaurantId}   { savedAt }
users/{uid}/mealPlan/{day_slot}    { dayLabel, slot, dishName,
                                      restaurantName, calories }
```

## Before your demo/submission: lock down security rules

Test mode leaves the whole database open to anyone for 30 days — fine
for development, not something you want live during grading. In the
Firebase console, **Firestore Database → Rules**, replace with:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /restaurants/{restaurantId} {
      allow read: if true;
      allow write: if request.auth != null;
    }
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
      match /{subcollection=**} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
    }
    match /profiles/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

This means: anyone can read the restaurant list (public reference
data), but a user can only read/write their own profile, saved places,
and meal plan — which directly supports the rubric's "security" line
under Database and Data Management.
