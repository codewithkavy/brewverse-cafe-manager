# BrewVerse production security review

Audit date: October 31, 2026 (IST). This review used local source inspection and read-only Firebase/Google Cloud metadata APIs. No customer documents were read, changed, migrated, or deleted. No APIs, billing, providers, rules, or functions were enabled/deployed.

## Release decision

**Not safe to distribute as a working production client yet.** Local application improvements and emulator tests cannot establish that missing cloud services are available. Production billing/API setup, reviewed security deployment, index creation, owner onboarding policy, signing registration, and real-device cloud tests remain approval gates.

## Verified production metadata

| Item | Read-only result |
|---|---|
| Firebase project | `brewverse-593dc`, active; Android app display name `caffora` |
| Android application ID | `com.example.brewverse_cafe_manager` |
| Android Firebase app ID | `1:974105282248:android:fb89d0d8fd9b620b5187fd` |
| Registered SHA-1 | `5b6192b20eb9d2a6ed1b7e72edaa48ef1bd232b3` |
| Registered SHA-256 | `b0756ae82748ee5b0874b771c6c4655272a6dda22428bb724c8f98047a382973` |
| Billing | `billingEnabled: false`; no paid plan was activated |
| Email/password provider | Enabled |
| Phone provider | Enabled, SMS region allowlist is India (`IN`); this does not establish paid SMS availability |
| Authorized Auth domains | `localhost`, `brewverse-593dc.firebaseapp.com`, `brewverse-593dc.web.app` |
| Firestore | Standard Native `(default)` database, `asia-south2`; PITR and delete protection disabled |
| Composite indexes | Empty; the four required local composite indexes are not deployed |
| Storage buckets | Bucket listing succeeded and returned no buckets |
| Functions | Listing failed because `cloudfunctions.googleapis.com` is disabled/never enabled; IAM listing permissions were granted. Required cloud handlers were not verified available |
| Security rules releases | Only a Firestore release was listed; no Storage release |

Registered certificate fingerprints must be compared with the actual preserved release signing certificate. Presence of a registered fingerprint is not proof that the newly built release matches it.

## Critical current production rules finding

The deployed October 16 Firestore rules allow **every authenticated user** to read and write every `stock_items` and `stock_movements` document. They perform no café membership, role, or immutable-ledger checks. All other paths are denied by the absence of matches. This both exposes legacy inventory to cross-café access and prevents the new tenant app from operating normally.

The reviewed local rules in `security-tests/firestore.rules` and `security-tests/storage.rules` are substantially stricter, but are **not deployed**. Deploying them without reviewing legacy ownership/access would preserve bytes but could block old clients. No ownership or subscription records may be fabricated to make the new app appear functional. Review existing production ownership and take an approved cloud backup before deploying rules or applying any migration.

## Confirmed local changes from this review

- Cloud callable authorization now requires verified email claims or a verified phone sign-in identity. The isolated test project plus explicit loopback Auth-emulator environment is the only server-side legacy test exemption. Client claims cannot enable that server environment exemption.
- Direct Firestore/Storage access applies the same identity policy, while retaining the explicit test-audience compatibility branch for emulator fixtures. A production Firebase token cannot choose the test-project audience.
- `addStock` now accepts an optional stable `operationId`. Transactions validate actor, café, item, quantity and normalized reason; matching concurrent calls or lost-response retries use one movement and one increment. Conflicting payload reuse is rejected. Existing callers without an operation ID retain legacy behavior; clients must persist and reuse an ID for retry protection.
- Café and stock-item creation also accept optional stable operation IDs. Their immutable original request metadata allows safe lost-response retries even after stock/item display fields later change. Concurrent creation yields one café/owner or one item/opening movement; conflicting payloads and changed actors/roles are rejected.
- New pure identity-policy tests and stock-addition/creation concurrent/retry/authorization integration regressions were added. Parent workflow must run the backend/rules integration suite using the guarded disposable emulators before approval.

No business subscription policy was changed.

## Remaining source and deployment gates

1. **New café subscription activation:** `createCafe` atomically creates the café and owner membership, but no subscription. Production write handlers and metadata/Storage rules fail closed without an active/grace `cafe_subscriptions` record. Decide and approve whether a new café is manually activated, starts an explicit trial, or follows a billing flow. Until then, new café onboarding can succeed but stock, checkout and staff changes cannot operate.
2. **Legacy inventory ownership:** legacy production rows may be unscoped. Existing rules do not establish owner/café linkage. No automatic migration or test-account import is permitted; use the existing preflight tooling and a reviewed versioned migration only with approval.
3. **App Check/abuse protection:** current callables are authenticated but do not enforce App Check. Add a compatible client attestation rollout and inspect metrics before enabling enforcement. Arbitrary signed-in accounts can still consume resources through their permitted actions; café creation has no per-account quota/rate policy.
4. **Legacy callers and creation retries:** optional operation IDs now cover `createCafe`, `createStockItem`, and `addStock`; old clients omitting IDs retain legacy behavior. Release clients must persist/reuse operation IDs across uncertain replies and restart. Legacy callers should not retry an ambiguous stock operation as a new request. Existing stored data is not migrated or rewritten.
5. **Product photos:** `getDownloadURL` produces bearer download-token URLs. A copied URL remains a capability even when a user later loses café membership; Storage Rules do not make an already leaked token URL private. Use authenticated object fetches or an approved revocable-delivery design if product photos must remain strictly private. Never reuse this design for invoices, credentials, or customer-sensitive files.
6. **Data protection configuration:** PITR, scheduled exports, retention, delete protection, least-privilege IAM and operational restore tests require separate review/approval. These may incur cost.
7. **Cloud validation:** no production registration, SMS, email delivery, password reset, financial operation, or data migration was performed. Cloud and laptop-off device checks remain unperformed until deployment is authorized.

## Current official Firebase prerequisites

- Phone SMS requires the Blaze plan; current documented limits include 3,000 sent SMS/day for standard Firebase Authentication, 150 verification requests/IP/hour, and additional SMS/IP/per-number controls. Use fictional configured numbers for development; never expose real OTPs. These limits can change. [Firebase Authentication limits](https://firebase.google.com/docs/auth/limits)
- Android Phone Auth requires the release SHA-256 for Play Integrity and SHA-1 for reCAPTCHA fallback. Sideloaded APKs can use the reCAPTCHA path; verify the auth-domain/API-key allowlist and redirect behavior on real devices. Phone-provider enablement alone is insufficient. [Android phone authentication](https://firebase.google.com/docs/auth/android/phone-auth)
- Cloud Functions production deployment requires Blaze. [Functions setup and deployment](https://firebase.google.com/docs/functions/get-started)
- Cloud Storage requires Blaze; the documented existing-bucket access requirement took effect February 3, 2026. No bucket is currently provisioned in this production project. [Storage billing requirements](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024)
- App Check supports distribution outside Google Play, but attestation settings must match that channel. Do not blindly require Play-recognized/licensed verdicts for a sideload-only distribution. Register the release SHA-256, monitor legitimate traffic, then approve enforcement. [App Check with Play Integrity](https://firebase.google.com/docs/app-check/android/play-integrity-provider)

## Reviewable deployment sequence — not executed

Use an explicit production-only config (`firebase.production.json`) containing the reviewed rules/indexes/functions, no emulator import/export or migration hooks, and the fixed production project on every command. The parent workflow prepares that artifact separately.

1. Approve billing/API activation, cost limits/alerts, Storage bucket region and retention requirements. The intended Firestore region is currently Delhi (`asia-south2`); Functions are presently authored for `us-central1`, which adds cross-region latency and potential cost.
2. Inspect/back up existing deployed rules, indexes, resources and authorized legacy clients. Review the subscription/onboarding policy and any required migration separately.
3. Review the exact source diff and successful isolated test results, then approve the deployment command:

   ```powershell
   firebase deploy --project brewverse-593dc --config firebase.production.json --only firestore:rules,firestore:indexes,storage,functions
   ```

   This is a proposed approval artifact, not authorization to run it. Selective deployment may be preferable during the approved rollout. A rules-only security remediation must still consider existing legacy access.
4. Register the preserved release certificate SHA-1/SHA-256 without replacing the Android application ID or app registration. Refresh local public Firebase app configuration only if required.
5. Verify production resources and run consented synthetic cloud accounts/cafés. Keep all emulator accounts/data out of production. Then perform real Android Wi-Fi/mobile-data/airplane-mode, update compatibility, and email/OTP tests before marking an APK safe to distribute.
