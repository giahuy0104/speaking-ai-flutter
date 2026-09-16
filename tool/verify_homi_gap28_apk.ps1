param(
    [string]$ApkPath = 'build/app/outputs/flutter-apk/app-debug.apk',
    [Parameter(Mandatory = $true)][string]$ApiKeyFile
)
$ErrorActionPreference = 'Stop'
$auditRoot = Split-Path -Parent $PSScriptRoot
$resolvedApk = (Resolve-Path -LiteralPath (Join-Path $auditRoot $ApkPath)).Path
# Keep credentials in memory only; never print or persist their contents.
$keyContent = [IO.File]::ReadAllText($ApiKeyFile).Trim().TrimStart([char]0xFEFF)
$keyMatches = [regex]::Matches($keyContent, '\bsk_[a-zA-Z0-9_\-]+\b')
$secretToCheck = if ($keyMatches.Count -eq 1) { $keyMatches[0].Value } else { $keyContent }
if ([string]::IsNullOrWhiteSpace($secretToCheck) -or $secretToCheck -match '\s') {
    throw 'Invalid credential format for verification.'
}
$expectedAudio = @{}
foreach ($name in @('main_assistant_audio', 'curriculum_audio')) {
    $manifest = [IO.File]::ReadAllText((Join-Path $auditRoot "assets/data/$name.json")) | ConvertFrom-Json
    foreach ($prompt in $manifest.prompts) {
        $expectedAudio["assets/flutter_assets/$($prompt.asset)"] = $prompt
    }
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($resolvedApk)
$verifiedAudio = 0
$verifiedGaps = 0
$scannedFiles = 0
$credentialHits = [Collections.Generic.List[string]]::new()
$receiptFiles = [Collections.Generic.List[string]]::new()
$failures = [Collections.Generic.List[string]]::new()
try {
    foreach ($entry in $archive.Entries) {
        if ($entry.FullName.EndsWith('/')) { continue }
        $scannedFiles++
        if ($entry.FullName -match 'assets/audio/(MAIN|CURRICULUM)/.*\.mp3\.json$') {
            $receiptFiles.Add($entry.FullName)
        }
        $expected = $expectedAudio[$entry.FullName]
        $hasher = if ($null -ne $expected) { [Security.Cryptography.SHA256]::Create() } else { $null }
        $stream = $entry.Open()
        $buffer = [byte[]]::new(65536)
        $carry = ''
        $hit = $false
        try {
            while (($readCount = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                if ($null -ne $hasher) { $null = $hasher.TransformBlock($buffer, 0, $readCount, $buffer, 0) }
                if (-not $hit) {
                    $chunk = $carry + [Text.Encoding]::UTF8.GetString($buffer, 0, $readCount)
                    if ($chunk.Contains($secretToCheck)) { $hit = $true }
                    $keep = [Math]::Min($secretToCheck.Length - 1, $chunk.Length)
                    $carry = $chunk.Substring($chunk.Length - $keep)
                }
            }
            if ($hit) { $credentialHits.Add($entry.FullName) }
            if ($null -ne $hasher) {
                $null = $hasher.TransformFinalBlock([byte[]]::new(0), 0, 0)
                $digest = [Convert]::ToHexString($hasher.Hash).ToLowerInvariant()
                if ($digest -ne $expected.sha256) { $failures.Add($entry.FullName) }
                $verifiedAudio++
                if ($expected.id -like 'GAP28-*') { $verifiedGaps++ }
            }
        } finally {
            $stream.Dispose()
            if ($null -ne $hasher) { $hasher.Dispose() }
        }
    }
    # The new packaged manifest must also point to the enabled entries.
    $packedManifest = $archive.GetEntry('assets/flutter_assets/assets/data/main_assistant_audio.json')
    if ($null -eq $packedManifest) { throw 'MAIN manifest missing from APK.' }
    $reader = [IO.StreamReader]::new($packedManifest.Open())
    try { $packed = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
    $enabledGaps = @($packed.prompts | Where-Object { $_.id -like 'GAP28-*' -and $_.enabled }).Count
    $result = [ordered]@{
        apk = $resolvedApk
        apkBytes = (Get-Item -LiteralPath $resolvedApk).Length
        scannedFiles = $scannedFiles
        expectedAudio = $expectedAudio.Count
        verifiedAudio = $verifiedAudio
        verifiedGaps = $verifiedGaps
        enabledGapsInPackagedManifest = $enabledGaps
        hashFailures = @($failures.ToArray())
        credentialHits = @($credentialHits.ToArray())
        bundledGenerationReceipts = @($receiptFiles.ToArray())
    }
    $resultJson = $result | ConvertTo-Json -Depth 5
    # Generated audit output only, never a credential or application source.
    [IO.File]::WriteAllText((Join-Path $auditRoot 'deliverables/homi-gap28-apk-verification.json'), $resultJson)
    Write-Output $resultJson
    if ($verifiedAudio -ne $expectedAudio.Count -or $verifiedGaps -ne 28 -or $enabledGaps -ne 28 -or
        $failures.Count -gt 0 -or $credentialHits.Count -gt 0 -or $receiptFiles.Count -gt 0) {
        throw 'APK verification failed; see the sanitized audit output.'
    }
} finally {
    $archive.Dispose()
    $secretToCheck = $null
    $keyContent = $null
}
