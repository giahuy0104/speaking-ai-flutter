param(
  [string]$ApiKeyPath = 'C:\Users\DELL\Documents\api_key_elevanlabs.txt',
  [string]$OutputRoot = 'outputs\assistant-audio-refresh-20260925',
  [ValidateRange(1, 8)][int]$ThrottleLimit = 3
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$outputPath = if ([IO.Path]::IsPathRooted($OutputRoot)) { $OutputRoot } else { Join-Path $repositoryRoot $OutputRoot }
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$apiKey = (Get-Content -LiteralPath $ApiKeyPath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'The ElevenLabs API key file is empty.' }

$voiceId = '5CVDNcIPiOYgRUQuxXd7'
$speed = 0.9
$prompts = @(
  @{ key='assistant.conversation.connection_failed.vi'; text='Không kết nối được.' },
  @{ key='assistant.conversation.not_heard.vi'; text='Không nghe rõ.' },
  @{ key='assistant.conversation.repeat.vi'; text='Hãy nói lại.' },
  @{ key='assistant.feedback.v4.retry.vi'; text='Bạn thử lại nhé.' },
  @{ key='assistant.guide.your_turn.vi'; text='Đến lượt bạn.' },
  @{ key='assistant.learning.challenge_controls.vi'; text='Bạn muốn nghe lại hay dừng lại?' },
  @{ key='assistant.learning.continue_vocabulary.vi'; text='Mình tiếp tục bộ từ vựng nhé.' },
  @{ key='assistant.learning.restart_lesson.vi'; text='Mình học lại bài này từ đầu nhé.' },
  @{ key='assistant.learning.song_controls.vi'; text='Bạn muốn nghe lại, dừng lại hay bỏ qua?' },
  @{ key='assistant.level.choose_relearn.vi'; text='Bạn chọn level 1, 2, 3 nhé.' },
  @{ key='assistant.main.topic_not_found.vi'; text='HOMI chưa chọn được chủ đề. Bạn thử lại nhé.' },
  @{ key='assistant.main.translation_acknowledged.vi'; text='Mình cùng dịch sang tiếng Anh nha.' }
)

$prompts | ForEach-Object -Parallel {
  $prompt = $_
  $target = Join-Path $using:outputPath "$($prompt.key).mp3"
  $headers = @{ 'xi-api-key'=$using:apiKey; Accept='audio/mpeg'; 'Content-Type'='application/json' }
  $body = @{ text=$prompt.text; model_id='eleven_v3'; language_code='vi'; voice_settings=@{ speed=$using:speed; stability=0.5; similarity_boost=0.75; use_speaker_boost=$true } } | ConvertTo-Json -Depth 5
  for ($attempt=1; $attempt -le 5; $attempt++) {
    try {
      Invoke-WebRequest -Uri "https://api.elevenlabs.io/v1/text-to-speech/$($using:voiceId)?output_format=mp3_44100_128" -Method Post -Headers $headers -Body $body -OutFile $target
      if ((Get-Item -LiteralPath $target).Length -lt 512) { throw "Invalid audio for $($prompt.key)" }
      break
    } catch {
      if ($attempt -eq 5) { throw }
      Start-Sleep -Seconds ([math]::Pow(2,$attempt))
    }
  }
} -ThrottleLimit $ThrottleLimit

function HashText([string]$text) {
  $sha=[Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($text -replace '\s+',' ').Trim())))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
}

$entries = foreach ($prompt in $prompts) {
  $path = Join-Path $outputPath "$($prompt.key).mp3"
  $durationText = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $path
  if ($LASTEXITCODE -ne 0) { throw "ffprobe failed for $path" }
  [ordered]@{
    key=$prompt.key; enabled=$true; locale='vi-VN'; text=$prompt.text
    asset="$($prompt.key).mp3"
    durationSeconds=[math]::Round([double]::Parse($durationText.Trim(),[Globalization.CultureInfo]::InvariantCulture),3)
    sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    modelId='eleven_v3'; language='vi'; voiceId=$voiceId; speed=$speed
    sizeBytes=(Get-Item -LiteralPath $path).Length; textHash=(HashText $prompt.text)
  }
}
$manifest=[ordered]@{schemaVersion=1;pack='assistant-audio-refresh';enabled=$true;prompts=@($entries)}
$manifest|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $outputPath 'manifest.json') -Encoding utf8
Write-Output "Created $($entries.Count) requested assistant audio files in $outputPath."
