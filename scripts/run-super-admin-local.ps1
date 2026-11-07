$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$config = Join-Path $projectRoot 'firebase.test-emulators.json'
$stateRoot = Join-Path $projectRoot '.firebase/admin-development'
$pointer = Get-Content (Join-Path $stateRoot 'fixture-pointer.json') -Raw | ConvertFrom-Json
if ($pointer.project -ne 'brewverse-security-tests' -or $pointer.authPort -ne 13198) { throw 'Invalid isolated fixture pointer.' }
$demo = $pointer.directory
if (!(Test-Path (Join-Path $demo 'firebase-export-metadata.json'))) { throw 'Run the guarded admin fixture setup first. See super_admin_dashboard/README.md.' }
if (!(Test-Path (Join-Path $projectRoot 'super_admin_dashboard/build/web/index.html'))) { throw 'Build the Flutter dashboard first.' }
$ports = @(13198,13185,13101,13199,13120,13121,13160,13129,13149)
$occupied = @(Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -in $ports })
$emulatorPid = $null
if ($occupied.Count) {
  $hub = Invoke-RestMethod http://127.0.0.1:13120/ -TimeoutSec 3
  $process = Get-CimInstance Win32_Process -Filter "ProcessId = $($hub.pid)"
  if (!$process.CommandLine.Contains($config) -or !$process.CommandLine.Contains('brewverse-security-tests')) { throw 'Unverified process on admin fixture ports. No process was stopped.' }
  $emulatorPid = $hub.pid
} else {
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
  $firebaseCli = Join-Path (Split-Path (Get-Command firebase).Source -Parent) 'node_modules/firebase-tools/lib/bin/firebase.js'
  $arguments = @($firebaseCli,'emulators:start','--config',$config,'--project','brewverse-security-tests','--only','auth,firestore,functions,storage','--import',$demo)
  $quoted = $arguments | ForEach-Object { '"' + $_ + '"' }
  $runtimeTemp = Join-Path $stateRoot "$stamp.runtime-temp"
  New-Item -ItemType Directory -Path $runtimeTemp | Out-Null
  $originalTemp = $env:TEMP; $originalTmp = $env:TMP
  try {
    $env:TEMP = $runtimeTemp; $env:TMP = $runtimeTemp
    $worker = Start-Process (Get-Command node).Source -WindowStyle Hidden -PassThru -WorkingDirectory $projectRoot -ArgumentList $quoted -RedirectStandardOutput (Join-Path $stateRoot 'demo-emulators.stdout.log') -RedirectStandardError (Join-Path $stateRoot 'demo-emulators.stderr.log')
  } finally { $env:TEMP = $originalTemp; $env:TMP = $originalTmp }
  $emulatorPid = $worker.Id
}
if (!(Get-NetTCPConnection -State Listen -LocalPort 8767 -ErrorAction SilentlyContinue)) {
  $server = Join-Path $PSScriptRoot 'serve-admin-dashboard.cjs'
  $web = Start-Process (Get-Command node).Source -WindowStyle Hidden -PassThru -WorkingDirectory $projectRoot -ArgumentList ('"' + $server + '"') -RedirectStandardOutput (Join-Path $stateRoot 'web.stdout.log') -RedirectStandardError (Join-Path $stateRoot 'web.stderr.log')
  @{ emulatorPid = $emulatorPid; webPid = $web.Id; config = $config } | ConvertTo-Json | Set-Content (Join-Path $stateRoot 'runtime.json')
}
Write-Host 'Dashboard starts at http://127.0.0.1:8767. Emulators need a moment to load Functions.'
Write-Host "Random synthetic admin credentials: $($pointer.credentialPath)"
