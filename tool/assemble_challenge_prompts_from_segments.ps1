param(
  [string]$ApiKeyPath = 'C:\Users\DELL\Documents\api_key_elevanlabs.txt',
  [ValidateSet('6-7')]
  [string]$AgeGroup = '6-7',
  [string]$VietnameseRoot = 'outputs\challenge-vi-c67-20260926-r1',
  [string]$VietnameseMp3Directory = '',
  [string]$OutputRoot = 'outputs\challenge-prompts-c67-20260926-r1',
  [string]$ConnectorAudioPath = 'C:\Users\DELL\Downloads\0926.mp4',
  [ValidateRange(1, 8)]
  [int]$ThrottleLimit = 3,
  [ValidateRange(1, 8)]
  [int]$RetryCount = 5,
  [switch]$PlanOnly
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$catalogPath = Join-Path $repositoryRoot 'assets\data\listening_lessons.json'
$cacheDirectory = Join-Path $repositoryRoot 'build\mixed-challenge-preview-cache'
$vietnameseRootPath = if ([IO.Path]::IsPathRooted($VietnameseRoot)) {
  [IO.Path]::GetFullPath($VietnameseRoot)
} else {
  [IO.Path]::GetFullPath((Join-Path $repositoryRoot $VietnameseRoot))
}
$vietnameseMp3DirectoryPath = if ([string]::IsNullOrWhiteSpace($VietnameseMp3Directory)) {
  $null
} elseif ([IO.Path]::IsPathRooted($VietnameseMp3Directory)) {
  [IO.Path]::GetFullPath($VietnameseMp3Directory)
} else {
  [IO.Path]::GetFullPath((Join-Path $repositoryRoot $VietnameseMp3Directory))
}
$outputRootPath = if ([IO.Path]::IsPathRooted($OutputRoot)) {
  [IO.Path]::GetFullPath($OutputRoot)
} else {
  [IO.Path]::GetFullPath((Join-Path $repositoryRoot $OutputRoot))
}
$connectorPath = [IO.Path]::GetFullPath($ConnectorAudioPath)
$outputAudioDirectory = Join-Path $outputRootPath 'challenge-6-7'
$englishRawDirectory = Join-Path $outputRootPath '.segments\en-raw-mp3'
$englishWavDirectory = Join-Path $outputRootPath '.segments\en-wav'
$englishReviewDirectory = Join-Path $outputRootPath '.segments\en-review-mp3'
$preparedVietnameseDirectory = Join-Path $outputRootPath '.segments\vi-from-review-mp3-wav'
$connectorWavPath = Join-Path $outputRootPath '.segments\provided-hay-0926.wav'
$viManifestPath = Join-Path $vietnameseRootPath 'challenge_6_7_vi_segments.json'

$modelId = 'eleven_v3'
$viVoiceId = '5CVDNcIPiOYgRUQuxXd7'
$viSpeed = 0.9
$enVoiceId = 'Nhs7eitvQWFTQBsf0yiT'
$enSpeed = 0.75

function Get-NormalizedText([string]$text) {
  return ($text -replace '\s+', ' ').Trim()
}

function Get-TextHash([string]$text) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    return ([BitConverter]::ToString(
      $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))
    )).Replace('-', '').ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

function Get-Duration([string]$path) {
  $value = & ffprobe -v error -show_entries format=duration `
    -of default=noprint_wrappers=1:nokey=1 $path
  if ($LASTEXITCODE -ne 0) {
    throw "ffprobe could not read $path."
  }
  return [double]::Parse(
    $value.Trim(),
    [Globalization.CultureInfo]::InvariantCulture
  )
}

function Get-SilenceIntervals([string]$path, [double]$duration) {
  $lines = & ffmpeg -hide_banner -i $path `
    -af 'silencedetect=noise=-45dB:d=0.08' -f null NUL 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "silencedetect could not read $path."
  }
  $intervals = [Collections.ArrayList]::new()
  $currentStart = $null
  foreach ($line in $lines) {
    $text = [string]$line
    if ($text -match 'silence_start:\s*([0-9.]+)') {
      $currentStart = [double]::Parse(
        $Matches[1],
        [Globalization.CultureInfo]::InvariantCulture
      )
    }
    if ($text -match 'silence_end:\s*([0-9.]+)\s*\|\s*silence_duration:\s*([0-9.]+)') {
      $end = [double]::Parse(
        $Matches[1],
        [Globalization.CultureInfo]::InvariantCulture
      )
      $silenceDuration = [double]::Parse(
        $Matches[2],
        [Globalization.CultureInfo]::InvariantCulture
      )
      $start = if ($null -ne $currentStart) {
        [double]$currentStart
      } else {
        [math]::Max(0.0, $end - $silenceDuration)
      }
      [void]$intervals.Add([pscustomobject]@{
        Start = $start
        End = $end
        Duration = $silenceDuration
        ReachesEnd = [math]::Abs($end - $duration) -le 0.035
      })
      $currentStart = $null
    }
  }
  return @($intervals)
}

function Get-VolumeStats([string]$path) {
  $lines = & ffmpeg -hide_banner -i $path -af volumedetect -f null NUL 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "volumedetect could not read $path."
  }
  $max = $null
  $mean = $null
  foreach ($line in $lines) {
    $text = [string]$line
    if ($text -match 'max_volume:\s*(-?[0-9.]+)\s*dB') {
      $max = [double]::Parse(
        $Matches[1],
        [Globalization.CultureInfo]::InvariantCulture
      )
    }
    if ($text -match 'mean_volume:\s*(-?[0-9.]+)\s*dB') {
      $mean = [double]::Parse(
        $Matches[1],
        [Globalization.CultureInfo]::InvariantCulture
      )
    }
  }
  return [pscustomobject]@{ MaxDb = $max; MeanDb = $mean }
}

if (!(Test-Path -LiteralPath $catalogPath)) {
  throw "Listening catalog was not found: $catalogPath"
}
if (!(Test-Path -LiteralPath $viManifestPath)) {
  throw "Vietnamese segment manifest was not found: $viManifestPath"
}
if ($null -ne $vietnameseMp3DirectoryPath -and
    !(Test-Path -LiteralPath $vietnameseMp3DirectoryPath)) {
  throw "Vietnamese MP3 directory was not found: $vietnameseMp3DirectoryPath"
}
if (!(Test-Path -LiteralPath $connectorPath)) {
  throw "Provided 'hay' audio was not found: $connectorPath"
}
if (!(Test-Path -LiteralPath $ApiKeyPath)) {
  throw "ElevenLabs API key file was not found: $ApiKeyPath"
}

$apiKey = (Get-Content -LiteralPath $ApiKeyPath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($apiKey)) {
  throw 'The ElevenLabs API key file is empty.'
}

$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
$group = $catalog.groups | Where-Object {
  $_.startAge -eq 6 -and $_.endAge -eq 7
}
if ($null -eq $group) {
  throw 'Age group 6-7 was not found in the listening catalog.'
}
$viManifest = Get-Content -LiteralPath $viManifestPath -Raw | ConvertFrom-Json

$viSegmentsById = @{}
foreach ($segment in $viManifest.segments) {
  $viSegmentsById[[string]$segment.segmentId] = $segment
}
$viMappings = @{}
foreach ($mapping in $viManifest.promptMappings) {
  $mappingKey = "$($mapping.lessonCode)|$($mapping.lessonQuestionNumber)"
  if ($viMappings.ContainsKey($mappingKey)) {
    throw "Duplicate Vietnamese mapping key: $mappingKey"
  }
  $viMappings[$mappingKey] = $mapping
}

$englishByText = [ordered]@{}
$items = [Collections.ArrayList]::new()
$seenQuestionIds = @{}
foreach ($topic in $group.topics) {
  foreach ($lesson in $topic.lessons) {
    $localQuestionNumber = 0
    foreach ($challenge in @($lesson.challengeBank)) {
      $localQuestionNumber++
      $id = ([string]$challenge.id).Trim()
      if ($seenQuestionIds.ContainsKey($id)) {
        throw "Duplicate challenge ID in age group 6-7: $id"
      }
      $seenQuestionIds[$id] = $true
      $prompt = Get-NormalizedText ([string]$challenge.prompt)
      if ($prompt -notmatch '^(?<vi>.+?):\s*(?<choiceA>.+?)\s+hay\s+(?<choiceB>.+?)$') {
        throw "Challenge $id does not match the expected VI: EN hay EN structure."
      }
      $viText = (Get-NormalizedText $Matches.vi) + ':'
      $choiceA = Get-NormalizedText $Matches.choiceA
      $choiceB = Get-NormalizedText $Matches.choiceB

      $mappingKey = "$($lesson.code)|$localQuestionNumber"
      if (!$viMappings.ContainsKey($mappingKey)) {
        throw "Missing Vietnamese mapping for $mappingKey."
      }
      $viMapping = $viMappings[$mappingKey]
      if ($viMapping.prompt -ne $prompt -or $viMapping.vietnameseText -ne $viText) {
        throw "Vietnamese mapping content changed for $mappingKey."
      }
      if (!$viSegmentsById.ContainsKey([string]$viMapping.segmentId)) {
        throw "Missing Vietnamese segment $($viMapping.segmentId)."
      }
      $viSegment = $viSegmentsById[[string]$viMapping.segmentId]
      $viAudioPath = if ($null -ne $vietnameseMp3DirectoryPath) {
        Join-Path $vietnameseMp3DirectoryPath "$($viMapping.segmentId).mp3"
      } else {
        Join-Path $vietnameseRootPath ([string]$viSegment.wavAsset)
      }
      if (!(Test-Path -LiteralPath $viAudioPath)) {
        throw "Vietnamese source audio is missing: $viAudioPath"
      }

      $englishParts = @()
      foreach ($englishText in @($choiceA, $choiceB)) {
        if (!$englishByText.Contains($englishText)) {
          $cacheKey = Get-TextHash (
            "$modelId|en|$enVoiceId|$enSpeed|default|$englishText"
          )
          $segmentNumber = $englishByText.Count + 1
          $englishByText[$englishText] = [pscustomobject]@{
            SegmentId = 'C67-EN-{0:D3}' -f $segmentNumber
            Text = $englishText
            CacheKey = $cacheKey
            CachePath = Join-Path $cacheDirectory "$cacheKey.mp3"
            WasCached = $false
          }
        }
        $englishParts += $englishByText[$englishText]
      }

      [void]$items.Add([pscustomobject]@{
        Id = $id
        Prompt = $prompt
        TopicNumber = [int]$topic.number
        LessonNumber = [int]$lesson.number
        LessonCode = [string]$lesson.code
        VietnameseText = $viText
        VietnameseSegmentId = [string]$viMapping.segmentId
        VietnameseAudioPath = $viAudioPath
        VietnameseSource = if ($null -ne $vietnameseMp3DirectoryPath) {
          'provided-vi-review-mp3-directory'
        } else {
          'approved-vi-segment-r1'
        }
        EnglishA = $englishParts[0]
        EnglishB = $englishParts[1]
      })
    }
  }
}

$englishSegments = @($englishByText.Values)
$cachedEnglish = @($englishSegments | Where-Object {
  (Test-Path -LiteralPath $_.CachePath) -and
  (Get-Item -LiteralPath $_.CachePath).Length -ge 512
})
$missingEnglish = @($englishSegments | Where-Object {
  !(Test-Path -LiteralPath $_.CachePath) -or
  (Get-Item -LiteralPath $_.CachePath).Length -lt 512
})
foreach ($segment in $cachedEnglish) {
  $segment.WasCached = $true
}

Write-Output "Challenge prompts: $($items.Count)."
Write-Output "Approved Vietnamese segments used: $(@($items.VietnameseSegmentId | Sort-Object -Unique).Count)."
Write-Output "Unique English segments: $($englishSegments.Count)."
Write-Output "Reused English cache: $($cachedEnglish.Count); new ElevenLabs requests: $($missingEnglish.Count)."
Write-Output "Provided 'hay' uses: $($items.Count)."

if ($PlanOnly) {
  Write-Output 'Plan-only mode completed without calling ElevenLabs or assembling files.'
  return
}

New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $outputAudioDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $englishRawDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $englishWavDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $englishReviewDirectory -Force | Out-Null

$vietnamesePreparation = [Collections.ArrayList]::new()
if ($null -ne $vietnameseMp3DirectoryPath) {
  New-Item -ItemType Directory -Path $preparedVietnameseDirectory -Force | Out-Null
  $preparedBySegmentId = @{}
  foreach ($item in $items) {
    if ($preparedBySegmentId.ContainsKey($item.VietnameseSegmentId)) {
      $item.VietnameseAudioPath = $preparedBySegmentId[$item.VietnameseSegmentId]
      $item.VietnameseSource = 'provided-vi-review-mp3-directory-tail-checked'
      continue
    }

    $sourcePath = $item.VietnameseAudioPath
    $sourceDuration = Get-Duration $sourcePath
    $sourceSilences = @(Get-SilenceIntervals $sourcePath $sourceDuration)
    $firstLongSilence = @($sourceSilences | Where-Object {
      $_.Duration -ge 0.50
    }) | Select-Object -First 1
    $trimEnd = $sourceDuration
    if ($null -ne $firstLongSilence) {
      $trimEnd = [math]::Min($sourceDuration, $firstLongSilence.Start + 0.04)
    }
    $trimEndText = $trimEnd.ToString(
      '0.######',
      [Globalization.CultureInfo]::InvariantCulture
    )
    $preparedPath = Join-Path $preparedVietnameseDirectory `
      "$($item.VietnameseSegmentId).wav"
    & ffmpeg -y -v error -i $sourcePath `
      -af "atrim=end=$trimEndText,asetpts=PTS-STARTPTS" `
      -ar 44100 -ac 1 -c:a pcm_s16le $preparedPath
    if ($LASTEXITCODE -ne 0) {
      throw "Could not prepare Vietnamese MP3 source $($item.VietnameseSegmentId)."
    }
    $preparedBySegmentId[$item.VietnameseSegmentId] = $preparedPath
    $item.VietnameseAudioPath = $preparedPath
    $item.VietnameseSource = 'provided-vi-review-mp3-directory-tail-checked'
    [void]$vietnamesePreparation.Add([ordered]@{
      segmentId = $item.VietnameseSegmentId
      sourceAsset = $sourcePath
      preparedAsset = $preparedPath
      sourceDurationSeconds = [math]::Round($sourceDuration, 3)
      durationSeconds = [math]::Round((Get-Duration $preparedPath), 3)
      removedAfterLongSilence = ($null -ne $firstLongSilence)
      trimmedTailSeconds = [math]::Round(
        [math]::Max(0.0, $sourceDuration - $trimEnd),
        3
      )
    })
  }
  $viPreparationPath = Join-Path $outputRootPath `
    'challenge_6_7_vi_source_preprocessing.json'
  [IO.File]::WriteAllText(
    $viPreparationPath,
    (@($vietnamesePreparation) | ConvertTo-Json -Depth 6) + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false)
  )
  Write-Output "Prepared $($vietnamesePreparation.Count) Vietnamese MP3 sources; removed long tails from $(@($vietnamesePreparation | Where-Object { $_.removedAfterLongSilence }).Count)."
}

$missingEnglish | ForEach-Object -Parallel {
  $segment = $_
  $headers = @{
    'xi-api-key' = $using:apiKey
    Accept = 'audio/mpeg'
    'Content-Type' = 'application/json'
  }
  $bodyText = @{
    text = $segment.Text
    model_id = $using:modelId
    language_code = 'en'
    voice_settings = @{
      speed = $using:enSpeed
      stability = 0.5
      similarity_boost = 0.75
      use_speaker_boost = $true
    }
  } | ConvertTo-Json -Depth 5
  $bodyBytes = [Text.Encoding]::UTF8.GetBytes($bodyText)
  $created = $false
  for ($attempt = 1; $attempt -le $using:RetryCount; $attempt++) {
    $temporaryPath = "$($segment.CachePath).partial.$([guid]::NewGuid().ToString('N'))"
    try {
      Invoke-WebRequest `
        -Uri "https://api.elevenlabs.io/v1/text-to-speech/$using:enVoiceId`?output_format=mp3_44100_128" `
        -Method Post `
        -Headers $headers `
        -ContentType 'application/json' `
        -Body $bodyBytes `
        -OutFile $temporaryPath
      if ((Get-Item -LiteralPath $temporaryPath).Length -lt 512) {
        throw "ElevenLabs returned an unexpectedly small file for '$($segment.Text)'."
      }
      & ffmpeg -v error -i $temporaryPath -f null NUL
      if ($LASTEXITCODE -ne 0) {
        throw "ElevenLabs returned an undecodable file for '$($segment.Text)'."
      }
      Move-Item -LiteralPath $temporaryPath -Destination $segment.CachePath -Force
      $created = $true
      Write-Output "generated|$($segment.SegmentId)|$($segment.Text)"
      break
    } catch {
      if (Test-Path -LiteralPath $temporaryPath) {
        Remove-Item -LiteralPath $temporaryPath -Force
      }
      if ($attempt -eq $using:RetryCount) {
        throw
      }
      $delay = [math]::Min(20, [math]::Pow(2, $attempt))
      Write-Output "retry|$($segment.SegmentId)|attempt=$attempt|delay=$delay"
      Start-Sleep -Seconds $delay
    }
  }
  if (!$created) {
    throw "Could not generate '$($segment.Text)'."
  }
} -ThrottleLimit $ThrottleLimit

$englishEntries = [Collections.ArrayList]::new()
$englishQa = [Collections.ArrayList]::new()
foreach ($segment in $englishSegments) {
  if (!(Test-Path -LiteralPath $segment.CachePath)) {
    throw "Missing provider audio for $($segment.SegmentId)."
  }
  $rawPath = Join-Path $englishRawDirectory "$($segment.SegmentId).mp3"
  $wavPath = Join-Path $englishWavDirectory "$($segment.SegmentId).wav"
  $reviewPath = Join-Path $englishReviewDirectory "$($segment.SegmentId).mp3"
  Copy-Item -LiteralPath $segment.CachePath -Destination $rawPath -Force

  $rawDuration = Get-Duration $rawPath
  $rawSilences = @(Get-SilenceIntervals $rawPath $rawDuration)
  $trailing = @($rawSilences | Where-Object { $_.ReachesEnd }) | Select-Object -Last 1
  $trimEnd = $rawDuration
  if ($null -ne $trailing -and $trailing.Duration -ge 0.08) {
    $trimEnd = [math]::Min($rawDuration, $trailing.Start + 0.04)
  }
  if ($trimEnd -lt 0.20) {
    $trimEnd = $rawDuration
  }
  $trimEndText = $trimEnd.ToString('0.######', [Globalization.CultureInfo]::InvariantCulture)
  & ffmpeg -y -v error -i $rawPath -af "atrim=end=$trimEndText,asetpts=PTS-STARTPTS" `
    -ar 44100 -ac 1 -c:a pcm_s16le $wavPath
  if ($LASTEXITCODE -ne 0) {
    throw "Could not create English WAV for $($segment.SegmentId)."
  }
  & ffmpeg -y -v error -i $wavPath -ar 44100 -ac 1 `
    -codec:a libmp3lame -b:a 128k $reviewPath
  if ($LASTEXITCODE -ne 0) {
    throw "Could not create English review MP3 for $($segment.SegmentId)."
  }
  & ffmpeg -v error -i $reviewPath -f null NUL
  if ($LASTEXITCODE -ne 0) {
    throw "English review MP3 is not decodable for $($segment.SegmentId)."
  }

  $finalDuration = Get-Duration $reviewPath
  $finalSilences = @(Get-SilenceIntervals $reviewPath $finalDuration)
  $volume = Get-VolumeStats $reviewPath
  $flags = [Collections.ArrayList]::new()
  $wordCount = @($segment.Text.TrimEnd('.', '?', '!') -split '\s+').Count
  $leading = @($finalSilences | Where-Object { $_.Start -le 0.01 }) | Select-Object -First 1
  $finalTrailing = @($finalSilences | Where-Object { $_.ReachesEnd }) | Select-Object -Last 1
  $internalLong = @($rawSilences | Where-Object {
    !$_.ReachesEnd -and $_.Duration -ge 0.30
  })
  if ($null -ne $leading -and $leading.Duration -gt 0.30) {
    [void]$flags.Add('long-leading-silence')
  }
  if ($null -ne $finalTrailing -and $finalTrailing.Duration -gt 0.15) {
    [void]$flags.Add('long-trailing-silence')
  }
  if ($internalLong.Count -gt 0) {
    [void]$flags.Add('long-internal-silence')
  }
  if ($wordCount -le 2 -and $finalDuration -gt 2.20) {
    [void]$flags.Add('long-duration-for-short-text')
  }
  if ($finalDuration -lt 0.25) {
    [void]$flags.Add('very-short-duration')
  }
  if ($null -ne $volume.MaxDb -and $volume.MaxDb -gt -0.10) {
    [void]$flags.Add('near-clipping')
  }

  $entry = [ordered]@{
    segmentId = $segment.SegmentId
    text = $segment.Text
    language = 'en'
    modelId = $modelId
    voiceId = $enVoiceId
    speed = $enSpeed
    source = if ($segment.WasCached) { 'cache' } else { 'elevenlabs-new' }
    cacheKey = $segment.CacheKey
    rawAsset = ".segments/en-raw-mp3/$($segment.SegmentId).mp3"
    wavAsset = ".segments/en-wav/$($segment.SegmentId).wav"
    reviewAsset = ".segments/en-review-mp3/$($segment.SegmentId).mp3"
    rawDurationSeconds = [math]::Round($rawDuration, 3)
    durationSeconds = [math]::Round($finalDuration, 3)
    trimmedTailSeconds = [math]::Round([math]::Max(0.0, $rawDuration - $trimEnd), 3)
    sha256 = (Get-FileHash -LiteralPath $reviewPath -Algorithm SHA256).Hash.ToLowerInvariant()
    sizeBytes = (Get-Item -LiteralPath $reviewPath).Length
    peakDb = $volume.MaxDb
    meanDb = $volume.MeanDb
    qaFlags = @($flags)
  }
  [void]$englishEntries.Add($entry)
  [void]$englishQa.Add([pscustomobject]@{
    segmentId = $segment.SegmentId
    text = $segment.Text
    source = $entry.source
    rawDurationSeconds = $entry.rawDurationSeconds
    durationSeconds = $entry.durationSeconds
    trimmedTailSeconds = $entry.trimmedTailSeconds
    peakDb = $entry.peakDb
    meanDb = $entry.meanDb
    flags = (@($flags) -join ';')
  })
  $segment | Add-Member -NotePropertyName WavPath -NotePropertyValue $wavPath -Force
  $segment | Add-Member -NotePropertyName Source -NotePropertyValue $entry.source -Force
}

$englishManifestPath = Join-Path $outputRootPath 'challenge_6_7_en_segments.json'
$englishQaJsonPath = Join-Path $outputRootPath 'challenge_6_7_en_qa.json'
$englishQaCsvPath = Join-Path $outputRootPath 'challenge_6_7_en_qa.csv'
$englishManifest = [ordered]@{
  schemaVersion = 1
  ageGroup = $AgeGroup
  uniqueSegmentCount = $englishEntries.Count
  modelId = $modelId
  voiceId = $enVoiceId
  speed = $enSpeed
  segments = @($englishEntries)
}
[IO.File]::WriteAllText(
  $englishManifestPath,
  ($englishManifest | ConvertTo-Json -Depth 10) + [Environment]::NewLine,
  [Text.UTF8Encoding]::new($false)
)
[IO.File]::WriteAllText(
  $englishQaJsonPath,
  (@($englishQa) | ConvertTo-Json -Depth 5) + [Environment]::NewLine,
  [Text.UTF8Encoding]::new($false)
)
$englishQa | Export-Csv -LiteralPath $englishQaCsvPath -NoTypeInformation -Encoding utf8

$flaggedEnglish = @($englishQa | Where-Object { $_.flags })
Write-Output "Created $($englishEntries.Count) English segments; QA flags: $($flaggedEnglish.Count)."
if ($flaggedEnglish.Count -gt 0) {
  $flaggedEnglish | Format-Table segmentId, text, durationSeconds, flags -AutoSize
  throw 'English segment QA requires review before final assembly.'
}

& ffmpeg -y -v error -i $connectorPath -map 0:a:0 -vn -ar 44100 -ac 1 `
  -c:a pcm_s16le $connectorWavPath
if ($LASTEXITCODE -ne 0) {
  throw "Could not decode the provided 'hay' audio."
}

$items | ForEach-Object -Parallel {
  $item = $_
  $outPath = Join-Path $using:outputAudioDirectory "listening.challenge.$($item.Id).prompt.vi.mp3"
  $filter = '[0:a]aformat=sample_rates=44100:channel_layouts=mono[a0];' +
    '[1:a]aformat=sample_rates=44100:channel_layouts=mono[a1];' +
    '[2:a]aformat=sample_rates=44100:channel_layouts=mono[a2];' +
    '[3:a]aformat=sample_rates=44100:channel_layouts=mono[a3];' +
    '[a0][a1][a2][a3]concat=n=4:v=0:a=1[out]'
  & ffmpeg -y -v error `
    -i $item.VietnameseAudioPath `
    -i $item.EnglishA.WavPath `
    -i $using:connectorWavPath `
    -i $item.EnglishB.WavPath `
    -filter_complex $filter -map '[out]' -ar 44100 -ac 1 `
    -codec:a libmp3lame -b:a 128k $outPath
  if ($LASTEXITCODE -ne 0) {
    throw "Could not assemble $($item.Id)."
  }
  & ffmpeg -v error -i $outPath -f null NUL
  if ($LASTEXITCODE -ne 0) {
    throw "Assembled file is not decodable: $($item.Id)."
  }
  Write-Output "assembled|$($item.Id)"
} -ThrottleLimit 4

$connectorHash = (Get-FileHash -LiteralPath $connectorPath -Algorithm SHA256).Hash.ToLowerInvariant()
$entries = [Collections.ArrayList]::new()
foreach ($item in $items) {
  $fileName = "listening.challenge.$($item.Id).prompt.vi.mp3"
  $targetPath = Join-Path $outputAudioDirectory $fileName
  $duration = Get-Duration $targetPath
  $volume = Get-VolumeStats $targetPath
  [void]$entries.Add([ordered]@{
    key = "listening.challenge.$($item.Id).prompt.vi"
    enabled = $true
    locale = 'vi-VN'
    asset = "challenge-6-7/$fileName"
    durationSeconds = [math]::Round($duration, 3)
    sha256 = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash.ToLowerInvariant()
    modelId = $modelId
    language = 'mixed'
    voiceId = $viVoiceId
    speed = $viSpeed
    sizeBytes = (Get-Item -LiteralPath $targetPath).Length
    textHash = Get-TextHash $item.Prompt
    text = $item.Prompt
    topicNumber = $item.TopicNumber
    lessonNumber = $item.LessonNumber
    lessonCode = $item.LessonCode
    peakDb = $volume.MaxDb
    meanDb = $volume.MeanDb
    segments = @(
      [ordered]@{
        language = 'vi'
        text = $item.VietnameseText
        segmentId = $item.VietnameseSegmentId
        voiceId = $viVoiceId
        speed = $viSpeed
        source = $item.VietnameseSource
      },
      [ordered]@{
        language = 'en'
        text = $item.EnglishA.Text
        segmentId = $item.EnglishA.SegmentId
        voiceId = $enVoiceId
        speed = $enSpeed
        source = $item.EnglishA.Source
      },
      [ordered]@{
        language = 'vi'
        text = 'hay'
        voiceId = 'provided-audio'
        speed = 1.0
        source = 'provided-0926.mp4'
      },
      [ordered]@{
        language = 'en'
        text = $item.EnglishB.Text
        segmentId = $item.EnglishB.SegmentId
        voiceId = $enVoiceId
        speed = $enSpeed
        source = $item.EnglishB.Source
      }
    )
  })
}

$manifest = [ordered]@{
  schemaVersion = 1
  pack = 'challenge-6-7'
  enabled = $true
  ageGroup = $AgeGroup
  sourceCatalog = 'assets/data/listening_lessons.json'
  vietnameseSegmentManifest = $viManifestPath
  vietnameseSourceDirectory = if ($null -ne $vietnameseMp3DirectoryPath) {
    $vietnameseMp3DirectoryPath
  } else {
    Join-Path $vietnameseRootPath 'vi-segments-wav'
  }
  connectorSource = $connectorPath
  connectorSha256 = $connectorHash
  promptCount = $entries.Count
  prompts = @($entries)
}
$manifestPath = Join-Path $outputRootPath 'challenge_6_7_prompts_audio.json'
[IO.File]::WriteAllText(
  $manifestPath,
  ($manifest | ConvertTo-Json -Depth 12) + [Environment]::NewLine,
  [Text.UTF8Encoding]::new($false)
)

Write-Output "Created $($entries.Count) final prompts in $outputAudioDirectory."
Write-Output "Manifest: $manifestPath"
