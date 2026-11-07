# BrewVerse V1 — Bill History implementation

Completed locally on 21 October 2026 in
`C:\Users\bhash\OneDrive\Desktop\brewverse_cafe_manager`, branch
`codex/fix-physical-device-cafe`. No deployment, push, merge, APK installation,
production Firebase modification or original-data mutation was performed.

## Implemented

- **Home → Bill History**, plus a **Bill History** icon in the Billing toolbar.
  Existing navigation, checkout and Print Last Receipt remain available.
- Dedicated history screen with newest-first server queries, deterministic
  document-ID tie breaking, 25-bill cursor pages, load-more, refresh, exact full
  bill-ID search, full international phone search, inclusive calendar-date
  range selection, filter clearing, and loading/empty/retry/error states.
- Bill details show saved ID, local date/time, order type, item names,
  quantities, unit prices, line totals, subtotal, discount, loyalty redemption
  and earnings when saved, original bill total, refund amount when saved,
  customer information when saved, and transaction status.
- Missing historical values are labelled **Not recorded**, never replaced with
  current product prices, recipes, customer profiles or loyalty settings.
- Phone numbers are masked in history and initially masked in details; revealing
  one requires an explicit tap. Receipt copies do not include customer phones.
- New loyalty checkouts retain the normalized phone on the bill so future
  bill-history phone searches can match it. No old bill was backfilled.
- Older bills can open the existing Bluetooth thermal-printer dialog with
  configurable **58 mm / 80 mm** paper width. Copies identify themselves as
  receipt copies and include the saved timestamp/status when available.
- Reprinting rechecks server access and saved amounts before opening the dialog.
  Duplicate taps are blocked during preparation and printing; system-back is
  blocked while the printer dialog is sending. Existing printer success and
  uncertain-delivery/failure messages are preserved.
- The reprint path has no checkout, stock, bill-write or loyalty-write dependency.
  Only local printer preferences may be saved by the existing printer dialog.

## Security and data preservation

Firestore security rules were **not changed**. History queries always constrain
`cafeId`; owner, manager and staff/cashier reads use existing active-membership
rules. Direct bill reads are authorized by those rules and additionally checked
against the selected café. Missing and unauthorized IDs produce the same
not-accessible result, including for people who belong to multiple cafés.

Tests use the isolated `brewverse-security-tests` project, never the production
`brewverse-593dc` registration. The original Firebase registration is unchanged.
Mutation/rules tests ran on separate Auth 13198, Firestore 13185, Functions 13101
and Storage 13199 ports. Guards reject the phone backend's ports.

Before-work backup:
`.firebase/bill-history-backup/20261021-165406/records-before.json`.
The final comparison covers all original cafés, memberships, inventory,
recipes, bills, stock movements and this café's loyalty records. All values
and timestamps match the before snapshot; equivalent trailing-zero timestamp
formatting from PowerShell JSON serialization was normalized for comparison.
An after snapshot is retained beside the backup.

Verified existing café state:

| Check | Result |
|---|---|
| Burger Bun inventory | **38 pieces, unchanged** |
| Veg Burger recipe | **2 Burger Buns per burger, unchanged** |
| Existing saved bills | **5, unchanged** |
| Existing bill totals | **₹2,480** |
| Existing billed quantities | **31 items** |
| Loyalty fixes | Preserved; existing regression tests pass |

## Executed validation

| Check | Final result |
|---|---|
| Complete Flutter test suite | **276 passed** |
| Additional current-data validation | **2 passed**, using a read-only snapshot of the five actual bills |
| Functions backend tests | **45 passed** |
| Authenticated callable integration tests | **6 passed** |
| Recipe flow emulator integration | **1 passed** |
| Photo flow emulator integration | **1 passed** |
| Firestore authorization rules | **11 passed** |
| Flutter analysis | **No issues** |
| Formatting / Git whitespace checks | Passed |
| Android debug APK | Built successfully after the checks passed |

History regression coverage includes sort order/ties, dates and boundaries,
exact-ID and normalized-phone search, pagination, empty/error/loading states,
workspace changes during a request, missing historical fields, phone masking,
details navigation, enlarged text, older reprints, rapid taps, printer failures,
invalid receipt amounts, and unchanged bill/stock/loyalty state during reprints.
Rules tests exercise owner/manager/cashier pages, phone/date queries, foreign
IDs/cafés, missing membership and revoked access without weakening authorization.

The two extra current-data tests imported the actual saved bills into an
in-memory Firestore instance: all five paginated, totals/quantities matched,
an existing bill opened through the new screens, and every bill generated
receipt bytes at both paper widths. These are **not** a physical printer test.

Initial screen tests had finder/picker/async asset-loading test-harness issues;
these were corrected and the final suite passed. An initial rules assertion
incorrectly expected an exact foreign-ID query to return empty rather than
permission-denied; the emulator exposed that assumption, the read path and
test were corrected, and all 11 rules tests then passed. The original combined
backend command stopped at that failed assertion, so its subsequent Storage
rules suite was not rerun or claimed as passed. Storage rules were not modified.

## Files changed for this feature

New application files:
- `lib/models/saved_bill.dart`
- `lib/services/bill_history_service.dart`
- `lib/services/bill_reprint_service.dart`
- `lib/screens/bill_history_screen.dart` (history and details screens)

Updated application/backend/configuration files:
- `lib/screens/home_screen.dart`
- `lib/screens/billing_screen.dart`
- `lib/screens/thermal_printer_dialog.dart`
- `lib/services/thermal_printer_service.dart`
- `functions/src/inventory_service.js`
- `firestore.indexes.json` (phone/date composite-index declaration only)

Tests and tooling:
- `test/services/bill_history_service_test.dart`
- `test/screens/bill_history_screen_test.dart`
- `functions/test/inventory_service.test.js`
- `functions/test/firestore_indexes.test.js`
- `security-tests/test/firestore.rules.test.cjs`
- `scripts/test-local-backend.ps1`
- `firebase.test-emulators.json` (dedicated isolated ports)
- `BILL_HISTORY_REPORT.md`

Current-data-only test artifacts remain private under `.firebase/history-tests/`.
Unrelated existing working-tree changes and previous loyalty fixes were retained.

## APK and remaining limitations

New debug APK:
`build/app/outputs/flutter-apk/app-debug.apk`

SHA-256:
`4C20177A6C2CFF0A233E308F738E93375C8E4CBA425B28B25433E899F8BDC88C`

Build flags:
`--debug --dart-define=BREWVERSE_TENANT_MODE=true --dart-define=BREWVERSE_USE_FIREBASE_EMULATORS=true --dart-define=BREWVERSE_FIREBASE_EMULATOR_HOST=127.0.0.1`.
The APK includes the existing local loyalty fixes. **It was not installed.**

- OPPO navigation and actual Bluetooth paper delivery require a manual test
  after the user approves installation. Software tests verify saved receipt
  content and safety, not physical delivery.
- History deliberately requests server-verified reads. **Offline history,
  offline billing and synchronization are not implemented or claimed.**
- Searches use a complete bill ID or normalized full international phone,
  not substring/fuzzy search.
- Historical bills without saved customer phones cannot match a phone search;
  no current customer profile is substituted into old bills.
- Ordered date pages require a stored `createdAt`; undated legacy documents can
  still be opened by full ID. All five current café bills have timestamps.
- Missing/inconsistent receipt fields block reprinting with a clear message;
  missing historical values are never invented to produce a receipt.
- The phone/date index was added to the local manifest, **not deployed**. A future
  production rollout must apply required indexes through an approved release.
- The build emitted existing Gradle native-access / cloud_functions Kotlin
  compatibility warnings but succeeded. Emulator Functions used host Node 24
  while the project declares Node 22; Node 22 was not separately verified.

Reproduce the complete isolated backend workflow when its dedicated ports are free:

```powershell
firebase emulators:exec --config firebase.test-emulators.json --project brewverse-security-tests --only auth,firestore,functions,storage "powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-local-backend.ps1 -BillHistory"
```

The guarded runner also supports `-BillHistory -FirestoreRulesOnly` for the
separate test Firestore when rerunning only that authorization suite.
