# BrewVerse production handoff

Updated: 2026-10-19 (Asia/Kolkata). Work stopped at the user's request after stabilization and handoff. Do not automatically start another task.

## Git and preservation

- Initial branch: `feature/saas-foundation`, matching its remote before changes.
- Checkpoint `1448acb` preserves the existing first-party work (94 files, including ignore rules).
- Integration branch: `codex/production-integration-phase1`. No force-push, remote overwrite, deployment, migration, or paid subscription activation.
- Dependencies, build outputs, emulator logs/state, credentials, generated failed-golden images and original scratch files remain local and ignored. Existing tracked Firebase client configuration is public client identification, not an Admin credential. Never add service-account keys or signing credentials.
- The initial checkpoint intentionally contains earlier UI, loyalty, backend, and test work. Those features were not newly implemented in this final session.

## Architecture and Firebase configuration

- Flutter app: `lib/main.dart` initializes Firebase; `AuthGate` selects legacy UI or the opt-in `CafeWorkspaceGate`.
- Default startup is legacy mode. Existing unscoped inventory, recipes and bills remain unchanged. Do not infer ownership or silently move them to a café.
- `BREWVERSE_TENANT_MODE=true` enables membership-based workspace selection. `CafeService(cafeId: ...)` scopes reads and calls trusted Functions for checkout, new stock, additions and recipes. Stock detail/photo updates use Firestore rules. Without a café ID the service retains legacy transactions.
- Backend: `functions/src/index.js`, `membership_service.js`, `inventory_service.js`, `loyalty_service.js`, `billing_service.js`. Callables authenticate callers and verify active membership/role transactionally. Checkout computes prices from stored products, validates tenant recipe references, deducts stock and writes bills/movements atomically; retries use an idempotency key.
- Collections: `cafes`, `cafe_members` (document ID `<uid>_<cafeId>`), `stock_items`, `product_recipes`, `bills`, `stock_movements`; tenant documents carry `cafeId`. Loyalty is nested under each café.
- Existing client configuration identifies project `brewverse-593dc` in `lib/firebase_options.dart` and `android/app/google-services.json`. Root `firebase.json` links indexes only; it does not configure deployment of the draft rules or Functions. There is no root `.firebaserc`.
- Local configuration: `security-tests/firebase.emulators.json`; project `brewverse-security-tests`; Auth 9099, Functions 5001, Firestore 8085, Storage 9199, UI disabled. Draft Firestore/Storage rules live under `security-tests/` and are not production rules.
- Emulator app mode changes the project ID and routes all four SDKs locally. Android emulator host is `10.0.2.2`; other platforms use `127.0.0.1`. Storage bucket/client identifiers otherwise inherit existing options. Use synthetic data only. Physical phones require separate host/network configuration.
- Live tenant mode is blocked unless `BREWVERSE_ALLOW_LIVE_TENANT_MODE=true`. Do not enable that override without a separately approved rollout.

## Completed and verified behavior

- Existing inventory, recipe, tenant checkout, loyalty earn/redeem/expiry, refund/void, role checks and retry handling passed local service/callable tests. Direct client bill/movement writes remain denied; security rules were not weakened.
- Final stabilization: a membership-scoped nested Navigator discards pushed screens on revocation or role changes; user changes reset selection and membership snapshots. Inventory, team, receipt, refund and More dialogs use that navigator. Two new widget regressions cover revocation with open screen/dialog and user replacement.
- Workspace selection/switching, owner/manager team management and tenant UI propagation are present. They remain opt-in; production integration is not complete.

## Remaining bugs, gaps and rollout blockers

1. **Production checkout permission-denied is not resolved or reproduced against production.** Legacy checkout writes bills/movements directly; tenant rules intentionally reject those writes. The secure local path uses café-scoped trusted callables and passes tests. Verify the affected app's mode, authentication/membership, Firebase project and deployed backend/rules before rollout. Do not loosen rules or claim a local pass fixes the live app. Legacy data needs an explicitly approved ownership/backup/migration plan before tenant access.
2. **Photos are incomplete.** Edit Inventory selects/uploads and displays a photo URL; Add asks the user to save first. No Add selection, removal, cleanup or full lifecycle test exists. The uploader writes a fixed `<itemId>.jpg` and labels all selected bytes JPEG: replacement can overwrite the old object before the document update succeeds, and PNG/WebP are mislabeled. Storage rules enforce role, café path, type and size, but client download-token URLs are bearer links; authenticated image delivery and token policy need review. Do not claim private photo access based only on Storage SDK rules tests.
3. **More menu:** team and loyalty settings use existing services. Printer settings and café profile editing remain disabled. Preferences/support/about are informational. No unsupported profile/settings backend was invented.
4. **Hardware:** no Android device is attached. Gallery permissions, live image display/cache behavior, BLE discovery/connect/reconnect, receipt output and Android back-button behavior through the nested workspace navigator need physical-device testing. Printer receipt-data validation has unit coverage; hardware output is unverified.
5. **Deployment:** Functions, tenant rules, indexes, Storage integration, verified owners, backups and migration rehearsal need an approved staging/production plan. No production configuration was read or changed to diagnose the live rules. Hosted CI has not been verified in this session.
6. **Tooling:** installed Node is 24.22.0 while Functions targets Node 22. Repeat integration checks under Node 22 before rollout. Firebase CLI detected local Application Default Credentials and warned about non-emulated services; tests used Auth/Firestore/Functions/Storage emulators only. Storage runtime emitted a shutdown NullPointerException after successful tests and exit 0. Android build may emit existing Cloud Functions Kotlin Gradle Plugin / Java warnings.

## Build and test

Prerequisites: Flutter/Dart, Android SDK/JDK, Node 22, npm and Firebase CLI. Existing CI pins Flutter 3.47.4, Java 21 and Firebase CLI 15.34.0; confirm compatibility when recreating the environment. Do not commit dependencies or generated files.

```powershell
flutter pub get
npm ci --prefix functions
npm ci --prefix security-tests
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
git diff --check
```

From `security-tests/`, run all local Firebase checks (start from free emulator ports):

```powershell
firebase emulators:exec --config firebase.emulators.json --project brewverse-security-tests --only auth,firestore,functions,storage "npm test && npm run test:storage && npm --prefix ../functions test && npm --prefix ../functions run test:callables"
```

For interactive tenant development, start emulators with the same config/project and run from the repository root:

```powershell
flutter run --dart-define=BREWVERSE_TENANT_MODE=true --dart-define=BREWVERSE_USE_FIREBASE_EMULATORS=true
```

Do not run deployment or migration commands. The preflight script is read-only planning against supplied JSON, not migration approval.

## Final verification record

- Firestore authorization: 9 passed; Storage authorization: 4 passed.
- Backend services/policies/preflight/index tests: 33 passed; callable integration: 4 passed. Combined emulator command exited 0.
- Focused workspace regressions: 5 passed (including 2 new tests).
- `flutter analyze --no-pub`: passed, no issues.
- Full Flutter suite, final APK and Git publication: see the final entry in `DEVELOPMENT_PROGRESS.md`.

Stop here. Future work requires a new user task; production deployment or migration requires explicit approval.
