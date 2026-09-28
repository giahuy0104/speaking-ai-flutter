param(
  [string]$InputListPath = 'C:\Users\DELL\Downloads\68-cau-audio-bi-rut-gon.txt',
  [string]$VietnameseSourceDirectory = 'D:\Code\HuaMei\App_noi\flutter\23_23th9\speaking-ai-flutter\outputs\challenge-vi-full-68-20260928-r1\68-full-vi-review-r1\by-question-id-mp3',
  [string]$ConnectorPath = 'C:\Users\DELL\Downloads\0926.mp4',
  [string]$OutputRoot = '',
  [string]$ReviewName = '68-merged-prompts-r1'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = Join-Path $repositoryRoot 'outputs\challenge-prompts-full-68-20260928-r1'
}
$reviewRoot = Join-Path $OutputRoot $ReviewName
$finalRoot = Join-Path $reviewRoot 'merged-audio-mp3'
$segmentRoot = Join-Path $OutputRoot '.segments'
$viWavRoot = Join-Path $segmentRoot 'vi-wav'
$enWavRoot = Join-Path $segmentRoot 'en-wav'
$sharedRoot = Join-Path $segmentRoot 'shared'
$englishCacheRoot = Join-Path $repositoryRoot 'build\mixed-challenge-preview-cache'

if (!(Test-Path -LiteralPath $InputListPath)) { throw "Input list not found: $InputListPath" }
if (!(Test-Path -LiteralPath $VietnameseSourceDirectory)) { throw "Vietnamese source directory not found: $VietnameseSourceDirectory" }
if (!(Test-Path -LiteralPath $ConnectorPath)) { throw "Connector source not found: $ConnectorPath" }
if (!(Test-Path -LiteralPath $englishCacheRoot)) { throw "English cache not found: $englishCacheRoot" }
if (Test-Path -LiteralPath $OutputRoot) { throw "Output already exists; choose a new revision: $OutputRoot" }
if (!(Get-Command ffmpeg -ErrorAction SilentlyContinue)) { throw 'ffmpeg is required.' }
if (!(Get-Command ffprobe -ErrorAction SilentlyContinue)) { throw 'ffprobe is required.' }

function Get-Sha256([string]$path) {
  return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TextHash([string]$value) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($value)))).Replace('-', '').ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

function Read-ZipJson([string]$zipPath, [string]$entryPattern) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $zipPath))
  try {
    $entry = $zip.Entries | Where-Object FullName -like $entryPattern | Select-Object -First 1
    if (!$entry) { throw "No ZIP entry matching $entryPattern in $zipPath" }
    $reader = [IO.StreamReader]::new($entry.Open(), [Text.Encoding]::UTF8)
    try { return ($reader.ReadToEnd() | ConvertFrom-Json) } finally { $reader.Dispose() }
  } finally {
    $zip.Dispose()
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
  $volumeText = (& ffmpeg -hide_banner -nostats -i $path -af volumedetect -f null NUL 2>&1) -join "`n"
  $maxDb = if ($volumeText -match 'max_volume:\s*(-?[0-9.]+) dB') { [double]$Matches[1] } else { $null }
  $meanDb = if ($volumeText -match 'mean_volume:\s*(-?[0-9.]+) dB') { [double]$Matches[1] } else { $null }
  return [pscustomobject]@{
    codec = [string]$stream.codec_name
    sampleRate = [int]$stream.sample_rate
    channels = [int]$stream.channels
    bitRate = [int]$(if ($stream.bit_rate) { $stream.bit_rate } else { $probe.format.bit_rate })
    durationSeconds = [math]::Round($duration, 3)
    maxDb = $maxDb
    meanDb = $meanDb
  }
}

$items = [Collections.Generic.List[object]]::new()
foreach ($line in (Get-Content -LiteralPath $InputListPath -Encoding UTF8)) {
  if ($line -match '^-\s+(?<id>C\d+[^\s]*)\s+—\s+Bạn muốn diễn đạt:\s*[“"](?<target>.+?)[”"]\.\s*') {
    $items.Add([pscustomobject]@{
      order = $items.Count + 1
      questionId = [string]$Matches.id
      target = (($Matches.target -replace '\s+', ' ').Trim())
    })
  }
}
if ($items.Count -ne 68) { throw "Expected 68 list entries, found $($items.Count)." }
if (@($items.questionId | Sort-Object -Unique).Count -ne 68) { throw 'The input list contains duplicate question IDs.' }

$sourceFiles = @(Get-ChildItem -LiteralPath $VietnameseSourceDirectory -File -Filter '*.mp3')
if ($sourceFiles.Count -ne 68) { throw "Expected 68 Vietnamese source files, found $($sourceFiles.Count)." }
foreach ($item in $items) {
  $expectedPath = Join-Path $VietnameseSourceDirectory "$($item.questionId).mp3"
  if (!(Test-Path -LiteralPath $expectedPath)) { throw "Missing Vietnamese source: $expectedPath" }
}

$sourceManifestPath = Join-Path (Split-Path -Parent $VietnameseSourceDirectory) '68_vi_review_manifest.json'
if (!(Test-Path -LiteralPath $sourceManifestPath)) { throw "Vietnamese source manifest not found: $sourceManifestPath" }
$sourceManifest = Get-Content -LiteralPath $sourceManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($sourceManifest.stage -ne 'full-vietnamese-meta-lead-review' -or $sourceManifest.itemCount -ne 68 -or $sourceManifest.qaFailureCount -ne 0) {
  throw 'The selected Vietnamese source directory is not the approved full-meta-lead review set.'
}
foreach ($item in $items) {
  $sourceQuestion = $sourceManifest.questions | Where-Object questionId -eq $item.questionId | Select-Object -First 1
  if (!$sourceQuestion -or $sourceQuestion.target -ne $item.target) {
    throw "Vietnamese source manifest mismatch for $($item.questionId)."
  }
}

$ageSources = @(
  [pscustomobject]@{
    ageGroup = '11-12'
    zipPath = Join-Path $repositoryRoot 'outputs\challenge-prompts-c1112-20260926-r1\challenge-11-12-prompts-r1-natural-pauses.zip'
  },
  [pscustomobject]@{
    ageGroup = '13-15'
    zipPath = Join-Path $repositoryRoot 'outputs\challenge-prompts-c1315-20260926-r2\challenge-13-15-prompts-r2-natural-pauses.zip'
  }
)

$promptById = @{}
$englishById = @{}
$sourcePromptManifestByAge = @{}
foreach ($ageSource in $ageSources) {
  if (!(Test-Path -LiteralPath $ageSource.zipPath)) { throw "Prior prompt pack not found: $($ageSource.zipPath)" }
  $promptManifest = Read-ZipJson $ageSource.zipPath '*prompts_audio.json'
  $englishManifest = Read-ZipJson $ageSource.zipPath '*en_segments.json'
  $sourcePromptManifestByAge[$ageSource.ageGroup] = $promptManifest
  foreach ($prompt in $promptManifest.prompts) {
    if ($prompt.key -match '^listening\.challenge\.(?<id>.+)\.prompt\.vi$') {
      $promptById[[string]$Matches.id] = $prompt
    }
  }
  foreach ($segment in $englishManifest.segments) {
    if (@($segment.qaFlags).Count -gt 0) { throw "Prior English QA failed for $($segment.segmentId)." }
    $englishById[[string]$segment.segmentId] = $segment
  }
}

foreach ($item in $items) {
  if (!$promptById.ContainsKey($item.questionId)) { throw "No prior assembly mapping for $($item.questionId)." }
  $segments = @($promptById[$item.questionId].segments)
  if ($segments.Count -ne 4 -or $segments[0].language -ne 'vi' -or $segments[1].language -ne 'en' -or $segments[2].text -ne 'hay' -or $segments[3].language -ne 'en') {
    throw "Unexpected segment structure for $($item.questionId)."
  }
  foreach ($index in @(1, 3)) {
    if (!$englishById.ContainsKey([string]$segments[$index].segmentId)) {
      throw "Missing English segment $($segments[$index].segmentId) for $($item.questionId)."
    }
  }
}

New-Item -ItemType Directory -Path $finalRoot, $viWavRoot, $enWavRoot, $sharedRoot -Force | Out-Null

$pause038Path = Join-Path $sharedRoot 'silence-0.38.wav'
$pause024Path = Join-Path $sharedRoot 'silence-0.24.wav'
& ffmpeg -y -v error -f lavfi -i 'anullsrc=r=44100:cl=mono' -t 0.38 -c:a pcm_s16le $pause038Path
if ($LASTEXITCODE -ne 0) { throw 'Could not create the 0.38-second pause.' }
& ffmpeg -y -v error -f lavfi -i 'anullsrc=r=44100:cl=mono' -t 0.24 -c:a pcm_s16le $pause024Path
if ($LASTEXITCODE -ne 0) { throw 'Could not create the 0.24-second pause.' }

$connectorDurationText = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $ConnectorPath
if ($LASTEXITCODE -ne 0) { throw 'Could not probe the connector source.' }
$connectorSourceDuration = [double]::Parse($connectorDurationText.Trim(), [Globalization.CultureInfo]::InvariantCulture)
$connectorTrimSeconds = 0.064
$connectorDuration = [math]::Round($connectorSourceDuration - $connectorTrimSeconds, 6)
$connectorWavPath = Join-Path $sharedRoot 'hay-trimmed.wav'
& ffmpeg -y -v error -i $ConnectorPath -af "atrim=0:$connectorDuration,asetpts=N/SR/TB" -ar 44100 -ac 1 -c:a pcm_s16le $connectorWavPath
if ($LASTEXITCODE -ne 0) { throw 'Could not prepare the connector audio.' }

$englishSegmentIds = [Collections.Generic.HashSet[string]]::new()
foreach ($item in $items) {
  $segments = @($promptById[$item.questionId].segments)
  [void]$englishSegmentIds.Add([string]$segments[1].segmentId)
  [void]$englishSegmentIds.Add([string]$segments[3].segmentId)
}
foreach ($segmentId in $englishSegmentIds) {
  $segment = $englishById[$segmentId]
  $cachePath = Join-Path $englishCacheRoot "$($segment.cacheKey).mp3"
  if (!(Test-Path -LiteralPath $cachePath)) { throw "Missing English cache audio: $cachePath" }
  $wavPath = Join-Path $enWavRoot "$segmentId.wav"
  $duration = [double]$segment.durationSeconds
  & ffmpeg -y -v error -i $cachePath -af "atrim=0:$duration,asetpts=N/SR/TB" -ar 44100 -ac 1 -c:a pcm_s16le $wavPath
  if ($LASTEXITCODE -ne 0) { throw "Could not prepare English segment $segmentId." }
}

$qaRows = [Collections.Generic.List[object]]::new()
$promptRows = [Collections.Generic.List[object]]::new()
foreach ($item in $items) {
  $priorPrompt = $promptById[$item.questionId]
  $priorSegments = @($priorPrompt.segments)
  $viSourcePath = Join-Path $VietnameseSourceDirectory "$($item.questionId).mp3"
  $viWavPath = Join-Path $viWavRoot "$($item.questionId).wav"
  & ffmpeg -y -v error -i $viSourcePath -ar 44100 -ac 1 -c:a pcm_s16le $viWavPath
  if ($LASTEXITCODE -ne 0) { throw "Could not decode Vietnamese source for $($item.questionId)." }

  $en1 = $englishById[[string]$priorSegments[1].segmentId]
  $en2 = $englishById[[string]$priorSegments[3].segmentId]
  $en1Wav = Join-Path $enWavRoot "$($en1.segmentId).wav"
  $en2Wav = Join-Path $enWavRoot "$($en2.segmentId).wav"
  $fileName = "listening.challenge.$($item.questionId).prompt.vi.mp3"
  $finalPath = Join-Path $finalRoot $fileName

  & ffmpeg -y -v error `
    -i $viWavPath -i $pause038Path -i $en1Wav -i $pause024Path `
    -i $connectorWavPath -i $pause024Path -i $en2Wav `
    -filter_complex '[0:a][1:a][2:a][3:a][4:a][5:a][6:a]concat=n=7:v=0:a=1[out]' `
    -map '[out]' -ar 44100 -ac 1 -c:a libmp3lame -b:a 128k $finalPath
  if ($LASTEXITCODE -ne 0) { throw "Could not assemble $($item.questionId)." }

  $viInfo = Get-AudioInfo $viSourcePath
  $finalInfo = Get-AudioInfo $finalPath
  $expectedDuration = $viInfo.durationSeconds + 0.38 + [double]$en1.durationSeconds + 0.24 + $connectorDuration + 0.24 + [double]$en2.durationSeconds
  $durationDelta = [math]::Abs($finalInfo.durationSeconds - $expectedDuration)
  $flags = [Collections.Generic.List[string]]::new()
  if ($finalInfo.codec -ne 'mp3') { $flags.Add('not-mp3') }
  if ($finalInfo.sampleRate -ne 44100) { $flags.Add('sample-rate-not-44100') }
  if ($finalInfo.channels -ne 1) { $flags.Add('not-mono') }
  if ($durationDelta -gt 0.10) { $flags.Add('duration-mismatch') }
  if ($null -eq $finalInfo.maxDb) { $flags.Add('max-volume-unavailable') }
  elseif ($finalInfo.maxDb -ge -0.05) { $flags.Add('possible-clipping') }
  if ($null -eq $finalInfo.meanDb) { $flags.Add('mean-volume-unavailable') }
  elseif ($finalInfo.meanDb -lt -34.0) { $flags.Add('mean-volume-too-low') }

  $qaRows.Add([pscustomobject]@{
    order = $item.order
    questionId = $item.questionId
    file = "merged-audio-mp3/$fileName"
    durationSeconds = $finalInfo.durationSeconds
    expectedDurationSeconds = [math]::Round($expectedDuration, 3)
    durationDeltaSeconds = [math]::Round($durationDelta, 3)
    codec = $finalInfo.codec
    sampleRate = $finalInfo.sampleRate
    channels = $finalInfo.channels
    bitRate = $finalInfo.bitRate
    maxDb = $finalInfo.maxDb
    meanDb = $finalInfo.meanDb
    sizeBytes = (Get-Item -LiteralPath $finalPath).Length
    sha256 = Get-Sha256 $finalPath
    qaFlags = @($flags)
  })

  $promptRows.Add([pscustomobject]@{
    order = $item.order
    ageGroup = if ($item.questionId -like 'C1112-*') { '11-12' } else { '13-15' }
    questionId = $item.questionId
    key = "listening.challenge.$($item.questionId).prompt.vi"
    target = $item.target
    vietnameseText = 'Bạn muốn diễn đạt: “{0}”' -f $item.target
    englishFirst = [string]$en1.text
    connectorText = 'hay'
    englishSecond = [string]$en2.text
    asset = "merged-audio-mp3/$fileName"
    vietnameseSource = $viSourcePath
    vietnameseSourceSha256 = Get-Sha256 $viSourcePath
    segments = @(
      [ordered]@{ language = 'vi'; text = 'Bạn muốn diễn đạt: “{0}”' -f $item.target; source = 'provided-full-vi-directory'; pauseAfterSeconds = 0.38 },
      [ordered]@{ language = 'en'; text = [string]$en1.text; segmentId = [string]$en1.segmentId; voiceId = [string]$en1.voiceId; speed = [double]$en1.speed; pauseAfterSeconds = 0.24 },
      [ordered]@{ language = 'vi'; text = 'hay'; source = 'provided-0926.mp4'; pauseAfterSeconds = 0.24 },
      [ordered]@{ language = 'en'; text = [string]$en2.text; segmentId = [string]$en2.segmentId; voiceId = [string]$en2.voiceId; speed = [double]$en2.speed; pauseAfterSeconds = 0.0 }
    )
  })
}

$failedQa = @($qaRows | Where-Object { @($_.qaFlags).Count -gt 0 })
if ($failedQa.Count -gt 0) {
  $failureText = ($failedQa | ForEach-Object { "$($_.questionId):$($_.qaFlags -join ',')" }) -join "`n"
  throw "Final prompt QA failed:`n$failureText"
}

$manifest = [ordered]@{
  schemaVersion = 1
  stage = 'mixed-challenge-prompts-from-full-vietnamese-source'
  inputList = (Resolve-Path -LiteralPath $InputListPath).Path
  vietnameseSourceDirectory = (Resolve-Path -LiteralPath $VietnameseSourceDirectory).Path
  vietnameseSourceManifest = (Resolve-Path -LiteralPath $sourceManifestPath).Path
  connectorSource = (Resolve-Path -LiteralPath $ConnectorPath).Path
  connectorSha256 = Get-Sha256 $ConnectorPath
  connectorTrimmedTailSeconds = $connectorTrimSeconds
  pauseProfile = [ordered]@{ afterVietnameseSeconds = 0.38; beforeConnectorSeconds = 0.24; afterConnectorSeconds = 0.24 }
  outputProfile = [ordered]@{ format = 'mp3'; sampleRate = 44100; channels = 1; bitRate = 128000 }
  promptCount = $promptRows.Count
  ageGroupCounts = [ordered]@{ '11-12' = @($promptRows | Where-Object ageGroup -eq '11-12').Count; '13-15' = @($promptRows | Where-Object ageGroup -eq '13-15').Count }
  englishUniqueSegmentCount = $englishSegmentIds.Count
  generatedAt = (Get-Date).ToUniversalTime().ToString('o')
  qaFailureCount = $failedQa.Count
  prompts = @($promptRows | ForEach-Object {
    $qa = $qaRows | Where-Object questionId -eq $_.questionId | Select-Object -First 1
    [ordered]@{
      order = $_.order
      ageGroup = $_.ageGroup
      questionId = $_.questionId
      key = $_.key
      target = $_.target
      vietnameseText = $_.vietnameseText
      englishFirst = $_.englishFirst
      connectorText = $_.connectorText
      englishSecond = $_.englishSecond
      asset = $_.asset
      durationSeconds = $qa.durationSeconds
      sha256 = $qa.sha256
      vietnameseSource = $_.vietnameseSource
      vietnameseSourceSha256 = $_.vietnameseSourceSha256
      segments = $_.segments
      qaFlags = @($qa.qaFlags)
    }
  })
}

$manifestPath = Join-Path $reviewRoot '68_merged_prompts_manifest.json'
$qaJsonPath = Join-Path $reviewRoot '68_merged_prompts_qa.json'
$qaCsvPath = Join-Path $reviewRoot '68_merged_prompts_qa.csv'
$listPath = Join-Path $reviewRoot '68_merged_prompts_list.txt'
$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
$qaRows | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $qaJsonPath -Encoding UTF8
$qaRows | Select-Object order,questionId,file,durationSeconds,expectedDurationSeconds,durationDeltaSeconds,codec,sampleRate,channels,bitRate,maxDb,meanDb,sizeBytes,sha256,@{n='qaFlags';e={$_.qaFlags -join '|'}} | Export-Csv -LiteralPath $qaCsvPath -NoTypeInformation -Encoding UTF8
$listLines = $promptRows | ForEach-Object { "{0:D2}. {1} | {2} / {3} / hay / {4} | {5}" -f $_.order, $_.questionId, $_.vietnameseText, $_.englishFirst, $_.englishSecond, $_.asset }
$listLines | Set-Content -LiteralPath $listPath -Encoding UTF8

$zipPath = Join-Path $OutputRoot "$ReviewName.zip"
Compress-Archive -LiteralPath $reviewRoot -DestinationPath $zipPath -CompressionLevel Optimal

[pscustomobject]@{
  outputRoot = $OutputRoot
  reviewRoot = $reviewRoot
  audioDirectory = $finalRoot
  zipPath = $zipPath
  promptCount = $promptRows.Count
  age1112Count = @($promptRows | Where-Object ageGroup -eq '11-12').Count
  age1315Count = @($promptRows | Where-Object ageGroup -eq '13-15').Count
  englishUniqueSegmentCount = $englishSegmentIds.Count
  qaFailureCount = $failedQa.Count
} | ConvertTo-Json -Depth 4
