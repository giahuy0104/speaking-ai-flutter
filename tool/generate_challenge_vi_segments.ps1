param(
  [string]$ApiKeyPath = 'C:\Users\DELL\Documents\api_key_elevanlabs.txt',
  [ValidateSet('3-5', '6-7', '8-10', '11-12', '13-15')]
  [string]$AgeGroup = '6-7',
  [string]$OutputRoot = 'outputs\challenge-vi-c67-20260926-r1',
  [ValidateRange(1, 8)]
  [int]$ThrottleLimit = 3,
  [ValidateRange(1, 8)]
  [int]$RetryCount = 5,
  [switch]$StripContextMetaLead,
  [switch]$PlanOnly
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$catalogPath = Join-Path $repositoryRoot 'assets\data\listening_lessons.json'
$cacheDirectory = Join-Path $repositoryRoot 'build\mixed-challenge-preview-cache'
$outputRootPath = if ([IO.Path]::IsPathRooted($OutputRoot)) {
  [IO.Path]::GetFullPath($OutputRoot)
} else {
  [IO.Path]::GetFullPath((Join-Path $repositoryRoot $OutputRoot))
}
$rawDirectory = Join-Path $outputRootPath 'raw-provider-mp3'
$wavDirectory = Join-Path $outputRootPath 'vi-segments-wav'
$mp3Directory = Join-Path $outputRootPath 'vi-segments-mp3'

$voiceId = '5CVDNcIPiOYgRUQuxXd7'
$speed = 0.9
$modelId = 'eleven_v3'
$groupCode = switch ($AgeGroup) {
  '3-5' { 'C35' }
  '6-7' { 'C67' }
  '8-10' { 'C810' }
  '11-12' { 'C1112' }
  '13-15' { 'C1315' }
  default { throw "Unsupported age group: $AgeGroup" }
}
$manifestStem = "challenge_$($AgeGroup.Replace('-', '_'))_vi"

function Get-NormalizedText([string]$text) {
  return ($text -replace '\s+', ' ').Trim()
}

function Get-ChoiceStartIndex($challenge, [string]$prompt) {
  $hayMatch = [regex]::Match($prompt, '(?<!\p{L})hay(?!\p{L})')
  if (!$hayMatch.Success) {
    throw "Could not locate connector 'hay' in challenge $($challenge.id)."
  }
  $firstChoice = Get-NormalizedText ([string]$challenge.choices[0])
  $needle = $firstChoice.TrimEnd('.')
  if ([string]::IsNullOrWhiteSpace($needle)) {
    throw "The first choice is empty in challenge $($challenge.id)."
  }
  # The same word can appear in the Vietnamese context (for example "Taxi").
  # The actual first choice is the last matching occurrence before "hay".
  $beforeConnector = $prompt.Substring(0, $hayMatch.Index)
  $choiceIndex = $beforeConnector.LastIndexOf(
    $needle,
    [StringComparison]::Ordinal
  )
  if ($choiceIndex -lt 0) {
    throw "Could not locate the first choice in challenge $($challenge.id)."
  }
  return $choiceIndex
}

function New-VietnameseFragment(
  [string]$text,
  [string]$role,
  [int]$sourceStart,
  [string]$sourceText = ''
) {
  $normalized = Get-NormalizedText $text
  $normalizedSource = if ([string]::IsNullOrWhiteSpace($sourceText)) {
    $normalized
  } else {
    Get-NormalizedText $sourceText
  }
  return [pscustomobject]@{
    Text = $normalized
    Role = $role
    SourceStart = $sourceStart
    SourceLength = $normalizedSource.Length
    SourceText = $normalizedSource
  }
}

function Get-VietnameseFragments($challenge, [string]$prompt) {
  $fragments = [Collections.ArrayList]::new()
  $format = [string]$challenge.format

  if ($format -eq 'VI_TO_EN') {
    $colonIndex = $prompt.IndexOf(':')
    if ($colonIndex -lt 1) {
      throw "Challenge $($challenge.id) does not contain a Vietnamese prefix ending in a colon."
    }
    [void]$fragments.Add((New-VietnameseFragment `
      $prompt.Substring(0, $colonIndex + 1) 'prompt' 0))
    return @($fragments)
  }

  $choiceStart = Get-ChoiceStartIndex $challenge $prompt
  $beforeChoices = $prompt.Substring(0, $choiceStart).TrimEnd()

  if ($format -eq 'CONTEXT') {
    if ([string]::IsNullOrWhiteSpace($beforeChoices)) {
      throw "Challenge $($challenge.id) has no Vietnamese context before its choices."
    }
    if ($StripContextMetaLead -and
        $beforeChoices -match '^Bạn muốn diễn đạt "(?<target>.+)"[.!?]$') {
      $targetText = (Get-NormalizedText ([string]$Matches.target)) + ':'
      [void]$fragments.Add((New-VietnameseFragment `
        $targetText 'target-without-meta-lead' 0 $beforeChoices))
    } else {
      [void]$fragments.Add((New-VietnameseFragment $beforeChoices 'context' 0))
    }
    return @($fragments)
  }

  if ($format -eq 'UNDERSTANDING') {
    # Two prompts in this group contain English choices only. They intentionally
    # produce no Vietnamese TTS segment; the shared "hay" clip is handled later.
    if ($beforeChoices -notmatch '^(?<lead>HOMI (?:hỏi|nói):)') {
      return @()
    }
    $lead = [string]$Matches.lead
    [void]$fragments.Add((New-VietnameseFragment $lead 'speaker-cue' 0))

    $instructionStarts = [Collections.ArrayList]::new()
    foreach ($instructionMarker in @('Bạn ', 'Hôm đó ')) {
      $candidateStart = $beforeChoices.IndexOf(
        $instructionMarker,
        $lead.Length,
        [StringComparison]::Ordinal
      )
      if ($candidateStart -ge $lead.Length) {
        [void]$instructionStarts.Add($candidateStart)
      }
    }
    if ($instructionStarts.Count -gt 0) {
      $instructionStart = ($instructionStarts | Measure-Object -Minimum).Minimum
      $instruction = $beforeChoices.Substring($instructionStart).Trim()
      [void]$fragments.Add((New-VietnameseFragment `
        $instruction 'instruction' $instructionStart))
    }
    return @($fragments)
  }

  throw "Unsupported challenge format '$format' in $($challenge.id)."
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
        # Treat sub-80 ms residual encoder/model noise after silence as tail.
        # A complete Vietnamese phoneme cannot fit in this residual window.
        ReachesEnd = [math]::Abs($end - $duration) -le 0.08
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
if (!(Test-Path -LiteralPath $ApiKeyPath)) {
  throw "ElevenLabs API key file was not found: $ApiKeyPath"
}

$apiKey = (Get-Content -LiteralPath $ApiKeyPath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($apiKey)) {
  throw 'The ElevenLabs API key file is empty.'
}

$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
$ageParts = $AgeGroup.Split('-')
$group = $catalog.groups | Where-Object {
  $_.startAge -eq [int]$ageParts[0] -and $_.endAge -eq [int]$ageParts[1]
}
if ($null -eq $group) {
  throw "Age group $AgeGroup was not found in the listening catalog."
}

$promptMappings = [Collections.ArrayList]::new()
$segmentsByText = [ordered]@{}
foreach ($topic in $group.topics) {
  foreach ($lesson in $topic.lessons) {
    $localQuestionNumber = 0
    foreach ($challenge in @($lesson.challengeBank)) {
      $localQuestionNumber++
      $prompt = Get-NormalizedText ([string]$challenge.prompt)
      $fragments = @(Get-VietnameseFragments $challenge $prompt)
      $fragmentMappings = [Collections.ArrayList]::new()
      foreach ($fragment in $fragments) {
        $viText = [string]$fragment.Text
        $quoteCount = ([regex]::Matches($viText, '"')).Count
        if ($quoteCount % 2 -ne 0) {
          throw "Vietnamese fragment has unmatched quotation marks in $($challenge.id): $viText"
        }
        if ($viText.Length -lt 2) {
          throw "Vietnamese fragment is unexpectedly short in $($challenge.id): $viText"
        }
        if (!$segmentsByText.Contains($viText)) {
          $profileText = "$modelId|vi|$voiceId|$speed|default|$viText"
          $cacheKey = Get-TextHash $profileText
          $segmentNumber = $segmentsByText.Count + 1
          $speechText = if ($viText.EndsWith(':')) {
            $viText.TrimEnd(':') + '.'
          } else {
            $viText
          }
          # Expand the only numeric time expression in the challenge catalog so
          # the Vietnamese voice cannot switch to an English-style number read.
          $speechText = $speechText -replace '\b11 giờ\b', 'mười một giờ'
          $segmentsByText[$viText] = [pscustomobject]@{
            SegmentId = "$groupCode-VI-{0:D3}" -f $segmentNumber
            Text = $viText
            SpeechText = $speechText
            CacheKey = $cacheKey
            CachePath = Join-Path $cacheDirectory "$cacheKey.mp3"
            FirstLessonCode = [string]$lesson.code
            FirstQuestionId = [string]$challenge.id
            WasCached = $false
          }
        }
        $segment = $segmentsByText[$viText]
        [void]$fragmentMappings.Add([ordered]@{
          order = $fragmentMappings.Count + 1
          role = [string]$fragment.Role
          text = $viText
          segmentId = $segment.SegmentId
          sourceStart = [int]$fragment.SourceStart
          sourceLength = [int]$fragment.SourceLength
          sourceText = [string]$fragment.SourceText
        })
      }
      $legacyText = if ($fragmentMappings.Count -eq 1) {
        [string]$fragmentMappings[0].text
      } else { $null }
      $legacySegmentId = if ($fragmentMappings.Count -eq 1) {
        [string]$fragmentMappings[0].segmentId
      } else { $null }
      [void]$promptMappings.Add([pscustomobject][ordered]@{
        lessonCode = [string]$lesson.code
        lessonQuestionNumber = $localQuestionNumber
        sourceQuestionId = [string]$challenge.id
        questionIdPrefixMatchesAgeGroup = ([string]$challenge.id).StartsWith("$groupCode-")
        format = [string]$challenge.format
        prompt = $prompt
        vietnameseFragmentCount = $fragmentMappings.Count
        vietnameseSegments = @($fragmentMappings)
        vietnameseText = $legacyText
        segmentId = $legacySegmentId
      })
    }
  }
}

$segments = @($segmentsByText.Values)
$cached = @($segments | Where-Object {
  (Test-Path -LiteralPath $_.CachePath) -and
  (Get-Item -LiteralPath $_.CachePath).Length -ge 512
})
$missing = @($segments | Where-Object {
  !(Test-Path -LiteralPath $_.CachePath) -or
  (Get-Item -LiteralPath $_.CachePath).Length -lt 512
})
foreach ($segment in $cached) {
  $segment.WasCached = $true
}

Write-Output "Prompts: $($promptMappings.Count)."
Write-Output "Unique Vietnamese segments: $($segments.Count)."
Write-Output "Reused from cache: $($cached.Count); new ElevenLabs requests: $($missing.Count)."
Write-Output "Source IDs with the wrong age-group prefix: $(@($promptMappings | Where-Object { !$_.questionIdPrefixMatchesAgeGroup }).Count)."

if ($PlanOnly) {
  Write-Output 'Plan-only mode completed without calling ElevenLabs.'
  return
}

New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $rawDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $wavDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $mp3Directory -Force | Out-Null

$missing | ForEach-Object -Parallel {
  $segment = $_
  $headers = @{
    'xi-api-key' = $using:apiKey
    Accept = 'audio/mpeg'
    'Content-Type' = 'application/json'
  }
  $bodyText = @{
    text = $segment.SpeechText
    model_id = $using:modelId
    language_code = 'vi'
    voice_settings = @{
      speed = $using:speed
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
        -Uri "https://api.elevenlabs.io/v1/text-to-speech/$using:voiceId`?output_format=mp3_44100_128" `
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

$segmentEntries = [Collections.ArrayList]::new()
$qaRows = [Collections.ArrayList]::new()
foreach ($segment in $segments) {
  if (!(Test-Path -LiteralPath $segment.CachePath)) {
    throw "Missing provider audio for $($segment.SegmentId): $($segment.CachePath)"
  }
  $rawPath = Join-Path $rawDirectory "$($segment.SegmentId).mp3"
  $wavPath = Join-Path $wavDirectory "$($segment.SegmentId).wav"
  $mp3Path = Join-Path $mp3Directory "$($segment.SegmentId).mp3"
  Copy-Item -LiteralPath $segment.CachePath -Destination $rawPath -Force

  $rawDuration = Get-Duration $rawPath
  $rawSilences = @(Get-SilenceIntervals $rawPath $rawDuration)
  $trailing = @($rawSilences | Where-Object { $_.ReachesEnd }) | Select-Object -Last 1
  $trimEnd = $rawDuration
  if ($null -ne $trailing -and $trailing.Duration -ge 0.08) {
    # ElevenLabs can leave tiny noise spikes between otherwise contiguous tail
    # silences. Walk backward through gaps under 50 ms so those spikes do not
    # preserve a long, silent tail.
    $tailStart = [double]$trailing.Start
    $orderedSilences = @($rawSilences | Sort-Object Start)
    $trailingIndex = [array]::IndexOf($orderedSilences, $trailing)
    for ($silenceIndex = $trailingIndex - 1; $silenceIndex -ge 0; $silenceIndex--) {
      $candidate = $orderedSilences[$silenceIndex]
      if (($tailStart - $candidate.End) -gt 0.05) {
        break
      }
      $tailStart = [double]$candidate.Start
    }
    $trimEnd = [math]::Min($rawDuration, $tailStart + 0.04)
  }
  if ($trimEnd -lt 0.20) {
    $trimEnd = $rawDuration
  }
  $trimEndText = $trimEnd.ToString('0.######', [Globalization.CultureInfo]::InvariantCulture)
  $compressedInternalSilenceSeconds = 0.0
  $speakerCuePause = $null
  if ($segment.Text -eq 'HOMI hỏi:') {
    $speakerCuePause = @($rawSilences | Where-Object {
      !$_.ReachesEnd -and $_.Duration -ge 0.30
    } | Sort-Object Duration -Descending) | Select-Object -First 1
  }
  if ($null -ne $speakerCuePause) {
    # Keep an 80 ms word boundary while removing the model's exaggerated pause
    # between the name HOMI and the Vietnamese reporting verb.
    $firstEnd = [math]::Min(
      $trimEnd,
      [double]$speakerCuePause.Start + 0.08
    )
    $secondStart = [double]$speakerCuePause.End
    $firstEndText = $firstEnd.ToString('0.######', [Globalization.CultureInfo]::InvariantCulture)
    $secondStartText = $secondStart.ToString('0.######', [Globalization.CultureInfo]::InvariantCulture)
    $filter = "[0:a]atrim=start=0:end=$firstEndText,asetpts=PTS-STARTPTS[a0];" +
      "[0:a]atrim=start=${secondStartText}:end=$trimEndText,asetpts=PTS-STARTPTS[a1];" +
      '[a0][a1]concat=n=2:v=0:a=1[out]'
    & ffmpeg -y -v error -i $rawPath -filter_complex $filter -map '[out]' `
      -ar 44100 -ac 1 -c:a pcm_s16le $wavPath
    $compressedInternalSilenceSeconds = [math]::Max(
      0.0,
      $secondStart - $firstEnd
    )
  } else {
    & ffmpeg -y -v error -i $rawPath -af "atrim=end=$trimEndText,asetpts=PTS-STARTPTS" `
      -ar 44100 -ac 1 -c:a pcm_s16le $wavPath
  }
  if ($LASTEXITCODE -ne 0) {
    throw "Could not create normalized WAV for $($segment.SegmentId)."
  }
  & ffmpeg -y -v error -i $wavPath -ar 44100 -ac 1 -codec:a libmp3lame -b:a 128k $mp3Path
  if ($LASTEXITCODE -ne 0) {
    throw "Could not create review MP3 for $($segment.SegmentId)."
  }
  & ffmpeg -v error -i $mp3Path -f null NUL
  if ($LASTEXITCODE -ne 0) {
    throw "Review MP3 is not decodable for $($segment.SegmentId)."
  }

  $finalDuration = Get-Duration $mp3Path
  $finalSilences = @(Get-SilenceIntervals $mp3Path $finalDuration)
  $volume = Get-VolumeStats $mp3Path
  $flags = [Collections.ArrayList]::new()
  $wordCount = @(($segment.Text.TrimEnd(':') -split '\s+') | Where-Object { $_ }).Count
  $leading = @($finalSilences | Where-Object { $_.Start -le 0.01 }) | Select-Object -First 1
  $finalTrailing = @($finalSilences | Where-Object { $_.ReachesEnd }) | Select-Object -Last 1
  $internalLong = @($finalSilences | Where-Object {
    !$_.ReachesEnd -and $_.Duration -ge 0.30
  })
  if ($null -ne $leading -and $leading.Duration -gt 0.25) {
    [void]$flags.Add('long-leading-silence')
  }
  if ($null -ne $finalTrailing -and $finalTrailing.Duration -gt 0.15) {
    [void]$flags.Add('long-trailing-silence')
  }
  if ($internalLong.Count -gt 0) {
    [void]$flags.Add('long-internal-silence')
  }
  if ($wordCount -le 2 -and $finalDuration -gt 1.80) {
    [void]$flags.Add('long-duration-for-short-text')
  }
  if ($finalDuration -lt 0.30) {
    [void]$flags.Add('very-short-duration')
  }
  if ($null -ne $volume.MaxDb -and $volume.MaxDb -gt -0.10) {
    [void]$flags.Add('near-clipping')
  }

  $trimmedSeconds = [math]::Max(0.0, $rawDuration - $trimEnd)
  $entry = [ordered]@{
    segmentId = $segment.SegmentId
    text = $segment.Text
    speechText = $segment.SpeechText
    language = 'vi'
    modelId = $modelId
    voiceId = $voiceId
    speed = $speed
    source = if ($segment.WasCached) { 'cache' } else { 'elevenlabs-new' }
    cacheKey = $segment.CacheKey
    rawAsset = "raw-provider-mp3/$($segment.SegmentId).mp3"
    wavAsset = "vi-segments-wav/$($segment.SegmentId).wav"
    reviewAsset = "vi-segments-mp3/$($segment.SegmentId).mp3"
    rawDurationSeconds = [math]::Round($rawDuration, 3)
    durationSeconds = [math]::Round($finalDuration, 3)
    trimmedTailSeconds = [math]::Round($trimmedSeconds, 3)
    compressedInternalSilenceSeconds = [math]::Round(
      $compressedInternalSilenceSeconds,
      3
    )
    sha256 = (Get-FileHash -LiteralPath $mp3Path -Algorithm SHA256).Hash.ToLowerInvariant()
    sizeBytes = (Get-Item -LiteralPath $mp3Path).Length
    peakDb = $volume.MaxDb
    meanDb = $volume.MeanDb
    qaFlags = @($flags)
  }
  [void]$segmentEntries.Add($entry)
  [void]$qaRows.Add([pscustomobject]@{
    segmentId = $segment.SegmentId
    text = $segment.Text
    source = $entry.source
    rawDurationSeconds = $entry.rawDurationSeconds
    durationSeconds = $entry.durationSeconds
    trimmedTailSeconds = $entry.trimmedTailSeconds
    compressedInternalSilenceSeconds = $entry.compressedInternalSilenceSeconds
    peakDb = $entry.peakDb
    meanDb = $entry.meanDb
    flags = (@($flags) -join ';')
  })
}

$manifest = [ordered]@{
  schemaVersion = 1
  stage = 'vietnamese-segments'
  ageGroup = $AgeGroup
  sourceCatalog = 'assets/data/listening_lessons.json'
  promptCount = $promptMappings.Count
  uniqueSegmentCount = $segmentEntries.Count
  modelId = $modelId
  voiceId = $voiceId
  speed = $speed
  generatedAt = [DateTimeOffset]::Now.ToString('o')
  mismatchedSourceIdCount = @($promptMappings | Where-Object {
    !$_.questionIdPrefixMatchesAgeGroup
  }).Count
  segments = @($segmentEntries)
  promptMappings = @($promptMappings)
}
$manifestPath = Join-Path $outputRootPath "$($manifestStem)_segments.json"
$qaJsonPath = Join-Path $outputRootPath "$($manifestStem)_qa.json"
$qaCsvPath = Join-Path $outputRootPath "$($manifestStem)_qa.csv"
$manifestJson = $manifest | ConvertTo-Json -Depth 12
[IO.File]::WriteAllText(
  $manifestPath,
  $manifestJson + [Environment]::NewLine,
  [Text.UTF8Encoding]::new($false)
)
$qaJson = @($qaRows) | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText(
  $qaJsonPath,
  $qaJson + [Environment]::NewLine,
  [Text.UTF8Encoding]::new($false)
)
$qaRows | Export-Csv -LiteralPath $qaCsvPath -NoTypeInformation -Encoding utf8

Write-Output "Created $($segmentEntries.Count) Vietnamese review MP3 files in $mp3Directory."
Write-Output "Created $($segmentEntries.Count) normalized WAV files in $wavDirectory."
Write-Output "QA flags: $(@($qaRows | Where-Object { $_.flags }).Count)."
Write-Output "Manifest: $manifestPath"
Write-Output "QA JSON: $qaJsonPath"
Write-Output "QA CSV: $qaCsvPath"
