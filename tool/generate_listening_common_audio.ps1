param(
  [string]$ApiKeyPath = 'C:\Users\DELL\Documents\api_key_elevanlabs.txt'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$catalogPath = Join-Path $repositoryRoot 'assets\data\listening_lessons.json'
$outputDirectory = Join-Path $repositoryRoot 'assets\audio\listening-common'
$manifestPath = Join-Path $repositoryRoot 'assets\data\listening_common_audio.json'
$cacheDirectory = Join-Path $repositoryRoot 'build\listening-common-tts-cache'
$apiKey = (Get-Content -LiteralPath $ApiKeyPath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($apiKey)) {
  throw 'The ElevenLabs API key file is empty.'
}

$voiceByLanguage = @{ en = 'Nhs7eitvQWFTQBsf0yiT'; vi = '5CVDNcIPiOYgRUQuxXd7' }
$speedByLanguage = @{ en = 0.75; vi = 0.9 }
$headers = @{
  'xi-api-key' = $apiKey
  Accept = 'audio/mpeg'
  'Content-Type' = 'application/json'
}

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null

function Get-TextHash([string]$value) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [Text.Encoding]::UTF8.GetBytes($value)
    return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

function Get-OrCreateSpeech([string]$language, [string]$text) {
  $normalized = ($text -replace '\s+', ' ').Trim()
  $cacheKey = Get-TextHash "$language|$normalized"
  $cachePath = Join-Path $cacheDirectory "$cacheKey.mp3"
  if (Test-Path -LiteralPath $cachePath) {
    return $cachePath
  }
  $voiceId = $voiceByLanguage[$language]
  $speed = $speedByLanguage[$language]
  $body = @{
    text = $normalized
    model_id = 'eleven_v3'
    language_code = $language
    voice_settings = @{
      speed = $speed
      stability = 0.5
      similarity_boost = 0.75
      use_speaker_boost = $true
    }
  } | ConvertTo-Json -Depth 5
  $uri = "https://api.elevenlabs.io/v1/text-to-speech/$voiceId" + '?output_format=mp3_44100_128'
  Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -Body $body -OutFile $cachePath
  return $cachePath
}

function Add-ManifestEntry(
  [Collections.ArrayList]$entries,
  [string]$key,
  [string]$assetPath,
  [string]$absolutePath,
  [string]$composition
) {
  $durationText = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $absolutePath
  $duration = [math]::Round([double]::Parse($durationText.Trim(), [Globalization.CultureInfo]::InvariantCulture), 3)
  $checksum = (Get-FileHash -LiteralPath $absolutePath -Algorithm SHA256).Hash.ToLowerInvariant()
  [void]$entries.Add([ordered]@{
    key = $key
    enabled = $true
    locale = 'vi-VN'
    asset = $assetPath
    durationSeconds = $duration
    sha256 = $checksum
    modelId = 'eleven_v3'
    composition = $composition
    vietnameseVoiceId = $voiceByLanguage.vi
    vietnameseSpeed = $speedByLanguage.vi
    englishVoiceId = $voiceByLanguage.en
    englishSpeed = $speedByLanguage.en
  })
}

$commonPrompts = @(
  @{ key = 'listening.navigation.choose_topic.vi'; text = 'Bạn muốn học Chủ đề số mấy?' },
  @{ key = 'listening.navigation.choose_level.vi'; text = 'Bạn đã hoàn thành khóa học rồi. Bạn muốn học lại Level số mấy?' },
  @{ key = 'listening.navigation.choose_lesson.vi'; text = 'Bạn muốn học Bài số mấy?' },
  @{ key = 'listening.navigation.replay_topic.vi'; text = 'Bạn muốn học chủ đề khác hay học lại?' },
  @{ key = 'listening.navigation.replay_lesson.vi'; text = 'Bạn muốn học lại Bài này hay học Bài tiếp theo?' },
  @{ key = 'listening.navigation.no_topic.vi'; text = 'Chưa có Chủ đề phù hợp. Bạn thử lại nhé.' },
  @{ key = 'listening.navigation.no_lesson.vi'; text = 'Chưa có Bài học phù hợp. Bạn thử lại nhé.' },
  @{ key = 'listening.guide.start.vi'; text = 'Nói theo mình nhé.' },
  @{ key = 'listening.guide.continue.vi'; text = 'Mình cùng học câu khác nhé!' },
  @{ key = 'listening.guide.repeat.vi'; text = 'Bạn nói lại nhé.' },
  @{ key = 'listening.guide.your_turn.vi'; text = 'Bây giờ đến lượt bạn. Bạn nói lại nhé.' },
  @{ key = 'listening.guide.try_again.vi'; text = 'Bạn thử nói nhé.' },
  @{ key = 'listening.guide.completed.vi'; text = 'Bạn đã học xong chủ đề này rồi. Bạn chọn tiếp chủ đề mới nhé.' },
  @{ key = 'listening.feedback.correct.vi'; text = 'Đúng rồi!' },
  @{ key = 'listening.feedback.incorrect.vi'; text = 'Chưa đúng. Mình nghe câu đúng nhé.' },
  @{ key = 'listening.feedback.try_again.vi'; text = 'Bạn thử lại nhé.' },
  @{ key = 'listening.feedback.completed.vi'; text = 'Bạn đã hoàn thành phần thử thách rồi.' }
)

$manifestEntries = [Collections.ArrayList]::new()
foreach ($prompt in $commonPrompts) {
  $fileName = $prompt.key + '.mp3'
  $absolutePath = Join-Path $outputDirectory $fileName
  Copy-Item -LiteralPath (Get-OrCreateSpeech 'vi' $prompt.text) -Destination $absolutePath -Force
  Add-ManifestEntry $manifestEntries $prompt.key "assets/audio/listening-common/$fileName" $absolutePath 'vi'
}

$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
$lessonCount = 0
foreach ($group in $catalog.groups) {
  foreach ($topic in $group.topics) {
    foreach ($lesson in $topic.lessons) {
      $lessonCount++
      $key = "listening.lesson.$($lesson.id).intro.vi"
      $fileName = $key + '.mp3'
      $absolutePath = Join-Path $outputDirectory $fileName
      $englishTitle = ([string]$lesson.titleEn).Trim()
      $entryText = ([string]$lesson.entry.text).Trim()
      $beforeTitle = if ([int]$lesson.number -eq 1) {
        "Chủ đề $($topic.number). Bài đầu tiên là"
      } else {
        'Bài này là'
      }
      $afterTitle = (($entryText + ' Bắt đầu nhé.') -replace '\s+', ' ').Trim()
      $segments = @(
        Get-OrCreateSpeech 'vi' $beforeTitle
        Get-OrCreateSpeech 'en' $englishTitle
        Get-OrCreateSpeech 'vi' $afterTitle
      )
      $listPath = Join-Path $cacheDirectory ((Get-TextHash $key) + '.concat.txt')
      $listLines = $segments | ForEach-Object { "file '$($_ -replace "'", "''")'" }
      Set-Content -LiteralPath $listPath -Value $listLines -Encoding utf8
      & ffmpeg -v error -y -f concat -safe 0 -i $listPath -ar 44100 -b:a 128k $absolutePath
      if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg could not compose intro audio for $($lesson.id)."
      }
      Add-ManifestEntry $manifestEntries $key "assets/audio/listening-common/$fileName" $absolutePath 'vi-en-vi'
      Write-Output "[$lessonCount] $key"
    }
  }
}

$manifest = [ordered]@{
  schemaVersion = 1
  pack = 'listening-common'
  enabled = $true
  prompts = $manifestEntries
}
$manifest | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $manifestPath -Encoding utf8
Write-Output "Generated $($commonPrompts.Count) common prompts and $lessonCount lesson intros."
