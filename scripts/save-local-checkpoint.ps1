$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$listener = Get-NetTCPConnection -State Listen -LocalPort 4420 | Select-Object -First 1
$suite = Get-CimInstance Win32_Process -Filter "ProcessId = $($listener.OwningProcess)"
if (!$suite.CommandLine.Contains((Join-Path $projectRoot 'firebase.json')) -or !$suite.CommandLine.Contains('brewverse-security-tests')) {
  throw 'Refusing to checkpoint an unverified emulator suite.'
}
& node (Join-Path $PSScriptRoot 'local-checkpoint.cjs') save
if ($LASTEXITCODE) { throw 'Checkpoint failed. Previous checkpoint and every partial export were retained.' }
