$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
# The in-process Kotlin compiler exceeds this checkout's 384 MB metaspace cap.
# Override for this build only; do not change the project's Gradle defaults.
$env:GRADLE_OPTS = '-Dorg.gradle.jvmargs="-Xmx2G -XX:MaxMetaspaceSize=1G -XX:ReservedCodeCacheSize=128m -XX:ActiveProcessorCount=2 -Dfile.encoding=UTF-8"'
& flutter build apk --release --target-platform android-arm64 --dart-define-from-file=dart_defines.production.json --dart-define=BACKEND_BASE_URL=https://speaking-ai-nextjs-backend-production.up.railway.app --dart-define=HOMI_AUDIO_DIAGNOSTICS=true
$buildExit = $LASTEXITCODE
Write-Output "DIAGNOSTIC_BUILD_EXIT=$buildExit"
exit $buildExit
