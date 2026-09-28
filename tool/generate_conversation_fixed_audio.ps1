param(
  [string]$ApiKeyPath = 'C:\Users\DELL\Documents\api_key_elevanlabs.txt',
  [string[]]$ForceKeys = @()
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $repositoryRoot 'assets\audio\assistant-core'
$manifestPath = Join-Path $repositoryRoot 'assets\data\assistant_core_audio.json'
$apiKey = (Get-Content -LiteralPath $ApiKeyPath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'The ElevenLabs API key file is empty.' }

$voiceId = '5CVDNcIPiOYgRUQuxXd7'
$prompts = @(
  @{ key = 'assistant.conversation.not_heard.vi'; text = 'Không nghe rõ.' },
  @{ key = 'assistant.conversation.repeat.vi'; text = 'Hãy nói lại.' },
  @{ key = 'assistant.conversation.connection_failed.vi'; text = 'Không kết nối được.' },
  @{ key = 'assistant.conversation.stopped.vi'; text = 'Hội thoại đã dừng.' },
  @{ key = 'assistant.translation.stopped.vi'; text = 'Dịch đã dừng.' },
  @{ key = 'assistant.conversation.recovery_error.vi'; text = 'HOMI đang gặp lỗi. Bạn thử lại nhé.' }
)

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$headers = @{
  'xi-api-key' = $apiKey
  Accept = 'audio/mpeg'
  'Content-Type' = 'application/json'
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$entries = [Collections.ArrayList]@($manifest.prompts)
foreach ($prompt in $prompts) {
  $fileName = "$($prompt.key).mp3"
  $absolutePath = Join-Path $outputDirectory $fileName
  if ($ForceKeys -contains $prompt.key -or -not (Test-Path -LiteralPath $absolutePath) -or (Get-Item -LiteralPath $absolutePath).Length -eq 0) {
    $body = @{
      text = $prompt.text
      model_id = 'eleven_v3'
      language_code = 'vi'
      voice_settings = @{
        speed = 0.9
        stability = 0.5
        similarity_boost = 0.75
        use_speaker_boost = $true
      }
    } | ConvertTo-Json -Depth 5
    $uri = "https://api.elevenlabs.io/v1/text-to-speech/$voiceId" + '?output_format=mp3_44100_128'
    $temporary = "$absolutePath.part"
    for ($attempt = 1; $attempt -le 3; $attempt++) {
      try {
        Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -Body $body -OutFile $temporary
        Move-Item -LiteralPath $temporary -Destination $absolutePath -Force
        break
      } catch {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
        if ($attempt -eq 3) { throw }
        Start-Sleep -Seconds (2 * $attempt)
      }
    }
  }
  $durationText = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $absolutePath
  $entry = [ordered]@{
    key = $prompt.key
    enabled = $true
    locale = 'vi-VN'
    asset = "assets/audio/assistant-core/$fileName"
    durationSeconds = [math]::Round([double]::Parse($durationText.Trim(), [Globalization.CultureInfo]::InvariantCulture), 3)
    sha256 = (Get-FileHash -LiteralPath $absolutePath -Algorithm SHA256).Hash.ToLowerInvariant()
    sizeBytes = (Get-Item -LiteralPath $absolutePath).Length
    voiceId = $voiceId
    modelId = 'eleven_v3'
    speed = 0.9
  }
  $existingIndex = -1
  for ($index = 0; $index -lt $entries.Count; $index++) {
    if ($entries[$index].key -eq $prompt.key) { $existingIndex = $index; break }
  }
  if ($existingIndex -ge 0) { $entries[$existingIndex] = $entry } else { [void]$entries.Add($entry) }
}
$output = [ordered]@{
  schemaVersion = 1
  pack = 'assistant-core'
  version = 'v2'
  enabled = $true
  prompts = @($entries)
}
$output | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8
Write-Output "Upserted $($prompts.Count) conversation/translation prompts into assistant-core."
