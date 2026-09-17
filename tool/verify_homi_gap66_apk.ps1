[CmdletBinding()]
param([string]$ApkPath = 'build/app/outputs/flutter-apk/app-release.apk')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$gapRoot = Split-Path -Parent $PSScriptRoot
$gapApk = (Resolve-Path (Join-Path $gapRoot $ApkPath)).Path
$gapZip = [System.IO.Compression.ZipFile]::OpenRead($gapApk)
try {
  $gapManifestEntry = $gapZip.GetEntry('assets/flutter_assets/assets/data/homi_gap66_audio.json')
  if ($null -eq $gapManifestEntry) { throw 'New audio manifest missing in APK.' }
  $gapReader = [System.IO.StreamReader]::new($gapManifestEntry.Open())
  try { $gapManifest = $gapReader.ReadToEnd() | ConvertFrom-Json } finally { $gapReader.Dispose() }
  if ($gapManifest.prompts.Count -ne 66) { throw 'APK does not contain 66 prompt entries.' }
  $gapChecked = 0
  foreach ($gapPrompt in $gapManifest.prompts) {
    if (-not $gapPrompt.enabled) { throw "Prompt disabled: $($gapPrompt.id)" }
    $gapEntry = $gapZip.GetEntry("assets/flutter_assets/$($gapPrompt.asset)")
    if ($null -eq $gapEntry) { throw "MP3 missing: $($gapPrompt.id)" }
    $gapStream = $gapEntry.Open()
    $gapHasher = [System.Security.Cryptography.SHA256]::Create()
    try { $gapDigest = [System.BitConverter]::ToString($gapHasher.ComputeHash($gapStream)).Replace('-', '').ToLowerInvariant() }
    finally { $gapHasher.Dispose(); $gapStream.Dispose() }
    if ($gapDigest -ne $gapPrompt.sha256) { throw "Checksum mismatch: $($gapPrompt.id)" }
    $gapChecked++
  }
  $gapUnexpected = @($gapZip.Entries | Where-Object {
    $_.FullName -match '(?i)(api_key_elevanlabs|deliverables/|GAP66/.*\.json$|production\.lock|\.source\.mp3$)'
  })
  if ($gapUnexpected.Count -gt 0) { throw 'Source/receipt/credential artifacts should not be in APK.' }
  [PSCustomObject]@{
    apk = $gapApk
    apkSha256 = (Get-FileHash -LiteralPath $gapApk -Algorithm SHA256).Hash.ToLowerInvariant()
    bundledAndChecksumVerified = $gapChecked
    unwantedStagingArtifacts = $gapUnexpected.Count
    modelId = $gapManifest.modelId
    vietnameseVoiceId = $gapManifest.profiles.vi.voiceId
    vietnameseSpeed = $gapManifest.profiles.vi.speed
    englishVoiceId = $gapManifest.profiles.en.voiceId
    englishSpeed = $gapManifest.profiles.en.speed
  } | ConvertTo-Json
} finally { $gapZip.Dispose() }
