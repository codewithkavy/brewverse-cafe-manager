# BrewVerse V1 consolidation

Canonical development directory:
`C:\Users\bhash\OneDrive\Desktop\brewverse_cafe_manager`

Working branch: `codex/fix-physical-device-cafe`. Changes remain local and
reviewable in this working tree. No deploy, push, remote merge, branch removal,
worktree removal, or production data changes were performed.

## Recovery backup

`C:\Users\bhash\OneDrive\Desktop\brewverse-safety-backups\20261021-140302`

Contains a verified all-branches Git bundle, verified source ZIPs of both
worktrees (including untracked local sources/assets), and binary Git diffs/status
records. Generated builds and dependency caches were excluded. The other
worktree remains intact, including its uncommitted main.dart and test edits.

## Integrated work

Reviewed `codex/checkout-integrity` at `66cfab8`, including its photo and Firebase
CI ancestors. Integrated checkout identity/retry protection, decimal stock
rounding, direct-stock finished products, pending-checkout recovery, basic
receipt formatting/delivery and printer preferences, safe product photo
lifecycle, and separate Firebase CI jobs. Included the useful uncommitted
stockMode test expectation without copying unrelated text encoding damage.

Kept the canonical physical-phone Firebase setup instead of the older automatic
Android host mapping and duplicate network configuration. Existing inventory,
assets, release Firebase registration, and user changes were preserved. No data
migration or inventory reset was performed.

Debug/profile builds always use the local test project and tenant path, even
without compile-time flags. Release behavior is unchanged. Root Firebase
configuration uses existing local rules and Functions source. Security tests
run on separate ports and their script rejects other project/port settings.

## Validation

- All 252 Flutter tests passed, including new checkout recovery/isolation and
  local-build Firebase safety tests.
- Flutter analysis: no issues; formatter: 69 files unchanged; Git whitespace
  checks passed.
- Backend service, callable integration, and security suites exited successfully
  against isolated emulators. Firestore rules: 9 passing; Storage rules: 4 passing.
- Integration exercised café creation, direct-stock checkout, cashier isolation,
  idempotent retries, and stale Auth refresh-token rejection.
- Canonical suite started with Auth 9099, Firestore 8085, Functions 5001, Storage
  9199, all on 127.0.0.1. Callable readiness probe returned the expected 401.
- PowerShell scripts parsed successfully. Missing-phone handling was exercised;
  complete installation cannot be exercised without an authorized device.
- Fresh debug APK built from this directory with emulator flags. Packaged
  network configuration denies general HTTP and permits only 127.0.0.1.

APK: `build/app/outputs/flutter-apk/app-debug.apk`

SHA256: `1F02A22838DA8E064DC4C17A39468ED12428DE56E6FC2B1F3AABD85F89C45E3B`

Tooling warnings remain: installed Node 24 differs from the declared Node 22,
Gradle reports plugin deprecations, and the rules runtime prints an exception
during shutdown after successful tests. These did not fail analysis/tests/build.

## One-command Windows workflow

Connect exactly one USB Android phone, enable USB debugging, and approve its ADB
authorization prompt. Flutter, Firebase CLI, Java, Node, and Android platform-tools
must be installed; dependencies are already available on this laptop.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\bhash\OneDrive\Desktop\brewverse_cafe_manager\scripts\run-v1-phone.ps1"
```

This rebuilds the canonical emulator APK, verifies/reuses the canonical suite
or starts it hidden with timestamped logs under `.firebase/workflow-logs`, waits
for createCafe to be ready, configures four ADB reverse mappings, and installs
the APK. It does not kill conflicting processes. Emulator data remains in memory
unless separately exported; no existing exports are removed or overwritten.

Remaining physical checks: sign in (or sign out/re-login after an Auth emulator
restart), create a café, create ingredient/product/recipe, sell an order, inspect
stock movements and bill history, and print a receipt if a BLE printer is used.
No phone or printer was connected during this consolidation.

## OPPO callable routing fix (21 October 2026)

Follow-up diagnosis found two emulator log entries requesting
`/brewverse-593dc/us-central1/createCafe` rather than the loaded local route
`/brewverse-security-tests/us-central1/createCafe`. FlutterFire reused Android's
auto-initialized default app: its soft options comparison ignores projectId.
Changing projectId alone therefore did not select the local native SDK project.

Local builds now initialize a named client app (`brewverse-local`) and all Auth,
Firestore, Functions, and Storage callers use centralized accessors for it.
This does not create another Firebase project. Release uses the existing default
registration. Client/server Functions region is explicitly `us-central1`.
The installer checks listeners and verifies ADB reverse mappings for all four
ports; the OPPO previously had only Auth and Functions reversed.

Verified on the connected OPPO with
`flutter test integration_test/local_cafe_flow_test.dart -d 7XINAEWO79WGEA89`:
native test account registration, café creation, active owner membership,
authorized inventory reads/writes through callables, billing, stock deduction,
and idempotent checkout retry all passed. Synthetic local records were retained.
All 252 Flutter tests, 45 backend tests, 6 callable integration tests, and Flutter
analysis passed. No production operations, deployment, push, or deletion.
The regular app APK is rebuilt after the instrumented test; its previous hash
above belongs to the earlier consolidation build.
