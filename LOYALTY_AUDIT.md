# BrewVerse V1 loyalty investigation — 21 October 2026

Canonical project: `C:\Users\bhash\OneDrive\Desktop\brewverse_cafe_manager`.
Branch: `codex/fix-physical-device-cafe`.

## Findings and root causes

1. **Checkout silently dropped customer phones unless lookup had succeeded.**
   `BillingScreen._checkout` sent `customerPhone: null` whenever
   `_loyaltyCustomer == null`, even when the user typed a phone or arrived from
   Loyalty with a prefilled phone. Two widget regressions reproduced the actual
   checkout request containing null. Checkout now preserves a nonempty phone;
   the trusted backend still validates it and registers the customer only when
   the sale commits. An empty phone still means a sale without loyalty, and a
   pending checkout retry keeps its original saved request. This bug can explain
   missing enrollment after entering a phone; historical user actions cannot be
   reconstructed conclusively from the stored records.
2. **The unavailable messages were hard-coded feature placeholders.**
   The Customers view implements phone lookup, not a customer directory. Its
   unavailable note appeared before any lookup and after successful lookup.
   The Transactions tab and customer-details history panel perform no history
   query at all. Their messages are not evidence of permission, connection or
   missing-data errors. Copy now says “Find customers by phone number” and
   “Transaction history is not included in this build.” Existing lookup errors
   remain errors; no fabricated directory or history was added.
3. **Enrollment and points wording was imprecise.** The UI now explains that a
   new customer is saved only after successful checkout. The new-customer
   lookup notice no longer promises points on every sale: below-threshold or
   disabled-policy sales may earn zero.

## Existing behavior, verified

- Customers are café-specific records under
  `cafes/{cafeId}/loyaltyCustomers/{hash}`. They are not Firebase Auth users and
  do not register via email/password or OTP. The deterministic ID hashes café
  ID plus normalized international phone, preventing duplicate enrollment for
  the same normalized phone within a café.
- Lookup is read-only. Entering a phone, pressing Find customer, or opening a
  new bill does not register anyone. The first completed checkout with a phone
  creates the customer, even if it earns zero points. Rejected checkout creates
  neither customer nor loyalty ledger entry.
- Balance lookup and checkout require an active owner, manager or staff
  membership. Owner-only settings can override the defaults below.
- The existing local café has no saved policy override. Its resolved default
  is **4 points per complete ₹100 of net payment**, plus the highest qualifying
  bonus: 5 points at ₹500, or 10 at ₹1,000. Bonuses are not cumulative.
  Examples: ₹80 earns 0; ₹160 earns 4; ₹500 earns 25; ₹1,000 earns 50.
- Default redemption value is **₹1 per point**, capped at 100% of the bill and
  the available unexpired balance. Lookup is needed to show a balance and choose
  redemption in the UI. Points are earned on payment after the discount.
- Default expiry is 12 calendar months. Redemption consumes the earliest
  expiring buckets first. Refund policy defaults reverse earned points and
  restore eligible redeemed points; expiry and policy still apply.
- Customer balance, loyalty ledger, bill and stock deduction commit in one
  transaction. Reusing a checkout request does not award/deduct twice. Two
  simultaneous redemptions cannot spend the same points twice.

## Existing local data and safety

Only read operations were performed against the phone backend on
127.0.0.1:9099/8085/5001/9199, project `brewverse-security-tests`.
Burger Bun was **38 before and after**. The original café, stock document and
loyalty collection responses exactly match the saved before/after snapshots in
`.firebase/loyalty-audit/20261021-164105/`.

The café contains **zero loyalty customers and zero loyalty transactions**.
An initial PowerShell diagnostic mistakenly counted an empty response as one;
the original saved response and direct Firestore SDK reads confirm zero. No
records disappeared during testing. Existing business data was not modified.

All mutation tests used separate emulators on Auth 12198, Firestore 12185,
Functions 12101 and Storage 12199. The phone backend remained running.
No production Firebase writes, deployment, Git push, or APK installation occurred.

## Tests actually executed

| Check | Result |
|---|---|
| Misleading initial-state regression before fix | Failed as expected |
| Entered/prefilled phone regressions before fix | Both failed as expected: actual request phone was null |
| Targeted Flutter suites after final fix: loyalty, customer details, settings, billing, checkout recovery | **61 passed** |
| `flutter analyze` after final fix | **No issues** |
| Real authenticated loyalty callable suite | **8 passed** (parent plus 7 scenarios) |
| Existing Functions backend suite | **45 passed** |
| Existing callable integration suite | **6 passed** |
| Dart formatting and Git whitespace checks | Passed |
| Before/after existing-data comparison | Exact match; Burger Bun 38 |

The real loyalty suite covered lookup without enrollment, insufficient-stock
rollback, zero-point enrollment, earning, retry idempotency, redemption totals,
invalid-redemption rollback, concurrent-redemption safety, missing
authentication and invalid phone format. Existing backend tests also exercised
expiry, café isolation and refund/void point handling.

Initial isolated harness startup failed because Firebase CLI resolved absolute
Functions source paths relative to the nested config directory. The failed
startup also left its test Firestore port occupied. A root-level config with
relative source paths and separate free ports corrected the harness; the
complete run then exited successfully. Firebase CLI also emitted a Storage
rules Java shutdown warning after the successful run. It did not fail tests.
The CLI used host Node 24 despite the declared Node 22 runtime; Node 22 was not
separately tested. No OPPO UI flow was executed in this investigation.

Reproduce backend tests from the canonical project (dedicated ports must be free):

```powershell
firebase emulators:exec --config firebase.loyalty-regression.local.json --project brewverse-security-tests --only auth,firestore,functions,storage "powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-loyalty-local.ps1"
```

## Files changed in this investigation

- `lib/screens/billing_screen.dart`: preserve entered phone; correct enrollment notice.
- `lib/screens/loyalty_screen.dart`: truthful feature and enrollment messages.
- `lib/screens/loyalty_customer_details_screen.dart`: truthful history message.
- `test/screens/billing_screen_test.dart`: entered/prefilled phone regressions.
- `test/screens/loyalty_screen_test.dart`: truthful-state regressions.
- `test/screens/loyalty_customer_details_screen_test.dart`: history-copy expectations.
- `functions/test/loyalty_flow.emulator.test.cjs`: real callable regressions.
- `scripts/test-loyalty-local.ps1`: guarded dedicated-port test runner.
- `firebase.loyalty-regression.local.json`: isolated emulator configuration.
- `LOYALTY_AUDIT.md`: this report.

## Next manual test

A **new APK is required** to exercise the phone-preservation fix and copy changes.
It has not been built or installed in this investigation. Installation requires
the user's approval. After installation, test a fresh international phone at
checkout without pressing Find customer, then look it up after the completed
sale; use a later bill to test redemption. A browsable customer directory and
transaction-history UI remain unimplemented features.
