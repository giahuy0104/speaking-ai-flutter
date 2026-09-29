param(
  [string]$ApiKeyPath = 'C:\Users\DELL\Documents\api_key_elevanlabs.txt',
  [ValidateSet('8-10', '11-12', '13-15')]
  [string]$AgeGroup = '8-10',
  [string]$VietnameseRoot = 'outputs\challenge-vi-c810-20260926-r1',
  [Parameter(Mandatory = $true)]
  [string]$VietnameseMp3Directory,
  [string]$OutputRoot = 'outputs\challenge-prompts-c810-20260926-r1',
  [string]$ConnectorAudioPath = 'C:\Users\DELL\Downloads\0926.mp4',
  [ValidateRange(1, 8)]
  [int]$ThrottleLimit = 3,
  [ValidateRange(1, 8)]
  [int]$RetryCount = 5,
  [ValidateSet('none', 'natural')]
  [string]$PauseProfile = 'natural',
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
$vietnameseMp3DirectoryPath = if ([IO.Path]::IsPathRooted($VietnameseMp3Directory)) {
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
$ageParts = $AgeGroup.Split('-')
$groupCode = switch ($AgeGroup) {
  '8-10' { 'C810' }
  '11-12' { 'C1112' }
  '13-15' { 'C1315' }
  default { throw "Unsupported age group: $AgeGroup" }
}
$manifestStem = "challenge_$($AgeGroup.Replace('-', '_'))"
$packName = "challenge-$AgeGroup"
$viManifestPath = Join-Path $vietnameseRootPath "$($manifestStem)_vi_segments.json"
$outputAudioDirectory = Join-Path $outputRootPath $packName
$segmentRoot = Join-Path $outputRootPath '.segments'
$preparedVietnameseDirectory = Join-Path $segmentRoot 'vi-from-provided-review-mp3'
$englishRawDirectory = Join-Path $segmentRoot 'en-raw-mp3'
$englishWavDirectory = Join-Path $segmentRoot 'en-wav'
$englishReviewDirectory = Join-Path $segmentRoot 'en-review-mp3'
$connectorWavPath = Join-Path $segmentRoot 'provided-hay-0926.wav'

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
    $lineText = [string]$line
    if ($lineText -match 'silence_start:\s*([0-9.]+)') {
      $currentStart = [double]::Parse(
        $Matches[1],
        [Globalization.CultureInfo]::InvariantCulture
      )
    }
    if ($lineText -match 'silence_end:\s*([0-9.]+)\s*\|\s*silence_duration:\s*([0-9.]+)') {
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

function Get-TrailingTrimEnd([string]$path, [double]$duration) {
  $silences = @(Get-SilenceIntervals $path $duration)
  $trailing = @($silences | Where-Object { $_.ReachesEnd }) | Select-Object -Last 1
  if ($null -eq $trailing -or $trailing.Duration -lt 0.08) {
    return $duration
  }
  $tailStart = [double]$trailing.Start
  $ordered = @($silences | Sort-Object Start)
  $index = [array]::IndexOf($ordered, $trailing)
  for ($i = $index - 1; $i -ge 0; $i--) {
    if (($tailStart - $ordered[$i].End) -gt 0.05) {
      break
    }
    $tailStart = [double]$ordered[$i].Start
  }
  return [math]::Max(0.20, [math]::Min($duration, $tailStart + 0.04))
}

function Get-VolumeStats([string]$path) {
  $lines = & ffmpeg -hide_banner -i $path -af volumedetect -f null NUL 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "volumedetect could not read $path."
  }
  $max = $null
  $mean = $null
  foreach ($line in $lines) {
    $lineText = [string]$line
    if ($lineText -match 'max_volume:\s*(-?[0-9.]+)\s*dB') {
      $max = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
    }
    if ($lineText -match 'mean_volume:\s*(-?[0-9.]+)\s*dB') {
      $mean = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
    }
  }
  return [pscustomobject]@{ MaxDb = $max; MeanDb = $mean }
}

function Test-RangeOverlap($left, $right) {
  return $left.Start -lt $right.End -and $right.Start -lt $left.End
}

function Get-PauseSeconds($left, $right, [string]$profile) {
  if ($profile -eq 'none' -or $null -eq $right) {
    return 0.0
  }
  # A short, balanced beat around the connector keeps both choices together.
  if ($left.Type -eq 'connector' -or $right.Type -eq 'connector') {
    return 0.24
  }
  # In dialogue prompts, allow the embedded English utterance to finish before
  # the Vietnamese situation/instruction begins.
  if ($left.Type -eq 'en' -and $right.Type -eq 'vi') {
    return 0.38
  }
  # Speaker cues ending in a colon need a smaller beat than a full instruction.
  if ($left.Type -eq 'vi' -and $right.Type -eq 'en') {
    if ($left.Text -match '^HOMI (?:hỏi|nói):$') {
      return 0.22
    }
    return 0.38
  }
  return 0.30
}

foreach ($requiredPath in @($catalogPath, $viManifestPath, $vietnameseMp3DirectoryPath, $connectorPath, $ApiKeyPath)) {
  if (!(Test-Path -LiteralPath $requiredPath)) {
    throw "Required path was not found: $requiredPath"
  }
}

$apiKey = (Get-Content -LiteralPath $ApiKeyPath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($apiKey)) {
  throw 'The ElevenLabs API key file is empty.'
}

$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
$group = $catalog.groups | Where-Object {
  $_.startAge -eq [int]$ageParts[0] -and $_.endAge -eq [int]$ageParts[1]
}
if ($null -eq $group) {
  throw "Age group $AgeGroup was not found in the listening catalog."
}
$viManifest = Get-Content -LiteralPath $viManifestPath -Raw | ConvertFrom-Json
if ([string]$viManifest.ageGroup -ne $AgeGroup) {
  throw "Unexpected Vietnamese manifest age group: $($viManifest.ageGroup)"
}

$viSegmentsById = @{}
foreach ($segment in @($viManifest.segments)) {
  $viSegmentsById[[string]$segment.segmentId] = $segment
}
$viMappingsByQuestionId = @{}
foreach ($mapping in @($viManifest.promptMappings)) {
  $id = [string]$mapping.sourceQuestionId
  if ($viMappingsByQuestionId.ContainsKey($id)) {
    throw "Duplicate Vietnamese mapping for $id."
  }
  $viMappingsByQuestionId[$id] = $mapping
}

$items = [Collections.ArrayList]::new()
$englishByText = [ordered]@{}
$seenQuestionIds = @{}
foreach ($topic in $group.topics) {
  foreach ($lesson in $topic.lessons) {
    foreach ($challenge in @($lesson.challengeBank)) {
      $id = ([string]$challenge.id).Trim()
      if ($seenQuestionIds.ContainsKey($id)) {
        throw "Duplicate challenge ID: $id"
      }
      $seenQuestionIds[$id] = $true
      if (!$viMappingsByQuestionId.ContainsKey($id)) {
        throw "Missing Vietnamese mapping for $id."
      }
      $mapping = $viMappingsByQuestionId[$id]
      $prompt = Get-NormalizedText ([string]$challenge.prompt)
      if ([string]$mapping.prompt -ne $prompt) {
        throw "Prompt text changed after Vietnamese review for $id."
      }

      $ranges = [Collections.ArrayList]::new()
      foreach ($viReference in @($mapping.vietnameseSegments)) {
        $segmentId = [string]$viReference.segmentId
        if (!$viSegmentsById.ContainsKey($segmentId)) {
          throw "Unknown Vietnamese segment $segmentId in $id."
        }
        $start = [int]$viReference.sourceStart
        $end = $start + [int]$viReference.sourceLength
        $sourceText = $prompt.Substring($start, $end - $start)
        $expectedSourceText = if ($null -ne $viReference.sourceText -and
            ![string]::IsNullOrWhiteSpace([string]$viReference.sourceText)) {
          [string]$viReference.sourceText
        } else {
          [string]$viReference.text
        }
        if ($sourceText -ne $expectedSourceText) {
          throw "Vietnamese source range changed for $id / $segmentId."
        }
        [void]$ranges.Add([pscustomobject]@{
          Start = $start
          End = $end
          Type = 'vi'
          Text = [string]$viReference.text
          SourceText = $sourceText
          SegmentId = $segmentId
        })
      }

      foreach ($choice in @($challenge.choices)) {
        $choiceText = Get-NormalizedText ([string]$choice)
        $needle = $choiceText.TrimEnd('.')
        $searchStart = 0
        $choiceRange = $null
        while ($searchStart -lt $prompt.Length) {
          $index = $prompt.IndexOf($needle, $searchStart, [StringComparison]::Ordinal)
          if ($index -lt 0) {
            break
          }
          $end = $index + $needle.Length
          while ($end -lt $prompt.Length -and '.,?!'.Contains($prompt[$end])) {
            $end++
          }
          $candidate = [pscustomobject]@{ Start = $index; End = $end }
          $overlap = @($ranges | Where-Object { Test-RangeOverlap $_ $candidate }).Count -gt 0
          if (!$overlap) {
            $choiceRange = $candidate
            break
          }
          $searchStart = $index + [math]::Max(1, $needle.Length)
        }
        if ($null -eq $choiceRange) {
          throw "Could not locate choice '$choiceText' in $id."
        }
        $renderedChoice = $prompt.Substring(
          $choiceRange.Start,
          $choiceRange.End - $choiceRange.Start
        )
        [void]$ranges.Add([pscustomobject]@{
          Start = $choiceRange.Start
          End = $choiceRange.End
          Type = 'en'
          Text = $renderedChoice
          SegmentId = $null
        })
      }

      $hayMatches = [regex]::Matches($prompt, '(?<!\p{L})hay(?!\p{L})')
      if ($hayMatches.Count -ne 1) {
        throw "Challenge $id must contain exactly one connector 'hay'."
      }
      $hayMatch = $hayMatches[0]
      [void]$ranges.Add([pscustomobject]@{
        Start = $hayMatch.Index
        End = $hayMatch.Index + $hayMatch.Length
        Type = 'connector'
        Text = 'hay'
        SegmentId = $null
      })

      $orderedRanges = @($ranges | Sort-Object Start, End)
      for ($i = 1; $i -lt $orderedRanges.Count; $i++) {
        if ($orderedRanges[$i].Start -lt $orderedRanges[$i - 1].End) {
          throw "Overlapping speech ranges in $id."
        }
      }

      $sequence = [Collections.ArrayList]::new()
      $cursor = 0
      foreach ($range in $orderedRanges) {
        if ($range.Start -gt $cursor) {
          $gapText = $prompt.Substring($cursor, $range.Start - $cursor).Trim()
          if (![string]::IsNullOrWhiteSpace($gapText)) {
            [void]$sequence.Add([pscustomobject]@{
              Type = 'en'
              Text = $gapText
              SegmentId = $null
            })
          }
        }
        [void]$sequence.Add([pscustomobject]@{
          Type = [string]$range.Type
          Text = [string]$range.Text
          SegmentId = if ($range.Type -eq 'vi') { [string]$range.SegmentId } else { $null }
        })
        $cursor = $range.End
      }
      if ($cursor -lt $prompt.Length) {
        $gapText = $prompt.Substring($cursor).Trim()
        if (![string]::IsNullOrWhiteSpace($gapText)) {
          [void]$sequence.Add([pscustomobject]@{
            Type = 'en'
            Text = $gapText
            SegmentId = $null
          })
        }
      }

      foreach ($sequenceSegment in $sequence) {
        if ($sequenceSegment.Type -ne 'en') {
          continue
        }
        $englishText = [string]$sequenceSegment.Text
        if (!$englishByText.Contains($englishText)) {
          $cacheKey = Get-TextHash "$modelId|en|$enVoiceId|$enSpeed|default|$englishText"
          $englishByText[$englishText] = [pscustomobject]@{
            SegmentId = "$groupCode-EN-{0:D3}" -f ($englishByText.Count + 1)
            Text = $englishText
            CacheKey = $cacheKey
            CachePath = Join-Path $cacheDirectory "$cacheKey.mp3"
            WasCached = $false
            WavPath = $null
            Source = $null
          }
        }
        $englishReference = $englishByText[$englishText]
        $sequenceSegment.SegmentId = $englishReference.SegmentId
        $sequenceSegment | Add-Member -NotePropertyName EnglishReference `
          -NotePropertyValue $englishReference -Force
      }
      for ($sequenceIndex = 0; $sequenceIndex -lt $sequence.Count; $sequenceIndex++) {
        $nextSegment = if ($sequenceIndex + 1 -lt $sequence.Count) {
          $sequence[$sequenceIndex + 1]
        } else {
          $null
        }
        $pauseSeconds = Get-PauseSeconds `
          $sequence[$sequenceIndex] $nextSegment $PauseProfile
        $sequence[$sequenceIndex] | Add-Member `
          -NotePropertyName PauseAfterSeconds `
          -NotePropertyValue $pauseSeconds -Force
      }

      [void]$items.Add([pscustomobject]@{
        Id = $id
        Prompt = $prompt
        Format = [string]$challenge.format
        TopicNumber = [int]$topic.number
        LessonNumber = [int]$lesson.number
        LessonCode = [string]$lesson.code
        Sequence = @($sequence)
      })
    }
  }
}

$englishSegments = @($englishByText.Values)
$cachedEnglish = @($englishSegments | Where-Object {
  (Test-Path -LiteralPath $_.CachePath) -and (Get-Item -LiteralPath $_.CachePath).Length -ge 512
})
$missingEnglish = @($englishSegments | Where-Object {
  !(Test-Path -LiteralPath $_.CachePath) -or (Get-Item -LiteralPath $_.CachePath).Length -lt 512
})
foreach ($segment in $cachedEnglish) {
  $segment.WasCached = $true
}
$usedVietnameseIds = @(
  $items.Sequence | ForEach-Object { $_ } | Where-Object { $_.Type -eq 'vi' } |
    ForEach-Object { $_.SegmentId } | Sort-Object -Unique
)

Write-Output "Challenge prompts: $($items.Count)."
Write-Output "Vietnamese review MP3 directory: $vietnameseMp3DirectoryPath"
Write-Output "Unique Vietnamese segments used: $($usedVietnameseIds.Count)."
Write-Output "Unique English segments: $($englishSegments.Count)."
Write-Output "Reused English cache: $($cachedEnglish.Count); new ElevenLabs requests: $($missingEnglish.Count)."
Write-Output "Provided 'hay' uses: $($items.Count)."
Write-Output "Pause profile: $PauseProfile."
$totalPlannedPauseSeconds = 0.0
foreach ($plannedItem in $items) {
  foreach ($plannedSegment in $plannedItem.Sequence) {
    $totalPlannedPauseSeconds += [double]$plannedSegment.PauseAfterSeconds
  }
}
Write-Output "Total synthetic pause time across the pack: $([math]::Round($totalPlannedPauseSeconds, 2)) seconds."
$sequencePatterns = @($items | ForEach-Object {
  [pscustomobject]@{
    Format = $_.Format
    Pattern = (@($_.Sequence.Type) -join '-')
  }
} | Group-Object Format, Pattern | Sort-Object Name)
foreach ($pattern in $sequencePatterns) {
  Write-Output "Sequence pattern: $($pattern.Name) = $($pattern.Count)."
}

if ($PlanOnly) {
  Write-Output 'Plan-only mode completed without calling ElevenLabs or assembling files.'
  return
}

foreach ($directory in @(
  $cacheDirectory,
  $outputAudioDirectory,
  $preparedVietnameseDirectory,
  $englishRawDirectory,
  $englishWavDirectory,
  $englishReviewDirectory
)) {
  New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

$preparedVietnamese = @{}
$vietnamesePreparation = [Collections.ArrayList]::new()
$vietnameseHashMismatchCount = 0
foreach ($segmentId in $usedVietnameseIds) {
  $sourcePath = Join-Path $vietnameseMp3DirectoryPath "$segmentId.mp3"
  if (!(Test-Path -LiteralPath $sourcePath)) {
    throw "Vietnamese review MP3 is missing: $sourcePath"
  }
  $manifestSegment = $viSegmentsById[$segmentId]
  $actualHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
  $manifestHashMatches = $actualHash -eq [string]$manifestSegment.sha256
  if (!$manifestHashMatches) {
    $vietnameseHashMismatchCount++
  }
  $sourceDuration = Get-Duration $sourcePath
  $trimEnd = Get-TrailingTrimEnd $sourcePath $sourceDuration
  $trimEndText = $trimEnd.ToString('0.######', [Globalization.CultureInfo]::InvariantCulture)
  $preparedPath = Join-Path $preparedVietnameseDirectory "$segmentId.wav"
  & ffmpeg -y -v error -i $sourcePath `
    -af "atrim=end=$trimEndText,asetpts=PTS-STARTPTS" `
    -ar 44100 -ac 1 -c:a pcm_s16le $preparedPath
  if ($LASTEXITCODE -ne 0) {
    throw "Could not decode Vietnamese review MP3 $segmentId."
  }
  $preparedVietnamese[$segmentId] = $preparedPath
  [void]$vietnamesePreparation.Add([ordered]@{
    segmentId = $segmentId
    sourceAsset = $sourcePath
    sourceSha256 = $actualHash
    manifestSha256 = [string]$manifestSegment.sha256
    manifestHashMatches = $manifestHashMatches
    preparedAsset = $preparedPath
    sourceDurationSeconds = [math]::Round($sourceDuration, 3)
    durationSeconds = [math]::Round((Get-Duration $preparedPath), 3)
    trimmedTailSeconds = [math]::Round(
      [math]::Max(0.0, $sourceDuration - $trimEnd),
      3
    )
    alteredTiming = ($trimEnd -lt $sourceDuration)
  })
}
Write-Output "Prepared $($vietnamesePreparation.Count) exact Vietnamese MP3 sources from the requested directory."
Write-Output "Vietnamese files differing from the original manifest hash: $vietnameseHashMismatchCount."
Write-Output "Vietnamese files with safely trimmed trailing silence: $(@($vietnamesePreparation | Where-Object { $_.alteredTiming }).Count)."

$missingEnglish | ForEach-Object -Parallel {
  $segment = $_
  $headers = @{
    'xi-api-key' = $using:apiKey
    Accept = 'audio/mpeg'
    'Content-Type' = 'application/json'
  }
  $body = @{
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
  $bodyBytes = [Text.Encoding]::UTF8.GetBytes($body)
  for ($attempt = 1; $attempt -le $using:RetryCount; $attempt++) {
    $temporaryPath = "$($segment.CachePath).partial.$([guid]::NewGuid().ToString('N'))"
    try {
      Invoke-WebRequest `
        -Uri "https://api.elevenlabs.io/v1/text-to-speech/$using:enVoiceId`?output_format=mp3_44100_128" `
        -Method Post -Headers $headers -ContentType 'application/json' `
        -Body $bodyBytes -OutFile $temporaryPath
      if ((Get-Item -LiteralPath $temporaryPath).Length -lt 512) {
        throw "ElevenLabs returned a small file for '$($segment.Text)'."
      }
      & ffmpeg -v error -i $temporaryPath -f null NUL
      if ($LASTEXITCODE -ne 0) {
        throw "ElevenLabs returned undecodable audio for '$($segment.Text)'."
      }
      Move-Item -LiteralPath $temporaryPath -Destination $segment.CachePath -Force
      Write-Output "generated|$($segment.SegmentId)|$($segment.Text)"
      break
    } catch {
      if (Test-Path -LiteralPath $temporaryPath) {
        Remove-Item -LiteralPath $temporaryPath -Force
      }
      if ($attempt -eq $using:RetryCount) {
        throw
      }
      Start-Sleep -Seconds ([math]::Min(20, [math]::Pow(2, $attempt)))
    }
  }
} -ThrottleLimit $ThrottleLimit

$englishEntries = [Collections.ArrayList]::new()
$englishQa = [Collections.ArrayList]::new()
foreach ($segment in $englishSegments) {
  $rawPath = Join-Path $englishRawDirectory "$($segment.SegmentId).mp3"
  $wavPath = Join-Path $englishWavDirectory "$($segment.SegmentId).wav"
  $reviewPath = Join-Path $englishReviewDirectory "$($segment.SegmentId).mp3"
  Copy-Item -LiteralPath $segment.CachePath -Destination $rawPath -Force
  $rawDuration = Get-Duration $rawPath
  $trimEnd = Get-TrailingTrimEnd $rawPath $rawDuration
  $trimEndText = $trimEnd.ToString('0.######', [Globalization.CultureInfo]::InvariantCulture)
  & ffmpeg -y -v error -i $rawPath -af "atrim=end=$trimEndText,asetpts=PTS-STARTPTS" `
    -ar 44100 -ac 1 -c:a pcm_s16le $wavPath
  if ($LASTEXITCODE -ne 0) {
    throw "Could not normalize English segment $($segment.SegmentId)."
  }
  & ffmpeg -y -v error -i $wavPath -ar 44100 -ac 1 -codec:a libmp3lame -b:a 128k $reviewPath
  if ($LASTEXITCODE -ne 0) {
    throw "Could not create English review MP3 $($segment.SegmentId)."
  }
  $duration = Get-Duration $reviewPath
  $silences = @(Get-SilenceIntervals $reviewPath $duration)
  $volume = Get-VolumeStats $reviewPath
  $flags = [Collections.ArrayList]::new()
  $longInternal = @($silences | Where-Object { !$_.ReachesEnd -and $_.Duration -ge 0.40 })
  $trailing = @($silences | Where-Object { $_.ReachesEnd }) | Select-Object -Last 1
  if ($longInternal.Count -gt 0) { [void]$flags.Add('long-internal-silence') }
  if ($null -ne $trailing -and $trailing.Duration -gt 0.15) { [void]$flags.Add('long-trailing-silence') }
  if ($duration -lt 0.25) { [void]$flags.Add('very-short-duration') }
  if ($null -ne $volume.MaxDb -and $volume.MaxDb -gt -0.10) { [void]$flags.Add('near-clipping') }
  $sourceLabel = if ($segment.WasCached) { 'cache' } else { 'elevenlabs-new' }
  $entry = [ordered]@{
    segmentId = $segment.SegmentId
    text = $segment.Text
    language = 'en'
    modelId = $modelId
    voiceId = $enVoiceId
    speed = $enSpeed
    source = $sourceLabel
    cacheKey = $segment.CacheKey
    rawAsset = ".segments/en-raw-mp3/$($segment.SegmentId).mp3"
    wavAsset = ".segments/en-wav/$($segment.SegmentId).wav"
    reviewAsset = ".segments/en-review-mp3/$($segment.SegmentId).mp3"
    rawDurationSeconds = [math]::Round($rawDuration, 3)
    durationSeconds = [math]::Round($duration, 3)
    trimmedTailSeconds = [math]::Round([math]::Max(0.0, $rawDuration - $trimEnd), 3)
    peakDb = $volume.MaxDb
    meanDb = $volume.MeanDb
    qaFlags = @($flags)
  }
  [void]$englishEntries.Add($entry)
  [void]$englishQa.Add([pscustomobject]@{
    segmentId = $segment.SegmentId
    text = $segment.Text
    source = $sourceLabel
    durationSeconds = $entry.durationSeconds
    flags = (@($flags) -join ';')
  })
  $segment.WavPath = $wavPath
  $segment.Source = $sourceLabel
}

$englishManifestPath = Join-Path $outputRootPath "$($manifestStem)_en_segments.json"
$englishQaCsvPath = Join-Path $outputRootPath "$($manifestStem)_en_qa.csv"
[IO.File]::WriteAllText(
  $englishManifestPath,
  (([ordered]@{
    schemaVersion = 1
    ageGroup = $AgeGroup
    uniqueSegmentCount = $englishEntries.Count
    modelId = $modelId
    voiceId = $enVoiceId
    speed = $enSpeed
    segments = @($englishEntries)
  }) | ConvertTo-Json -Depth 10) + [Environment]::NewLine,
  [Text.UTF8Encoding]::new($false)
)
$englishQa | Export-Csv -LiteralPath $englishQaCsvPath -NoTypeInformation -Encoding utf8
$flaggedEnglish = @($englishQa | Where-Object { $_.flags })
Write-Output "Created $($englishEntries.Count) English segments; QA flags: $($flaggedEnglish.Count)."
if ($flaggedEnglish.Count -gt 0) {
  $flaggedEnglish | Format-Table segmentId, text, durationSeconds, flags -AutoSize
  throw 'English segment QA requires review before final assembly.'
}

$connectorDuration = Get-Duration $connectorPath
$connectorTrimEnd = Get-TrailingTrimEnd $connectorPath $connectorDuration
$connectorTrimText = $connectorTrimEnd.ToString('0.######', [Globalization.CultureInfo]::InvariantCulture)
& ffmpeg -y -v error -i $connectorPath -map 0:a:0 -vn `
  -af "atrim=end=$connectorTrimText,asetpts=PTS-STARTPTS" `
  -ar 44100 -ac 1 -c:a pcm_s16le $connectorWavPath
if ($LASTEXITCODE -ne 0) {
  throw "Could not prepare the provided 'hay' audio."
}

foreach ($item in $items) {
  $inputPaths = [Collections.ArrayList]::new()
  foreach ($sequenceSegment in $item.Sequence) {
    $path = switch ($sequenceSegment.Type) {
      'vi' { $preparedVietnamese[[string]$sequenceSegment.SegmentId] }
      'en' { $sequenceSegment.EnglishReference.WavPath }
      'connector' { $connectorWavPath }
      default { throw "Unknown sequence type '$($sequenceSegment.Type)' in $($item.Id)." }
    }
    if ([string]::IsNullOrWhiteSpace([string]$path) -or !(Test-Path -LiteralPath $path)) {
      throw "Missing assembled input for $($item.Id): $path"
    }
    [void]$inputPaths.Add([string]$path)
  }
  $arguments = [Collections.ArrayList]::new()
  foreach ($token in @('-y', '-v', 'error')) { [void]$arguments.Add($token) }
  foreach ($path in $inputPaths) {
    [void]$arguments.Add('-i')
    [void]$arguments.Add($path)
  }
  $filterParts = [Collections.ArrayList]::new()
  $concatInputs = ''
  $concatNodeCount = 0
  for ($i = 0; $i -lt $inputPaths.Count; $i++) {
    [void]$filterParts.Add("[$i`:a]aformat=sample_rates=44100:channel_layouts=mono[a$i]")
    $concatInputs += "[a$i]"
    $concatNodeCount++
    $pauseSeconds = [double]$item.Sequence[$i].PauseAfterSeconds
    if ($i + 1 -lt $inputPaths.Count -and $pauseSeconds -gt 0.0) {
      $pauseText = $pauseSeconds.ToString(
        '0.###',
        [Globalization.CultureInfo]::InvariantCulture
      )
      [void]$filterParts.Add("anullsrc=r=44100:cl=mono:d=$pauseText[p$i]")
      $concatInputs += "[p$i]"
      $concatNodeCount++
    }
  }
  [void]$filterParts.Add("$concatInputs`concat=n=$concatNodeCount`:v=0:a=1[out]")
  $filter = $filterParts -join ';'
  $fileName = "listening.challenge.$($item.Id).prompt.vi.mp3"
  $outputPath = Join-Path $outputAudioDirectory $fileName
  foreach ($token in @(
    '-filter_complex', $filter,
    '-map', '[out]',
    '-ar', '44100',
    '-ac', '1',
    '-codec:a', 'libmp3lame',
    '-b:a', '128k',
    $outputPath
  )) { [void]$arguments.Add($token) }
  & ffmpeg @arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Could not assemble $($item.Id)."
  }
  Write-Output "assembled|$($item.Id)"
}

$connectorHash = (Get-FileHash -LiteralPath $connectorPath -Algorithm SHA256).Hash.ToLowerInvariant()
$entries = [Collections.ArrayList]::new()
$finalQa = [Collections.ArrayList]::new()
foreach ($item in $items) {
  $fileName = "listening.challenge.$($item.Id).prompt.vi.mp3"
  $targetPath = Join-Path $outputAudioDirectory $fileName
  & ffmpeg -v error -i $targetPath -f null NUL
  if ($LASTEXITCODE -ne 0) {
    throw "Final prompt is not decodable: $($item.Id)."
  }
  $duration = Get-Duration $targetPath
  $silences = @(Get-SilenceIntervals $targetPath $duration)
  $volume = Get-VolumeStats $targetPath
  $flags = [Collections.ArrayList]::new()
  $longSilences = @($silences | Where-Object { $_.Duration -ge 1.00 })
  $trailing = @($silences | Where-Object { $_.ReachesEnd }) | Select-Object -Last 1
  if ($longSilences.Count -gt 0) { [void]$flags.Add('very-long-silence') }
  if ($null -ne $trailing -and $trailing.Duration -gt 0.30) { [void]$flags.Add('long-trailing-silence') }
  if ($duration -lt 1.0) { [void]$flags.Add('very-short-final') }
  if ($duration -gt 20.0) { [void]$flags.Add('very-long-final') }
  if ($null -ne $volume.MaxDb -and $volume.MaxDb -gt -0.10) { [void]$flags.Add('near-clipping') }
  $sequenceManifest = [Collections.ArrayList]::new()
  foreach ($sequenceSegment in $item.Sequence) {
    $source = switch ($sequenceSegment.Type) {
      'vi' { 'provided-vi-review-mp3-directory' }
      'en' { [string]$sequenceSegment.EnglishReference.Source }
      'connector' { 'provided-0926.mp4' }
    }
    [void]$sequenceManifest.Add([ordered]@{
      language = if ($sequenceSegment.Type -eq 'connector') { 'vi' } else { $sequenceSegment.Type }
      text = [string]$sequenceSegment.Text
      segmentId = if ($sequenceSegment.Type -eq 'connector') { $null } else { [string]$sequenceSegment.SegmentId }
      voiceId = switch ($sequenceSegment.Type) {
        'vi' { $viVoiceId }
        'en' { $enVoiceId }
        'connector' { 'provided-audio' }
      }
      speed = switch ($sequenceSegment.Type) {
        'vi' { $viSpeed }
        'en' { $enSpeed }
        'connector' { 1.0 }
      }
      source = $source
      pauseAfterSeconds = [double]$sequenceSegment.PauseAfterSeconds
    })
  }
  [void]$entries.Add([ordered]@{
    key = "listening.challenge.$($item.Id).prompt.vi"
    enabled = $true
    locale = 'vi-VN'
    asset = "$packName/$fileName"
    durationSeconds = [math]::Round($duration, 3)
    sha256 = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash.ToLowerInvariant()
    modelId = $modelId
    language = 'mixed'
    voiceId = $viVoiceId
    speed = $viSpeed
    sizeBytes = (Get-Item -LiteralPath $targetPath).Length
    textHash = Get-TextHash $item.Prompt
    text = $item.Prompt
    format = $item.Format
    topicNumber = $item.TopicNumber
    lessonNumber = $item.LessonNumber
    lessonCode = $item.LessonCode
    peakDb = $volume.MaxDb
    meanDb = $volume.MeanDb
    segments = @($sequenceManifest)
  })
  [void]$finalQa.Add([pscustomobject]@{
    questionId = $item.Id
    durationSeconds = [math]::Round($duration, 3)
    segmentCount = $item.Sequence.Count
    peakDb = $volume.MaxDb
    meanDb = $volume.MeanDb
    flags = (@($flags) -join ';')
  })
}

$viPreparationPath = Join-Path $outputRootPath "$($manifestStem)_vi_source_preprocessing.json"
$manifestPath = Join-Path $outputRootPath "$($manifestStem)_prompts_audio.json"
$qaCsvPath = Join-Path $outputRootPath "$($manifestStem)_prompts_qa.csv"
[IO.File]::WriteAllText(
  $viPreparationPath,
  (@($vietnamesePreparation) | ConvertTo-Json -Depth 6) + [Environment]::NewLine,
  [Text.UTF8Encoding]::new($false)
)
[IO.File]::WriteAllText(
  $manifestPath,
  (([ordered]@{
    schemaVersion = 1
    pack = $packName
    enabled = $true
    ageGroup = $AgeGroup
    sourceCatalog = 'assets/data/listening_lessons.json'
    vietnameseSegmentManifest = $viManifestPath
    vietnameseSourceDirectory = $vietnameseMp3DirectoryPath
    connectorSource = $connectorPath
    connectorSha256 = $connectorHash
    connectorTrimmedTailSeconds = [math]::Round(
      [math]::Max(0.0, $connectorDuration - $connectorTrimEnd),
      3
    )
    pauseProfile = $PauseProfile
    totalSyntheticPauseSeconds = [math]::Round($totalPlannedPauseSeconds, 3)
    promptCount = $entries.Count
    prompts = @($entries)
  }) | ConvertTo-Json -Depth 14) + [Environment]::NewLine,
  [Text.UTF8Encoding]::new($false)
)
$finalQa | Export-Csv -LiteralPath $qaCsvPath -NoTypeInformation -Encoding utf8
$flaggedFinal = @($finalQa | Where-Object { $_.flags })
Write-Output "Created $($entries.Count) final prompts in $outputAudioDirectory."
Write-Output "Final QA flags: $($flaggedFinal.Count)."
Write-Output "Manifest: $manifestPath"
Write-Output "QA CSV: $qaCsvPath"
if ($flaggedFinal.Count -gt 0) {
  $flaggedFinal | Format-Table questionId, durationSeconds, segmentCount, flags -AutoSize
  throw 'Final prompt QA requires review.'
}
