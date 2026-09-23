param(
  [string]$ApiKeyPath = 'C:\Users\DELL\Documents\api_key_elevanlabs.txt'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $repositoryRoot 'assets\audio\assistant-core'
$manifestPath = Join-Path $repositoryRoot 'assets\data\assistant_core_audio.json'
$apiKey = (Get-Content -LiteralPath $ApiKeyPath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($apiKey)) {
  throw 'The ElevenLabs API key file is empty.'
}

$voiceByLanguage = @{
  en = 'Nhs7eitvQWFTQBsf0yiT'
  vi = '5CVDNcIPiOYgRUQuxXd7'
}
$speedByLanguage = @{
  en = 0.75
  vi = 0.9
}

$prompts = @(
  @{ key = 'assistant.main.open_menu.vi'; language = 'vi'; locale = 'vi-VN'; text = 'HOMI đây. Bạn muốn Dịch tiếng Anh, học Chủ đề hay Bộ từ vựng?' },
  @{ key = 'assistant.main.choose_translation.vi'; language = 'vi'; locale = 'vi-VN'; text = 'Bạn muốn Dịch tiếng Anh, học Chủ đề hay Bộ từ vựng?' },
  @{ key = 'assistant.main.choose_listening.vi'; language = 'vi'; locale = 'vi-VN'; text = 'Bạn chọn Chủ đề số mấy?' },
  @{ key = 'assistant.main.choose_vocabulary.vi'; language = 'vi'; locale = 'vi-VN'; text = 'Bạn muốn học phần Ba mẹ đã thêm, Ngôi sao hay Luyện lại?' },
  @{ key = 'assistant.main.invalid_choice.vi'; language = 'vi'; locale = 'vi-VN'; text = 'Bạn muốn Dịch tiếng Anh, học Chủ đề hay Bộ từ vựng?' },
  @{ key = 'assistant.main.no_speech.vi'; language = 'vi'; locale = 'vi-VN'; text = 'Bạn muốn Dịch tiếng Anh, học Chủ đề hay Bộ từ vựng?' },
  @{ key = 'assistant.main.cancelled.vi'; language = 'vi'; locale = 'vi-VN'; text = 'Mình tạm dừng nhé.' },
  @{ key = 'assistant.main.switched_to_listening.vi'; language = 'vi'; locale = 'vi-VN'; text = 'Mình đã chuyển sang Chủ đề.' },
  @{ key = 'assistant.main.switched_to_vocabulary.vi'; language = 'vi'; locale = 'vi-VN'; text = 'Mình đã chuyển sang Bộ từ vựng.' },
  @{ key = 'assistant.main.switched_to_translation.vi'; language = 'vi'; locale = 'vi-VN'; text = 'Mình đã chuyển sang Dịch tiếng Anh.' },
  @{ key = 'assistant.main.translation_acknowledged.vi'; language = 'vi'; locale = 'vi-VN'; text = 'Mình cùng dịch sang tiếng Anh nha.' },
  @{ key = 'assistant.main.translation_started.vi'; language = 'vi'; locale = 'vi-VN'; text = 'Bạn cứ nói từng câu. Muốn dừng thì nói “Dừng lại”.' },
  @{ key = 'assistant.main.translation_stopped.vi'; language = 'vi'; locale = 'vi-VN'; text = 'Đã dừng.' },
  @{ key = 'assistant.main.active_learning_controls.vi'; language = 'vi'; locale = 'vi-VN'; text = 'Bạn muốn nghe lại, câu trước hay câu sau?' },
  @{ key = 'assistant.main.keep_current_content.vi'; language = 'vi'; locale = 'vi-VN'; text = 'Mình giữ nội dung hiện tại nhé.' },
  @{ key = 'assistant.main.lesson_not_found.vi'; language = 'vi'; locale = 'vi-VN'; text = 'Chủ đề này chưa có bài học. Bạn thử lại sau nhé.' },
  @{ key = 'assistant.main.topic_not_found.vi'; language = 'vi'; locale = 'vi-VN'; text = 'HOMI chưa chọn được Chủ đề. Bạn thử lại nhé.' },
  @{ key = 'assistant.main.start_now.vi'; language = 'vi'; locale = 'vi-VN'; text = 'Bắt đầu nhé.' }
  @{ key = 'assistant.main.song_replay.vi'; language = 'vi'; locale = 'vi-VN'; text = 'Mình phát lại bài hát nhé.' }
)

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$headers = @{
  'xi-api-key' = $apiKey
  Accept = 'audio/mpeg'
  'Content-Type' = 'application/json'
}
$manifestPrompts = @()

foreach ($prompt in $prompts) {
  $voiceId = $voiceByLanguage[$prompt.language]
  $speed = $speedByLanguage[$prompt.language]
  $fileName = ($prompt.key -replace '[^a-zA-Z0-9._-]', '_') + '.mp3'
  $absolutePath = Join-Path $outputDirectory $fileName
  $assetPath = 'assets/audio/assistant-core/' + $fileName
  $body = @{
    text = $prompt.text
    model_id = 'eleven_v3'
    language_code = $prompt.language
    voice_settings = @{
      speed = $speed
      stability = 0.5
      similarity_boost = 0.75
      use_speaker_boost = $true
    }
  } | ConvertTo-Json -Depth 5
  $uri = "https://api.elevenlabs.io/v1/text-to-speech/$voiceId" + '?output_format=mp3_44100_128'
  Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -Body $body -OutFile $absolutePath

  $durationText = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $absolutePath
  $duration = [math]::Round([double]::Parse($durationText.Trim(), [Globalization.CultureInfo]::InvariantCulture), 3)
  $checksum = (Get-FileHash -LiteralPath $absolutePath -Algorithm SHA256).Hash.ToLowerInvariant()
  $manifestPrompts += [ordered]@{
    key = $prompt.key
    enabled = $true
    locale = $prompt.locale
    asset = $assetPath
    durationSeconds = $duration
    sha256 = $checksum
    voiceId = $voiceId
    modelId = 'eleven_v3'
    speed = $speed
  }
}

$manifest = [ordered]@{
  schemaVersion = 1
  pack = 'assistant-core'
  enabled = $true
  prompts = $manifestPrompts
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8
Write-Output "Generated $($manifestPrompts.Count) assistant-core prompts."
