param(
  [string]$ApiKeyPath = 'C:\Users\DELL\Documents\api_key_elevanlabs.txt',
  [string]$CatalogPath = '',
  [switch]$DryRun,
  [switch]$SkipLessonIntroStatePrompts,
  [string[]]$ForceKeys = @()
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($CatalogPath)) {
  $CatalogPath = Join-Path $PSScriptRoot 'fixed_audio_prompts.json'
}

$modelId = 'eleven_v3'
$outputFormat = 'mp3_44100_128'
$voiceByLanguage = @{ en = 'Nhs7eitvQWFTQBsf0yiT'; vi = '5CVDNcIPiOYgRUQuxXd7' }
$speedByLanguage = @{ en = 0.75; vi = 0.9 }
$manifestByPack = @{
  'assistant-core' = 'assets\data\assistant_core_audio.json'
  'listening-common' = 'assets\data\listening_common_audio.json'
  'vocabulary-common' = 'assets\data\vocabulary_common_audio.json'
}
$directoryByPack = @{
  'assistant-core' = 'assets\audio\assistant-core'
  'listening-common' = 'assets\audio\listening-common'
  'vocabulary-common' = 'assets\audio\vocabulary-common'
}
$cacheDirectory = Join-Path $repositoryRoot 'build\fixed-prompt-tts-cache'
$legacyListeningCacheDirectory = Join-Path $repositoryRoot 'build\listening-common-tts-cache'
$receiptPath = Join-Path $repositoryRoot 'deliverables\fixed_audio_generation_report.json'
$script:apiRequestCount = 0

function Normalize-Text([string]$Value) {
  return (($Value -replace '\s+', ' ').Trim())
}

function Get-Sha256Text([string]$Value) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

function Get-AudioInfo([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  $file = Get-Item -LiteralPath $Path
  if ($file.Length -lt 512) { return $null }
  $durationText = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $Path
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($durationText)) { return $null }
  $duration = 0.0
  if (-not [double]::TryParse(
      $durationText.Trim(),
      [Globalization.NumberStyles]::Float,
      [Globalization.CultureInfo]::InvariantCulture,
      [ref]$duration
    ) -or $duration -le 0) {
    return $null
  }
  return [ordered]@{
    duration = [math]::Round($duration, 3)
    checksum = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    size = $file.Length
  }
}

function Get-SynthesisHash([string]$Language, [string]$Text) {
  $voiceId = $voiceByLanguage[$Language]
  $speed = $speedByLanguage[$Language]
  $spec = "$modelId|$outputFormat|$Language|$voiceId|$speed|0.5|0.75|true|$(Normalize-Text $Text)"
  return Get-Sha256Text $spec
}

function Invoke-ElevenLabsSpeech(
  [string]$Language,
  [string]$Text,
  [string]$Destination,
  [hashtable]$Headers
) {
  $voiceId = $voiceByLanguage[$Language]
  $speed = $speedByLanguage[$Language]
  $body = @{
    text = (Normalize-Text $Text)
    model_id = $modelId
    language_code = $Language
    voice_settings = @{
      speed = $speed
      stability = 0.5
      similarity_boost = 0.75
      use_speaker_boost = $true
    }
  } | ConvertTo-Json -Depth 5
  $bodyBytes = [Text.Encoding]::UTF8.GetBytes($body)
  $uri = "https://api.elevenlabs.io/v1/text-to-speech/$voiceId" + "?output_format=$outputFormat"
  $temporaryPath = "$Destination.partial.$([guid]::NewGuid().ToString('N'))"
  try {
    for ($attempt = 1; $attempt -le 2; $attempt++) {
      try {
        Invoke-WebRequest -Uri $uri -Method Post -Headers $Headers -Body $bodyBytes -OutFile $temporaryPath
        $info = Get-AudioInfo $temporaryPath
        if ($null -eq $info) { throw 'ElevenLabs returned invalid MP3 data.' }
        Move-Item -LiteralPath $temporaryPath -Destination $Destination -Force
        $script:apiRequestCount += 1
        return
      } catch {
        if (Test-Path -LiteralPath $temporaryPath) {
          Remove-Item -LiteralPath $temporaryPath -Force
        }
        $status = $null
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
          $status = [int]$_.Exception.Response.StatusCode
        }
        if ($attempt -eq 2 -or ($status -ne 429 -and ($status -lt 500 -or $status -ge 600))) {
          throw
        }
        Start-Sleep -Seconds 2
      }
    }
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) {
      Remove-Item -LiteralPath $temporaryPath -Force
    }
  }
}

function Get-OrCreateSegment(
  [string]$Language,
  [string]$Text,
  [hashtable]$Headers
) {
  $hash = Get-SynthesisHash $Language $Text
  $path = Join-Path $cacheDirectory "$hash.mp3"
  if ($null -eq (Get-AudioInfo $path)) {
    $legacyHash = Get-Sha256Text "$Language|$(Normalize-Text $Text)"
    $legacyPath = Join-Path $legacyListeningCacheDirectory "$legacyHash.mp3"
    if ($null -ne (Get-AudioInfo $legacyPath)) {
      Copy-Item -LiteralPath $legacyPath -Destination $path -Force
    } else {
      Invoke-ElevenLabsSpeech $Language $Text $path $Headers
    }
  }
  return $path
}

function Get-LessonIntroStatePrompts {
  $items = [Collections.ArrayList]::new()
  $lessonCatalogPath = Join-Path $repositoryRoot 'assets\data\listening_lessons.json'
  $lessonCatalog = Get-Content -LiteralPath $lessonCatalogPath -Raw -Encoding utf8 | ConvertFrom-Json
  $maximumStarCount = 0
  $topicNumbers = @{}
  foreach ($group in $lessonCatalog.groups) {
    foreach ($topic in $group.topics) {
      $topicNumber = [int]$topic.number
      if (-not $topicNumbers.ContainsKey($topicNumber)) {
        $topicNumbers[$topicNumber] = $true
        [void]$items.Add([pscustomobject]@{
          pack = 'listening-common'
          key = "listening.topic.${topicNumber}.resume.vi"
          locale = 'vi-VN'
          language = 'vi'
          text = "Mình học tiếp Chủ đề $topicNumber nhé."
        })
      }
      foreach ($lesson in $topic.lessons) {
        $lessonId = ([string]$lesson.id).Trim()
        $lessonTitle = Normalize-Text ([string]$lesson.titleEn)
        if ([string]::IsNullOrWhiteSpace($lessonTitle)) {
          $lessonTitle = Normalize-Text ([string]$lesson.titleVi)
        }
        $sentenceCount = @($lesson.sentences).Count
        if ($sentenceCount -gt $maximumStarCount) { $maximumStarCount = $sentenceCount }

        [void]$items.Add([pscustomobject]@{
          pack = 'listening-common'
          key = "listening.lesson.${lessonId}.resume.vi"
          locale = 'vi-VN'
          language = 'vi'
          text = "Mình học tiếp bài $lessonTitle nhé."
          segments = @(
            [pscustomobject]@{ language = 'vi'; text = 'Mình học tiếp bài' }
            [pscustomobject]@{ language = 'en'; text = $lessonTitle }
            [pscustomobject]@{ language = 'vi'; text = 'nhé.' }
          )
        })
        [void]$items.Add([pscustomobject]@{
          pack = 'listening-common'
          key = "listening.lesson.${lessonId}.relearn.vi"
          locale = 'vi-VN'
          language = 'vi'
          text = "Mình học lại bài $lessonTitle nhé."
          segments = @(
            [pscustomobject]@{ language = 'vi'; text = 'Mình học lại bài' }
            [pscustomobject]@{ language = 'en'; text = $lessonTitle }
            [pscustomobject]@{ language = 'vi'; text = 'nhé.' }
          )
        })

        $songTitle = Normalize-Text ([string]$lesson.songTitle)
        if (-not [string]::IsNullOrWhiteSpace($songTitle)) {
          [void]$items.Add([pscustomobject]@{
            pack = 'listening-common'
            key = "listening.lesson.${lessonId}.song_resume.vi"
            locale = 'vi-VN'
            language = 'vi'
            text = "Mình nghe lại bài hát $songTitle nhé."
            segments = @(
              [pscustomobject]@{ language = 'vi'; text = 'Mình nghe lại bài hát' }
              [pscustomobject]@{ language = 'en'; text = $songTitle }
              [pscustomobject]@{ language = 'vi'; text = 'nhé.' }
            )
          })
        }
      }
    }
  }

  for ($remaining = 1; $remaining -le $maximumStarCount; $remaining++) {
    foreach ($variant in @(
        [pscustomobject]@{
          name = 'young'
          text = "Bài này bạn còn $remaining Ngôi sao chưa chinh phục. Mình cùng thử nhé!"
        },
        [pscustomobject]@{
          name = 'older'
          text = "Bài này bạn còn $remaining Ngôi sao chưa chinh phục."
        }
      )) {
      [void]$items.Add([pscustomobject]@{
        pack = 'listening-common'
        key = "listening.lesson.remaining_stars.${remaining}.$($variant.name).vi"
        locale = 'vi-VN'
        language = 'vi'
        text = $variant.text
      })
    }
  }
  return $items.ToArray()
}

function Write-JsonNoBom([string]$Path, [object]$Value) {
  $json = $Value | ConvertTo-Json -Depth 12
  $temporaryPath = "$Path.partial.$([guid]::NewGuid().ToString('N'))"
  $backupPath = "$Path.backup.$([guid]::NewGuid().ToString('N'))"
  try {
    [IO.File]::WriteAllText($temporaryPath, "$json`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::Replace($temporaryPath, $Path, $backupPath)
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) {
      Remove-Item -LiteralPath $temporaryPath -Force
    }
    if (Test-Path -LiteralPath $backupPath) {
      Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
    }
  }
}

if (-not (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
  throw 'ffprobe is required to validate generated audio.'
}
$catalog = Get-Content -LiteralPath $CatalogPath -Raw -Encoding utf8 | ConvertFrom-Json
if ($catalog.schemaVersion -ne 1 -or $catalog.modelId -ne $modelId -or $catalog.outputFormat -ne $outputFormat) {
  throw 'The fixed audio catalog has an unsupported synthesis contract.'
}
$prompts = @($catalog.prompts)
if (-not $SkipLessonIntroStatePrompts) {
  $prompts += @(Get-LessonIntroStatePrompts)
}
$duplicateKeys = $prompts | Group-Object { "$($_.key)|$($_.locale)" } | Where-Object Count -gt 1
if ($duplicateKeys) { throw 'The fixed audio catalog contains duplicate key/locale entries.' }

$manifests = @{}
$allExisting = [Collections.ArrayList]::new()
foreach ($pack in $manifestByPack.Keys) {
  $manifestPath = Join-Path $repositoryRoot $manifestByPack[$pack]
  $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
  if ($manifest.pack -ne $pack) { throw "Unexpected pack in $manifestPath." }
  $manifests[$pack] = $manifest
  foreach ($entry in @($manifest.prompts)) {
    [void]$allExisting.Add([pscustomobject]@{ pack = $pack; entry = $entry })
  }
}

$plan = [Collections.ArrayList]::new()
foreach ($prompt in $prompts) {
  if (-not $manifestByPack.ContainsKey([string]$prompt.pack)) {
    throw "Unsupported target pack: $($prompt.pack)"
  }
  $language = [string]$prompt.language
  if (-not $voiceByLanguage.ContainsKey($language)) { throw "Unsupported language: $language" }
  $normalizedText = Normalize-Text ([string]$prompt.text)
  if ([string]::IsNullOrWhiteSpace($normalizedText)) { throw "Empty prompt text: $($prompt.key)" }
  $textHash = Get-Sha256Text $normalizedText
  $manifest = $manifests[[string]$prompt.pack]
  $existing = @($manifest.prompts | Where-Object { $_.key -eq $prompt.key -and $_.locale -eq $prompt.locale })
  if ($existing.Count -gt 1) { throw "Duplicate manifest entry: $($prompt.key)" }
  $force = $ForceKeys -contains [string]$prompt.key
  $validExisting = $false
  if (-not $force -and $existing.Count -eq 1) {
    $entry = $existing[0]
    $assetFile = if ($entry.asset) { Join-Path $repositoryRoot ($entry.asset -replace '/', '\') } else { '' }
    $info = if ($assetFile) { Get-AudioInfo $assetFile } else { $null }
    $validExisting = $null -ne $info -and
      $entry.textHash -eq $textHash -and
      $entry.modelId -eq $modelId -and
      $entry.voiceId -eq $voiceByLanguage[$language] -and
      [double]$entry.speed -eq [double]$speedByLanguage[$language] -and
      $entry.sha256 -eq $info.checksum -and
      [int64]$entry.sizeBytes -eq [int64]$info.size
  }
  $reuse = $null
  if (-not $validExisting -and -not $force -and -not $prompt.segments) {
    $reuse = $allExisting | Where-Object {
      $candidateVoice = if ($_.entry.voiceId) {
        $_.entry.voiceId
      } elseif ($language -eq 'en') {
        $_.entry.englishVoiceId
      } else {
        $_.entry.vietnameseVoiceId
      }
      $candidateSpeed = if ($null -ne $_.entry.speed) {
        $_.entry.speed
      } elseif ($language -eq 'en') {
        $_.entry.englishSpeed
      } else {
        $_.entry.vietnameseSpeed
      }
      $_.entry.locale -eq $prompt.locale -and
      $_.entry.textHash -eq $textHash -and
      $_.entry.modelId -eq $modelId -and
      $candidateVoice -eq $voiceByLanguage[$language] -and
      [double]$candidateSpeed -eq [double]$speedByLanguage[$language] -and
      $_.entry.asset
    } | Select-Object -First 1
    if ($reuse) {
      $reusePath = Join-Path $repositoryRoot ($reuse.entry.asset -replace '/', '\')
      if ($null -eq (Get-AudioInfo $reusePath)) { $reuse = $null }
    }
  }
  [void]$plan.Add([pscustomobject]@{
    prompt = $prompt
    normalizedText = $normalizedText
    textHash = $textHash
    status = if ($validExisting) { 'valid' } elseif ($reuse) { 'reuse' } else { 'generate' }
    reuse = $reuse
  })
}

$vietnameseCharacterMeasure = $plan |
  Where-Object { $_.status -eq 'generate' -and $_.prompt.language -eq 'vi' } |
  ForEach-Object { $_.normalizedText.Length } |
  Measure-Object -Sum
$englishCharacterMeasure = $plan |
  Where-Object { $_.status -eq 'generate' -and $_.prompt.language -eq 'en' } |
  ForEach-Object { $_.normalizedText.Length } |
  Measure-Object -Sum
$vietnameseCharacterCount = if ($null -eq $vietnameseCharacterMeasure.Sum) { 0 } else { $vietnameseCharacterMeasure.Sum }
$englishCharacterCount = if ($null -eq $englishCharacterMeasure.Sum) { 0 } else { $englishCharacterMeasure.Sum }
$summary = [ordered]@{
  catalogPrompts = $plan.Count
  valid = @($plan | Where-Object status -eq 'valid').Count
  reused = @($plan | Where-Object status -eq 'reuse').Count
  generated = 0
  apiRequests = 0
  vietnameseCharacters = $vietnameseCharacterCount
  englishCharacters = $englishCharacterCount
  pendingSegmentApiRequests = 0
  pendingSegmentCharacters = 0
}
$pendingSegments = @{}
foreach ($item in @($plan | Where-Object status -eq 'generate')) {
  $segments = if ($item.prompt.segments) {
    @($item.prompt.segments)
  } else {
    @([pscustomobject]@{
      language = [string]$item.prompt.language
      text = $item.normalizedText
    })
  }
  foreach ($segment in $segments) {
    $language = [string]$segment.language
    $text = Normalize-Text ([string]$segment.text)
    $hash = Get-SynthesisHash $language $text
    if ($pendingSegments.ContainsKey($hash)) { continue }
    $currentPath = Join-Path $cacheDirectory "$hash.mp3"
    $legacyHash = Get-Sha256Text "$language|$text"
    $legacyPath = Join-Path $legacyListeningCacheDirectory "$legacyHash.mp3"
    if ($null -eq (Get-AudioInfo $currentPath) -and $null -eq (Get-AudioInfo $legacyPath)) {
      $pendingSegments[$hash] = [pscustomobject]@{ language = $language; text = $text }
    }
  }
}
$summary.pendingSegmentApiRequests = $pendingSegments.Count
$pendingCharacterMeasure = $pendingSegments.Values |
  ForEach-Object { $_.text.Length } |
  Measure-Object -Sum
$summary.pendingSegmentCharacters = if ($null -eq $pendingCharacterMeasure.Sum) { 0 } else { $pendingCharacterMeasure.Sum }
Write-Output "Fixed audio plan: $($summary.catalogPrompts) catalog prompts; $($summary.valid) valid; $($summary.reused) reusable; $(@($plan | Where-Object status -eq 'generate').Count) to generate."
Write-Output "New full-text characters: vi=$($summary.vietnameseCharacters), en=$($summary.englishCharacters)."
Write-Output "Uncached synthesis segments: $($summary.pendingSegmentApiRequests) requests, $($summary.pendingSegmentCharacters) characters."
if ($DryRun) { return }

$apiKey = (Get-Content -LiteralPath $ApiKeyPath -Raw -Encoding utf8).Trim()
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'The ElevenLabs API key file is empty.' }
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
  throw 'ffmpeg is required to compose bilingual prompts.'
}
$headers = @{
  'xi-api-key' = $apiKey
  Accept = 'audio/mpeg'
  'Content-Type' = 'application/json; charset=utf-8'
}
New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null

foreach ($item in $plan) {
  $prompt = $item.prompt
  $pack = [string]$prompt.pack
  $outputDirectory = Join-Path $repositoryRoot $directoryByPack[$pack]
  New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
  $fileName = (([string]$prompt.key) -replace '[^a-zA-Z0-9._-]', '_') + '.mp3'
  $absolutePath = Join-Path $outputDirectory $fileName
  $assetPath = ([string]$directoryByPack[$pack]).Replace('\', '/') + '/' + $fileName

  if ($item.status -eq 'reuse') {
    $reusePath = Join-Path $repositoryRoot ($item.reuse.entry.asset -replace '/', '\')
    if (-not [string]::Equals(
        [IO.Path]::GetFullPath($reusePath),
        [IO.Path]::GetFullPath($absolutePath),
        [StringComparison]::OrdinalIgnoreCase
      )) {
      Copy-Item -LiteralPath $reusePath -Destination $absolutePath -Force
    }
  } elseif ($item.status -eq 'generate') {
    if ($prompt.segments) {
      $segments = @()
      foreach ($segment in @($prompt.segments)) {
        $segments += Get-OrCreateSegment ([string]$segment.language) ([string]$segment.text) $headers
      }
      $concatPath = Join-Path $cacheDirectory "$($item.textHash).concat.txt"
      $concatLines = $segments | ForEach-Object { "file '$($_ -replace "'", "''")'" }
      [IO.File]::WriteAllLines($concatPath, $concatLines, [Text.UTF8Encoding]::new($false))
      $temporaryPath = "$absolutePath.partial.$([guid]::NewGuid().ToString('N')).mp3"
      & ffmpeg -v error -y -f concat -safe 0 -i $concatPath -ar 44100 -b:a 128k $temporaryPath
      if ($LASTEXITCODE -ne 0 -or $null -eq (Get-AudioInfo $temporaryPath)) {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
        throw "ffmpeg could not compose $($prompt.key)."
      }
      Move-Item -LiteralPath $temporaryPath -Destination $absolutePath -Force
    } else {
      $segmentPath = Get-OrCreateSegment ([string]$prompt.language) $item.normalizedText $headers
      Copy-Item -LiteralPath $segmentPath -Destination $absolutePath -Force
    }
    $summary.generated += 1
  }

  $info = Get-AudioInfo $absolutePath
  if ($null -eq $info) { throw "Invalid final audio: $absolutePath" }
  $entry = [ordered]@{
    key = [string]$prompt.key
    enabled = $true
    locale = [string]$prompt.locale
    text = $item.normalizedText
    asset = $assetPath
    durationSeconds = $info.duration
    sha256 = $info.checksum
    sizeBytes = $info.size
    textHash = $item.textHash
    voiceId = $voiceByLanguage[[string]$prompt.language]
    modelId = $modelId
    speed = $speedByLanguage[[string]$prompt.language]
  }
  if ($prompt.segments) { $entry.composition = 'vi-en-vi' }
  $manifest = $manifests[$pack]
  $next = [Collections.ArrayList]::new()
  $replaced = $false
  foreach ($candidate in @($manifest.prompts)) {
    if ($candidate.key -eq $prompt.key -and $candidate.locale -eq $prompt.locale) {
      [void]$next.Add([pscustomobject]$entry)
      $replaced = $true
    } else {
      [void]$next.Add($candidate)
    }
  }
  if (-not $replaced) { [void]$next.Add([pscustomobject]$entry) }
  $manifest.prompts = $next.ToArray()
}

$targetPacks = @($plan | ForEach-Object { [string]$_.prompt.pack } | Sort-Object -Unique)
foreach ($pack in $targetPacks) {
  $path = Join-Path $repositoryRoot $manifestByPack[$pack]
  Write-JsonNoBom $path $manifests[$pack]
}
$summary.apiRequests = $script:apiRequestCount
New-Item -ItemType Directory -Path (Split-Path -Parent $receiptPath) -Force | Out-Null
$receipt = [ordered]@{
  generatedAt = [DateTime]::UtcNow.ToString('o')
  modelId = $modelId
  outputFormat = $outputFormat
  voices = $voiceByLanguage
  speeds = $speedByLanguage
  summary = $summary
  generatedKeys = @($plan | Where-Object status -eq 'generate' | ForEach-Object { $_.prompt.key })
  reusedKeys = @($plan | Where-Object status -eq 'reuse' | ForEach-Object { $_.prompt.key })
}
Write-JsonNoBom $receiptPath $receipt
Write-Output "Completed fixed audio generation: $($summary.generated) generated, $($summary.reused) reused, $($summary.valid) already valid."
