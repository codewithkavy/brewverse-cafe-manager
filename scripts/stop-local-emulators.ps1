$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$manager = Join-Path $PSScriptRoot 'local-checkpoint.cjs'
# A checkpoint must succeed before this script stops any process.
& (Join-Path $PSScriptRoot 'save-local-checkpoint.ps1')
& node $manager verify-live
if ($LASTEXITCODE) { throw 'Checkpoint comparison failed during shutdown preparation. Nothing was stopped; inspect the error before retrying.' }
$listener = Get-NetTCPConnection -State Listen -LocalPort 4420 | Select-Object -First 1
$suite = Get-CimInstance Win32_Process -Filter "ProcessId = $($listener.OwningProcess)"
$session = Get-Content (Join-Path $projectRoot '.firebase/checkpoints/session.json') -Raw | ConvertFrom-Json
$normalSuite = $suite.CommandLine.Contains((Join-Path $projectRoot 'firebase.json')) -and $suite.CommandLine.Contains('brewverse-security-tests')
$recoveryAdapter = $suite.CommandLine.Contains((Join-Path $projectRoot 'scripts/connect-existing-local-firestore.cjs'))
if ((!$normalSuite -and !$recoveryAdapter) -or $suite.ProcessId -ne $session.hubPid) {
  throw 'Refusing to stop an unverified or changed emulator process.'
}
# Windows has no reliable graceful signal for this hidden CLI. All data has
# already been exported and verified; stop only this verified process tree.
$all = Get-CimInstance Win32_Process
$ids = [System.Collections.Generic.List[int]]::new()
$ids.Add([int]$suite.ProcessId)
for ($i=0; $i -lt $ids.Count; $i++) {
  foreach ($child in $all | Where-Object { $_.ParentProcessId -eq $ids[$i] }) { $ids.Add([int]$child.ProcessId) }
}
$firestoreListener = Get-NetTCPConnection -State Listen -LocalPort 8085 | Select-Object -First 1
if (!$ids.Contains([int]$firestoreListener.OwningProcess)) {
  # The recovery adapter can attach an already-running Firestore process.
  # Stop it only after the same verified full save and exact identity check.
  $externalFirestore = Get-CimInstance Win32_Process -Filter "ProcessId = $($firestoreListener.OwningProcess)"
  if (!$externalFirestore.CommandLine.Contains('--port 8085') -or !$externalFirestore.CommandLine.Contains('brewverse-security-tests') -or !$externalFirestore.CommandLine.Contains((Join-Path $projectRoot 'security-tests'))) {
    throw 'Unverified external Firestore process. No process was stopped.'
  }
  $ids.Add([int]$externalFirestore.ProcessId)
}
for ($i=$ids.Count-1; $i -ge 0; $i--) { Stop-Process -Id $ids[$i] -ErrorAction SilentlyContinue }
$ports = @(9099,8085,5001,9199,4420,4520,9160,9299,9499)
$deadline = (Get-Date).AddSeconds(20)
do {
  $listeners = @(Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -in $ports })
  if (!$listeners.Count) { break }
  Start-Sleep -Milliseconds 500
} while ((Get-Date) -lt $deadline)
if ($listeners.Count) { throw 'Emulator ports are still occupied. Checkpoint is retained; startup remains blocked.' }
& node $manager mark-clean
if ($LASTEXITCODE) { throw 'Could not mark shutdown clean. Startup remains blocked for inspection.' }
Write-Host 'Local emulators stopped after a verified full checkpoint. All historical backups retained.'
