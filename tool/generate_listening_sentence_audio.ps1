param(
  [string]$ApiKeyPath = 'C:\Users\DELL\Documents\api_key_elevanlabs.txt',
  [ValidateRange(1, 8)]
  [int]$ThrottleLimit = 3
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$catalogPath = Join-Path $repositoryRoot 'assets\data\listening_lessons.json'
$cacheDirectory = Join-Path $repositoryRoot 'build\listening-sentence-tts-cache'
$apiKey = (Get-Content -LiteralPath $ApiKeyPath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($apiKey)) {
  throw 'The ElevenLabs API key file is empty.'
}

$voiceByLanguage = @{ en = 'Nhs7eitvQWFTQBsf0yiT'; vi = '5CVDNcIPiOYgRUQuxXd7' }
$speedByLanguage = @{ en = 0.75; vi = 0.9 }
$packByAge = @{
  '3-5' = 'listening-3-5'
  '6-7' = 'listening-6-7'
  '8-10' = 'listening-8-10'
  '11-12' = 'listening-11-12'
  '13-15' = 'listening-13-15'
}
$manifestNameByAge = @{
  '3-5' = 'listening_3_5_audio.json'
  '6-7' = 'listening_6_7_audio.json'
  '8-10' = 'listening_8_10_audio.json'
  '11-12' = 'listening_11_12_audio.json'
  '13-15' = 'listening_13_15_audio.json'
}

New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null

function Get-TextHash([string]$value) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [Text.Encoding]::UTF8.GetBytes($value)
    return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

function Get-NormalizedText([string]$value) {
  return ($value -replace '\s+', ' ').Trim()
}

function Get-DurationSeconds([string]$path) {
  $durationText = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $path
  if ($LASTEXITCODE -ne 0) {
    throw "ffprobe could not read $path."
  }
  return [math]::Round(
    [double]::Parse($durationText.Trim(), [Globalization.CultureInfo]::InvariantCulture),
    3
  )
}

$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
$requestsByCacheKey = @{}
foreach ($group in $catalog.groups) {
  foreach ($topic in $group.topics) {
    foreach ($lesson in $topic.lessons) {
      foreach ($sentence in $lesson.sentences) {
        foreach ($language in @('en', 'vi')) {
          $text = if ($language -eq 'en') { $sentence.english } else { $sentence.vietnamese }
          $normalized = Get-NormalizedText ([string]$text)
          if ([string]::IsNullOrWhiteSpace($normalized)) {
            throw "Sentence $($sentence.id) has empty $language text."
          }
          $voiceId = $voiceByLanguage[$language]
          $speed = $speedByLanguage[$language]
          $cacheKey = Get-TextHash "eleven_v3|$language|$voiceId|$speed|$normalized"
          if (!$requestsByCacheKey.ContainsKey($cacheKey)) {
            $requestsByCacheKey[$cacheKey] = [pscustomobject]@{
              Language = $language
              Text = $normalized
              VoiceId = $voiceId
              Speed = $speed
              CachePath = Join-Path $cacheDirectory "$cacheKey.mp3"
            }
          }
        }
      }
    }
  }
}

$requests = @($requestsByCacheKey.Values)
$missingRequests = @($requests | Where-Object { !(Test-Path -LiteralPath $_.CachePath) })
Write-Output "Unique speech clips: $($requests.Count); missing from cache: $($missingRequests.Count)."

$missingRequests | ForEach-Object -Parallel {
  $request = $_
  $headers = @{
    'xi-api-key' = $using:apiKey
    Accept = 'audio/mpeg'
    'Content-Type' = 'application/json'
  }
  $body = @{
    text = $request.Text
    model_id = 'eleven_v3'
    language_code = $request.Language
    voice_settings = @{
      speed = $request.Speed
      stability = 0.5
      similarity_boost = 0.75
      use_speaker_boost = $true
    }
  } | ConvertTo-Json -Depth 5
  $uri = "https://api.elevenlabs.io/v1/text-to-speech/$($request.VoiceId)?output_format=mp3_44100_128"
  $temporaryPath = "$($request.CachePath).partial.$([guid]::NewGuid().ToString('N'))"
  for ($attempt = 1; $attempt -le 7; $attempt++) {
    try {
      Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -Body $body -OutFile $temporaryPath
      if ((Get-Item -LiteralPath $temporaryPath).Length -lt 512) {
        throw 'ElevenLabs returned an unexpectedly small audio file.'
      }
      Move-Item -LiteralPath $temporaryPath -Destination $request.CachePath -Force
      Write-Output "generated|$($request.Language)|$($request.CachePath)"
      break
    } catch {
      if (Test-Path -LiteralPath $temporaryPath) {
        Remove-Item -LiteralPath $temporaryPath -Force
      }
      if ($attempt -eq 7) { throw }
      Start-Sleep -Seconds ([math]::Min(30, [math]::Pow(2, $attempt)))
    }
  }
} -ThrottleLimit $ThrottleLimit

$cachePathByLanguageAndText = @{}
foreach ($request in $requests) {
  $cachePathByLanguageAndText["$($request.Language)|$($request.Text)"] = $request.CachePath
}

foreach ($group in $catalog.groups) {
  $ageKey = "$($group.startAge)-$($group.endAge)"
  $pack = $packByAge[$ageKey]
  if ([string]::IsNullOrWhiteSpace($pack)) {
    throw "No audio pack is configured for age group $ageKey."
  }
  $outputDirectory = Join-Path $repositoryRoot "assets\audio\$pack"
  New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
  $entries = [Collections.ArrayList]::new()
  foreach ($topic in $group.topics) {
    foreach ($lesson in $topic.lessons) {
      foreach ($sentence in $lesson.sentences) {
        $sentenceId = ([string]$sentence.id).Trim()
        foreach ($language in @('en', 'vi')) {
          $text = if ($language -eq 'en') { $sentence.english } else { $sentence.vietnamese }
          $normalized = Get-NormalizedText ([string]$text)
          $key = "listening.sentence.$sentenceId.$language"
          $fileName = "$key.mp3"
          $absolutePath = Join-Path $outputDirectory $fileName
          $cachePath = $cachePathByLanguageAndText["$language|$normalized"]
          if ([string]::IsNullOrWhiteSpace($cachePath) -or !(Test-Path -LiteralPath $cachePath)) {
            throw "Missing generated cache file for $key."
          }
          Copy-Item -LiteralPath $cachePath -Destination $absolutePath -Force
          $locale = if ($language -eq 'en') { 'en-US' } else { 'vi-VN' }
          [void]$entries.Add([ordered]@{
            key = $key
            enabled = $true
            locale = $locale
            asset = "assets/audio/$pack/$fileName"
            durationSeconds = Get-DurationSeconds $absolutePath
            sha256 = (Get-FileHash -LiteralPath $absolutePath -Algorithm SHA256).Hash.ToLowerInvariant()
            modelId = 'eleven_v3'
            language = $language
            voiceId = $voiceByLanguage[$language]
            speed = $speedByLanguage[$language]
          })
        }
      }
    }
  }
  $manifest = [ordered]@{
    schemaVersion = 1
    pack = $pack
    enabled = $true
    prompts = $entries
  }
  $manifestPath = Join-Path $repositoryRoot "assets\data\$($manifestNameByAge[$ageKey])"
  $manifest | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $manifestPath -Encoding utf8
  Write-Output "Wrote $($entries.Count) entries for $pack."
}

Write-Output 'Listening sentence audio generation completed.'
