param(
  [string]$ApiKeyPath = 'C:\Users\DELL\Documents\api_key_elevanlabs.txt',
  [string]$OutputRoot = 'outputs\listening-c810-vi-refresh-20260925',
  [string]$SentenceId,
  [string[]]$SelectedIds,
  [ValidateRange(1, 8)][int]$ThrottleLimit = 3
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$output = if ([IO.Path]::IsPathRooted($OutputRoot)) { $OutputRoot } else { Join-Path $repo $OutputRoot }
New-Item -ItemType Directory -Path $output -Force | Out-Null
$apiKey = (Get-Content -LiteralPath $ApiKeyPath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'The ElevenLabs API key file is empty.' }

$ids = @(
  'C810-L2-T04-B03-T01', 'C810-L2-T04-B03-T03',
  'C810-L2-T05-B02-T03', 'C810-L2-T06-B02-T02',
  'C810-L2-T06-B02-T03', 'C810-L3-T07-B02-T04',
  'C810-L3-T07-B03-T01', 'C810-L3-T10-B02-T01',
  'C810-L3-T10-B02-T03', 'C810-L3-T10-B02-T04',
  'C810-L2-T05-B02-T04', 'C810-L3-T08-B02-T01'
)
if (![string]::IsNullOrWhiteSpace($SentenceId)) {
  if ($SentenceId -notin $ids) { throw "Sentence ID is not in this batch: $SentenceId" }
  $ids = @($SentenceId)
}
if ($SelectedIds.Count -gt 0) { $ids = @($SelectedIds) }
$catalog = Get-Content -LiteralPath (Join-Path $repo 'assets\data\listening_lessons.json') -Raw | ConvertFrom-Json
$sentences = @($catalog.groups.topics.lessons.sentences)
$requests = foreach ($id in $ids) {
  $matches = @($sentences | Where-Object id -eq $id)
  if ($matches.Count -ne 1) { throw "Expected one sentence for $id, found $($matches.Count)." }
  $key = "listening.sentence.$id.vi"
  [pscustomobject]@{
    Key = $key
    Text = [string]$matches[0].vietnamese
    Path = Join-Path $output "$key.mp3"
  }
}

$voiceId = '5CVDNcIPiOYgRUQuxXd7'
$speed = 0.9
$requests | ForEach-Object -Parallel {
  $request = $_
  $headers = @{
    'xi-api-key' = $using:apiKey
    Accept = 'audio/mpeg'
    'Content-Type' = 'application/json'
  }
  $body = @{
    text = $request.Text
    model_id = 'eleven_v3'
    language_code = 'vi'
    voice_settings = @{
      speed = $using:speed
      stability = 0.5
      similarity_boost = 0.75
      use_speaker_boost = $true
    }
  } | ConvertTo-Json -Depth 5
  Invoke-WebRequest -Uri "https://api.elevenlabs.io/v1/text-to-speech/$($using:voiceId)?output_format=mp3_44100_128" -Method Post -Headers $headers -Body $body -OutFile $request.Path
  if ((Get-Item -LiteralPath $request.Path).Length -lt 512) { throw "Empty or invalid audio: $($request.Key)" }
} -ThrottleLimit $ThrottleLimit

function TextHash([string]$value) {
  $hasher = [Security.Cryptography.SHA256]::Create()
  try {
    $normalized = ($value -replace '\s+', ' ').Trim()
    return ([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($normalized)))).Replace('-', '').ToLowerInvariant()
  } finally { $hasher.Dispose() }
}
$entries = foreach ($request in $requests) {
  $durationText = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $request.Path
  if ($LASTEXITCODE -ne 0) { throw "ffprobe failed: $($request.Key)" }
  [ordered]@{
    key = $request.Key; enabled = $true; locale = 'vi-VN'
    text = $request.Text; asset = "$($request.Key).mp3"
    durationSeconds = [math]::Round([double]::Parse($durationText.Trim(), [Globalization.CultureInfo]::InvariantCulture), 3)
    sha256 = (Get-FileHash -LiteralPath $request.Path -Algorithm SHA256).Hash.ToLowerInvariant()
    modelId = 'eleven_v3'; language = 'vi'; voiceId = $voiceId; speed = $speed
    sizeBytes = (Get-Item -LiteralPath $request.Path).Length
    textHash = TextHash $request.Text
  }
}
[ordered]@{ schemaVersion = 1; pack = 'listening-c810-vi-refresh'; enabled = $true; prompts = @($entries) } |
  ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $output 'manifest.json') -Encoding utf8
Write-Output "Created $(@($requests).Count) Vietnamese audio files in $output."
