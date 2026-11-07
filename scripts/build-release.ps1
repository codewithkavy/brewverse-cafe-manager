param([switch]$SkipValidation)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$versionLine=Select-String -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Pattern '^version:\s*(.+)$'
$version=$versionLine.Matches[0].Groups[1].Value.Trim()
$versionParts=$version.Split('+')
if($versionParts.Count -ne 2){throw 'Release version must include a build number'}
$buildNumber=[int]$versionParts[1]
$previousManifest=Join-Path $projectRoot 'dist/release-manifest.json'
if(Test-Path -LiteralPath $previousManifest){
 $prior=Get-Content -LiteralPath $previousManifest -Raw | ConvertFrom-Json
 if($prior.buildNumber -and $buildNumber -le $prior.buildNumber){throw 'Increase pubspec.yaml version/build number before another release.'}
}
$metadataPath=Join-Path $env:LOCALAPPDATA 'BrewVerse/signing/release-signing.json'
if(!(Test-Path -LiteralPath $metadataPath)){throw 'Create or locate the approved release identity first; debug signing is not permitted.'}
$metadata=Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
if(!(Test-Path -LiteralPath $metadata.storeFile)){throw 'Release keystore missing. Never generate a replacement for an existing signed client release.'}
$secure=(Get-Content -LiteralPath $metadata.secretPath -Raw).Trim() | ConvertTo-SecureString
$pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
$names=@('BREWVERSE_RELEASE_STORE_FILE','BREWVERSE_RELEASE_KEY_ALIAS','BREWVERSE_RELEASE_STORE_PASSWORD','BREWVERSE_RELEASE_KEY_PASSWORD')
$previous=@{}
foreach($name in $names){$previous[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
Push-Location $projectRoot
try {
 $env:BREWVERSE_RELEASE_STORE_FILE=$metadata.storeFile
 $env:BREWVERSE_RELEASE_KEY_ALIAS=$metadata.keyAlias
 $env:BREWVERSE_RELEASE_STORE_PASSWORD=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
 $env:BREWVERSE_RELEASE_KEY_PASSWORD=$env:BREWVERSE_RELEASE_STORE_PASSWORD
 if(!$SkipValidation){
  & flutter clean; if($LASTEXITCODE){throw 'Flutter clean failed'}
  & flutter pub get; if($LASTEXITCODE){throw 'Dependency resolution failed'}
  & flutter analyze; if($LASTEXITCODE){throw 'Analysis failed'}
  & flutter test; if($LASTEXITCODE){throw 'Tests failed'}
 }
 & flutter build apk --release; if($LASTEXITCODE){throw 'Release APK build failed'}
 $apk=Join-Path $projectRoot 'build/app/outputs/flutter-apk/app-release.apk'
 $sdk=Join-Path $env:LOCALAPPDATA 'Android/sdk'
 $apksigner=Join-Path $sdk 'build-tools/36.0.0/apksigner.bat'
 & $apksigner verify --verbose --print-certs $apk
 if($LASTEXITCODE){throw 'APK signature verification failed'}
 $dist=Join-Path $projectRoot 'dist'
 New-Item -ItemType Directory -Force -Path $dist | Out-Null
 $target=Join-Path $dist 'BrewVerse-Cafe-Manager.apk'
 if(Test-Path -LiteralPath $target){
  $archive=Join-Path $dist ('archive/'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
  New-Item -ItemType Directory -Path $archive -Force | Out-Null
  Copy-Item -LiteralPath $target -Destination (Join-Path $archive 'BrewVerse-Cafe-Manager.apk')
 }
 Copy-Item -LiteralPath $apk -Destination $target
 $hash=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
 Set-Content -LiteralPath (Join-Path $dist 'BrewVerse-Cafe-Manager.apk.sha256') -Value ($hash+'  BrewVerse-Cafe-Manager.apk')
 @{version=$version;buildNumber=$buildNumber;path=$target;sha256=$hash;bytes=(Get-Item -LiteralPath $target).Length;builtAt=(Get-Date).ToUniversalTime().ToString('o');productionProject='brewverse-593dc';distributionApproved=$false;note='Signed release candidate. Cloud deployment, release SHA registration and real-device production checks require separate approval/verification.'} | ConvertTo-Json | Set-Content (Join-Path $dist 'release-manifest.json')
 Write-Output "Verified signed release candidate: $target"
 Write-Output "SHA-256: $hash"
} finally {
 foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$previous[$name],'Process')}
 [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
 $secure.Dispose()
 Pop-Location
}
