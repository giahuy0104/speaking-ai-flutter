param(
  [string]$ApiKeyPath = 'C:\Users\DELL\Documents\api_key_elevanlabs.txt'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$commonOutput = Join-Path $repositoryRoot 'assets\audio\vocabulary-common'
$commonManifestPath = Join-Path $repositoryRoot 'assets\data\vocabulary_common_audio.json'
$builtInManifestPath = Join-Path $repositoryRoot 'assets\data\vocabulary_built_in_audio.json'
$apiKey = (Get-Content -LiteralPath $ApiKeyPath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($apiKey)) {
  throw 'The ElevenLabs API key file is empty.'
}

$voiceId = '5CVDNcIPiOYgRUQuxXd7'
$prompts = @(
  @{ key = 'vocabulary.guide.listen.vi'; text = 'Mình cùng nghe nhé.' },
  @{ key = 'vocabulary.guide.repeat.vi'; text = 'Mình cùng nói lại nhé.' },
  @{ key = 'vocabulary.guide.your_turn.vi'; text = 'Đến lượt bạn.' },
  @{ key = 'vocabulary.guide.correct.vi'; text = 'Chính xác rồi!' },
  @{ key = 'vocabulary.guide.try_again.vi'; text = 'Mình thử lại nhé.' },
  @{ key = 'vocabulary.guide.next.vi'; text = 'Tiếp theo nhé.' },
  @{ key = 'vocabulary.guide.completed.vi'; text = 'Hoàn thành rồi.' },
  @{ key = 'vocabulary.flow.menu.vi'; text = 'Bạn muốn học phần Ba mẹ đã thêm, Ngôi sao hay Luyện lại?' },
  @{ key = 'vocabulary.flow.today_intro.vi'; text = 'Đã có nội dung mới cho bạn. Bắt đầu học thôi!' },
  @{ key = 'vocabulary.flow.today_resume.vi'; text = 'Mình học tiếp Danh sách hôm nay nhé.' },
  @{ key = 'vocabulary.flow.today_completed.vi'; text = 'Bạn muốn học nội dung khác hay học lại?' },
  @{ key = 'vocabulary.flow.parent_listen.vi'; text = 'Mình cùng nghe nhé.' },
  @{ key = 'vocabulary.flow.parent_resume.vi'; text = 'Mình nghe tiếp nhé.' },
  @{ key = 'vocabulary.flow.parent_group_completed.vi'; text = 'Bạn muốn học nội dung khác hay học tiếp?' },
  @{ key = 'vocabulary.flow.parent_other_menu.vi'; text = 'Bạn muốn học Ngôi sao hay Luyện lại?' },
  @{ key = 'vocabulary.flow.parent_completed.vi'; text = 'Bạn đã nghe hết rồi. Bạn muốn học nội dung khác hay học lại?' },
  @{ key = 'vocabulary.flow.parent_empty.vi'; text = 'Chưa có nội dung ở phần này. Bạn muốn học Ngôi sao hay Luyện lại?' },
  @{ key = 'vocabulary.flow.star_listen.vi'; text = 'Mình cùng nghe Ngôi sao nhé.' },
  @{ key = 'vocabulary.flow.star_empty.vi'; text = 'Bạn chưa có Ngôi sao nào. Bạn muốn học phần Ba mẹ đã thêm hay Luyện lại?' },
  @{ key = 'vocabulary.flow.star_my_voice.vi'; text = 'Giọng của bạn đây.' },
  @{ key = 'vocabulary.flow.star_resume.vi'; text = 'Mình nghe tiếp nhé.' },
  @{ key = 'vocabulary.flow.star_group_completed.vi'; text = 'Bạn muốn học nội dung khác hay học tiếp?' },
  @{ key = 'vocabulary.flow.star_other_menu.vi'; text = 'Bạn muốn học phần Ba mẹ đã thêm hay Luyện lại?' },
  @{ key = 'vocabulary.flow.star_completed.vi'; text = 'Bạn đã nghe hết Ngôi sao rồi. Bạn muốn học nội dung khác hay học lại?' },
  @{ key = 'vocabulary.flow.review_listen.vi'; text = 'Mình cùng luyện lại nhé. Bắt đầu thôi!' },
  @{ key = 'vocabulary.flow.review_resume.vi'; text = 'Mình luyện tiếp nhé.' },
  @{ key = 'vocabulary.flow.review_group_completed.vi'; text = 'Bạn muốn học nội dung khác hay học tiếp?' },
  @{ key = 'vocabulary.flow.review_other_menu.vi'; text = 'Bạn muốn học phần Ba mẹ đã thêm hay Ngôi sao?' },
  @{ key = 'vocabulary.flow.review_completed.vi'; text = 'Mình đã luyện xong rồi. Bạn muốn học phần Ba mẹ đã thêm hay Ngôi sao?' },
  @{ key = 'vocabulary.flow.review_empty.vi'; text = 'Không có nội dung cần luyện lại. Bạn muốn học phần Ba mẹ đã thêm hay Ngôi sao?' }
)

function Get-TextHash([string]$text) {
  $hasher = [Security.Cryptography.SHA256]::Create()
  try {
    return ([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-', '').ToLowerInvariant()
  } finally {
    $hasher.Dispose()
  }
}

function Get-Duration([string]$path) {
  $durationText = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $path
  return [math]::Round([double]::Parse($durationText.Trim(), [Globalization.CultureInfo]::InvariantCulture), 3)
}

New-Item -ItemType Directory -Path $commonOutput -Force | Out-Null
$headers = @{
  'xi-api-key' = $apiKey
  Accept = 'audio/mpeg'
  'Content-Type' = 'application/json'
}
$audioByText = @{}
$manifestPrompts = @()
foreach ($prompt in $prompts) {
  $textHash = Get-TextHash $prompt.text
  $fileName = "$($textHash.Substring(0, 24)).vi.mp3"
  $absolutePath = Join-Path $commonOutput $fileName
  if (-not $audioByText.ContainsKey($textHash)) {
    if (-not (Test-Path -LiteralPath $absolutePath) -or (Get-Item -LiteralPath $absolutePath).Length -eq 0) {
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
      $temporaryPath = "$absolutePath.part"
      for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
          Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -Body $body -OutFile $temporaryPath
          Move-Item -LiteralPath $temporaryPath -Destination $absolutePath -Force
          break
        } catch {
          if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
          if ($attempt -eq 3) { throw }
          Start-Sleep -Seconds (2 * $attempt)
        }
      }
    }
    $file = Get-Item -LiteralPath $absolutePath
    $audioByText[$textHash] = @{
      asset = 'assets/audio/vocabulary-common/' + $fileName
      duration = Get-Duration $absolutePath
      checksum = (Get-FileHash -LiteralPath $absolutePath -Algorithm SHA256).Hash.ToLowerInvariant()
      size = $file.Length
    }
  }
  $audio = $audioByText[$textHash]
  $manifestPrompts += [ordered]@{
    key = $prompt.key
    enabled = $true
    locale = 'vi-VN'
    asset = $audio.asset
    durationSeconds = $audio.duration
    sha256 = $audio.checksum
    sizeBytes = $audio.size
    voiceId = $voiceId
    modelId = 'eleven_v3'
    speed = 0.9
  }
}

$commonManifest = [ordered]@{
  schemaVersion = 1
  pack = 'vocabulary-common'
  version = 'v1'
  enabled = $true
  prompts = $manifestPrompts
}
$commonManifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $commonManifestPath -Encoding utf8

$builtInPrompts = @()
$listeningManifests = Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'assets\data') -Filter 'listening_*_audio.json' |
  Where-Object { $_.Name -ne 'listening_common_audio.json' }
foreach ($manifestFile in $listeningManifests) {
  $manifest = Get-Content -LiteralPath $manifestFile.FullName -Raw | ConvertFrom-Json
  foreach ($entry in $manifest.prompts) {
    if ($entry.key -notmatch '^listening\.sentence\.(.+)\.(en|vi)$') { continue }
    $entryId = $Matches[1]
    $language = $Matches[2]
    $kind = if ($language -eq 'en') { 'word' } else { 'meaning' }
    $absoluteAsset = Join-Path $repositoryRoot ($entry.asset -replace '/', '\')
    if (-not (Test-Path -LiteralPath $absoluteAsset)) {
      throw "Missing built-in vocabulary audio: $($entry.asset)"
    }
    $builtInPrompts += [ordered]@{
      key = "vocabulary.entry.$entryId.$kind.$language"
      enabled = $true
      locale = $entry.locale
      asset = $entry.asset
      durationSeconds = $entry.durationSeconds
      sha256 = $entry.sha256
      sizeBytes = (Get-Item -LiteralPath $absoluteAsset).Length
      voiceId = $entry.voiceId
      modelId = $entry.modelId
      speed = $entry.speed
    }
  }
}
$builtInManifest = [ordered]@{
  schemaVersion = 1
  pack = 'vocabulary-built-in'
  version = 'v1'
  enabled = $true
  prompts = $builtInPrompts
}
$builtInManifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $builtInManifestPath -Encoding utf8

Write-Output "Generated $($manifestPrompts.Count) vocabulary-common entries from $($audioByText.Count) unique recordings."
Write-Output "Indexed $($builtInPrompts.Count) existing recordings in vocabulary-built-in."
