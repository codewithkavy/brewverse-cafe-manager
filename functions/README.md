# BrewVerse trusted membership handlers

This package contains isolated trusted backend operation prototypes for the SaaS foundation:

- `createCafe` creates a café and its initial active owner membership in one Firestore transaction.
- `grantCafeMembership` enforces the owner/manager role limits and reactivates only permitted memberships.
- `revokeCafeMembership` revokes access transactionally, prevents self-revocation, and prevents removing café ownership.
- `listCafeMemberships` returns at most 200 same-café memberships to active owners/managers; staff and cross-café access are denied.
- `createStockItem` records opening stock and its movement atomically; `addStock` records replenishment transactionally.
- `saveRecipe` validates that its product and all referenced stock belong to the same café.
- `checkout` validates role, tenant ownership, recipes, and stock, then writes the bill, deductions, and movements atomically with checkout-ID retry protection.
- `getSalesSummary` reads completed bills for an active café member over a bounded date range and returns saved revenue totals and best sellers.

The Flutter tenant-mode path can call these handlers, including the café team screen, but it is disabled by default and guarded from live Firebase unless `BREWVERSE_ALLOW_LIVE_TENANT_MODE` is explicitly defined. Team managers can grant access to an existing BrewVerse account by email; this does not send invitations or create accounts. Existing legacy records are not tenant scoped; do not enable live tenant mode or migrate those screens until ownership and compatibility have been verified.

## Local tests

Install this package's dependencies. The service tests run against Firestore only from `security-tests/` with:

```bash
firebase emulators:exec --config firebase.json --project brewverse-security-tests --only firestore "npm --prefix ../functions test"
```

The authenticated callable integration test starts the isolated Auth, Firestore, and Functions emulators from the second test-only config:

```bash
firebase emulators:exec --config firebase.emulators.json --project brewverse-security-tests --only auth,firestore,functions "npm --prefix ../functions run test:callables"
```

It creates a synthetic Auth Emulator user, then exercises café creation, stock creation, recipe save, checkout retry, analytics, and unauthenticated rejection. It refuses to run unless all three local emulators use project ID `brewverse-security-tests`.

The tests refuse to run unless the Firestore Emulator environment is active with project ID `brewverse-security-tests`. They use the Admin SDK against the local emulator and do not access production.

This package is not connected to the root Firebase deployment configuration and has not been deployed.
