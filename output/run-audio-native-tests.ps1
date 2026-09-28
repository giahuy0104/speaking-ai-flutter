$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath 'D:\Documents\ai-speaking-flutter-app\android'
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
& .\gradlew.bat :app:testDebugUnitTest -x compileFlutterBuildDebug -x copyFlutterAssetsDebug '-Dorg.gradle.jvmargs=-Xmx1G -XX:MaxMetaspaceSize=768m -XX:ReservedCodeCacheSize=128m -XX:ActiveProcessorCount=2 -Dfile.encoding=UTF-8' --max-workers=1
$nativeTestExit = $LASTEXITCODE
Write-Output "NATIVE_TEST_EXIT=$nativeTestExit"
exit $nativeTestExit
