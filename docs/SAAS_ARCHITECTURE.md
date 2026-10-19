# BrewVerse SaaS Foundation — Architecture and Migration Plan

**Status:** Isolated emulator-tested backend and opt-in Flutter tenant path exist; neither is deployed or enabled by default.
**Branch:** `feature/saas-foundation`  
**Scope:** Planning, isolated emulator-tested backend prototypes, and a guarded opt-in Flutter tenant path. No production Firebase configuration, Firestore data, Storage, or deployed rules have been changed.

## Goals

Turn BrewVerse from a single-café starter into a multi-tenant café management product while preserving existing data and avoiding cross-café access.

Initial product requirements:
- Monthly and yearly subscriptions.
- Configurable plan prices; final amounts and payment provider are not yet selected.
- No free trial.
- Android first, with Windows and iOS considered in the platform plan.
- Existing café data must be preserved and assigned to the correct café during migration.

## Proposed Firestore data model

### `cafes/{cafeId}`
Café profile and lifecycle:
- `name`, `createdAt`, `createdBy`
- `status`: `active`, `suspended`, or `closed`
- `settings`: café-specific settings such as currency and receipt preferences

### `cafe_members/{uid_cafeId}` (or an equivalent membership layout)
Membership record:
- `uid`, `cafeId`
- `role`: `owner`, `manager`, or `staff`
- `status`: `active` or `revoked`
- `createdAt`, `createdBy`

The final document ID/layout must support reliable membership checks in Firestore Security Rules. Users must not be able to grant themselves roles or join arbitrary cafés by editing client data.

### `plans/{planId}`
Admin-controlled plan catalogue:
- `name`, `active`
- `monthlyPriceMinor`, `yearlyPriceMinor` (integer minor currency units, e.g. paise)
- `currency`, `features`, optional usage limits
- `updatedAt`

Only a trusted admin workflow may modify plan prices or entitlements. Client apps must not be trusted to decide the amount due.

### `subscriptions/{subscriptionId}`
Subscription and entitlement state:
- `cafeId`, `planId`, `billingPeriod` (`monthly` or `yearly`)
- `status`: `pending`, `active`, `past_due`, `cancelled`, or `expired`
- `currentPeriodStart`, `currentPeriodEnd`
- `provider`, provider reference IDs, and server-managed timestamps

Payment provider and payment flow remain undecided. Subscription activation, renewals, cancellations, and payment verification should be handled by trusted backend code/webhooks—not by a client setting `status: active`.

### Existing business data
The current app uses top-level collections:
- `stock_items`
- `stock_movements`
- `product_recipes`
- `bills`

The target design must associate every business record with a `cafeId` (or place it beneath a café-scoped path). The choice between adding `cafeId` fields and moving data under `cafes/{cafeId}/...` must be made before implementation. A staged `cafeId` migration may be less disruptive to existing queries, but it is safe only when rules and query changes are coordinated.

### Tenant query indexes to prepare before rollout

The current tenant and reporting queries need these composite indexes in the eventual production index manifest:

| Collection | Fields | Query used by |
| --- | --- | --- |
| `stock_movements` | `cafeId` ascending, `createdAt` descending | Recent tenant movement history |
| `bills` | `cafeId` ascending, `createdAt` descending | Recent tenant bill history |
| `bills` | `cafeId` ascending, `createdAt` ascending | Bounded sales-summary date range |

The member list filters on `cafeId`, orders by document ID ascending for stable cursor pagination, and sorts each returned page by UID for display. Firestore appends `__name__` using the direction of the last indexed field by default; the automatic ascending `cafeId` index should therefore support this ordering without an additional composite index. The root `firestore.indexes.json` now records the three tenant history/report composites above, and `firebase.json` points to that manifest. This only defines local deployment inputs; no indexes were deployed. Emulator tests do not validate index availability, so verify them against a staging database before production rollout. See [Firestore index ordering](https://firebase.google.com/docs/firestore/query-data/index-overview#default_ordering_and_the_name_field).

## Authorization principles

1. Firebase Authentication proves identity; it does not by itself grant access to a café.
2. Every business-data read/write must be scoped to a café and checked against an active membership.
3. Roles are enforced in Firestore/Storage Security Rules and, where appropriate, trusted backend code—not only by hiding UI controls.
4. Only owners/managers should receive administrative capabilities; staff permissions should be explicitly defined.
5. Subscription entitlements must be checked from trusted server-controlled state. Never trust price, role, membership, or subscription status supplied by the app.
6. Storage paths and Storage Rules must also be café-scoped.
7. Avoid broad rules such as allowing every authenticated user to read/write all business records.
8. Rules must be tested with emulator/security-rule tests for two separate cafés and users with different roles before deployment.

## Legacy data migration plan

Current known snapshot counts:
- `stock_items`: 7 documents
- `stock_movements`: 10 documents
- `product_recipes`: 0 documents
- `bills`: 0 documents

These are the collections previously checked, not proof that no other root collections exist.

1. Inventory all root collections, nested collections, Storage assets, current rules, and authentication users.
2. Obtain a restoration-capable Firestore export or a verified restore strategy. Existing JSON snapshots are useful for inspection but are not a native Firestore backup and may transform Firestore data types.
3. Decide which existing café owns the legacy records and verify the owner account.
4. Design an idempotent migration script with dry-run mode, explicit document counts, logging, and validation.
5. Add and test tenant-aware queries and rules in a non-production/test environment first.
6. Run migration against a test copy; verify item/movement counts, document IDs, timestamps, references, and app workflows.
7. Schedule a controlled production migration with a maintenance window and rollback plan.
8. Deploy restrictive rules only after all required records and app queries are ready. Never leave a temporary permissive ruleset in place.
9. Verify that Café A cannot read or change Café B data, including direct document access and Storage objects.

### Offline ownership preflight

`functions/src/legacy_migration_preflight.js` is a pure helper for checking an explicitly supplied, normalized JSON snapshot. It does not read Firebase or write documents. `functions/scripts/preflight_legacy_migration.js` is a local read-only CLI wrapper and reads only the explicit file argument (or stdin when passed `-`); it has no Firebase imports or project configuration. For example, from the repository root:

```bash
npm --prefix functions run migration:preflight -- examples/legacy_migration_preflight.sample.json
npm --prefix functions run migration:preflight -- C:/path/to/operator-reviewed-export.json
```

The sample is synthetic. Input must contain all four collection document lists, an explicit `collection/documentId -> cafeId` assignment for every record, and an operator-reviewed owner UID for every café. The helper checks stock categories, recipe product and ingredient categories, line quantities, bill product references, and tenant consistency. The output is a deterministic list of proposed `cafeId` additions plus blocking errors and warnings; exit code 0 means no blocking errors, and exit code 2 means the plan needs correction. A missing stock item referenced by an old movement is a warning for manual history review; cross-café or unmapped recipe and bill references block the plan. `safeToReview` does not authorize or execute a migration. A raw native Firestore export is not this JSON format; normalize a copy and validate data types before running the preflight. Back up separately before any migration tool is designed.

## Implementation sequence

1. **Planning and inventory** — this document; no production changes.
2. **Data-access design** — define a single source of truth for the active café and membership; add tests.
3. **Tenant-aware services** — update inventory, recipes, movements, billing, and photo storage consistently.
4. **Authentication and onboarding** — create a café and owner membership atomically through a trusted flow; existing users need a deliberate migration path.
5. **Security rules** — test and deploy only after migration readiness.
6. **Subscription backend** — plan administration, payment verification, lifecycle webhooks, and entitlement checks.
7. **Billing UI and platform verification** — monthly/yearly selection, clear pricing, no trial, renewal/cancellation status, and platform-specific payment-policy review.
8. **Production rollout** — restore-tested backup, monitoring, support process, and rollback plan.

## Decisions still needed

- Final monthly/yearly prices and whether plans have different features or usage limits.
- Payment provider and supported payment methods.
- Exact staff permission matrix.
- Whether a user may belong to multiple cafés.
- Whether tenant data stays in top-level collections with `cafeId` or moves under café subcollections.
- Native Firestore export/restore strategy and backup retention.
- Production rollout date and acceptable maintenance window.

## Non-goals for this planning change

- No Firestore or Storage writes.
- No security-rule deployment.
- No live-data migration.
- No payment integration or subscription activation.
- No changes to the Flutter app's runtime behavior.
