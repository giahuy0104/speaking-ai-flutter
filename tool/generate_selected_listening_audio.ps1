param(
  [string]$ApiKeyPath = 'C:\Users\DELL\Documents\api_key_elevanlabs.txt',
  [string]$OutputRoot = 'outputs\listening-selected-refresh-20260925',
  [string[]]$SelectedKeys,
  [ValidateRange(1, 8)][int]$ThrottleLimit = 3
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$output = if ([IO.Path]::IsPathRooted($OutputRoot)) { $OutputRoot } else { Join-Path $repo $OutputRoot }
New-Item -ItemType Directory -Path $output -Force | Out-Null
$apiKey = (Get-Content -LiteralPath $ApiKeyPath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'The ElevenLabs API key file is empty.' }

$selected = @(
  'C35-L1-T01-B03-T02|vi', 'C35-L1-T01-B03-T03|vi',
  'C35-L1-T01-B03-T04|vi', 'C35-L1-T01-B03-T06|en',
  'C35-L1-T01-B03-T06|vi', 'C67-L1-T03-B01-T01|vi',
  'C67-L1-T03-B01-T02|vi', 'C67-L1-T03-B01-T03|vi',
  'C67-L1-T03-B01-T05|vi', 'C67-L2-T04-B02-T03|vi',
  'C67-L2-T05-B01-T03|vi', 'C67-L2-T05-B01-T04|vi',
  'C67-L2-T06-B01-T04|vi', 'C67-L2-T06-B01-T05|vi',
  'C67-L2-T06-B02-T03|vi', 'C67-L3-T07-B01-T01|vi',
  'C67-L3-T07-B01-T02|vi', 'C67-L3-T08-B02-T02|vi',
  'C67-L3-T09-B01-T02|vi', 'C67-L3-T09-B01-T03|vi',
  'C67-L3-T09-B01-T05|vi', 'C67-L3-T10-B01-T05|vi',
  'C67-L3-T10-B02-T01|vi', 'C67-L3-T10-B02-T02|vi',
  'C67-L1-T02-B02-T10|vi'
)
if ($SelectedKeys.Count -gt 0) { $selected = @($SelectedKeys) }
$catalog = Get-Content -LiteralPath (Join-Path $repo 'assets\data\listening_lessons.json') -Raw | ConvertFrom-Json
$sentences = @($catalog.groups.topics.lessons.sentences)
$requests = foreach ($selection in $selected) {
  $parts = $selection.Split('|')
  $matches = @($sentences | Where-Object id -eq $parts[0])
  if ($matches.Count -ne 1) { throw "Expected one sentence for $selection; found $($matches.Count)." }
  $language = $parts[1]
  $text = if ($language -eq 'en') { $matches[0].english } else { $matches[0].vietnamese }
  $voiceId = if ($language -eq 'en') { 'Nhs7eitvQWFTQBsf0yiT' } else { '5CVDNcIPiOYgRUQuxXd7' }
  $speed = if ($language -eq 'en') { 0.75 } else { 0.9 }
  [pscustomobject]@{
    Key = "listening.sentence.$($parts[0]).$language"
    Text = [string]$text
    Language = $language
    Locale = if ($language -eq 'en') { 'en-US' } else { 'vi-VN' }
    VoiceId = $voiceId
    Speed = $speed
    Path = Join-Path $output "listening.sentence.$($parts[0]).$language.mp3"
  }
}

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
    language_code = $request.Language
    voice_settings = @{
      speed = $request.Speed
      stability = 0.5
      similarity_boost = 0.75
      use_speaker_boost = $true
    }
  } | ConvertTo-Json -Depth 5
  Invoke-WebRequest -Uri "https://api.elevenlabs.io/v1/text-to-speech/$($request.VoiceId)?output_format=mp3_44100_128" -Method Post -Headers $headers -Body $body -OutFile $request.Path
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
    key = $request.Key; enabled = $true; locale = $request.Locale
    text = $request.Text; asset = "$($request.Key).mp3"
    durationSeconds = [math]::Round([double]::Parse($durationText.Trim(), [Globalization.CultureInfo]::InvariantCulture), 3)
    sha256 = (Get-FileHash -LiteralPath $request.Path -Algorithm SHA256).Hash.ToLowerInvariant()
    modelId = 'eleven_v3'; language = $request.Language
    voiceId = $request.VoiceId; speed = $request.Speed
    sizeBytes = (Get-Item -LiteralPath $request.Path).Length
    textHash = TextHash $request.Text
  }
}
[ordered]@{ schemaVersion = 1; pack = 'listening-selected-refresh'; enabled = $true; prompts = @($entries) } |
  ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $output 'manifest.json') -Encoding utf8
Write-Output "Created $(@($requests).Count) selected listening audio files in $output."
