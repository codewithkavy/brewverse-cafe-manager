# Local emulator checkpoints

Use only the canonical Desktop project and `brewverse-security-tests` with
Auth 9099, Firestore 8085, Functions 5001, and Storage 9199.

Pause phone testing while saving or stopping the suite. These operations
verify state stability; they cannot make transactions across three Firebase
services globally atomic while clients continue writing.

## Commands

- `scripts/save-local-checkpoint.ps1`: coordinated full exports plus recursive
  Firestore snapshots, Auth/Storage stability checks, native export checks,
  Storage checksums, stock-ledger checks, and photo/object reference checks.
  A second full export and a second Firestore capture detect activity during
  capture. A failure retains the exports but does not promote them.
- `scripts/stop-local-emulators.ps1`: save, compare live state with the new
  checkpoint, verify canonical project/process identity, then stop only that
  emulator process tree. It marks the session clean only when all suite ports
  have closed. On Windows, the explicit verified save precedes process stop;
  this does not rely on a graceful signal reaching hidden Firebase processes.
- `scripts/start-local-emulators.ps1`: validate the explicit pointer, export
  hashes, native data files, snapshot and integrity checks; require a clean
  previous session; import all three services; compare live imported state.
  No folder-date selection, empty start, or older-backup fallback is permitted.
- `node scripts/local-checkpoint.cjs verify-live`: read-only database checks
  and a retained export to compare the live dataset with the selected checkpoint.

The install/build workflow remains `scripts/run-v1-phone.ps1`; use the commands
above for data maintenance without building or reinstalling the APK.

## Retention and failure behavior

`.firebase/checkpoints/current.json` explicitly selects an immutable checkpoint
directory and pins its manifest checksum. The manifest hashes every file in
the coordinated export and its logical Firestore snapshot. All prior
directories and verification captures are retained; nothing is pruned.

`.firebase/checkpoints/session.json` records starting/running/clean state.
A crash, failed startup, or missing session marker blocks automatic import,
even if an older valid pointer exists. `operation.lock` prevents simultaneous
checkpoint-manager operations. A lock retained after a crash requires operator
inspection; do not automatically remove it or bypass the stale-session guard.

`--export-on-exit` is retained as an additional salvage path under
`.firebase/checkpoints/salvage/`, never automatically selected or promoted.
If the latest session died before a verified save, inspect retained captures
and explicitly reconcile the newest records. Do not point startup at an older
checkpoint merely to make it launch. Export-on-exit alone is not crash durability.
Save after important test batches and before any planned shutdown. Unexported
in-memory writes can still be lost on machine/process failure.

Native emulator import regenerates Firestore create/update metadata and Auth
`passwordUpdatedAt`, `validSince`, and `lastRefreshAt`. Restart comparisons
allow only those known metadata differences. Saved Firestore fields, including
bill dates, loyalty balances, stock movements, and receipt values, must match.
Auth identities/credentials/config and Storage bytes/object metadata must match.

The current user-cafe promotion invariant checks Burger Bun ledger continuity,
current quantity, and movement presence for completed Veg Burger bills.
Other cafes' synthetic fixtures may intentionally have incomplete ledgers;
they are captured and compared without being rewritten. Photo references to
local Storage must resolve to objects in the same full export; an unset photo
is valid. No remote photo URL is fetched by this workflow.

## Ledger recovery completed (22 October 2026)

After explicit user authorization, four historical movements totaling -56 buns
were restored with original IDs and fields. The two later movements retained
their original deductions, dates and bill links; only `quantityAfter` changed
from 88 to 32 and 86 to 30. Current stock is 30. All other documents were
preserved. The repaired checkpoint passed save, controlled stop, pointer-based
startup and full post-import verification. Earlier conflict captures remain.

Windows/OneDrive may temporarily deny an export directory rename. A failed
capture leaves the current pointer unchanged and keeps its temporary export.
Inspect the error and retry saving; never stop the suite until the full save
and live comparison succeed. During validation, the missing `checks/` parent
directory was fixed and a subsequent transient rename failure was retained;
the later save and restart completed successfully.

Run standalone safeguard tests (no Firebase access or fixture clearing):

`node --test scripts/test/local-checkpoint.test.cjs`

Backend mutation/security suites must use the separate-port
`firebase.test-emulators.json` and `scripts/test-local-backend.ps1` guard.
