param([switch]$VerifyOnly)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$credentialRoot = Join-Path $projectRoot '.firebase/local-credentials'
$indexPath = Join-Path $credentialRoot 'current-login.json'
if (!$VerifyOnly -and (Test-Path -LiteralPath $indexPath)) { throw 'Recovery credentials already exist. Refusing to replace an existing recovery.' }
$backup = (Get-Content -LiteralPath (Join-Path $projectRoot '.firebase/recovery/current-account-backup.txt') -Raw).Trim()
if (!(Test-Path -LiteralPath (Join-Path $backup 'business-records-before.json'))) { throw 'Verified pre-recovery backup missing.' }
$random = $null
$bytes = $null
$secure = $null
if ($VerifyOnly) {
  if (!(Test-Path -LiteralPath $indexPath)) { throw 'Recovery credentials are missing.' }
  $account = Get-Content -LiteralPath $indexPath -Raw | ConvertFrom-Json
  $secure = (Get-Content -LiteralPath $account.secretPath -Raw).Trim() | ConvertTo-SecureString
  $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
} else {
  New-Item -ItemType Directory -Force -Path $credentialRoot | Out-Null
  # Keep encrypted credentials private to this Windows account.
  $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
  $acl = New-Object Security.AccessControl.DirectorySecurity
  $acl.SetOwner($sid)
  $acl.SetAccessRuleProtection($true, $false)
  $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
  Set-Acl -LiteralPath $credentialRoot -AclObject $acl
  $secretPath = Join-Path $credentialRoot ((Get-Date -Format 'yyyyMMdd-HHmmss') + '.dpapi')
  $random = [Security.Cryptography.RandomNumberGenerator]::Create()
  $bytes = New-Object byte[] 18
  $random.GetBytes($bytes)
  $password = [Convert]::ToBase64String($bytes) + '!9aA'
  $secure = ConvertTo-SecureString -String $password -AsPlainText -Force
  $secure | ConvertFrom-SecureString | Set-Content -LiteralPath $secretPath
  $account = @{ uid = 'P3OvJpZGoBRKEpElF4keS512MvEG'; cafeId = 'SnEadZW3hynRmz4Gc0lC'; email = 'kannumehta3@gmail.com'; secretPath = $secretPath }
  $account | ConvertTo-Json | Set-Content -LiteralPath $indexPath
}
$payload = @{ uid = $account.uid; cafeId = $account.cafeId; email = $account.email; password = $password; backupPath = $backup; verifyOnly = [bool]$VerifyOnly } | ConvertTo-Json -Compress
$start = New-Object Diagnostics.ProcessStartInfo
$start.FileName = (Get-Command node -ErrorAction Stop).Source
$start.Arguments = '"' + (Join-Path $PSScriptRoot 'recover-local-test-account.cjs') + '"'
$start.WorkingDirectory = $projectRoot
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.RedirectStandardInput = $true
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$start.EnvironmentVariables['GCLOUD_PROJECT'] = 'brewverse-security-tests'
$start.EnvironmentVariables['FIREBASE_AUTH_EMULATOR_HOST'] = '127.0.0.1:9099'
$start.EnvironmentVariables['FIRESTORE_EMULATOR_HOST'] = '127.0.0.1:8085'
$start.EnvironmentVariables['FIREBASE_STORAGE_EMULATOR_HOST'] = '127.0.0.1:9199'
try {
  $worker = [Diagnostics.Process]::Start($start)
  $worker.StandardInput.WriteLine($payload)
  $worker.StandardInput.Close()
  $outTask = $worker.StandardOutput.ReadToEndAsync()
  $errTask = $worker.StandardError.ReadToEndAsync()
  if (!$worker.WaitForExit(150000)) { throw 'Recovery verification exceeded its deadline; do not rerun mutation. Inspect the local recovery state first.' }
  if ($worker.ExitCode) { throw ('Recovery stopped: ' + $errTask.Result) }
  $result = $outTask.Result | ConvertFrom-Json
  if (!$result.recovered -or !$result.loginVerified -or !$result.businessDataUnchanged -or !$result.storageVerified) { throw 'Recovery verification incomplete.' }
  Write-Output $outTask.Result
  Write-Output 'Password stored with Windows DPAPI. Use scripts/show-local-test-login.ps1 to view it securely; it was not printed.'
} finally {
  $password = $null
  $payload = $null
  if ($bytes) { [Array]::Clear($bytes, 0, $bytes.Length) }
  if ($random) { $random.Dispose() }
  if ($secure) { $secure.Dispose() }
}
