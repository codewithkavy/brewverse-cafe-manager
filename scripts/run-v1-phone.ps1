$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$adb = Join-Path $env:LOCALAPPDATA 'Android/sdk/platform-tools/adb.exe'
if (!(Test-Path -LiteralPath $adb)) { throw "Android platform-tools missing: $adb" }
& $adb get-state
if ($LASTEXITCODE) { throw 'Connect and authorize exactly one USB Android phone, then run this command again.' }

Push-Location $projectRoot
try {
    & flutter build apk --debug --dart-define=BREWVERSE_TENANT_MODE=true --dart-define=BREWVERSE_USE_FIREBASE_EMULATORS=true --dart-define=BREWVERSE_FIREBASE_EMULATOR_HOST=127.0.0.1
    if ($LASTEXITCODE) { throw 'Debug APK build failed. Installation was not attempted.' }
  $ready = $false
  try {
    $hub = Invoke-RestMethod -Uri 'http://127.0.0.1:4420/emulators' -TimeoutSec 3
    $ready = $hub.auth.port -eq 9099 -and $hub.firestore.port -eq 8085 -and
      $hub.functions.port -eq 5001 -and $hub.storage.port -eq 9199
  } catch { }
  if ($ready) {
    $listener = Get-NetTCPConnection -State Listen -LocalPort 4420 | Select-Object -First 1
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $($listener.OwningProcess)"
    if (!$process.CommandLine.Contains((Join-Path $projectRoot 'firebase.json')) -or
        !$process.CommandLine.Contains('brewverse-security-tests')) {
      throw 'Ports belong to an unverified emulator suite. Stop it in its terminal before retrying; no process was killed.'
    }
    Write-Host 'Reusing the canonical Desktop emulator suite.'
  } else {
    & (Join-Path $PSScriptRoot 'start-local-emulators.ps1') -CheckOnly
    $logRoot = Join-Path $projectRoot '.firebase/workflow-logs'
    New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $stdout = Join-Path $logRoot "$stamp.stdout.log"
    $stderr = Join-Path $logRoot "$stamp.stderr.log"
    $launcher = Join-Path $PSScriptRoot 'start-local-emulators.ps1'
    $worker = Start-Process powershell.exe -WindowStyle Hidden -PassThru -WorkingDirectory $projectRoot -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $launcher + '"')) -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    Write-Host "Starting local emulators. Logs: $stdout and $stderr"
    $deadline = (Get-Date).AddMinutes(3)
    do {
      if ($worker.HasExited -and $worker.ExitCode -ne 0) { throw "Emulator launcher failed. See $stdout and $stderr" }
      try {
        $hub = Invoke-RestMethod -Uri 'http://127.0.0.1:4420/emulators' -TimeoutSec 2
        $ready = $hub.auth.port -eq 9099 -and $hub.firestore.port -eq 8085 -and $hub.functions.port -eq 5001 -and $hub.storage.port -eq 9199
      } catch { }
      if (!$ready) { Start-Sleep -Seconds 2 }
    } while (!$ready -and (Get-Date) -lt $deadline)
    if (!$ready) { throw "Emulator startup timed out. See $stdout and $stderr. No processes were killed." }
  }
  # The hub can appear before callable source loading finishes. Probe an
  # unauthenticated request: 401 means the handler is ready, with no writes.
  $callableReady = $false
  $deadline = (Get-Date).AddMinutes(2)
  do {
    try {
      $null = Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:5001/brewverse-security-tests/us-central1/createCafe' -Method Post -ContentType 'application/json' -Body '{"data":{}}' -TimeoutSec 3
    } catch {
      if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 401) {
        $callableReady = $true
      }
    }
    if (!$callableReady) { Start-Sleep -Seconds 2 }
  } while (!$callableReady -and (Get-Date) -lt $deadline)
  if (!$callableReady) { throw 'createCafe did not become ready. Inspect the emulator startup logs before retrying.' }
  & (Join-Path $PSScriptRoot 'install-phone-debug.ps1')
} finally {
  Pop-Location
}
