# BrewVerse development roadmap

Updated: 2026-10-19. Branch: `codex/production-integration-phase1`.

The final user instruction is to finish safe changes already underway, verify, checkpoint, push and stop. No further feature work is active. See `PRODUCTION_HANDOFF.md` for architecture, commands, limitations and the final test record in `DEVELOPMENT_PROGRESS.md`.

## Completed handoff scope

- Preserve prior first-party work in checkpoint `1448acb` on `feature/saas-foundation`; exclude local credentials, dependencies and generated artifacts.
- Preserve the existing legacy data paths and opt-in tenant backend/UI work.
- Finish workspace route/dialog cleanup on membership revocation and user changes, with regression coverage.
- Run Flutter analysis, full tests, Android debug build and isolated Firebase authorization/backend/callable tests.
- Publish the development branch without force-pushing and leave a clean tracked working tree.

## Deferred priorities for a future authorized session

1. Reproduce the live checkout denial using reviewed app configuration and deployed-rule information. Local tenant checkout passes; production is not fixed. Preserve denial of direct bill/stock-movement writes.
2. Complete Add/Edit photo selection, accurate image type handling, unique replacement objects, removal/cleanup and authenticated access policy. Current Edit upload is incomplete and hardware-unverified.
3. Verify workspace navigation, revocation and Android back behavior on a device; plan safe staging rollout with verified memberships and tenant indexes.
4. Finish only More actions backed by existing services. Printer settings/profile editing remain disabled; preferences/support are informational.
5. Verify loyalty policy, refunds and BLE receipt output with the café operator and real hardware. Repeat emulator checks on the targeted Node 22 runtime.
6. Separately approve any staging/production rules, Functions or indexes deployment and legacy data migration after backup/ownership review. No subscription activation is authorized.

Previous roadmap details remain recoverable from checkpoint `1448acb`. Do not automatically begin another task after handoff.
