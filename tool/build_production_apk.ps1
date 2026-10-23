[CmdletBinding()]
param(
  [string]$DeviceId = ''
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$definesFile = Join-Path $repositoryRoot 'dart_defines.production.json'
$apkFile = Join-Path $repositoryRoot 'build\app\outputs\flutter-apk\app-release.apk'
$expectedBackendUrl = 'https://speaking-ai-nextjs-backend-production.up.railway.app'

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
    & flutter install `
      -d $DeviceId `
      --use-application-binary $apkFile
    if ($LASTEXITCODE -ne 0) {
      throw "Flutter APK install failed with exit code $LASTEXITCODE."
    }
  }
} finally {
  Pop-Location
}
