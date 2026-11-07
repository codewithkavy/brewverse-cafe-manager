# BrewVerse V1 Bluetooth receipt printing — 2026-10-25

## Scope and safety

Implemented in the canonical checkout. Existing working changes were retained.
No deployment, production Firebase access, emulator fixture changes, APK installation,
login/session clearing, Git ref changes, or protected-checkpoint updates were performed.
Tests use mocks/fake Firestore; no running Firebase project was required.

## Files changed by this task

- `android/app/src/main/kotlin/com/example/brewverse_cafe_manager/MainActivity.kt`
- `lib/services/bluetooth_receipt_transport.dart` (new)
- `lib/services/checked_ble_receipt_writer.dart`
- `lib/services/printer_settings_store.dart`
- `lib/services/receipt_print_coordinator.dart`
- `lib/services/thermal_printer_service.dart`
- `lib/screens/thermal_printer_dialog.dart`
- `lib/screens/billing_screen.dart`
- `test/services/bluetooth_receipt_transport_test.dart` (new)
- `test/screens/thermal_printer_dialog_test.dart` (new)
- `BLUETOOTH_PRINTING_REPORT.md` (new)

No package dependency or Android manifest change was necessary. Existing declarations
already cover BLE and Classic scan/connect permission requirements.

## Implemented behavior

- Existing BLE/GATT transport retained with checked 20-byte writes and pacing.
- Android Classic uses a secure RFCOMM socket with the standard SPP UUID
  `00001101-0000-1000-8000-00805F9B34FB`. Connection and writes run off the UI thread.
- Classic discovery lists paired Classic/dual-mode candidates. Pair new devices in
  Android Settings first. BLE discovery remains a nearby BLE scan. The picker labels
  each transport separately, including dual-mode devices sharing one address.
- Device/cafe-local settings persist name, address, transport, width, encoding,
  feed lines (0–10), cut command, and automatic-print preference. Legacy settings
  retain BLE, ASCII, three feed lines and cutting. No saved login data is touched.
- One process-wide queue serves checkout, manual copies and test receipts. Starting
  discovery also goes through this queue. Scanning stops before transport begins.
- Classic cancels Android discovery before connecting. Android 12+ requests Nearby
  devices scan/connect permission. Older Classic paired-device access needs legacy
  Bluetooth permissions, not location; older BLE scans still require location.
- Classic uses a 45-second socket deadline that closes the socket to unblock native
  operations. Owned sockets close in finally; activity destruction also closes them.
- BLE keeps queue ownership until underlying operations and cleanup settle. Universal
  BLE bounds connect/discovery/write/disconnect operations; the receipt checks a
  60-second deadline before each chunk. This is not a hard 60-second wall-clock cap:
  an in-flight command and cleanup can extend it. No blind retry is performed.
- Save-printer does not claim hardware compatibility. A visible Print Test Receipt
  action is available for the saved printer; each candidate also has a test icon.
  Test receipts are synthetic and have no bill/stock/loyalty dependencies.
- 58 mm / 80 mm receipts use 32 / 48 text columns, wrap long item names, and align
  amount columns. Oversize amount combinations move onto separate lines.
- Each receipt resets printer formatting. ASCII output remains the default. An
  opt-in CP1252 Latin profile selects that ESC/POS table and allows U+00A0–U+00FF;
  unsupported text still becomes `?`. This is deliberately a limited Western Latin
  profile: it does not implement arbitrary Unicode, Indic scripts, or CP1252's
  special punctuation/Euro mappings. Currency remains `Rs`.
- Paper feed and cutting are configurable independently. Disable cutting for
  tear-bar printers or devices that do not support the command.
- Automatic printing remains after committed checkout, using saved bill values.
  Delivery failure never resubmits checkout. Automatic attempts remain claimed
  after failure/uncertainty; recovery requires explicit printing.
- Last-receipt printing uses the saved bill and now passes its date/status/cafe name
  (with a fallback when absent) and `RECEIPT COPY`. History copies retain existing
  access checks, saved-value validation, copy labeling and rapid-tap protection.
- Status says bytes were sent and paper is not confirmed. Partial-send errors tell
  the user to inspect paper before retrying.

## Verification

Final targeted regression run: **90 tests passed, 0 failed**, covering:

- Legacy migration, profile persistence/validation and transport selection.
- BLE/Classic routing with independent mocks; scan-stop ordering.
- Disconnect/timeout failures and queue recovery for explicit reprint.
- Concurrent automatic/manual jobs across separate transport instances.
- Classic method-channel candidate and byte forwarding.
- BLE session cleanup on false connection, partial write failure and deadline expiry.
- BLE chunk bounds, acknowledged/without-response writes, no writable endpoint,
  and partial-write error propagation.
- Width, wrapping, ASCII/Latin encoding, copy marker and cut command behavior.
- Saved Classic settings and test action on a 320px-wide phone.
- Existing automatic-print deduplication, malformed receipt rejection, saved-history
  authorization, billing recovery, inventory direct stock and loyalty regressions.
- Fake Firestore assertions that historical reprints leave bills, stock quantity
  and loyalty balance unchanged.

An intermediate narrow-screen test found a dropdown overflow. It was fixed and the
final run passes. `flutter analyze --no-pub`: **passed, no issues**.

Debug APK compilation includes the native Classic code. The APK is only a local
build artifact and was not installed. Native Android Bluetooth operations are not
validated by Dart mocks; there was no hardware/instrumentation execution.

Commands:

```powershell
flutter analyze --no-pub
flutter test --no-pub test/services/bluetooth_receipt_transport_test.dart test/services/checked_ble_receipt_writer_test.dart test/services/receipt_print_coordinator_test.dart test/services/thermal_printer_service_test.dart test/services/bill_history_service_test.dart test/screens/bill_history_screen_test.dart test/screens/billing_screen_test.dart test/screens/thermal_printer_dialog_test.dart test/screens/inventory_direct_stock_test.dart test/screens/loyalty_screen_test.dart test/services/checkout_recovery_store_test.dart
flutter build apk --debug --no-pub
```

## Compatibility limits and release blockers

No physical printer, including SEZNIK Veer, has been certified by this work.
ESC/POS describes commands, not Bluetooth transport or endpoint compatibility.

- Classic requires a paired device exposing standard secure SPP. No insecure socket,
  hidden-channel reflection fallback or vendor proprietary framing is implemented.
- BLE requires a raw ESC/POS writable GATT endpoint. The inherited writer prefers
  the first writable characteristic, then write-without-response; vendor UUID
  profiles/handshakes may be needed for some models. Unnamed BLE advertisements are
  still omitted by the installed plugin. Dual-mode candidates require testing.
- No USB transport is added. No Wi-Fi, iOS Classic or background print service.
- The queue is process-local. Another app/phone may still contend for the printer.
- Automatic-attempt claims are per cafe/bill/address and local to this installation.
  Clearing app data or choosing another address can permit another automatic copy.
- Socket/GATT delivery cannot prove physical output, paper availability or successful
  cutting. Printer firmware may buffer data after the socket closes.
- Runtime permission dialogs, native timeout cancellation, lifecycle cleanup,
  long-receipt buffering and repeated physical output remain release gates.
- CP1252 table numbering/support, 32/48 columns, feed/cut behavior and non-ASCII
  glyphs must be checked on the specific model/firmware before enabling that profile.
- Existing Gradle build warnings concern JVM native access and cloud_functions'
  Kotlin Gradle plugin migration; they did not prevent debug compilation.

## Manual device checklist — not executed

1. Record phone Android version, printer exact model/firmware and self-test output.
   Identify BLE, Classic SPP or dual mode; verify supported ESC/POS/codepages/cutter.
2. On Android 12+, test Nearby devices allow, deny, permanent deny and later revoke.
   On Android 11 or older, test BLE location allow/deny and location services off/on.
3. Pair Classic in Android Settings, reopen scan, confirm Classic label; confirm BLE
   advertising appears separately. Test unpaired, powered-off and unsupported devices.
4. Save transport/58mm or 80mm/feed/cut/profile, restart app and confirm persistence
   for the correct cafe. Confirm login and cafe data remain available.
5. Print the synthetic test receipt independently over BLE and Classic. Inspect
   actual paper, alignment, feed and cutting before claiming compatibility.
6. Print long receipts, unbroken item names, large amounts/quantities, discounts,
   both widths and accented Latin text. Check unsupported text degrades to `?`.
7. Interrupt connection and mid-receipt printing: power off, walk out of range,
   paper-out, lid-open, sleep/wake, low battery and another app holding the printer.
   Verify bounded recovery, no overlapping jobs, honest uncertain status and cleanup.
8. Submit rapid consecutive synthetic sales while opening manual/test printing.
   Verify serialization and no byte interleaving. Verify failed automatic printing
   does not automatically resend; inspect paper before an explicit copy.
9. Reprint last and older saved bills after menu prices change. Confirm copy marker,
   original saved amounts/date/status, and unchanged bill/stock/loyalty records.
10. Run at least 20 consecutive receipts on each transport and repeat after app
    background/resume, printer power cycle and phone Bluetooth toggle.

For any future checkout-on-device tests, use only `brewverse-security-tests` with
all four local emulators via `scripts/run-v1-phone.ps1`, prescribed ports and ADB
reverse. A future APK installation requires separate authorization; none occurred
in this task. Never test checkout or stock writes against production Firebase.
