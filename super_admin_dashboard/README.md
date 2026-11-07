# BrewVerse Super Admin — local V1

Separate Flutter Web application. The cafe mobile application's UI and Firebase
release registration (`brewverse-593dc`) are unchanged. This build deliberately
cannot connect to production: it requires a loopback page origin, a named
`brewverse-local` Firebase client, project `brewverse-security-tests`, Auth
13198 and Functions 13101. No public hosting configuration is provided.

## Implemented

- Firebase email/password login; every admin API verifies an active
  `platform_admins/{authenticatedUid}` record with role `super_admin`.
  Cafe ownership, emails and client-supplied roles/UIDs never authorize access.
  There is no admin signup, grant-admin API or production provisioning script.
- Responsive overview, cafe search/status filters and owner email/UID details.
  List pages contain 50 cafes; search/filter loads remaining pages automatically.
  Counts and status come from the server, refreshed every minute and manually.
- Monthly price in paise, 0–14 grace days, activation/renewal, forward-only
  extension, suspension and resume. Expiry uses server time at every new
  transaction, rather than trusting a client flag or waiting for a scheduled job.
  Grace is copied at activation/renewal, not retroactively changed.
- Manual verified UPI payment recording with amount/date/reference/note and
  explicit human confirmation. A normalized reference hash is a global document
  ID; concurrent duplicates are rejected atomically. Payment records never
  automatically activate access. Revenue counts recorded verified payments only.
- Revision-protected subscription/policy writes; operation IDs make retries
  idempotent. Successful login, reads and mutations are audited server-side.
- New checkout, stock creation/replenishment, recipe saves and refund/void writes
  check subscription access. Matching retries of already-completed operations
  remain read-only. Existing cafe-member reads remain isolated and available.

## Local rollout compatibility

Missing subscription records are tolerated only in emulators when the
server-managed `platform_config/subscriptions.enforcementEnabled` is not true.
This preserves the existing phone dataset without backfilling it. Any cafe that
has a managed subscription is checked even in this compatibility mode.
The isolated dashboard demo sets enforcement true. Production always fails
closed for a missing/expired/suspended subscription, even if this local policy
is false. A deliberate migration/activation plan is mandatory before release.

Admin data lives in `platform_admins`, `platform_config`, `cafe_subscriptions`,
`subscription_payments`, and `platform_audit`. Clients cannot write any of them.
Cafe members may read only their own subscription metadata. Admin cross-cafe
access goes through guarded callables, not direct client collection reads.

## Tests and synthetic fixtures

From the canonical project root:

```powershell
firebase emulators:exec --config firebase.test-emulators.json --project brewverse-security-tests --only auth,firestore,functions,storage "powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-local-backend.ps1 -BillHistory -AdminDashboard"
```

The guard requires all four separate 131xx services. Never run fixture-clearing
tests against phone ports. To additionally produce fresh demo fixtures, append
`-SeedAdminDemo` to the guarded script, or use `-SeedAdminDemo -AdminDemoOnly`
for fixture creation alone in a fresh isolated suite. The seed uses random
credentials and writes their path to
`.firebase/admin-development/dashboard-demo-login-path.txt`. It creates only
synthetic cafe/account/payment records and refuses to overwrite existing demo
cafes. Every credential file is retained and excluded from Git.

The seed exports directly via hub `127.0.0.1:13120`, verifies that the export
contains its synthetic admin, and saves `fixture-pointer.json`. Do **not** add
CLI `--export-on-exit` or use an unqualified `emulators:export` while the phone
suite is also running: Firebase's global project hub locator can select the
phone hub. Protected checkpoints are never imported into the dashboard demo.

```powershell
cd super_admin_dashboard
flutter pub get
flutter analyze
flutter test
flutter build web --no-web-resources-cdn
cd ..
./scripts/run-super-admin-local.ps1
```

Open http://127.0.0.1:8767. The static server binds only loopback and serves only
the compiled dashboard directory. It cannot serve credentials or emulator files.
The demo emulators bind only loopback; no tunneling or deployment is configured.
Only synthetic admin fixtures should be used to exercise mutations here.

`run-super-admin-local.ps1` reuses a verified isolated suite or starts it from
the explicit fixture pointer. Demo edits are temporary unless exported directly
through hub 13120. Runtime process IDs and logs are retained under
`.firebase/admin-development/`. Never stop processes by an unverified port/name.

## Limits and release blockers

- No production deployment, production web registration or admin onboarding has
  been done. Provision real admins through a separately authorized trusted IAM
  procedure, with MFA, least privilege and an emergency revocation process.
- Configure production web settings/authorized domains, App Check/rate limiting,
  HTTPS hosting and audit retention/monitoring before release. The local-only
  transport is intentionally not a production-ready build switch.
- Overview is bounded to 5,000 cafes/subscriptions and 10,000 payment records.
  Individual cafe payment/audit views show at most 500 records with an explicit
  warning when truncated. Stored history is never deleted; aggregate scaling
  and history pagination/export are needed beyond these limits.
- UPI verification is a human assertion. There is no bank integration, payment
  gateway, reconciliation feed, automatic verification or payment-to-period link.
  Monthly price is a configured reference; an admin chooses the expiry explicitly.
- Effective expiry is automatic; the stored record is not rewritten by a cron
  job. Direct inventory-detail/photo edits and membership revocation remain
  governed by cafe-role rules; subscription enforcement targets transactional
  backend writes. Decide whether to freeze these management settings at release.
- Cloud Admin SDK credentials can bypass rules. Platform registry/audit integrity
  therefore depends on trusted operator IAM; these APIs provide no delete/edit
  route for payment or audit history.
- Host Node 24 was used by the emulator, while Functions declares Node 22.
  Verify the declared runtime before a production rollout.

## Validation completed

9 subscription/admin tests, 45 existing backend tests, 6 callable integration
tests, recipe/photo flows (1 each), 12 Firestore rules tests and 4 Storage rules
tests passed: 78 backend/security checks. Flutter analysis and 3 dashboard
widget tests passed; web compilation passed. Browser login with the random
synthetic admin rendered the four-cafe overview and recorded fixture revenue.

The CLI/rules emulator emitted a shutdown exception and left an isolated
Firestore process behind. Only its verified 13185 process was stopped. A CLI
auto-export also selected the phone hub and failed; explicit hub export replaced
that workflow. The phone's surviving Firestore was backed up and preserved;
missing companion services were reattached from the verified stable export.
Subsequent full comparison passed. The protected checkpoint's file hashes
matched before/after; no phone bills, inventory, loyalty or image fields changed.
