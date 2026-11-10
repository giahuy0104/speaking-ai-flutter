[CmdletBinding()]
param(
  [string]$DeviceId = ''
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$definesFile = Join-Path $repositoryRoot 'dart_defines.production.json'
$apkFile = Join-Path $repositoryRoot 'build\app\outputs\flutter-apk\app-release.apk'
$signingPropertiesFile = Join-Path $repositoryRoot 'android\key.properties'
$expectedBackendUrl = 'https://api.hoamytech.com'

if (-not (Test-Path -LiteralPath $signingPropertiesFile)) {
  throw "Production signing requires $signingPropertiesFile."
}

$productionDefines = Get-Content -Raw -LiteralPath $definesFile | ConvertFrom-Json
if ($productionDefines.BACKEND_BASE_URL -ne $expectedBackendUrl) {
  throw "Production APK must use $expectedBackendUrl. Found: $($productionDefines.BACKEND_BASE_URL)"
}

$requiredLegalUrls = @(
  'PRIVACY_POLICY_URL',
  'TERMS_URL',
  'SUPPORT_URL'
)
foreach ($key in $requiredLegalUrls) {
  $rawValue = [string]$productionDefines.$key
  $parsedUri = $null
  if ([string]::IsNullOrWhiteSpace($rawValue) -or
      -not [Uri]::TryCreate($rawValue, [UriKind]::Absolute, [ref]$parsedUri) -or
      $parsedUri.Scheme -ne 'https' -or
      [string]::IsNullOrWhiteSpace($parsedUri.Host)) {
    throw "Production APK requires a valid HTTPS $key. Found: $rawValue"
  }
}

if ([string]::IsNullOrWhiteSpace([string]$productionDefines.AI_SUBPROCESSORS) -or
    [string]::IsNullOrWhiteSpace([string]$productionDefines.DATA_RETENTION_SUMMARY)) {
  throw 'Production APK requires AI_SUBPROCESSORS and DATA_RETENTION_SUMMARY disclosures.'
}

Push-Location $repositoryRoot
try {
  & flutter build apk --release --dart-define-from-file=$definesFile
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter production APK build failed with exit code $LASTEXITCODE."
  }

  if ($DeviceId.Trim().Length -gt 0) {
    $adbCommand = Get-Command adb -ErrorAction SilentlyContinue
    $adbExecutable = if ($adbCommand) {
      $adbCommand.Source
    } elseif ($env:ANDROID_SDK_ROOT) {
      Join-Path $env:ANDROID_SDK_ROOT 'platform-tools\adb.exe'
    } elseif ($env:ANDROID_HOME) {
      Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'
    } else {
      Join-Path $env:LOCALAPPDATA 'Android\sdk\platform-tools\adb.exe'
    }
    if (-not (Test-Path -LiteralPath $adbExecutable)) {
      throw "Android adb was not found: $adbExecutable"
    }
    & $adbExecutable -s $DeviceId install -r $apkFile
    if ($LASTEXITCODE -ne 0) {
      throw "Android APK update failed with exit code $LASTEXITCODE; the installed app was kept."
    }
  }
} finally {
  Pop-Location
}
