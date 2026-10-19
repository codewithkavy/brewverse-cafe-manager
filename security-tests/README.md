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

The separate `firebase.emulators.json` config runs Auth, Firestore, Functions, and Storage emulators with the test-only rules. From this directory, start them with:

```bash
firebase emulators:start --config firebase.emulators.json --project brewverse-security-tests --only auth,firestore,functions,storage
```

In a second terminal, run the Flutter app on an Android emulator with `--dart-define=BREWVERSE_TENANT_MODE=true --dart-define=BREWVERSE_USE_FIREBASE_EMULATORS=true`. Android emulators connect through `10.0.2.2`. The app routes Auth, Firestore, Functions, and Storage to these local emulators when the emulator flag is set. The current generated Firebase options only configure Android; web/desktop previews are not set up. Create a test account through the app's login screen. The tenant-mode flag is otherwise guarded from live Firebase by default. Do not add `BREWVERSE_ALLOW_LIVE_TENANT_MODE` for ordinary local testing.

## Test-only authorization contract

This draft assumes top-level business collections with a required immutable `cafeId` field and membership documents at `cafe_members/{uid}_{cafeId}`. Memberships and café ownership are provisioned by trusted server code; clients can read only their own membership documents.

- Active owners, managers, and staff can read their café's business data.
- Active owners and managers can edit inventory item details, but cannot create/delete stock documents or directly change quantities. Staff cannot make inventory changes.
- Recipe writes, bills, and stock movements are reserved for trusted backend operations. This allows the backend to validate same-café recipe references and commit checkout, stock deductions, bill, and movements together.
- Memberships and café profiles remain trusted-backend managed. Every trusted call must independently verify the caller's active membership and role; only active owners and managers can list same-café memberships.
- Unknown paths, unauthenticated requests, cross-café access, and revoked memberships are denied.

The Firestore emulator tests cover membership access, café reads, tenant isolation for inventory/recipes/bills/movements, role limits, immutable audit records, and default denial. The Storage emulator tests cover café-scoped photo reads, manager upload/delete limits, and deny-by-default legacy paths. These are safe starting contracts, not production-ready rules. Isolated trusted Functions cover café/team membership management, stock creation/additions, recipe validation, transactional checkout, and sales summaries; the opt-in Flutter tenant path calls the relevant handlers. Neither ruleset nor Functions have been deployed. Tenant inventory managers can choose and upload a JPEG product photo from the edit-item dialog; files use a unique name below the selected café's Storage path and the app rejects files larger than 5 MiB. Subscriptions, entitlement checks, email invitations, field-level validation, and the finalized role matrix also remain out of scope.

The rules are test-only and must never be deployed through the root Firebase project. The Flutter app has an opt-in tenant-mode path that scopes reads and routes stock creation/addition, recipe saves, and checkout through trusted Functions. Tenant mode remains disabled by default and guarded from live Firebase unless a second explicit compile-time flag is set. The legacy mode still writes records without `cafeId` and performs checkout from the client. Do not deploy these rules until legacy data ownership, backup, migration rehearsal, production query/index requirements, and the complete emulator suite are verified.
