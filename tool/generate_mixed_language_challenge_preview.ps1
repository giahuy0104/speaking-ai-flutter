param(
  [string]$ApiKeyPath = 'C:\Users\DELL\Documents\api_key_elevanlabs.txt',
  [string]$AgeGroup = '3-5',
  [int]$TopicNumber = 1,
  [string]$OutputRoot = 'outputs\challenge-preview-3-5-topic-01',
  [string]$ConnectorAudioPath,
  [ValidateRange(1, 8)][int]$ThrottleLimit = 3
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$outputRootPath = if ([IO.Path]::IsPathRooted($OutputRoot)) {
  $OutputRoot
} else {
  Join-Path $repositoryRoot $OutputRoot
}
$pack = "challenge-$AgeGroup"
$outputDirectory = Join-Path $outputRootPath $pack
$cacheDirectory = Join-Path $repositoryRoot 'build\mixed-challenge-preview-cache'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null

$providedConnectorPath = $null
if (![string]::IsNullOrWhiteSpace($ConnectorAudioPath)) {
  $sourceConnector = [IO.Path]::GetFullPath($ConnectorAudioPath)
  if (!(Test-Path -LiteralPath $sourceConnector)) { throw "Connector audio was not found: $sourceConnector" }
  $sourceHash = (Get-FileHash -LiteralPath $sourceConnector -Algorithm SHA256).Hash.ToLowerInvariant()
  $providedConnectorPath = Join-Path $cacheDirectory "provided-hay-$sourceHash.mp3"
  if (!(Test-Path -LiteralPath $providedConnectorPath)) {
    & ffmpeg -y -v error -i $sourceConnector -vn -ar 44100 -ac 1 -codec:a libmp3lame -b:a 128k $providedConnectorPath
    if ($LASTEXITCODE -ne 0) { throw 'Could not extract the provided connector audio.' }
  }
}

$apiKey = (Get-Content -LiteralPath $ApiKeyPath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'The ElevenLabs API key file is empty.' }

$profiles = @{
  vi = @{ VoiceId = '5CVDNcIPiOYgRUQuxXd7'; Speed = 0.9; Locale = 'vi-VN' }
  en = @{ VoiceId = 'Nhs7eitvQWFTQBsf0yiT'; Speed = 0.75; Locale = 'en-US' }
}

function Normalize([string]$text) { return ($text -replace '\s+', ' ').Trim() }
function Hash([string]$text) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-', '').ToLowerInvariant()
  } finally { $sha.Dispose() }
}
function Duration([string]$path) {
  $value = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $path
  if ($LASTEXITCODE -ne 0) { throw "ffprobe could not read $path" }
  return [math]::Round([double]::Parse($value.Trim(), [Globalization.CultureInfo]::InvariantCulture), 3)
}

function Split-Prompt([string]$prompt, [object[]]$choices) {
  $ranges = @()
  foreach ($choice in $choices) {
    $needle = (Normalize ([string]$choice)).TrimEnd('.', '?', '!')
    if ([string]::IsNullOrWhiteSpace($needle)) { continue }
    $start = 0
    while ($start -lt $prompt.Length) {
      $index = $prompt.IndexOf($needle, $start, [StringComparison]::OrdinalIgnoreCase)
      if ($index -lt 0) { break }
      $end = $index + $needle.Length
      while ($end -lt $prompt.Length -and '.,?!'.Contains($prompt[$end])) { $end++ }
      $ranges += [pscustomobject]@{ Start = $index; End = $end }
      $start = $end
    }
  }
  $ranges = @($ranges | Sort-Object Start, End -Unique)
  $segments = @()
  $cursor = 0
  foreach ($range in $ranges) {
    if ($range.Start -lt $cursor) { continue }
    if ($range.Start -gt $cursor) {
      $vi = Normalize $prompt.Substring($cursor, $range.Start - $cursor)
      if ($vi) { $segments += [pscustomobject]@{ Language = 'vi'; Text = $vi } }
    }
    $en = Normalize $prompt.Substring($range.Start, $range.End - $range.Start)
    if ($en) { $segments += [pscustomobject]@{ Language = 'en'; Text = $en } }
    $cursor = $range.End
  }
  if ($cursor -lt $prompt.Length) {
    $tail = Normalize $prompt.Substring($cursor)
    if ($tail -and $tail -match '^\p{P}+$' -and $segments.Count -gt 0) {
      $segments[-1].Text += $tail
    } elseif ($tail) {
      $segments += [pscustomobject]@{ Language = 'vi'; Text = $tail }
    }
  }
  return $segments
}

$catalog = Get-Content -LiteralPath (Join-Path $repositoryRoot 'assets\data\listening_lessons.json') -Raw | ConvertFrom-Json
$parts = $AgeGroup.Split('-')
$group = $catalog.groups | Where-Object { $_.startAge -eq [int]$parts[0] -and $_.endAge -eq [int]$parts[1] }
$topic = $group.topics | Where-Object { $_.number -eq $TopicNumber }
if ($null -eq $topic) { throw "Topic $TopicNumber was not found for age group $AgeGroup." }

$items = @()
$requests = @{}
foreach ($lesson in $topic.lessons) {
  foreach ($challenge in $lesson.challengeBank) {
    $segments = @(Split-Prompt (Normalize ([string]$challenge.prompt)) @($challenge.choices))
    $answer = Normalize ([string]$challenge.correctAnswer)
    $items += [pscustomobject]@{ Challenge = $challenge; Segments = $segments; Answer = $answer }
    foreach ($segment in $segments) {
      $profile = $profiles[$segment.Language]
      # Keep the Vietnamese connector as its own explicitly versioned clip so
      # it can never be reused from an English or whole-prompt rendition.
      $connectorProfile = if ($segment.Language -eq 'vi' -and $segment.Text -eq 'hay') { 'vi-connector-v2' } else { 'default' }
      $cacheKey = Hash "eleven_v3|$($segment.Language)|$($profile.VoiceId)|$($profile.Speed)|$connectorProfile|$($segment.Text)"
      $usesProvidedConnector = $segment.Language -eq 'vi' -and $segment.Text -eq 'hay' -and $null -ne $providedConnectorPath
      $requests[$cacheKey] = [pscustomobject]@{ Language=$segment.Language; Text=$segment.Text; VoiceId=$profile.VoiceId; Speed=$profile.Speed; Path=$(if ($usesProvidedConnector) { $providedConnectorPath } else { Join-Path $cacheDirectory "$cacheKey.mp3" }); Provided=$usesProvidedConnector }
      $segment | Add-Member -NotePropertyName CacheKey -NotePropertyValue $cacheKey
      $segment | Add-Member -NotePropertyName Provided -NotePropertyValue $usesProvidedConnector
    }
    $profile = $profiles.en
    $answerKey = Hash "eleven_v3|en|$($profile.VoiceId)|$($profile.Speed)|$answer"
    $requests[$answerKey] = [pscustomobject]@{ Language='en'; Text=$answer; VoiceId=$profile.VoiceId; Speed=$profile.Speed; Path=(Join-Path $cacheDirectory "$answerKey.mp3") }
    $items[-1] | Add-Member -NotePropertyName AnswerKey -NotePropertyValue $answerKey
  }
}

Write-Output "Generating $($requests.Count) unique language-specific clips for $($items.Count) challenges."
@($requests.Values) | ForEach-Object -Parallel {
  $request = $_
  if ($request.Provided) { return }
  if ((Test-Path -LiteralPath $request.Path) -and (Get-Item -LiteralPath $request.Path).Length -ge 512) { return }
  $headers = @{ 'xi-api-key'=$using:apiKey; Accept='audio/mpeg'; 'Content-Type'='application/json' }
  # ElevenLabs can return an empty stream for a very short fragment ending in
  # a colon (for example "Kem:"). A full stop preserves the intended pause
  # while giving the model a speakable terminal boundary.
  $speechText = if ($request.Text.EndsWith(':')) { $request.Text.TrimEnd(':') + '.' } else { $request.Text }
  $body = @{ text=$speechText; model_id='eleven_v3'; language_code=$request.Language; voice_settings=@{ speed=$request.Speed; stability=0.5; similarity_boost=0.75; use_speaker_boost=$true } } | ConvertTo-Json -Depth 5
  for ($attempt = 1; $attempt -le 5; $attempt++) {
    try {
      Invoke-WebRequest -Uri "https://api.elevenlabs.io/v1/text-to-speech/$($request.VoiceId)?output_format=mp3_44100_128" -Method Post -Headers $headers -Body $body -OutFile $request.Path
      if ((Get-Item -LiteralPath $request.Path).Length -lt 512) { throw "Invalid audio for $($request.Text)" }
      break
    } catch {
      if (Test-Path -LiteralPath $request.Path) { Remove-Item -LiteralPath $request.Path -Force }
      if ($attempt -eq 5) { throw }
      Start-Sleep -Seconds ([math]::Pow(2, $attempt))
    }
  }
} -ThrottleLimit $ThrottleLimit

$entries = @()
foreach ($item in $items) {
  $id = [string]$item.Challenge.id
  $promptName = "listening.challenge.$id.prompt.vi.mp3"
  $promptPath = Join-Path $outputDirectory $promptName
  $concatPath = Join-Path $cacheDirectory "$id.concat.txt"
  @($item.Segments | ForEach-Object { "file '$($requests[$_.CacheKey].Path.Replace("'", "'\''"))'" }) | Set-Content -LiteralPath $concatPath -Encoding utf8
  & ffmpeg -y -v error -f concat -safe 0 -i $concatPath -ar 44100 -ac 1 -codec:a libmp3lame -b:a 128k $promptPath
  if ($LASTEXITCODE -ne 0) { throw "Could not assemble $promptName" }

  $answerName = "listening.challenge.$id.answer.en.mp3"
  $answerPath = Join-Path $outputDirectory $answerName
  Copy-Item -LiteralPath $requests[$item.AnswerKey].Path -Destination $answerPath -Force
  foreach ($spec in @(
    @{ Key="listening.challenge.$id.prompt.vi"; Name=$promptName; Path=$promptPath; Language='mixed'; Locale='vi-VN'; Text=(Normalize ([string]$item.Challenge.prompt)); VoiceId=$profiles.vi.VoiceId; Speed=$profiles.vi.Speed; Segments=$item.Segments },
    @{ Key="listening.challenge.$id.answer.en"; Name=$answerName; Path=$answerPath; Language='en'; Locale='en-US'; Text=$item.Answer; VoiceId=$profiles.en.VoiceId; Speed=$profiles.en.Speed; Segments=@([pscustomobject]@{Language='en';Text=$item.Answer}) }
  )) {
    $entries += [ordered]@{ key=$spec.Key; enabled=$true; locale=$spec.Locale; asset="$pack/$($spec.Name)"; durationSeconds=(Duration $spec.Path); sha256=(Get-FileHash $spec.Path -Algorithm SHA256).Hash.ToLowerInvariant(); modelId='eleven_v3'; language=$spec.Language; voiceId=$spec.VoiceId; speed=$spec.Speed; sizeBytes=(Get-Item $spec.Path).Length; textHash=(Hash $spec.Text); segments=@($spec.Segments | ForEach-Object { $p=$profiles[$_.Language]; [ordered]@{ language=$_.Language; text=$_.Text; voiceId=$(if ($_.Provided) { 'provided-audio' } else { $p.VoiceId }); speed=$(if ($_.Provided) { 1.0 } else { $p.Speed }); source=$(if ($_.Provided) { [IO.Path]::GetFileName($ConnectorAudioPath) } else { 'elevenlabs' }) } }) }
  }
}

$manifest = [ordered]@{ schemaVersion=1; pack=$pack; enabled=$true; ageGroup=$AgeGroup; topicNumber=$TopicNumber; topicTitleVi=$topic.titleVi; topicTitleEn=$topic.titleEn; prompts=$entries }
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outputRootPath "challenge_$($AgeGroup.Replace('-', '_'))_audio.json") -Encoding utf8
Write-Output "Created $($entries.Count) mixed-language preview files in $outputRootPath."
