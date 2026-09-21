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
