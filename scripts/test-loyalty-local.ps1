$ErrorActionPreference = 'Stop'
if ($env:GCLOUD_PROJECT -ne 'brewverse-security-tests' -or
    $env:FIRESTORE_EMULATOR_HOST -ne '127.0.0.1:12185' -or
    $env:FIREBASE_AUTH_EMULATOR_HOST -ne '127.0.0.1:12198' -or
    $env:FIREBASE_STORAGE_EMULATOR_HOST -ne '127.0.0.1:12199') {
  throw 'Loyalty regression tests require their dedicated isolated emulator ports; phone data must not be used.'
}
$env:BREWVERSE_FUNCTIONS_TEST_URL = 'http://127.0.0.1:12101'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
  node --test functions/test/loyalty_flow.emulator.test.cjs
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  npm --prefix functions test
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  npm --prefix functions run test:callables
  exit $LASTEXITCODE
} finally {
  Pop-Location
}
