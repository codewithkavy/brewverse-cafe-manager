param([switch]$CheckOnly, [string]$ImportPath, [switch]$DebugLogging)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $projectRoot 'firebase.json'
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
foreach ($command in 'firebase', 'node', 'java') {
  if (!(Get-Command $command -ErrorAction SilentlyContinue)) {
    throw "Missing $command on PATH. Install it before starting the local Firebase suite."
  }
}
foreach ($resource in @($config.firestore.rules, $config.firestore.indexes,
    $config.storage.rules, 'functions/src/index.js', 'functions/node_modules/firebase-functions/package.json')) {
  if (!(Test-Path -LiteralPath (Join-Path $projectRoot $resource))) {
    throw "Missing required local resource: $resource. For Functions dependencies run npm --prefix functions ci."
  }
}
$ports = @($config.emulators.auth.port, $config.emulators.firestore.port,
  $config.emulators.functions.port, $config.emulators.storage.port,
  $config.emulators.hub.port, $config.emulators.logging.port,
  $config.emulators.firestore.websocketPort, $config.emulators.eventarc.port,
  $config.emulators.tasks.port)
$listeners = @(Get-NetTCPConnection -State Listen -ErrorAction Stop |
  Where-Object { $_.LocalPort -in $ports })
if ($listeners.Count) {
  $details = ($listeners | ForEach-Object {
    "port $($_.LocalPort) (PID $($_.OwningProcess))"
  }) -join ', '
  throw "Local emulator ports are occupied: $details. Stop the conflicting suite in its terminal or reuse it; this script never kills processes."
}
Write-Host 'Local project: brewverse-security-tests. Auth 127.0.0.1:9099; Firestore 127.0.0.1:8085; Functions :5001; Storage :9199.'
$manager = Join-Path $PSScriptRoot 'local-checkpoint.cjs'
$validatedImport = & node $manager resolve
if ($LASTEXITCODE) { throw 'No safe checkpoint is available. Import was not attempted.' }
if ($ImportPath -and [IO.Path]::GetFullPath($ImportPath) -ne [IO.Path]::GetFullPath($validatedImport)) {
  throw 'Explicit import differs from the validated checkpoint pointer. Arbitrary older imports are disabled.'
}
$ImportPath = $validatedImport
if ($CheckOnly) { Write-Host 'Emulator preflight and checkpoint integrity passed.'; return }
$reserved = & node $manager reserve
if ($LASTEXITCODE -or $reserved -ne $ImportPath) { throw 'Could not reserve the validated checkpoint.' }
$logRoot = Join-Path $projectRoot '.firebase/workflow-logs'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$stateArgs = @('--export-on-exit', (Join-Path $projectRoot ".firebase/checkpoints/salvage/$stamp"))
if ($DebugLogging) { $stateArgs += '--debug' }
$firebaseCli = Join-Path (Split-Path (Get-Command firebase).Source -Parent) 'node_modules/firebase-tools/lib/bin/firebase.js'
if (!(Test-Path -LiteralPath $firebaseCli)) { throw 'Could not resolve the installed Firebase CLI entry point.' }
$arguments = @($firebaseCli, 'emulators:start', '--config', $configPath, '--project', 'brewverse-security-tests', '--only', 'auth,firestore,functions,storage') + $stateArgs + @('--import', $ImportPath)
$quoted = $arguments | ForEach-Object { '"' + $_ + '"' }
$stdout = Join-Path $logRoot "$stamp.emulators.stdout.log"
$stderr = Join-Path $logRoot "$stamp.emulators.stderr.log"
$runtimeTemp = Join-Path $logRoot "$stamp.runtime-temp"
New-Item -ItemType Directory -Path $runtimeTemp | Out-Null
$originalTemp = $env:TEMP; $originalTmp = $env:TMP
try {
  $env:TEMP = $runtimeTemp; $env:TMP = $runtimeTemp
  $worker = Start-Process (Get-Command node).Source -WindowStyle Hidden -PassThru -WorkingDirectory $projectRoot -ArgumentList $quoted -RedirectStandardOutput $stdout -RedirectStandardError $stderr
} finally { $env:TEMP = $originalTemp; $env:TMP = $originalTmp }
Write-Host "Restoring validated checkpoint: $ImportPath"
Write-Host "Logs: $stdout and $stderr"
$ready = $false
$deadline = (Get-Date).AddMinutes(3)
do {
  if ($worker.HasExited) { throw "Emulator startup failed. Check $stdout and $stderr. Checkpoint is retained; automatic retry is blocked." }
  try {
    $hub = Invoke-RestMethod -Uri 'http://127.0.0.1:4420/emulators' -TimeoutSec 2
    $ready = $hub.auth.port -eq 9099 -and $hub.firestore.port -eq 8085 -and $hub.functions.port -eq 5001 -and $hub.storage.port -eq 9199
  } catch { }
  if (!$ready) { Start-Sleep -Seconds 2 }
} while (!$ready -and (Get-Date) -lt $deadline)
if (!$ready) { throw 'Emulator startup timed out. Automatic stale fallback is blocked; inspect retained logs.' }
$hubIdentity = Invoke-RestMethod http://127.0.0.1:4420/ -TimeoutSec 5
if ($hubIdentity.pid -ne $worker.Id) { throw 'Unexpected phone hub identity.' }
# Checkpoint tools run in the normal shell; publish the verified phone locator.
$hubIdentity | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $originalTemp 'hub-brewverse-security-tests.json')
& node $manager mark-running
if ($LASTEXITCODE) { throw 'Could not verify the running emulator identity.' }
& node $manager verify-live
if ($LASTEXITCODE) { throw 'Imported state differs from the checkpoint. Stop phone testing and inspect logs.' }
Write-Host 'All four local emulators restored and verified. Use scripts/stop-local-emulators.ps1 for a verified save before shutdown.'
