# BrewVerse V1 Super Admin Dashboard

Implemented locally in the canonical Desktop project. No production deployment,
Firebase production data writes, push, APK reinstall, checkpoint replacement or
existing cafe-data migration was performed. The phone may be unplugged while
working with this desktop-only dashboard.

## Architecture and conflicts resolved

The existing app uses Firebase Auth, cafe-scoped memberships, callable Functions,
and client rules that disallow direct bill/movement writes. Cafe owner/manager
roles are not platform roles. The separate Flutter Web app uses a server-managed
UID registry, not email matching or public registration, for Super Admin access.

The dashboard connects only to `brewverse-security-tests` on loopback using the
separate four 131xx emulators. Production `brewverse-593dc` options/registration
are preserved. Existing phone cafes have no subscription records; they remain
usable under explicit emulator compatibility behavior. Production will require
a migration/activation plan because missing subscriptions fail closed.

Admin authorization is checked in every transaction, including read operations.
Server checks are essential because the Admin SDK bypasses client rules:
https://firebase.google.com/docs/firestore/solutions/role-based-access

## Files created

- `super_admin_dashboard/`: independent Flutter Web project; `lib/backend.dart`
  contains named-app local transport; `lib/main.dart` contains login and server
  authorization; `lib/dashboard.dart` contains responsive overview, cafe and
  subscription/payment screens; `test/dashboard_test.dart` covers widgets.
- `functions/src/subscription_service.js`: platform roles, server-time expiry,
  policy, pagination, revenue, payments, revisions, idempotency and audit records.
- `functions/test/subscription_service.test.cjs`: nine isolated security/business
  tests, including real authenticated callable requests and concurrency.
- `scripts/seed-super-admin-demo.cjs`: guarded synthetic fixtures, random private
  credentials and explicit local-only checks.
- `scripts/serve-admin-dashboard.cjs`: loopback static server restricted to the
  compiled dashboard folder; cannot serve emulator files or credentials.
- `scripts/run-super-admin-local.ps1`: local preview and isolated-fixture launcher.
- `super_admin_dashboard/README.md`: run instructions, security model, rollout
  behavior, limits and release requirements.

## Files modified

- `functions/src/index.js`: guarded admin endpoints and server-side owner lookup.
- `functions/src/inventory_service.js`: subscription checks for new checkout,
  stock creation/replenishment and recipe saves. Existing unrelated edits retained.
- `functions/src/billing_service.js`: subscription checks for new refund/void
  writes; matching existing retries remain read-only.
- `security-tests/firestore.rules`: cafe-scoped subscription reads; client writes
  stay denied. Platform roles, policy, payments and audit remain backend-only.
- `security-tests/test/firestore.rules.test.cjs`: platform-injection and isolation
  regression test, including a forged client admin claim.
- `scripts/test-local-backend.ps1`: guarded admin testing/seeding and direct export
  via isolated hub 13120, with verification of the synthetic account in the export.
- `scripts/connect-existing-local-firestore.cjs`: explicit verified import input
  for restoring missing companion services without replacing surviving Firestore.
- `scripts/stop-local-emulators.ps1`: verified external-Firestore handling after
  recovery, preserving the save-before-stop requirement.

## Implemented behavior

Login has no registration or admin-grant action. Every API verifies the active
UID registry, so revocation takes effect without waiting for refreshed claims.
Overview reports registered, active, grace, expired, suspended, pending and
verified-payment revenue totals. Cafes can be listed/searched, inspected,
activated/renewed, extended, suspended and resumed without deleting any data.

Policy stores monthly price and bounded grace. Admins choose explicit expiry
dates; renewals cannot shorten an existing expiry. Revisions reject stale
concurrent edits, and operation IDs prevent repeated subscription/policy actions.
Subscription status is derived using server time on requests. New transactional
writes are blocked for expired/suspended cafes; read-only historical access and
matching retries remain available. No scheduled rewrite of saved cafe data occurs.

Manual UPI records require explicit external verification, amount/date/reference
and a note. Globally normalized references are atomically unique. Recording a
payment does not activate a cafe or prove receipt of money. All successful admin
reads and mutations create audit records. There is no payment gateway.

## Validation

Final isolated suite: **78 backend/security checks passed**:

- 9 new subscription/admin tests.
- 45 existing backend tests.
- 6 callable integration tests.
- 1 recipe and 1 photo flow.
- 12 Firestore authorization and 4 Storage authorization tests.

Flutter analysis: no issues. Three dashboard widget tests passed, covering
laptop/mobile layouts, navigation/search, mandatory payment confirmation and
unauthorized-user rejection. Web compilation passed. PowerShell/Node syntax
checks passed. Browser verification signed in with a random synthetic admin and
rendered four synthetic cafes, subscription states, owner email, payment history
and audit details.

The protected `stable-v1-20261022-182112` file hashes matched the pre-work snapshot.
All live phone Firestore documents/metadata matched the pre-work snapshot. Its
seven bills, stock 30, loyalty and product image were not changed.

## Local runtime incident and recovery

The Firebase CLI/rules runtime emitted shutdown exceptions and left test
Firestore running on 13185. Only that verified test process was stopped.
CLI automatic export selected the phone hub because both suites share a project
ID; the export failed and terminated the phone's companion services. Its live
Firestore process survived and still matched the protected checkpoint exactly.

A fresh native backup of that surviving database was taken. Auth, Functions and
Storage were reattached from the verified stable export without stopping or
importing over live Firestore. All four phone services and a complete live-state
comparison subsequently passed. Current hub/session metadata was repaired; the
protected checkpoint itself was unchanged. The fixture workflow now explicitly
exports through 13120 and verifies its synthetic Auth account; it never relies
on the global CLI hub locator or auto-export. Failed/partial captures were kept.

## Release blockers and limits

1. Production deployment/hosting/web registration and trusted admin provisioning
   need separate approval. Local transport intentionally has no production toggle.
2. Plan subscription activation for existing cafes before any production rollout;
   absent subscriptions fail closed in production.
3. Add/configure MFA, App Check, rate limits, least-privilege IAM, audit retention
   and monitoring; verify the declared Node 22 runtime (host emulator used Node 24).
4. Scale overview beyond 5,000 cafes/10,000 payments and paginate/export cafe
   histories beyond the explicitly flagged 500-record view limit.
5. Manual bank verification remains the administrator's responsibility; no
   payment-to-period allocation, reconciliation feed or gateway is implemented.
6. Direct cafe inventory-detail/photo edits and membership administration retain
   cafe-role permissions. Decide whether subscription suspension should freeze
   those non-sales management settings too.

Preview: http://127.0.0.1:8767. Synthetic credentials are not hardcoded or printed;
their private local path is recorded in
`.firebase/admin-development/dashboard-demo-login-path.txt`. Only compiled web
assets are served. Full run instructions are in `super_admin_dashboard/README.md`.
