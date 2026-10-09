$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath 'D:\Documents\ai-speaking-flutter-app'
Start-Transcript -Path 'D:\Documents\ai-speaking-flutter-app\output\apk\rebuild-1e528244-production.transcript.log' -Force
$expectedCommit = '1e528244b69b09ca663e79c09527baf69db9272d'
$currentCommit = (& git rev-parse HEAD).Trim()
if ($currentCommit -ne $expectedCommit) {
  throw "Expected commit $expectedCommit, got $currentCommit."
}
& git diff --quiet HEAD -- lib android pubspec.yaml pubspec.lock
if ($LASTEXITCODE -ne 0) {
  throw 'App source has changed since the requested commit.'
}
$defines = Get-Content -Raw -LiteralPath 'dart_defines.production.json' | ConvertFrom-Json
foreach ($name in @('PRIVACY_POLICY_URL', 'TERMS_URL', 'SUPPORT_URL')) {
  if (-not ([string]$defines.$name).StartsWith('https://')) {
    throw "Missing production legal URL: $name"
  }
}
Write-Output "BUILD_COMMIT=$currentCommit"
Write-Output 'BUILD_BACKEND=https://speaking-ai-nextjs-backend-production.up.railway.app'
& 'C:\Users\Windows\.cache\flutter-sdk\bin\flutter.bat' build apk --release --dart-define-from-file=dart_defines.production.json --dart-define=BACKEND_BASE_URL=https://speaking-ai-nextjs-backend-production.up.railway.app
$buildExit = $LASTEXITCODE
Write-Output "BUILD_EXIT_CODE=$buildExit"
Stop-Transcript
exit $buildExit
