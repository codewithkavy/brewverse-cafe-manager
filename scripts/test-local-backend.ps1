param([switch]$BillHistory, [switch]$FirestoreRulesOnly, [switch]$AdminDashboard, [switch]$SeedAdminDemo, [switch]$AdminDemoOnly, [switch]$Reliability, [switch]$BillingProtection, [switch]$InventoryLoyalty, [switch]$ProductionReadiness, [switch]$CreationRetryOnly, [switch]$SecurityVerification)
$ErrorActionPreference = 'Stop'
$firestorePort = if ($Reliability) { 14185 } elseif ($BillHistory) { 13185 } else { 8185 }
$authPort = if ($Reliability) { 14198 } elseif ($BillHistory) { 13198 } else { 9198 }
$storagePort = if ($Reliability) { 14199 } elseif ($BillHistory) { 13199 } else { 9298 }
if ($env:GCLOUD_PROJECT -ne 'brewverse-security-tests' -or
    $env:FIRESTORE_EMULATOR_HOST -ne "127.0.0.1:$firestorePort" -or
    $env:FIREBASE_AUTH_EMULATOR_HOST -ne "127.0.0.1:$authPort" -or
    $env:FIREBASE_STORAGE_EMULATOR_HOST -ne "127.0.0.1:$storagePort") {
  throw 'Run only through firebase.test-emulators.json; security tests clear their isolated fixtures.'
}
$env:BREWVERSE_FUNCTIONS_TEST_URL = if ($Reliability) { 'http://127.0.0.1:14101' } elseif ($BillHistory) { 'http://127.0.0.1:13101' } else { 'http://127.0.0.1:5101' }
Set-Location (Split-Path $PSScriptRoot -Parent)
if ($SecurityVerification) {
  if (!$Reliability -or !$AdminDashboard -or $BillHistory) { throw 'Security verification requires isolated 141xx emulators.' }
  node --test functions/test/subscription_service.test.cjs
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  npm --prefix security-tests test
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  npm --prefix security-tests run test:storage
  exit $LASTEXITCODE
}
if ($CreationRetryOnly) {
  if (!$BillHistory -or $Reliability) { throw 'Creation retry tests require isolated 131xx services.' }
  node --test --test-name-pattern="cafe creation operation IDs|stock item creation retries" functions/test/membership_service.test.js functions/test/inventory_service.test.js
  exit $LASTEXITCODE
}
if ($ProductionReadiness) {
  if (!$BillHistory -or $Reliability -or $BillingProtection -or $InventoryLoyalty) { throw 'Production readiness tests require only the isolated 131xx suite.' }
  npm --prefix functions test
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  node --test functions/test/auth_policy.test.js functions/test/billing_protection.emulator.test.cjs functions/test/step53_loyalty.emulator.test.cjs
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  npm --prefix functions run test:callables
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  npm --prefix security-tests test
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  npm --prefix security-tests run test:storage
  exit $LASTEXITCODE
}
if ($InventoryLoyalty) {
  if (!$BillHistory -or $Reliability -or $BillingProtection) { throw 'Inventory and loyalty tests require only the isolated 131xx suite.' }
  node --test functions/test/inventory_service.test.js functions/test/loyalty_service.test.js functions/test/step53_loyalty.emulator.test.cjs
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
  npm --prefix security-tests test
  exit $LASTEXITCODE
}
if ($BillingProtection) {
  if (!$BillHistory -or $Reliability) { throw 'Billing protection requires the isolated 131xx suite.' }
  node --test functions/test/billing_protection.emulator.test.cjs
  exit $LASTEXITCODE
}

function Save-AdminDemo {
  if (!$BillHistory -or !$AdminDashboard -or !$SeedAdminDemo) { throw 'Demo seeding requires the guarded admin workflow on all four 131xx ports.' }
  node scripts/seed-super-admin-demo.cjs
  if ($LASTEXITCODE) { throw 'Demo fixture creation failed.' }
  # Never use CLI auto-export here: two suites share a project ID and its
  # global locator may identify the phone hub. Address this hub explicitly.
  $directory = Join-Path (Get-Location) ('.firebase/admin-development/fixtures-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
  $body = @{ path = $directory; initiatedBy = 'isolated-admin-fixtures' } | ConvertTo-Json
  Invoke-RestMethod http://127.0.0.1:13120/_admin/export -Method Post -ContentType application/json -Body $body -TimeoutSec 60 | Out-Null
  $credentialPath = (Get-Content .firebase/admin-development/dashboard-demo-login-path.txt -Raw).Trim()
  $login = Get-Content -LiteralPath $credentialPath -Raw | ConvertFrom-Json
  $accounts = Get-Content (Join-Path $directory 'auth_export/accounts.json') -Raw | ConvertFrom-Json
  if (!($accounts.users | Where-Object { $_.email -eq $login.email })) { throw 'Fixture export does not contain the synthetic admin account.' }
  @{ project = 'brewverse-security-tests'; authPort = 13198; directory = $directory; credentialPath = $credentialPath } | ConvertTo-Json | Set-Content .firebase/admin-development/fixture-pointer.json
  Write-Host "Isolated synthetic fixture export verified: $directory"
}
if ($AdminDemoOnly) { Save-AdminDemo; exit 0 }
if ($Reliability) {
  node --test functions/test/reliability.emulator.test.cjs
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
}
if ($AdminDashboard) {
  if (!$BillHistory -and !$Reliability) { throw 'Admin tests require separate 131xx or 141xx emulators.' }
  node --test functions/test/subscription_service.test.cjs
  if ($LASTEXITCODE) { exit $LASTEXITCODE }
}
if ($FirestoreRulesOnly) {
  npm --prefix security-tests test
  exit $LASTEXITCODE
}
npm --prefix functions test
if ($LASTEXITCODE) { exit $LASTEXITCODE }
npm --prefix functions run test:callables
if ($LASTEXITCODE) { exit $LASTEXITCODE }
node --test security-tests/test/recipe_flow.emulator.test.cjs
if ($LASTEXITCODE) { exit $LASTEXITCODE }
node --test security-tests/test/photo_flow.emulator.test.cjs
if ($LASTEXITCODE) { exit $LASTEXITCODE }
npm --prefix security-tests test
if ($LASTEXITCODE) { exit $LASTEXITCODE }
npm --prefix security-tests run test:storage
if ($LASTEXITCODE) { exit $LASTEXITCODE }
if ($SeedAdminDemo) {
  Save-AdminDemo
}
exit 0
