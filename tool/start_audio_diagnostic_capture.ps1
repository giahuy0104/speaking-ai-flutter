[CmdletBinding()]
param(
  [string]$DeviceId = 'ORH6S4ZT85BMWGSK',
  [string]$AdbPath = 'C:\Users\Windows\AppData\Local\Android\sdk\platform-tools\adb.exe'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$captureDirectory = Join-Path $repositoryRoot ('output\audio-diagnostics-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $captureDirectory | Out-Null
& $AdbPath -s $DeviceId shell setprop log.tag.HomiDiag DEBUG
if ($LASTEXITCODE -ne 0) { throw 'Cannot enable native diagnostics on the selected phone.' }

# Keep capture alive after this task returns; do not clear existing device logs.
$capture = Start-Process -FilePath $AdbPath -WindowStyle Hidden -PassThru `
  -ArgumentList @('-s', $DeviceId, 'logcat', '-v', 'epoch', '-T', '1',
    'HomiDiag:V', 'flutter:I', 'HfpAudioBridge:V', 'AudioManager:I',
    'AudioService:I', 'SpeechRecognizer:V', 'AndroidRuntime:E', '*:S') `
  -RedirectStandardOutput (Join-Path $captureDirectory 'device.log') `
  -RedirectStandardError (Join-Path $captureDirectory 'capture.stderr.log')
Start-Sleep -Milliseconds 500
if ($capture.HasExited) { throw "Log capture exited. Inspect $captureDirectory" }
Write-Output "CAPTURE_PID=$($capture.Id)"
Write-Output "CAPTURE_DIRECTORY=$captureDirectory"
