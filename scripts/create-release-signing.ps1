$ErrorActionPreference='Stop'
$directory=Join-Path $env:LOCALAPPDATA 'BrewVerse/signing'
$metadataFile=Join-Path $directory 'release-signing.json'
if(Test-Path -LiteralPath $metadataFile){
 $existing=Get-Content -LiteralPath $metadataFile -Raw | ConvertFrom-Json
 if(!(Test-Path -LiteralPath $existing.storeFile) -or !(Test-Path -LiteralPath $existing.secretPath) -or (Get-Item -LiteralPath $existing.secretPath).Length -eq 0){throw 'Existing signing identity is incomplete. Inspect it; never silently generate a replacement for a client release.'}
 Write-Output 'Existing release identity retained.'
 return
}
New-Item -ItemType Directory -Path $directory -Force | Out-Null
if(Get-ChildItem -LiteralPath $directory -Filter '*.jks'){throw 'Unindexed keystore exists. Recover its metadata instead of replacing it.'}
$store=Join-Path $directory 'brewverse-release.jks'
$secretPath=Join-Path $directory 'release-password.dpapi'
$bytes=New-Object byte[] 48
$rng=[System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($bytes)
$plain=[Convert]::ToBase64String($bytes)
$secure=ConvertTo-SecureString -String $plain -AsPlainText -Force
try {
 $cipher=ConvertFrom-SecureString -SecureString $secure
 if([string]::IsNullOrWhiteSpace($cipher)){throw 'DPAPI encryption failed'}
 Set-Content -LiteralPath $secretPath -Value $cipher -NoNewline
 $env:BREWVERSE_KEYTOOL_SECRET=$plain
 & 'C:/Program Files/Android/Android Studio/jbr/bin/keytool.exe' -genkeypair -keystore $store -storetype JKS -alias brewverse-release -keyalg RSA -keysize 4096 -validity 10000 -dname 'CN=BrewVerse Android Release' -storepass:env BREWVERSE_KEYTOOL_SECRET -keypass:env BREWVERSE_KEYTOOL_SECRET
 if($LASTEXITCODE){throw 'Release identity creation failed; inspect retained files'}
 $roundtrip=$cipher | ConvertTo-SecureString
 $pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($roundtrip)
 try{if([Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) -cne $plain){throw 'Protected password validation failed'}}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer);$roundtrip.Dispose()}
 @{storeFile=$store;keyAlias='brewverse-release';secretPath=$secretPath;createdAt=(Get-Date).ToUniversalTime().ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath $metadataFile
 & icacls.exe $directory '/inheritance:r' '/grant:r' ($env:USERDOMAIN+'\'+$env:USERNAME+':(OI)(CI)F') '/grant:r' 'SYSTEM:(OI)(CI)F' | Out-Null
 if($LASTEXITCODE){throw 'Signing folder permission hardening failed'}
 Write-Output 'New private release identity created. Back it up securely before distribution.'
} finally {
 $env:BREWVERSE_KEYTOOL_SECRET=$null
 $plain=$null
 $secure.Dispose();$rng.Dispose();[Array]::Clear($bytes,0,$bytes.Length)
}
