$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$adb = Join-Path $env:LOCALAPPDATA 'Android/sdk/platform-tools/adb.exe'
$apk = Join-Path $projectRoot 'build/app/outputs/flutter-apk/app-debug.apk'
if (!(Test-Path -LiteralPath $apk)) { throw 'Build the emulator debug APK first.' }
& $adb get-state
if ($LASTEXITCODE) { throw 'Connect and authorize exactly one Android phone over USB, then retry.' }
foreach ($port in 9099,8085,5001,9199) {
  if (!(Test-NetConnection -ComputerName '127.0.0.1' -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue)) {
    throw "Local emulator is not reachable on 127.0.0.1:$port. Start the complete canonical emulator suite first."
  }
  & $adb reverse "tcp:$port" "tcp:$port"
  if ($LASTEXITCODE) { throw "ADB reverse failed for port $port" }
}
$mappings = & $adb reverse --list
if ($LASTEXITCODE) { throw 'Could not verify ADB reverse mappings.' }
foreach ($port in 9099,8085,5001,9199) {
  if (!($mappings -match "\btcp:$port\s+tcp:$port\b")) {
    throw "Required ADB reverse mapping missing: tcp:$port."
  }
}
Write-Host 'Verified all four local emulator ports and ADB reverse mappings.'
& $adb install -r $apk
if ($LASTEXITCODE) { throw 'APK installation failed.' }
Write-Host 'Installed without clearing app data. BrewVerse was not opened. Sign in with your existing local test account when ready.'
