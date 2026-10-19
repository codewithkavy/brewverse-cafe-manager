# BrewVerse Authorization Test Plan

**Status:** Emulator-only Firestore and Storage rule prototypes plus this authorization plan; none are production rules.
**Branch:** `feature/saas-foundation`

## Current milestone

The `CafeMembership` domain model and unit tests define accepted membership roles (`owner`, `manager`, `staff`) and statuses (`active`, `revoked`). Model validation is not an authorization boundary. Emulator rule suites exercise the isolated prototypes; no production rules or data have been changed.

## Test-only role and data contract (draft)

The isolated `security-tests/firestore.rules` prototype currently assumes top-level business documents carry an immutable `cafeId`, with membership records at `cafe_members/{uid}_{cafeId}`. Active members can read café records. Owners and managers can edit inventory item details but cannot create/delete stock documents or change stock quantities. Recipe writes, bills, stock movements, memberships, and café ownership are reserved for trusted backend operations. This prevents direct client writes from bypassing recipe-reference checks or stock audit transactions. This conservative matrix is for emulator work only and still needs product review before release.

The Flutter app has a guarded, opt-in tenant path: tenant reads are scoped by `cafeId`, while stock creation/addition, recipe saves, and checkout use trusted callable handlers. Legacy mode remains the default and still uses unscoped records and client-side checkout. Membership administration callables also exist. The test rules and handlers remain isolated and undeployed; legacy data ownership, migration, indexes, Storage authorization, subscriptions, and a reviewed final role matrix are still release blockers.

The isolated Storage rules prototype uses `cafes/{cafeId}/products/{fileName}`. Active café members can read images; active owners/managers can upload, replace, or delete JPEG/PNG/WebP files up to 5 MiB; staff and cross-café users cannot write. Other paths, including the legacy `products/{itemId}.jpg` path, are denied. Four Storage Emulator tests exercise those limits. The tenant inventory editor uses `PhotoService` to upload JPEGs under a unique café-scoped object name and writes the returned URL to that café's stock item. Device upload verification remains incomplete. No Storage rule has been deployed.

## Before any rules deployment

Implement and run Firestore Emulator tests using at least two independent cafés (A and B), users (owner A, manager A, staff A, owner B, and a signed-out/unauthenticated context).

### Tenant isolation cases

- Owner A can access only Café A records for which their membership is active.
- Owner A cannot list, read, create, update, or delete Café B records.
- A user cannot bypass tenant isolation by guessing a document ID or calling a direct document path.
- A query that is not constrained to the authorized tenant must fail where required by the chosen data model and rules.
- Missing, malformed, revoked, or mismatched membership denies access.
- Unauthenticated requests are denied for private café data.
- Cross-tenant references (for example, a recipe in Café A referencing a stock item in Café B) are denied.

### Role cases

- Owner permissions match the finalized role matrix.
- Manager permissions match the finalized role matrix and cannot perform owner-only actions.
- Staff permissions match the finalized role matrix.
- Client writes cannot grant a user a role, activate a revoked membership, change a café's owner, or alter trusted subscription status.
- Revoked membership loses access on subsequent requests.

The precise operation-by-role matrix must be agreed and recorded before rules are written. Do not infer that the UI hiding a control provides security.

### Subscription cases

- Client requests cannot change a subscription to `active` or set a trusted price.
- Expired, suspended, or otherwise ineligible subscriptions receive only the explicitly chosen access (for example, read-only billing/account access if that policy is selected).
- Subscription state is changed only by a trusted backend/payment-verification path.

### Storage cases

- Café A can access only objects under Café A's authorized storage scope.
- Café A cannot read, overwrite, or delete Café B's photos/receipts.
- Upload type, size, and path rules are validated as required by the product.

## Release gate

Do not deploy restrictive rules until:
1. the final data layout and role matrix are agreed;
2. all production records have a verified tenant assignment;
3. the migration has been rehearsed against a test copy;
4. a restoration-capable backup and rollback plan exist;
5. emulator tests pass, including cross-tenant denial;
6. tenant-aware application queries are deployed together with the rules.

The existing JSON snapshots are useful inspection artifacts, but are not a native Firestore export and should not be the only disaster-recovery mechanism.
