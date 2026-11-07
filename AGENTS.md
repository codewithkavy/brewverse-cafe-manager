# BrewVerse V1 working agreement

- Canonical project: `C:\Users\bhash\OneDrive\Desktop\brewverse_cafe_manager`.
- Perform development, debugging, tests, and APK builds here. Other worktrees
  are retained for recovery/reference; do not maintain a second app there.
- Stabilize inventory, recipes, stock tracking/deduction, billing/history, and
  basic receipts. Preserve existing features and data; avoid unrelated rewrites.
- Never deploy or write production Firebase during local development. Use the
  explicit `brewverse-security-tests` project and all four local emulators.
- Phone ports: Auth 9099, Firestore 8085, Functions 5001, Storage 9199. Physical
  Android uses 127.0.0.1 via ADB reverse; keep automatic host mapping disabled.
- Use `BrewVerseFirebaseConfig` accessors for every Firebase service. Local
  builds bind the named `brewverse-local` client app to `brewverse-security-tests`
  and Functions region `us-central1`. Never use default SDK service singletons
  in local application code: Android's native default app retains the release
  registration even when only projectId is overridden in initializeApp options.
- Debug-only network security permits loopback HTTP; do not enable release HTTP.
- Security suites clear fixtures: run them only through the separate-port
  `firebase.test-emulators.json` and guarded `scripts/test-local-backend.ps1`.
- Do not delete branches/worktrees/data, reset changes, deploy, push, or merge
  remote main without the user's explicit authorization.
- Main Windows workflow: `scripts/run-v1-phone.ps1`.
