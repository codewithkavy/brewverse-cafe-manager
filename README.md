# BrewVerse Cafe Manager

BrewVerse is a Flutter café operations app for inventory, recipes, checkout, and sales summaries. The current branch also contains an **opt-in, emulator-first SaaS tenant prototype**. It is development work and is not approved for production rollout.

Current workflows include transactional opening stock, stock additions and checkout deductions; finished-product recipes; duplicate checkout protection; post-checkout receipt output; tenant membership and role controls; café-scoped sales summaries; and tenant-scoped product photo uploads. Flutter, trusted backend, and isolated Firebase Emulator tests cover these workflows. Bluetooth printer output and image picking still need physical-device verification.

## Before running

1. Install Flutter, Android Studio, Node.js 22, and Java.
2. Run `flutter pub get` from the project root.
3. For tenant development, follow [the isolated emulator preview](security-tests/README.md). It uses the test-only project ID `brewverse-security-tests` and does not require live Firebase credentials.
4. The generated Firebase options currently configure Android only. For a safe local tenant run, use the emulator defines shown in the preview guide; a plain `flutter run` uses the generated Firebase project options.

To run local Flutter checks, use `flutter analyze --no-pub`, `flutter test --no-pub`, and `flutter build apk --debug --no-pub`. The [GitHub Actions workflow](.github/workflows/ci.yml) runs Flutter checks and isolated emulator suites on pushes and pull requests.

## Important status

The legacy app path still uses unscoped records and client-side Firestore checkout. The tenant path is disabled by default, uses test-only rules and undeployed Functions, and is guarded from live Firebase unless a second explicit compile-time flag is supplied. Do not enable it against production until legacy data ownership, backup, migration rehearsal, indexes, and production rules are reviewed. Never deploy rules under `security-tests/` through the root Firebase project.

## Desktop

Flutter desktop support must be enabled for your target OS. Run `flutter devices` to see available targets. If you want a browser-based computer version, enable web support and select Web in `flutterfire configure`.

## Opening stock history

New items may be created with a positive opening quantity. The app writes the item and its opening stock movement in one Firestore transaction. Use the “Add stock” action for later deliveries or adjustments.
