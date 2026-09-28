param(
  [string]$InputPath = 'C:\Users\DELL\Downloads\68-cau-audio-bi-rut-gon.txt',
  [string]$OutputRoot = '',
  [string]$ReviewName = '68-vi-review-r1',
  [string]$ApiKeyPath = 'C:\Users\DELL\Documents\api_key_elevanlabs.txt',
  [ValidateRange(1, 6)]
  [int]$ThrottleLimit = 3,
  [switch]$Resume,
  [switch]$IncludeMetaLead,
  [switch]$ExactQuestionIdFileNames
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = Join-Path $repositoryRoot 'outputs\challenge-vi-shortened-68-20260928-r1'
}
$reviewName = $ReviewName
$reviewRoot = Join-Path $OutputRoot $reviewName
$rawRoot = Join-Path $OutputRoot 'raw-provider-mp3'
$uniqueMp3Root = Join-Path $reviewRoot 'unique-vi-segments-mp3'
$uniqueWavRoot = Join-Path $reviewRoot 'unique-vi-segments-wav'
$byQuestionRoot = Join-Path $reviewRoot 'by-question-id-mp3'
$cacheRoot = Join-Path $repositoryRoot $(if ($IncludeMetaLead) { 'build\full-vi-tts-cache' } else { 'build\shortened-vi-tts-cache' })
$catalogPath = Join-Path $repositoryRoot 'assets\data\listening_lessons.json'
$voiceId = '5CVDNcIPiOYgRUQuxXd7'
$modelId = 'eleven_v3'
$speed = 0.9

if (!(Test-Path -LiteralPath $InputPath)) { throw "Input file not found: $InputPath" }
if (!(Test-Path -LiteralPath $catalogPath)) { throw "Catalog not found: $catalogPath" }
if ((Test-Path -LiteralPath $OutputRoot) -and !$Resume) {
  throw "Output already exists; choose a new revision instead of overwriting it: $OutputRoot"
}
if (!(Get-Command ffmpeg -ErrorAction SilentlyContinue)) { throw 'ffmpeg is required.' }
if (!(Get-Command ffprobe -ErrorAction SilentlyContinue)) { throw 'ffprobe is required.' }

function Get-NormalizedTarget([string]$value) {
  return (($value -replace '\s+', ' ').Trim() -replace '[\s\.:;!?,]+$', '').ToLowerInvariant()
}

function Get-Sha256([string]$path) {
  return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TextHash([string]$value) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [Text.Encoding]::UTF8.GetBytes($value)
    return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

function Get-AudioInfo([string]$path) {
  $probeText = & ffprobe -v error -select_streams a:0 `
    -show_entries stream=codec_name,sample_rate,channels,bit_rate `
    -show_entries format=duration,bit_rate -of json $path
  if ($LASTEXITCODE -ne 0) { throw "ffprobe failed for $path" }
  $probe = $probeText | ConvertFrom-Json
  $stream = @($probe.streams)[0]
  $duration = [double]::Parse([string]$probe.format.duration, [Globalization.CultureInfo]::InvariantCulture)

  $volumeOutput = (& ffmpeg -hide_banner -nostats -i $path -af volumedetect -f null NUL 2>&1) -join "`n"
  $maxDb = if ($volumeOutput -match 'max_volume:\s*(-?[0-9.]+) dB') { [double]$Matches[1] } else { $null }
  $meanDb = if ($volumeOutput -match 'mean_volume:\s*(-?[0-9.]+) dB') { [double]$Matches[1] } else { $null }

  $flags = [Collections.Generic.List[string]]::new()
  if ([int]$stream.sample_rate -ne 44100) { $flags.Add('sample-rate-not-44100') }
  if ([int]$stream.channels -ne 1) { $flags.Add('not-mono') }
  if ($stream.codec_name -ne 'mp3') { $flags.Add('not-mp3') }
  # A single Vietnamese syllable can legitimately be about 0.4 seconds.
  if ($duration -lt 0.30) { $flags.Add('duration-too-short') }
  if ($duration -gt 8.0) { $flags.Add('duration-too-long') }
  if ($null -eq $maxDb) { $flags.Add('max-volume-unavailable') }
  elseif ($maxDb -ge -0.05) { $flags.Add('possible-clipping') }
  if ($null -eq $meanDb) { $flags.Add('mean-volume-unavailable') }
  elseif ($meanDb -lt -34.0) { $flags.Add('mean-volume-too-low') }

  return [pscustomobject]@{
    codec = [string]$stream.codec_name
    sampleRate = [int]$stream.sample_rate
    channels = [int]$stream.channels
    bitRate = [int]$(if ($stream.bit_rate) { $stream.bit_rate } else { $probe.format.bit_rate })
    durationSeconds = [math]::Round($duration, 3)
    maxDb = $maxDb
    meanDb = $meanDb
    qaFlags = @($flags)
  }
}

# The TXT is treated only as input data. Only bullet lines with the expected ID/text form are parsed.
$items = [Collections.Generic.List[object]]::new()
foreach ($line in (Get-Content -LiteralPath $InputPath -Encoding UTF8)) {
  if ($line -match '^-\s+(?<id>C\d+[^\s]*)\s+—\s+Bạn muốn diễn đạt:\s*[“"](?<target>.+?)[”"]\.\s*') {
    $items.Add([pscustomobject]@{
      order = $items.Count + 1
      questionId = [string]$Matches.id
      target = (($Matches.target -replace '\s+', ' ').Trim())
    })
  }
}
if ($items.Count -ne 68) { throw "Expected 68 parsed rows, found $($items.Count)." }
if (@($items.questionId | Sort-Object -Unique).Count -ne 68) { throw 'The input contains duplicate question IDs.' }

$catalogById = @{}
$catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($group in $catalog.groups) {
  foreach ($topic in $group.topics) {
    foreach ($lesson in $topic.lessons) {
      foreach ($challenge in $lesson.challengeBank) {
        $catalogById[[string]$challenge.id] = $challenge
      }
    }
  }
}
$catalogMismatches = [Collections.Generic.List[string]]::new()
foreach ($item in $items) {
  if (!$catalogById.ContainsKey($item.questionId)) {
    $catalogMismatches.Add("missing-id:$($item.questionId)")
    continue
  }
  $catalogTarget = [string]$catalogById[$item.questionId].correctVietnamese
  if ((Get-NormalizedTarget $catalogTarget) -ne (Get-NormalizedTarget $item.target)) {
    $catalogMismatches.Add("target-mismatch:$($item.questionId):$($item.target):$catalogTarget")
  }
}
if ($catalogMismatches.Count -gt 0) {
  throw "TXT/catalog validation failed:`n$($catalogMismatches -join "`n")"
}

New-Item -ItemType Directory -Path $rawRoot, $uniqueMp3Root, $uniqueWavRoot, $byQuestionRoot, $cacheRoot -Force | Out-Null

# Reuse only previously reviewed clips with the exact model/voice/speed and no QA flags.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$wantedByKey = @{}
foreach ($item in $items) { $wantedByKey[(Get-NormalizedTarget $item.target)] = $item.target }
$candidateByKey = @{}
$reviewZips = Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'outputs') -Recurse -File -Filter '*vi-review*.zip'
foreach ($zipFile in $reviewZips) {
  $zip = [IO.Compression.ZipFile]::OpenRead($zipFile.FullName)
  try {
    $manifestEntry = $zip.Entries | Where-Object FullName -like '*segments.json' | Select-Object -First 1
    if (!$manifestEntry) { continue }
    $reader = [IO.StreamReader]::new($manifestEntry.Open(), [Text.Encoding]::UTF8)
    try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
    foreach ($segment in $manifest.segments) {
      if ($segment.modelId -ne $modelId -or $segment.voiceId -ne $voiceId -or [double]$segment.speed -ne $speed) { continue }
      if (@($segment.qaFlags).Count -gt 0) { continue }
      $key = Get-NormalizedTarget ([string]$segment.speechText)
      if (!$wantedByKey.ContainsKey($key)) { continue }
      $entryName = ($manifestEntry.FullName -replace '[^/]+$', '') + [string]$segment.reviewAsset
      $rank = 100
      if ($zipFile.Name -match '13-15.*r2') { $rank = 10 }
      elseif ($zipFile.Name -match '8-10') { $rank = 20 }
      elseif ($zipFile.Name -match '6-7') { $rank = 30 }
      elseif ($zipFile.Name -match '11-12') { $rank = 40 }
      if (!$candidateByKey.ContainsKey($key) -or $rank -lt $candidateByKey[$key].rank) {
        $candidateByKey[$key] = [pscustomobject]@{
          rank = $rank
          zipPath = $zipFile.FullName
          entryName = $entryName
          sourceSegmentId = [string]$segment.segmentId
        }
      }
    }
  } finally {
    $zip.Dispose()
  }
}

$uniqueTargets = [Collections.Generic.List[object]]::new()
$uniqueByKey = @{}
foreach ($item in $items) {
  $key = Get-NormalizedTarget $item.target
  if ($uniqueByKey.ContainsKey($key)) { continue }
  $record = [pscustomobject]@{
    segmentId = ('VI68-{0:D3}' -f ($uniqueTargets.Count + 1))
    target = $item.target
    key = $key
    displayText = if ($IncludeMetaLead) { 'Bạn muốn diễn đạt: “{0}”' -f $item.target } else { $item.target }
    speechText = if ($IncludeMetaLead) { "Bạn muốn diễn đạt: $($item.target)." } else { "$($item.target)." }
    source = ''
    sourceDetail = ''
    rawPath = ''
    mp3Path = ''
    wavPath = ''
  }
  $uniqueTargets.Add($record)
  $uniqueByKey[$key] = $record
}

$generationRequests = [Collections.Generic.List[object]]::new()
foreach ($segment in $uniqueTargets) {
  $rawPath = Join-Path $rawRoot "$($segment.segmentId).mp3"
  $segment.rawPath = $rawPath
  if (!$IncludeMetaLead -and $candidateByKey.ContainsKey($segment.key)) {
    $candidate = $candidateByKey[$segment.key]
    $zip = [IO.Compression.ZipFile]::OpenRead($candidate.zipPath)
    try {
      $entry = $zip.GetEntry($candidate.entryName)
      if (!$entry) { throw "Missing ZIP entry $($candidate.entryName) in $($candidate.zipPath)" }
      [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $rawPath, $true)
    } finally {
      $zip.Dispose()
    }
    $segment.source = 'reviewed-reuse'
    $segment.sourceDetail = "$($candidate.zipPath)|$($candidate.sourceSegmentId)"
  } else {
    $cacheKey = Get-TextHash "$modelId|vi|$voiceId|$speed|$($segment.speechText)"
    $cachePath = Join-Path $cacheRoot "$cacheKey.mp3"
    $generationRequests.Add([pscustomobject]@{
      segmentId = $segment.segmentId
      text = $segment.speechText
      cachePath = $cachePath
      rawPath = $rawPath
      wasCached = (Test-Path -LiteralPath $cachePath)
      wasAlreadyOutput = (Test-Path -LiteralPath $rawPath)
    })
  }
}

$missingRequests = @($generationRequests | Where-Object { !$_.wasCached })
if ($missingRequests.Count -gt 0) {
  if (!(Test-Path -LiteralPath $ApiKeyPath)) { throw "ElevenLabs API key file not found: $ApiKeyPath" }
  $apiKey = (Get-Content -LiteralPath $ApiKeyPath -Raw).Trim()
  if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'The ElevenLabs API key file is empty.' }
  Write-Output "Generating $($missingRequests.Count) new Vietnamese clips with ElevenLabs..."
  $missingRequests | ForEach-Object -Parallel {
    $request = $_
    $headers = @{
      'xi-api-key' = $using:apiKey
      Accept = 'audio/mpeg'
      'Content-Type' = 'application/json'
    }
    $body = @{
      text = $request.text
      model_id = 'eleven_v3'
      language_code = 'vi'
      voice_settings = @{
        speed = 0.9
        stability = 0.5
        similarity_boost = 0.75
        use_speaker_boost = $true
      }
    } | ConvertTo-Json -Depth 5
    $uri = 'https://api.elevenlabs.io/v1/text-to-speech/5CVDNcIPiOYgRUQuxXd7?output_format=mp3_44100_128'
    $temporaryPath = "$($request.cachePath).partial.$([guid]::NewGuid().ToString('N'))"
    for ($attempt = 1; $attempt -le 6; $attempt++) {
      try {
        Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -Body $body -OutFile $temporaryPath
        if ((Get-Item -LiteralPath $temporaryPath).Length -lt 1024) { throw 'ElevenLabs returned an unexpectedly small audio file.' }
        Move-Item -LiteralPath $temporaryPath -Destination $request.cachePath -Force
        Write-Output "generated|$($request.segmentId)"
        break
      } catch {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
        if ($attempt -eq 6) { throw }
        Start-Sleep -Seconds ([math]::Min(20, [math]::Pow(2, $attempt)))
      }
    }
  } -ThrottleLimit $ThrottleLimit
}

foreach ($request in $generationRequests) {
  Copy-Item -LiteralPath $request.cachePath -Destination $request.rawPath
  $segment = $uniqueTargets | Where-Object segmentId -eq $request.segmentId | Select-Object -First 1
  $segment.source = if ($request.wasAlreadyOutput) { 'elevenlabs-new' } elseif ($request.wasCached) { 'tts-cache' } else { 'elevenlabs-new' }
  $segment.sourceDetail = $request.cachePath
}

$qaRows = [Collections.Generic.List[object]]::new()
foreach ($segment in $uniqueTargets) {
  $mp3Path = Join-Path $uniqueMp3Root "$($segment.segmentId).mp3"
  $wavPath = Join-Path $uniqueWavRoot "$($segment.segmentId).wav"
  $segment.mp3Path = $mp3Path
  $segment.wavPath = $wavPath

  if ($segment.source -eq 'reviewed-reuse') {
    Copy-Item -LiteralPath $segment.rawPath -Destination $mp3Path
    & ffmpeg -y -v error -i $mp3Path -ar 44100 -ac 1 -c:a pcm_s16le $wavPath
    if ($LASTEXITCODE -ne 0) { throw "Could not decode reviewed clip $($segment.segmentId)." }
  } else {
    $filter = 'highpass=f=55,lowpass=f=15000,silenceremove=start_periods=1:start_duration=0.02:start_threshold=-50dB,areverse,silenceremove=start_periods=1:start_duration=0.10:start_threshold=-50dB,areverse,apad=pad_dur=0.12,loudnorm=I=-16:TP=-1.0:LRA=11'
    & ffmpeg -y -v error -i $segment.rawPath -af $filter -ar 44100 -ac 1 -c:a pcm_s16le $wavPath
    if ($LASTEXITCODE -ne 0) { throw "Could not normalize $($segment.segmentId)." }
    & ffmpeg -y -v error -i $wavPath -ar 44100 -ac 1 -c:a libmp3lame -b:a 128k $mp3Path
    if ($LASTEXITCODE -ne 0) { throw "Could not encode $($segment.segmentId)." }
  }

  $info = Get-AudioInfo $mp3Path
  $qaRows.Add([pscustomobject]@{
    segmentId = $segment.segmentId
    target = $segment.target
    source = $segment.source
    file = "unique-vi-segments-mp3/$($segment.segmentId).mp3"
    durationSeconds = $info.durationSeconds
    codec = $info.codec
    sampleRate = $info.sampleRate
    channels = $info.channels
    bitRate = $info.bitRate
    maxDb = $info.maxDb
    meanDb = $info.meanDb
    sha256 = Get-Sha256 $mp3Path
    qaFlags = @($info.qaFlags)
  })
}

$failedQa = @($qaRows | Where-Object { @($_.qaFlags).Count -gt 0 })
if ($failedQa.Count -gt 0) {
  $failureText = ($failedQa | ForEach-Object { "$($_.segmentId):$($_.qaFlags -join ',')" }) -join "`n"
  throw "Technical audio QA failed:`n$failureText"
}

$questionRows = [Collections.Generic.List[object]]::new()
foreach ($item in $items) {
  $segment = $uniqueByKey[(Get-NormalizedTarget $item.target)]
  $fileName = if ($ExactQuestionIdFileNames) { "$($item.questionId).mp3" } else { "listening.challenge.$($item.questionId).prompt.vi.mp3" }
  $destination = Join-Path $byQuestionRoot $fileName
  Copy-Item -LiteralPath $segment.mp3Path -Destination $destination
  $qa = $qaRows | Where-Object segmentId -eq $segment.segmentId | Select-Object -First 1
  $questionRows.Add([pscustomobject]@{
    order = $item.order
    ageGroup = if ($item.questionId -like 'C1112-*') { '11-12' } else { '13-15' }
    questionId = $item.questionId
    target = $item.target
    segmentId = $segment.segmentId
    file = "by-question-id-mp3/$fileName"
    durationSeconds = $qa.durationSeconds
    sha256 = Get-Sha256 $destination
  })
}

$manifest = [ordered]@{
  schemaVersion = 1
  stage = if ($IncludeMetaLead) { 'full-vietnamese-meta-lead-review' } else { 'isolated-vietnamese-review' }
  sourceList = (Resolve-Path -LiteralPath $InputPath).Path
  sourceCatalog = (Resolve-Path -LiteralPath $catalogPath).Path
  itemCount = $items.Count
  uniqueTargetCount = $uniqueTargets.Count
  ageGroupCounts = [ordered]@{ '11-12' = @($items | Where-Object questionId -like 'C1112-*').Count; '13-15' = @($items | Where-Object questionId -like 'C1315-*').Count }
  modelId = $modelId
  voiceId = $voiceId
  speed = $speed
  outputProfile = [ordered]@{ format = 'mp3'; sampleRate = 44100; channels = 1; bitRate = 128000 }
  generatedAt = (Get-Date).ToUniversalTime().ToString('o')
  reviewedReuseCount = @($uniqueTargets | Where-Object source -eq 'reviewed-reuse').Count
  cacheReuseCount = @($uniqueTargets | Where-Object source -eq 'tts-cache').Count
  newlyGeneratedCount = @($uniqueTargets | Where-Object source -eq 'elevenlabs-new').Count
  qaFailureCount = $failedQa.Count
  uniqueSegments = @($uniqueTargets | ForEach-Object {
    $qa = $qaRows | Where-Object segmentId -eq $_.segmentId | Select-Object -First 1
    [ordered]@{
      segmentId = $_.segmentId
      target = $_.target
      displayText = $_.displayText
      speechText = $_.speechText
      source = $_.source
      sourceDetail = $_.sourceDetail
      reviewAsset = "unique-vi-segments-mp3/$($_.segmentId).mp3"
      wavAsset = "unique-vi-segments-wav/$($_.segmentId).wav"
      durationSeconds = $qa.durationSeconds
      sha256 = $qa.sha256
      qaFlags = @($qa.qaFlags)
    }
  })
  questions = @($questionRows)
}

$manifestPath = Join-Path $reviewRoot '68_vi_review_manifest.json'
$qaJsonPath = Join-Path $reviewRoot '68_vi_review_qa.json'
$qaCsvPath = Join-Path $reviewRoot '68_vi_review_qa.csv'
$listPath = Join-Path $reviewRoot '68_vi_review_list.txt'
$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
$qaRows | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $qaJsonPath -Encoding UTF8
$qaRows | Select-Object segmentId,target,source,file,durationSeconds,codec,sampleRate,channels,bitRate,maxDb,meanDb,sha256,@{n='qaFlags';e={$_.qaFlags -join '|'}} | Export-Csv -LiteralPath $qaCsvPath -NoTypeInformation -Encoding UTF8
$listLines = [Collections.Generic.List[string]]::new()
$currentAge = ''
foreach ($row in $questionRows) {
  if ($row.ageGroup -ne $currentAge) {
    if ($listLines.Count -gt 0) { $listLines.Add('') }
    $currentAge = $row.ageGroup
    $listLines.Add("PHẠM VI $currentAge TUỔI")
  }
  $listLines.Add(("{0:D2}. {1} | {2} | {3}" -f $row.order, $row.questionId, $row.target, $row.file))
}
$listLines | Set-Content -LiteralPath $listPath -Encoding UTF8

$zipPath = Join-Path $OutputRoot "$reviewName.zip"
Compress-Archive -LiteralPath $reviewRoot -DestinationPath $zipPath -CompressionLevel Optimal

[pscustomobject]@{
  outputRoot = $OutputRoot
  reviewRoot = $reviewRoot
  zipPath = $zipPath
  itemCount = $items.Count
  uniqueTargetCount = $uniqueTargets.Count
  reviewedReuseCount = $manifest.reviewedReuseCount
  cacheReuseCount = $manifest.cacheReuseCount
  newlyGeneratedCount = $manifest.newlyGeneratedCount
  qaFailureCount = $manifest.qaFailureCount
} | ConvertTo-Json -Depth 4
