# BrewVerse Cafe Manager — Flutter starter

This project is a starter for a cloud-connected cafe stock app. It includes:
- Firebase initialization (requires generated `lib/firebase_options.dart`)
- Live inventory list
- Add ingredient/finished-product stock item
- Add stock and record stock movements
- Dashboard low-stock list
- Product photo upload service
- Basic PDF bill generator

## Before running

1. Install Flutter and Android Studio.
2. Open this folder in Android Studio.
3. In the terminal, run `flutter pub get`.
4. Install/configure Firebase CLI and FlutterFire CLI:
   - `npm install -g firebase-tools`
   - `firebase login`
   - `dart pub global activate flutterfire_cli`
   - `flutterfire configure`
5. Enable Email/Password Authentication, Firestore, and Storage in Firebase Console.
6. Create a Firestore `stock_items` collection by adding your first item from the app.
7. Configure secure Firestore and Storage rules before using real data.
8. Run `flutter run`.

## Important status

This is a development starter, not a production-ready POS. The checkout flow that atomically deducts recipe ingredients, secure staff roles, PDF bill screen, and push notification backend still need implementation.

## Desktop

Flutter desktop support must be enabled for your target OS. Run `flutter devices` to see available targets. If you want a browser-based computer version, enable web support and select Web in `flutterfire configure`.

## Current starter note

For correct opening-stock history, use the fix described below before using the Add Item form:
- Create new items with quantity `0`.
- After the item is created, use the “Add stock” button to record the opening stock. This records the initial amount exactly once.
