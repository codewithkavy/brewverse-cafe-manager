# Isolated Firestore security tests

This directory is a **test-only sandbox**. It is not the root Firebase deployment configuration and must not be used to deploy production rules.

## Prerequisites

- Node.js 20 or a compatible supported version
- Java runtime required by the Firestore Emulator
- Firebase CLI

## Run locally

From this directory:

```bash
npm ci
firebase emulators:exec --config firebase.json --project brewverse-security-tests --only firestore "npm test"
```

The test project ID is deliberately `brewverse-security-tests`, not the live `brewverse-593dc` project. Emulator tests should not need live credentials.

The Firestore rules suite and the separate Storage rules suite are both test-only. Run the Storage suite with its Firestore-backed membership fixtures from this directory:

```bash
firebase emulators:exec --config firebase.emulators.json --project brewverse-security-tests --only firestore,storage "npm run test:storage"
```

## Local tenant-mode app preview

The root `firebase.json` now runs Auth, Firestore, Functions, and Storage with these existing test-only rules and Functions source. From the repository root, use the checked launcher:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-local-emulators.ps1
```

In a second terminal, run the Flutter app on an Android emulator with `--dart-define=BREWVERSE_TENANT_MODE=true --dart-define=BREWVERSE_USE_FIREBASE_EMULATORS=true`. Physical Android phones default to `127.0.0.1` through USB ADB reverse. Automatic SDK host mapping is disabled for all four services. Android virtual devices must explicitly set `--dart-define=BREWVERSE_FIREBASE_EMULATOR_HOST=10.0.2.2`. The app routes Auth, Firestore, Functions, and Storage to these local emulators when the emulator flag is set. The current generated Firebase options only configure Android; web/desktop previews are not set up. Create a test account through the app's login screen. The tenant-mode flag is otherwise guarded from live Firebase by default. Do not add `BREWVERSE_ALLOW_LIVE_TENANT_MODE` for ordinary local testing.

## Test-only authorization contract

This draft assumes top-level business collections with a required immutable `cafeId` field and membership documents at `cafe_members/{uid}_{cafeId}`. Memberships and café ownership are provisioned by trusted server code; clients can read only their own membership documents.

- Active owners, managers, and staff can read their café's business data.
- Active owners and managers can edit inventory item details, but cannot create/delete stock documents or directly change quantities. Staff cannot make inventory changes.
- Recipe writes, bills, and stock movements are reserved for trusted backend operations. This allows the backend to validate same-café recipe references and commit checkout, stock deductions, bill, and movements together.
- Memberships and café profiles remain trusted-backend managed. Every trusted call must independently verify the caller's active membership and role; only active owners and managers can list same-café memberships.
- Unknown paths, unauthenticated requests, cross-café access, and revoked memberships are denied.

The Firestore emulator tests cover membership access, café reads, tenant isolation for inventory/recipes/bills/movements, role limits, immutable audit records, and default denial. The Storage emulator tests cover café-scoped photo reads, manager upload/delete limits, and deny-by-default legacy paths. These are safe starting contracts, not production-ready rules. Isolated trusted Functions cover café/team membership management, stock creation/additions, recipe validation, transactional checkout, and sales summaries; the opt-in Flutter tenant path calls the relevant handlers. Neither ruleset nor Functions have been deployed. Tenant inventory managers can choose and upload a JPEG product photo from the edit-item dialog; files use a unique name below the selected café's Storage path and the app rejects files larger than 5 MiB. Subscriptions, entitlement checks, email invitations, field-level validation, and the finalized role matrix also remain out of scope.

The rules are test-only and must never be deployed through the root Firebase project. The Flutter app has an opt-in tenant-mode path that scopes reads and routes stock creation/addition, recipe saves, and checkout through trusted Functions. Tenant mode remains disabled by default and guarded from live Firebase unless a second explicit compile-time flag is set. The legacy mode still writes records without `cafeId` and performs checkout from the client. Do not deploy these rules until legacy data ownership, backup, migration rehearsal, production query/index requirements, and the complete emulator suite are verified.


## Physical Android phone over USB

Build with:

```powershell
flutter build apk --debug --dart-define=BREWVERSE_TENANT_MODE=true --dart-define=BREWVERSE_USE_FIREBASE_EMULATORS=true --dart-define=BREWVERSE_FIREBASE_EMULATOR_HOST=127.0.0.1
adb reverse tcp:9099 tcp:9099
adb reverse tcp:8085 tcp:8085
adb reverse tcp:5001 tcp:5001
adb reverse tcp:9199 tcp:9199
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

The app validates persisted Auth credentials before entering tenant mode. After an
Auth emulator restart, choose **Sign out and sign in again** if verification fails;
use **Retry connection** for temporary connectivity failures. The café chooser and
membership error screen also provide **Sign out**. No app data clear is needed.

Run backend and security checks on separate ports (the rules tests clear only
this isolated test instance):

```powershell
firebase emulators:exec --config security-tests/firebase.test-emulators.json --project brewverse-security-tests --only auth,firestore,functions,storage "powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-local-backend.ps1"
```

Run that command from the repository root. Keep the phone suite on its normal
ports. Tests must never point at production or an emulator containing records
you need to retain.


## Root local configuration

The root `.firebaserc` defaults to `brewverse-security-tests`; the launcher also
passes that project explicitly. Generated Flutter settings still identify the
existing Android registration and are preserved; the emulator build overrides
the runtime project ID. Do not deploy the root configuration: its rules are the
existing local security-test rules.

The launcher checks dependencies, resource paths, and occupied ports without
terminating other processes. `-CheckOnly` performs preflight without starting.
Auth/Firestore/Functions/Storage bind only to `127.0.0.1` on
9099/8085/5001/9199. Auxiliary hub/logging/WebSocket ports are 4420/4520/9160;
Eventarc/Tasks use 9299/9499. Auxiliary ports intentionally avoid another
existing local suite. Keep this terminal open while using the phone.

In a second terminal at the repository root, connect an authorized USB phone and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-phone-debug.ps1
```

The installer retains ADB reverse for all four phone ports and installs the
existing emulator debug APK. No launcher imports, clears, or deletes emulator
records. Emulator state is in memory unless separately exported; restarting
Auth may require signing in again.
