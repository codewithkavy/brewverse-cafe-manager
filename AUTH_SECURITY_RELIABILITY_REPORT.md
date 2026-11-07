# BrewVerse V1 authentication, security and reliability

Date: 22 October 2026. Canonical project: `C:\Users\bhash\OneDrive\Desktop\brewverse_cafe_manager`.

**Assessment: ready for the next controlled phone acceptance session; not approved for commercial production release.** No deployment, production Firebase writes, GitHub push, APK installation, or application-data clearing was performed. Development and fixtures used only `brewverse-security-tests` on loopback.

## Changes and verified behavior

| Area | Result | Evidence and limits |
|---|---|---|
| Visible sign-out | Added to More and reused in the café chooser. Prevents repeated taps, shows progress and friendly success/failure feedback. | Widget tests cover duplicate submission and failure. No automatic sign-out or local-data clearing was added. |
| Password reset | Uses the existing Firebase reset-email capability, now with email validation, busy protection and clear feedback. Unknown-email responses are neutral. | Synthetic Auth emulator reset code was used to change a synthetic password; old password failed and new password succeeded. Actual email delivery remains untested. |
| Email/password login | Kept Firebase authentication and existing persistent sessions. Added input checks, progress and friendly credential/network errors. | SDK emulator sign-in/reset/sign-out and Flutter UI tests pass. |
| Phone OTP | Kept native Firebase verification. Added international-number and six-digit code checks, resend cooldown, request timeout/cancel, stale-callback rejection, single-flight sign-in and caught auto-verification errors. | Emulator Auth endpoint accepts the correct code and rejects an incorrect code. Flutter tests exercise native callback handling. Real SMS, Android app verification and OPPO auto-retrieval remain untested. |
| Protected navigation | Private routes belong to a UID-scoped navigator. Signing out or changing identities discards its stack and removes root dialogs. Android Back is forwarded to the nested navigator. | Widget test opens a private detail route and root dialog, tests Android Back, signs out and switches users. Old content disappears. |
| Multi-café separation | Server-side memberships remain the authority. No client role or café-ID assertion grants access. | Two independent synthetic owners, cafés and staff were created with separate inventory, recipes, sales and loyalty customers. Both directions of foreign reads/writes, recipe references, customer lookup, checkout and team access are denied. |
| Staff permissions | Staff may perform authorized checkout, but cannot manage recipes, inventory, team access or platform roles. Revoked access is rejected. | Backend, callable and rules suites. Café-switching widget test uses only active memberships; backend rejects foreign/revoked identities independently. |
| Subscription enforcement | Added server transaction checks to loyalty-policy saves and membership grants. Added server-clock subscription checks to direct inventory-detail/photo-reference edits and Storage upload/delete. | Active/grace succeed; expired/suspended fail; existing records and image reads remain available to authorized members. Backend rejects new checkout after expiry. |
| Legacy subscription fixtures | Unmanaged local fixtures remain usable. Rules permit this exception only for tokens belonging to `brewverse-security-tests`; backend production defaults fail closed. | No production rollout policy or customer subscription was changed. Production café activation/migration still needs review. |
| Concurrent subscription updates | Existing revision and operation-ID checks retained. | Concurrent renewals permit one update and reject the stale revision; retries and administrator audit records are tested. |
| Billing reliability | Existing transactional checkout and durable checkout IDs retained. Added screen-recreation regression coverage for a lost reply. | Simultaneous cashiers cannot oversell; concurrent retries make one bill and deduction; insufficient stock rolls everything back. Recovery retains the original ID across screen recreation and retry. |
| Offline handling | V1 remains online-confirmed billing. An unavailable connection leaves an unconfirmed order locked for explicit retry using the same ID. No background sale queue was introduced. | UI recovery test plus backend rejection of an uncommitted request submitted after expiry. A matching previously committed checkout retry is read-only even after expiry. Physical network loss/reconnection remains a phone test. |
| Receipt failures | Printing remains separate from the committed sale. No automatic re-checkout occurs on printer failure. | Existing print-coordinator/BLE tests cover one-time automatic claims, partial write failure, unavailable transport, saved-receipt validation and explicit print-only retry paths. Hardware printing is untested this session. |
| Professional polish | Kept the calm Emerald design. Authentication progress, validation, error feedback and duplicate guards improved. | Existing navigation, inventory, recipes, billing, loyalty, empty/loading/error states and narrow-screen tests pass. Login also tested at 278px with 1.6 text scale. |

Suspension does not prevent security-related membership revocation. Historical reads and matching committed-checkout retrieval remain available; new operational writes are blocked. Creating an initial café is still onboarding, not a paid checkout.

## Automated verification

| Check | Result |
|---|---:|
| Main Flutter suite | 285 passed, 0 failed |
| New reliability integration: Auth, subscription restrictions, offline expiry and two-owner separation | 5 passed |
| Super Admin subscription/payment/concurrency/callable security | 9 passed |
| Existing trusted backend service tests | 45 passed |
| Authenticated/unauthenticated callable integration | 6 passed |
| Recipe flow integration | 1 passed |
| Photo flow integration | 1 passed |
| Firestore authorization rules | 14 passed |
| Storage authorization rules | 5 passed |
| Checkpoint integrity tests | 11 passed |
| Dart analysis | No issues |
| Modified PowerShell launch/stop scripts and recovery adapter | Syntax checks passed |

Total: **382 automated tests passed** (285 Flutter + 86 backend/security + 11 checkpoint). Expected permission-denied logs are assertions of rejected attacks, not test failures. Initial test-harness failures were corrected: Windows Functions source resolution, Node phone-credential support, overly broad test expectations, PowerShell stderr handling and recovery-adapter process recognition. Final logs are retained locally.

Reproduce the isolated backend suite with `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-reliability-tests.ps1`. It uses Auth 14198, Firestore 14185, Functions 14101 and Storage 14199, refuses occupied ports, imports no phone data and performs no CLI auto-export.

## Emulator reliability incident and preservation

A fresh coordinated Auth/Firestore/Storage export and full Firestore snapshot were captured before changes under `.firebase/reliability/2026-10-22T14-02-25-380Z/`. Protected checkpoint file hashes were captured separately.

The initial separate-port test suite exposed an additional Firebase CLI 15.34 local-runtime defect: Storage instances share `os.tmpdir()/firebase/storage/blobs`. Storage cleanup/shutdown can remove another suite's bytes. The phone companion process logged `ENOENT` for a missing blob and stopped, while its external Firestore worker survived.

Recovery did not import over, restart or replace phone Firestore. All 918 Firestore document contents and versions first matched the pre-work capture. Missing Auth/Functions/Storage services were reconnected using the fresh pre-work export. The original Auth `validSince` cutoff was restored from that export so import would not newly invalidate existing local sessions. Passwords, identities, providers and account configuration were preserved. Emulator import regenerated password-update timing; that emulator timing field is excluded from the identity comparison. On-device session acceptance still needs checking.

The reliability runner now starts the entire suite with a private TEMP/TMP directory, preventing Storage cleanup from affecting the phone suite. Phone startup, recovery and admin-demo launch paths also allocate private temporary directories for future starts. The phone hub locator is published only after identity/port checks; exports use the explicit phone hub endpoint. Stop logic now recognizes the canonical recovery adapter while retaining PID and checkpoint checks. Private temporary folders and failed exports are retained, not deleted.

After the isolated run and cleanup, preservation verification checks:

- All 918 Firestore documents, including their versions, match the pre-work snapshot.
- Brewverse Test Café still has 7 bills; the other cafés still have 26 bills.
- Burger Bun remains 30. Loyalty, recipes, bills, customers and movements are unchanged.
- The local Auth identity, credentials, original session cutoff and Auth configuration match the backup.
- Both Storage objects match their original bytes and metadata; photo references remain intact.
- Every file hash in `stable-v1-20261022-182112` is unchanged. Its pointer was not advanced.

The evidence is `.firebase/reliability/2026-10-22T14-02-25-380Z/preservation-result.json`. `scripts/verify-reliability-preservation.cjs` can repeat this read-only comparison and save a new native export without advancing the checkpoint pointer. One export attempt hit a OneDrive `EPERM` rename; the partial export was retained and a fresh attempt succeeded.

The isolated runner was exercised live. Revised phone/admin startup paths were syntax checked; another full phone stop/restart was deliberately not used as an acceptance test in this session. The synthetic admin demo suite also suffered the shared-temp interruption; its surviving Firestore was not reset or replaced. Its complete preview service restart still needs attention before using that preview again.

## Files created or modified in this task

Pre-existing unrelated working-tree changes were retained.

| Files | Purpose |
|---|---|
| `lib/services/authentication_service.dart` (new) | Firebase-backed authentication boundary and friendly error mapping |
| `lib/widgets/sign_out_button.dart` (new) | Shared visible sign-out action with duplicate guard |
| `lib/screens/login_screen.dart` | Reset/login validation, progress, OTP lifecycle/error handling |
| `lib/screens/auth_gate.dart` | UID-scoped route disposal and Android Back handling |
| `lib/screens/more_screen.dart`, `lib/screens/cafe_workspace_gate.dart` | Sign-out entry points |
| `functions/src/loyalty_service.js`, `functions/src/membership_service.js` | Subscription enforcement within existing transactions |
| `security-tests/firestore.rules`, `security-tests/storage.rules` | Operational-write subscription restrictions |
| `test/screens/authentication_test.dart` (new), `test/screens/billing_screen_test.dart` | Authentication/navigation/layout and durable retry regressions |
| `functions/test/reliability.emulator.test.cjs` (new) | Synthetic Auth, subscription and independent café fixtures |
| `functions/test/subscription_service.test.cjs` | Guarded 141xx support and configurable callable endpoint |
| `security-tests/test/firestore.rules.test.cjs`, `security-tests/test/storage.rules.test.cjs` | Expiry/suspension and bidirectional isolation tests |
| `scripts/run-reliability-tests.ps1` (new), `scripts/test-local-backend.ps1` | Guarded isolated runtime, logs, temporary-folder isolation and cleanup |
| `scripts/start-local-emulators.ps1`, `scripts/run-super-admin-local.ps1`, `scripts/connect-existing-local-firestore.cjs`, `scripts/stop-local-emulators.ps1` | Private runtime temporary directories and verified recovery lifecycle support |
| `scripts/verify-reliability-preservation.cjs` (new) | Phone data/checkpoint preservation evidence |
| `AUTH_SECURITY_RELIABILITY_REPORT.md` (new) | This report |

## Remaining risks and release blockers

1. **Production has not been validated or deployed.** Review production rules, indexes, callable rollout, café ownership migration and subscription activation before release. Current release defaults still permit the legacy app route unless tenant mode is explicitly enabled; tenant mode also has a separate live-mode safety gate. A commercial build must deliberately select and validate the tenant path. Do not ship the default build as a commercial tenant release.
2. Verify email/password and phone providers, Android release signing fingerprints, SMS region/quota configuration, app verification and reset-email settings. Emulators do not prove actual delivery. Follow [Firebase Flutter phone authentication](https://firebase.google.com/docs/auth/flutter/phone-auth) and [user/password management](https://firebase.google.com/docs/auth/flutter/manage-users).
3. The host emulator used Node 24 while Functions declares Node 22. Verify the declared runtime before release. App Check enforcement, abuse/rate controls, monitoring, IAM and administrator MFA still require a release review; no production configuration was changed.
4. Product photos currently use `getDownloadURL()`. These are shareable, long-lived token URLs; possessing the URL is a separate access capability from café membership. Rules tests prove authenticated path isolation, not privacy of a leaked token URL. Do not store private customer documents using this mechanism. Strict photo revocation/privacy needs a planned authenticated-download approach and existing-token migration; existing photo URLs/tokens were preserved. See [Firebase Storage reference](https://firebase.google.com/docs/reference/swift/firebasestorage/api/reference/Classes/StorageReference).
5. Physical offline transitions, app process death, device sign-in persistence and Bluetooth printing need acceptance tests. A screen-recreation simulation is not a phone process-death test. V1 does not support finalized offline sales or automatic background synchronization.
6. The legacy standalone café-service path remains in source for compatibility; commercial access must remain on the tenant-scoped path and restrictive rules. On-device cached data is retained as requested; this work does not erase a shared device's cache on sign-out.
7. Café profile editing remains disabled, preferences are informational, support contact is not configured, and loyalty transaction history is not implemented. These were not expanded into Version 2 features. Verify launch expectations and support information before selling V1.
8. Firebase CLI still emits a Java rules-runtime shutdown `NullPointerException` after successful tests. The runner cleans only the verified isolated Firestore orphan. A validated checkpoint remains necessary before stopping a real local test session. OneDrive export rename failures must stop promotion rather than silently select an older export.

## Manual acceptance checklist for 23 October 2026

Use synthetic accounts and disposable fixtures on the isolated suite. Keep the protected phone dataset out of destructive tests. The installed phone APK was not replaced; source changes will require an explicitly authorized updated test build before phone verification.

1. Confirm OPPO ADB authorization and all four reverse ports. Open the existing app and check its persisted session, 7 bills, 30 buns, loyalty and photo before any test operation.
2. On the updated test build, open More → Sign out. Check progress, login screen, Android Back, a previously opened detail screen and a dialog; none should reveal the old private workspace. Reopen the app and verify it remains signed out.
3. With synthetic accounts, test correct/incorrect passwords, registration validation and repeated taps. Request a password reset, verify delivered email and expired-link feedback, then sign in using the new password.
4. Test real SMS OTP only after provider/release-signing configuration review: correct/wrong/expired codes, resend cooldown, cancellation, number change, automatic retrieval, connectivity loss and background/resume.
5. Sign in as each synthetic café owner and staff member. Switch cafés, revoke a staff membership and confirm stock, recipes, customers and bill history always belong to the selected authorized café.
6. Exercise active, grace, expired, suspended and renewed access. Historical reads should remain available; new sales, inventory edits, photo changes, policy saves and membership grants must be blocked when access is expired/suspended.
7. Use two cashiers on disposable data: compete for the last stock, tap checkout repeatedly, lose the reply, kill/reopen the app, reconnect and retry the same order. Confirm exactly one bill and stock/loyalty effect. Never create a replacement sale merely because confirmation is delayed.
8. Keep an unconfirmed order offline until expiry. Reconnect and confirm the server rejects an uncommitted sale. If it had already committed, retrieval must return that original bill without another deduction.
9. Disconnect or power off the receipt printer mid-send. Confirm the bill stays saved; use explicit receipt-only retry and inspect actual paper. Check 58/80mm layouts and Bluetooth permissions.
10. Inspect navigation, keyboard, empty/error/loading states and enlarged text on the OPPO. Save and validate a fresh non-protected checkpoint after acceptance tests; then test the revised controlled stop/restart workflow and compare all three stateful services.
