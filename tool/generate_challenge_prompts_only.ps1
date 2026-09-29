param(
  [string]$ApiKeyPath = 'C:\Users\DELL\Documents\api_key_elevanlabs.txt',
  [ValidateSet('3-5', '6-7', '8-10', '11-12', '13-15')]
  [string]$AgeGroup = '3-5',
  [string]$OutputRoot = 'outputs\challenge-prompts-refresh-20260926',
  [Parameter(Mandatory = $true)]
  [string]$ConnectorAudioPath,
  [ValidateRange(1, 8)]
  [int]$ThrottleLimit = 3,
  [switch]$PlanOnly
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$catalogPath = Join-Path $repositoryRoot 'assets\data\listening_lessons.json'
$outputRootPath = if ([IO.Path]::IsPathRooted($OutputRoot)) {
  [IO.Path]::GetFullPath($OutputRoot)
} else {
  [IO.Path]::GetFullPath((Join-Path $repositoryRoot $OutputRoot))
}
$pack = "challenge-$AgeGroup"
$outputDirectory = Join-Path $outputRootPath $pack
$cacheDirectory = Join-Path $repositoryRoot 'build\mixed-challenge-preview-cache'
$temporaryDirectory = Join-Path $outputRootPath '.assembly'

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $temporaryDirectory -Force | Out-Null

$sourceConnector = [IO.Path]::GetFullPath($ConnectorAudioPath)
if (!(Test-Path -LiteralPath $sourceConnector)) {
  throw "Connector audio was not found: $sourceConnector"
}

$apiKey = (Get-Content -LiteralPath $ApiKeyPath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($apiKey)) {
  throw 'The ElevenLabs API key file is empty.'
}

$profiles = @{
  vi = @{ VoiceId = '5CVDNcIPiOYgRUQuxXd7'; Speed = 0.9; Locale = 'vi-VN' }
  en = @{ VoiceId = 'Nhs7eitvQWFTQBsf0yiT'; Speed = 0.75; Locale = 'en-US' }
}

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

function Get-DurationSeconds([string]$path) {
  $durationText = & ffprobe -v error -show_entries format=duration `
    -of default=noprint_wrappers=1:nokey=1 $path
  if ($LASTEXITCODE -ne 0) {
    throw "ffprobe could not read $path."
  }
  return [math]::Round(
    [double]::Parse(
      $durationText.Trim(),
      [Globalization.CultureInfo]::InvariantCulture
    ),
    3
  )
}

function Add-Segment([Collections.ArrayList]$segments, [string]$language, [string]$text) {
  $normalized = Get-NormalizedText $text
  if ([string]::IsNullOrWhiteSpace($normalized)) {
    return
  }
  if ($normalized -match '^\p{P}+$' -and $segments.Count -gt 0) {
    $segments[$segments.Count - 1].Text += $normalized
    return
  }
  [void]$segments.Add([pscustomobject]@{
    Language = $language
    Text = $normalized
  })
}

function Split-ChallengePrompt([string]$prompt, [object[]]$choices) {
  $ranges = @()
  foreach ($choice in $choices) {
    $needle = (Get-NormalizedText ([string]$choice)).TrimEnd('.', '?', '!')
    if ([string]::IsNullOrWhiteSpace($needle)) {
      continue
    }
    $start = 0
    while ($start -lt $prompt.Length) {
      $index = $prompt.IndexOf(
        $needle,
        $start,
        [StringComparison]::OrdinalIgnoreCase
      )
      if ($index -lt 0) {
        break
      }
      $end = $index + $needle.Length
      while ($end -lt $prompt.Length -and '.,?!'.Contains($prompt[$end])) {
        $end++
      }
      $ranges += [pscustomobject]@{ Start = $index; End = $end }
      $start = $end
    }
  }

  $ranges = @($ranges | Sort-Object Start, End -Unique)
  $segments = [Collections.ArrayList]::new()
  $cursor = 0
  foreach ($range in $ranges) {
    if ($range.Start -lt $cursor) {
      continue
    }
    if ($range.Start -gt $cursor) {
      Add-Segment $segments 'vi' $prompt.Substring($cursor, $range.Start - $cursor)
    }
    Add-Segment $segments 'en' $prompt.Substring($range.Start, $range.End - $range.Start)
    $cursor = $range.End
  }
  if ($cursor -lt $prompt.Length) {
    Add-Segment $segments 'vi' $prompt.Substring($cursor)
  }
  return @($segments)
}

$sourceConnectorHash = (
  Get-FileHash -LiteralPath $sourceConnector -Algorithm SHA256
).Hash.ToLowerInvariant()
$connectorCachePath = Join-Path $cacheDirectory "provided-hay-$sourceConnectorHash.mp3"
if (!(Test-Path -LiteralPath $connectorCachePath)) {
  & ffmpeg -y -v error -i $sourceConnector -map 0:a:0 -vn -ar 44100 -ac 1 `
    -codec:a libmp3lame -b:a 128k $connectorCachePath
  if ($LASTEXITCODE -ne 0) {
    throw 'Could not extract the provided connector audio.'
  }
}
if ((Get-Item -LiteralPath $connectorCachePath).Length -lt 512) {
  throw 'The provided connector audio is unexpectedly small.'
}

$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
$ageParts = $AgeGroup.Split('-')
$group = $catalog.groups | Where-Object {
  $_.startAge -eq [int]$ageParts[0] -and $_.endAge -eq [int]$ageParts[1]
}
if ($null -eq $group) {
  throw "Age group $AgeGroup was not found in the listening catalog."
}

$items = [Collections.ArrayList]::new()
$requestsByCacheKey = @{}
foreach ($topic in $group.topics) {
  foreach ($lesson in $topic.lessons) {
    foreach ($challenge in $lesson.challengeBank) {
      $prompt = Get-NormalizedText ([string]$challenge.prompt)
      $segments = @(Split-ChallengePrompt $prompt @($challenge.choices))
      if ($segments.Count -eq 0) {
        throw "Challenge $($challenge.id) produced no speech segments."
      }
      if (@($segments | Where-Object {
        $_.Language -eq 'vi' -and $_.Text -eq 'hay'
      }).Count -ne 1) {
        throw "Challenge $($challenge.id) must contain exactly one Vietnamese 'hay' segment."
      }

      foreach ($segment in $segments) {
        if ($segment.Language -eq 'vi' -and $segment.Text -eq 'hay') {
          $segment | Add-Member -NotePropertyName CacheKey -NotePropertyValue 'provided-hay'
          $segment | Add-Member -NotePropertyName SourcePath -NotePropertyValue $connectorCachePath
          $segment | Add-Member -NotePropertyName Source -NotePropertyValue 'provided-0926.mp4'
          continue
        }

        $profile = $profiles[$segment.Language]
        $cacheKey = Get-TextHash (
          "eleven_v3|$($segment.Language)|$($profile.VoiceId)|$($profile.Speed)|default|$($segment.Text)"
        )
        $cachePath = Join-Path $cacheDirectory "$cacheKey.mp3"
        if (!$requestsByCacheKey.ContainsKey($cacheKey)) {
          $requestsByCacheKey[$cacheKey] = [pscustomobject]@{
            CacheKey = $cacheKey
            Language = $segment.Language
            Text = $segment.Text
            VoiceId = $profile.VoiceId
            Speed = $profile.Speed
            Path = $cachePath
          }
        }
        $segment | Add-Member -NotePropertyName CacheKey -NotePropertyValue $cacheKey
        $segment | Add-Member -NotePropertyName SourcePath -NotePropertyValue $cachePath
        $segment | Add-Member -NotePropertyName Source -NotePropertyValue 'elevenlabs'
      }

      [void]$items.Add([pscustomobject]@{
        Id = ([string]$challenge.id).Trim()
        Prompt = $prompt
        TopicNumber = [int]$topic.number
        LessonNumber = [int]$lesson.number
        Segments = $segments
      })
    }
  }
}

$requests = @($requestsByCacheKey.Values)
$cachedRequests = @($requests | Where-Object {
  (Test-Path -LiteralPath $_.Path) -and (Get-Item -LiteralPath $_.Path).Length -ge 512
})
$missingRequests = @($requests | Where-Object {
  !(Test-Path -LiteralPath $_.Path) -or (Get-Item -LiteralPath $_.Path).Length -lt 512
})

Write-Output "Challenge prompts: $($items.Count)."
Write-Output "Unique ElevenLabs segments: $($requests.Count)."
Write-Output "Reused from cache: $($cachedRequests.Count); new paid requests: $($missingRequests.Count)."
Write-Output "The provided 'hay' connector will be used $($items.Count) times."

if ($PlanOnly) {
  Write-Output 'Plan-only mode completed without calling ElevenLabs or assembling final files.'
  return
}

$missingRequests | ForEach-Object -Parallel {
  $request = $_
  $headers = @{
    'xi-api-key' = $using:apiKey
    Accept = 'audio/mpeg'
    'Content-Type' = 'application/json'
  }
  $speechText = if ($request.Text.EndsWith(':')) {
    $request.Text.TrimEnd(':') + '.'
  } else {
    $request.Text
  }
  $body = @{
    text = $speechText
    model_id = 'eleven_v3'
    language_code = $request.Language
    voice_settings = @{
      speed = $request.Speed
      stability = 0.5
      similarity_boost = 0.75
      use_speaker_boost = $true
    }
  } | ConvertTo-Json -Depth 5
  $temporaryPath = "$($request.Path).partial.$([guid]::NewGuid().ToString('N'))"
  try {
    Invoke-WebRequest `
      -Uri "https://api.elevenlabs.io/v1/text-to-speech/$($request.VoiceId)?output_format=mp3_44100_128" `
      -Method Post `
      -Headers $headers `
      -Body $body `
      -OutFile $temporaryPath
    if ((Get-Item -LiteralPath $temporaryPath).Length -lt 512) {
      throw "ElevenLabs returned an unexpectedly small file for '$($request.Text)'."
    }
    Move-Item -LiteralPath $temporaryPath -Destination $request.Path -Force
    Write-Output "generated|$($request.Language)|$($request.CacheKey)|$($request.Text)"
  } catch {
    if (Test-Path -LiteralPath $temporaryPath) {
      Remove-Item -LiteralPath $temporaryPath -Force
    }
    throw
  }
} -ThrottleLimit $ThrottleLimit

$entries = [Collections.ArrayList]::new()
foreach ($item in $items) {
  $fileName = "listening.challenge.$($item.Id).prompt.vi.mp3"
  $targetPath = Join-Path $outputDirectory $fileName
  $concatPath = Join-Path $temporaryDirectory "$($item.Id).concat.txt"
  @($item.Segments | ForEach-Object {
    "file '$($_.SourcePath.Replace("'", "'\''"))'"
  }) | Set-Content -LiteralPath $concatPath -Encoding utf8

  & ffmpeg -y -v error -f concat -safe 0 -i $concatPath -ar 44100 -ac 1 `
    -codec:a libmp3lame -b:a 128k $targetPath
  if ($LASTEXITCODE -ne 0) {
    throw "Could not assemble $fileName."
  }
  & ffmpeg -v error -i $targetPath -f null -
  if ($LASTEXITCODE -ne 0) {
    throw "The assembled file cannot be decoded: $fileName."
  }

  [void]$entries.Add([ordered]@{
    key = "listening.challenge.$($item.Id).prompt.vi"
    enabled = $true
    locale = 'vi-VN'
    asset = "$pack/$fileName"
    durationSeconds = Get-DurationSeconds $targetPath
    sha256 = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash.ToLowerInvariant()
    modelId = 'eleven_v3'
    language = 'mixed'
    voiceId = $profiles.vi.VoiceId
    speed = $profiles.vi.Speed
    sizeBytes = (Get-Item -LiteralPath $targetPath).Length
    textHash = Get-TextHash $item.Prompt
    text = $item.Prompt
    topicNumber = $item.TopicNumber
    lessonNumber = $item.LessonNumber
    segments = @($item.Segments | ForEach-Object {
      $profile = $profiles[$_.Language]
      [ordered]@{
        language = $_.Language
        text = $_.Text
        voiceId = if ($_.Source -eq 'provided-0926.mp4') {
          'provided-audio'
        } else {
          $profile.VoiceId
        }
        speed = if ($_.Source -eq 'provided-0926.mp4') { 1.0 } else { $profile.Speed }
        source = $_.Source
      }
    })
  })
}

$manifest = [ordered]@{
  schemaVersion = 1
  pack = $pack
  enabled = $true
  ageGroup = $AgeGroup
  sourceCatalog = 'assets/data/listening_lessons.json'
  connectorSource = $sourceConnector
  connectorSha256 = $sourceConnectorHash
  promptCount = $entries.Count
  prompts = @($entries)
}
$manifestPath = Join-Path $outputRootPath "challenge_$($AgeGroup.Replace('-', '_'))_prompts_audio.json"
$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8

Write-Output "Created $($entries.Count) prompt-only files in $outputDirectory."
Write-Output "Wrote staging manifest: $manifestPath."
