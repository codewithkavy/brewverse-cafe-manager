# BrewVerse Android release and update procedure

Updated October 31, 2026. This supersedes historical environment/build statements in PRODUCTION_HANDOFF.md; that report remains retained as history.

## Current release decision

**Do not distribute the candidate to clients yet.** Cloud Functions API is disabled, billing is off, the project has no Storage bucket and no required composite indexes, and currently deployed Firestore rules expose all legacy inventory/movement rows to any authenticated user. Reviewed stricter source rules have not been deployed. See PRODUCTION_SECURITY_REVIEW.md.

## Environments and data preservation

- Production stays `brewverse-593dc`; local development stays `brewverse-security-tests`.
- Release mode unconditionally disables emulators, validates the Firebase project, uses tenant membership authorization, and uses HTTPS. A Dart define cannot turn release into an emulator build.
- Nonrelease builds default to named local app `brewverse-local`; all four loopback emulators and ADB reverse are required. An explicit `BREWVERSE_USE_FIREBASE_EMULATORS=false` development build selects cloud and must be used only for approved synthetic cloud tests.
- There is no automatic emulator-account/data migration to production. Production legacy rows are not assigned invented owners or moved.
- Complete checkpoint backup, protected credential copy, and newer full live export are retained under `.firebase/production-prep/2026-10-31T10-02-46-594Z-781af210`.
- The user approved restoring that newer export after a 48-second crash gap. It preserves 920 documents, both Auth identities/credentials, and two Storage objects. Missing false Auth import defaults are normalized for comparison only; exports/accounts are never rewritten by the validator.

## Signing and compatible upgrades

- Keep application ID `com.example.brewverse_cafe_manager` permanently.
- The first private production signing identity is stored outside the repository under `%LOCALAPPDATA%\BrewVerse\signing`. Its metadata points to the exact keystore and Windows-DPAPI-protected password. Nothing in this folder should be committed or sent to clients.
- `scripts/create-release-signing.ps1` refuses to replace an existing identity. An unused earlier candidate with an incomplete protected-password file is retained; the metadata selects only the round-trip-validated current key. No APK was signed with the unused key.
- Back up the selected keystore and password securely off this computer, e.g. an encrypted offline backup plus a password manager. DPAPI files alone are not portable to another Windows user/computer. Never create a replacement key for published clients.
- Existing installed debug APKs use the Android Debug certificate. Their registered Firebase SHA fingerprints are the debug fingerprints, not the new release fingerprints. Android cannot install a release-signed APK over a differently signed debug installation. Do not uninstall a client app automatically. Keep that installation, verify/export necessary local-only data, and obtain explicit approval for a transition or use another device for release testing. Reusing the package name does not override signature checks.
- Every future release must increase `pubspec.yaml` version and build number. The build script rejects non-increasing build numbers relative to the previous dist manifest.
- Normal same-signature upgrades preserve Android private storage; production Firebase records remain in the same authorized project. Schema additions here are optional/backward compatible. Any future destructive migration needs a separately reviewed versioned plan and backup.

## Reproducible local build

From the canonical project in PowerShell 7:

```powershell
.\scripts\create-release-signing.ps1
.\scripts\build-release.ps1
```

The default build runs `flutter clean`, `flutter pub get`, `flutter analyze`, `flutter test`, and `flutter build apk --release`; signing secrets are passed through process environment only and restored afterward. Release Gradle never falls back to debug signing. Existing distributable artifacts are archived before replacement. `-SkipValidation` exists for a deliberate internal rebuild only and does not authorize distribution.

Output: `build/app/outputs/flutter-apk/app-release.apk`, copied after signature verification to `dist/BrewVerse-Cafe-Manager.apk`. The adjacent SHA-256 and manifest identify the exact candidate. A signed APK is not evidence that its cloud backend is deployed or working.

## Remaining approvals and device checks

1. Approve a staged legacy-access/security remediation with an approved production backup/ownership review before stricter rule deployment. Rule changes can block old clients even without deleting bytes.
2. Select/approve Firebase Blaze billing, budget alerts and Storage region; enable required APIs, create the approved bucket, deploy reviewed Functions/rules/indexes, and wait for indexes to become ready. No paid activation or deployment has occurred.
3. Approve the new-owner subscription activation policy. Current server behavior requires admin activation; no unrequested free trial was added.
4. Register the exact release SHA-1/SHA-256 while retaining existing debug fingerprints. Verify phone app verification/SMS regions and paid quotas. Monitor and plan App Check enforcement compatibly; it is not silently enabled.
5. With explicit permission and synthetic production test accounts/café only, verify email registration/verification/reset delivery, phone SMS/linking, persistent login, authorized inventory/checkout/receipts/loyalty/reports, data isolation, Wi-Fi/mobile data without laptop, airplane mode/reconnect, and a compatible signed update. Do not claim these real-device tests passed before execution.

## Offline behavior

Cached membership/inventory/history may be read for a persisted identity; cached/unconfirmed state is labeled. Permission failures are not treated as cache fallback. No offline stock or financial write synchronization is claimed: stock changes, checkout, refund and void require confirmed connectivity. Same-user verification-token refresh restarts connection monitoring. Retry IDs for checkout, stock additions, stock-item and café creation are retained per user/workspace through lost replies and app restarts.

## Known remaining caveats

- Existing public download-token photo URLs remain capability links; changing existing tokens would require an approved migration. Sensitive customer documents remain protected by café rules, but do not treat such URLs as revocable per-user authorization.
- Cloud Functions are authored for `us-central1` while Firestore is `asia-south2`; review latency/cost before a separately approved region migration.
- Local Functions tests used installed Node 24 while deployment declares Node 22; actual deployed Node 22 behavior and production attestation still require cloud validation.
- No current physical device was available at the final build stage; no release install, uninstall, mobile-data test, or signed upgrade was performed.
