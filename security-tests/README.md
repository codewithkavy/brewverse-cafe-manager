# Isolated Firestore security tests

This directory is a **test-only sandbox**. It is not the root Firebase deployment configuration and must not be used to deploy production rules.

## Prerequisites

- Node.js 20 or a compatible supported version
- Java runtime required by the Firestore Emulator
- Firebase CLI

## Run locally

From this directory:

```bash
npm install
firebase emulators:exec --config firebase.json --project brewverse-security-tests --only firestore "npm test"
```

The test project ID is deliberately `brewverse-security-tests`, not the live `brewverse-593dc` project. Emulator tests should not need live credentials.

## Scope and limitations

The initial draft tests only top-level `stock_items` tenant isolation and denies every other path by default. It does not yet cover recipes, bills, stock movements, Storage, subscription entitlements, or the complete owner/manager/staff permission matrix.

The tests and rules have been committed to a separate test directory so they cannot silently replace the root Firebase configuration. They have not been executed in this environment. Run them locally and inspect failures before using this draft to guide production rules. Do not deploy this test-only rules file.
