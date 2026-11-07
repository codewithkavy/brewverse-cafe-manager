# Local product photo upload repair

Observed on 21 October 2026 in the canonical Desktop project.

## Evidence and cause

The OPPO log repeatedly reported POST failures to
`http://127.0.0.1:9199/v0/b/brewverse-593dc.firebasestorage.app/o`, followed by
Storage exponential-backoff messages (`network unavailable, sleeping`). ADB
reverse already included all four required ports. Only Firestore 8085 was
listening on Windows; Auth, Functions, Storage, and the emulator hub had stopped.
The App Check placeholder warning was not evidence of a Storage rules rejection.

PhotoService awaited native upload retries, URL retrieval, and failure cleanup
without application deadlines. Failure cleanup could itself keep the form's
`finally` block from resetting its loading state.

## Changes

- Upload: 30-second Dart deadline plus native retry limit and bounded cancel.
- Image-file reads and download URL: 10-second deadlines.
- Failed-attempt, previous-photo, and rollback cleanup: 2-second deadlines.
- A cancelled attempt that later completes cleans only its own unique object.
- Clear connection, authentication, and permission messages; existing inventory
  and photo compare-and-set behavior retained.
- Startup supports local import and unique export-on-exit snapshots, never
  overwriting the recovery backup. A hidden launcher now runs the restored suite.
- Added timeout/cancellation/cleanup regressions and an authenticated local
  upload/download/Firestore-link/permission integration test to the test runner.

## Data protection and recovery

Before restarting the orphaned Firestore process, a native export plus a JSON
business-record snapshot was saved under:
`.firebase/recovery/20261021-153630`.

After import, every document name and field matched for 45 cafes, 711 membership
records, 46 inventory items, 16 recipes, 27 bills, and 33 stock movements. No
existing inventory photo links were present in that snapshot. A complete
Firestore/Auth/Storage checkpoint was then verified at:
`.firebase/saved-state/20261021-154748-checkpoint`.

Auth had already stopped before recovery. Its prior in-memory test accounts were
not present in the surviving Firestore export; the recovered Auth emulator has
zero users. Existing local login may need same-UID account recovery. No account
passwords were reset and no replacement identities were created. Production
Firebase was not contacted for data operations or modified.

## Executed validation

- Flutter analysis: no issues; 259 Flutter tests passed.
- Timeout tests cover a stalled upload, stalled cancellation, stalled cleanup,
  stalled URL retrieval, successful upload, and permission failure preservation.
- Real authenticated Storage integration passed against spare loopback ports,
  using the Android bucket name: owner upload/download, metadata, transactional
  Firestore pointer save without quantity change, staff read/upload denial,
  anonymous upload denial, and successful-image preservation.
- Firestore rules: 10 passing; Storage rules: 4 passing.
- PowerShell syntax and Git whitespace checks passed.
- Fresh debug APK built successfully with local emulator settings.

APK: `build/app/outputs/flutter-apk/app-debug.apk`.

No APK was installed and no phone UI was opened during this repair. Installing
requires the user's approval. The actual gallery flow with the updated Android
code therefore remains pending. Existing Node/Gradle deprecation and emulator
rules-runtime shutdown warnings did not fail the tests or build.
