param([switch]$SecurityVerification)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$ports = @(14198,14185,14101,14199,14120,14121,14160,14129,14149)
if (Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -in $ports }) {
  throw 'Reliability fixture ports are occupied. No running emulator was stopped.'
}
$directory = Join-Path $root ('.firebase/reliability/tests-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $directory | Out-Null
$config = Get-Content firebase.test-emulators.json -Raw | ConvertFrom-Json
$config.firestore.rules = Join-Path $root 'security-tests/firestore.rules'
$config.firestore.indexes = Join-Path $root 'firestore.indexes.json'
$config.storage.rules = Join-Path $root 'security-tests/storage.rules'
$config.functions[0].source = '../../../functions'
foreach ($name in @('auth','firestore','functions','storage','hub','logging','eventarc','tasks')) { $config.emulators.$name.port += 1000 }
$config.emulators.firestore.websocketPort += 1000
$file = Join-Path $directory 'firebase.test-emulators.json'
$config | ConvertTo-Json -Depth 20 | Set-Content $file
$originalTemp = $env:TEMP
$originalTmp = $env:TMP
$runtimeTemp = Join-Path $directory 'runtime-temp'
New-Item -ItemType Directory -Path $runtimeTemp | Out-Null
try {
  # Storage uses os.tmpdir()/firebase/storage/blobs even when ports differ.
  # Isolate its files so fixture cleanup cannot remove another suite's photos.
  $env:TEMP = $runtimeTemp
  $env:TMP = $runtimeTemp
  # Explicitly no import or auto-export: these are disposable synthetic fixtures.
  # Expected permission-denied test logs use stderr. PowerShell 5 must not
  # promote those log lines into terminating NativeCommandError exceptions.
  $ErrorActionPreference = 'Continue'
  $testCommand = 'powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-local-backend.ps1 -Reliability -AdminDashboard'
  if ($SecurityVerification) { $testCommand += ' -SecurityVerification' }
  firebase emulators:exec --config $file --project brewverse-security-tests --only auth,firestore,functions,storage $testCommand 2>&1 | Tee-Object (Join-Path $directory 'tests.log')
  $result = $LASTEXITCODE
} finally {
  $env:TEMP = $originalTemp
  $env:TMP = $originalTmp
  $ErrorActionPreference = 'Stop'
  # Firebase CLI can leave its isolated Java worker behind on Windows.
  foreach ($listener in @(Get-NetTCPConnection -State Listen -LocalPort 14185 -ErrorAction SilentlyContinue)) {
    $orphan = Get-CimInstance Win32_Process -Filter "ProcessId = $($listener.OwningProcess)"
    if ($orphan.Name -eq 'java.exe' -and $orphan.CommandLine.Contains('cloud-firestore-emulator') -and $orphan.CommandLine.Contains('--port 14185')) {
      Stop-Process -Id $orphan.ProcessId
    } else { throw 'Unverified process on reliability Firestore port; no process was stopped.' }
  }
  # The child uses its own TEMP locator. Restore the phone hub's global locator
  # only when that verified primary hub is actually running.
  if (Get-NetTCPConnection -State Listen -LocalPort 4420 -ErrorAction SilentlyContinue) {
    $hub = Invoke-RestMethod http://127.0.0.1:4420/ -TimeoutSec 5
    $worker = Get-CimInstance Win32_Process -Filter "ProcessId = $($hub.pid)"
    $normalPhone = $worker.CommandLine.Contains((Join-Path $root 'firebase.json')) -and $worker.CommandLine.Contains('brewverse-security-tests')
    $recoveryPhone = $worker.CommandLine.Contains((Join-Path $root 'scripts/connect-existing-local-firestore.cjs'))
    if (!$normalPhone -and !$recoveryPhone) { throw 'Phone hub process verification failed.' }
    $hub | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $env:TEMP 'hub-brewverse-security-tests.json')
  }
}
Write-Host "Reliability results: $directory"
exit $result
