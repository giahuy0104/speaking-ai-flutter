param(
  [string]$ApiKeyPath = 'C:\Users\DELL\Documents\api_key_elevanlabs.txt',
  [string]$OutputRoot = 'outputs\listening-vi-refresh-20260925',
  [ValidateRange(1,8)][int]$ThrottleLimit = 3
)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$out=if([IO.Path]::IsPathRooted($OutputRoot)){$OutputRoot}else{Join-Path $repo $OutputRoot}
New-Item -ItemType Directory -Path $out -Force|Out-Null
$apiKey=(Get-Content -LiteralPath $ApiKeyPath -Raw).Trim()
if([string]::IsNullOrWhiteSpace($apiKey)){throw 'The ElevenLabs API key file is empty.'}
$voiceId='5CVDNcIPiOYgRUQuxXd7'; $speed=0.9
$prompts=@(
  @{key='listening.sentence.C35-L1-T01-B01-T01.vi';text='Quả táo.'},
  @{key='listening.sentence.C35-L1-T01-B01-T08.vi';text='Cái mũ.'},
  @{key='listening.sentence.C35-L1-T01-B01-T09.vi';text='Kem.'},
  @{key='listening.sentence.C35-L1-T02-B01-T01.vi';text='Một.'},
  @{key='listening.sentence.C35-L1-T02-B01-T02.vi';text='Hai.'},
  @{key='listening.sentence.C35-L1-T02-B01-T03.vi';text='Ba.'},
  @{key='listening.sentence.C35-L1-T02-B02-T01.vi';text='Một tiếng vỗ tay.'},
  @{key='listening.sentence.C35-L1-T03-B01-T04.vi';text='Xanh lá.'},
  @{key='listening.sentence.C35-L1-T03-B01-T05.vi';text='Đen.'},
  @{key='listening.sentence.C35-L1-T03-B01-T06.vi';text='Trắng.'},
  @{key='listening.sentence.C35-L1-T03-B02-T01.vi';text='Nó màu đỏ.'},
  @{key='listening.sentence.C35-L1-T03-B02-T05.vi';text='Nó màu đen.'},
  @{key='listening.sentence.C35-L2-T04-B01-T01.vi';text='Hình tròn.'},
  @{key='listening.sentence.C35-L2-T04-B01-T02.vi';text='Hình vuông.'},
  @{key='listening.sentence.C35-L2-T05-B02-T03.vi';text='Nó là con chim.'},
  @{key='listening.sentence.C35-L2-T05-B02-T04.vi';text='Nó là con bò.'},
  @{key='listening.sentence.C35-L2-T05-B02-T05.vi';text='Nó là con vịt.'},
  @{key='listening.sentence.C35-L2-T06-B01-T01.vi';text='Đầu.'},
  @{key='listening.sentence.C35-L2-T06-B01-T02.vi';text='Mắt.'},
  @{key='listening.sentence.C35-L2-T06-B01-T04.vi';text='Tay.'},
  @{key='listening.sentence.C35-L3-T07-B02-T02.vi';text='Cho mình chuối nhé.'},
  @{key='listening.sentence.C35-L3-T07-B02-T01.vi';text='Cho mình táo nhé.'},
  @{key='listening.sentence.C35-L3-T07-B02-T03.vi';text='Cho mình cơm nhé.'},
  @{key='listening.sentence.C35-L3-T08-B01-T02.vi';text='Ba.'},
  @{key='listening.sentence.C35-L3-T08-B01-T03.vi';text='Anh, em trai.'},
  @{key='listening.sentence.C35-L3-T08-B01-T04.vi';text='Chị, em gái.'},
  @{key='listening.sentence.C35-L3-T08-B01-T05.vi';text='Gia đình.'},
  @{key='listening.sentence.C35-L3-T09-B02-T03.vi';text='Áo thun.'},
  @{key='listening.sentence.C35-L3-T10-B01-T02.vi';text='Ăn.'},
  @{key='listening.sentence.C35-L3-T10-B01-T03.vi';text='Chơi.'},
  @{key='listening.sentence.C35-L3-T10-B01-T05.vi';text='Ngủ.'}
)
$prompts|ForEach-Object -Parallel {
  $p=$_; $target=Join-Path $using:out "$($p.key).mp3"
  $headers=@{'xi-api-key'=$using:apiKey;Accept='audio/mpeg';'Content-Type'='application/json'}
  $body=@{text=$p.text;model_id='eleven_v3';language_code='vi';voice_settings=@{speed=$using:speed;stability=0.5;similarity_boost=0.75;use_speaker_boost=$true}}|ConvertTo-Json -Depth 5
  for($attempt=1;$attempt -le 5;$attempt++){
    try{
      Invoke-WebRequest -Uri "https://api.elevenlabs.io/v1/text-to-speech/$($using:voiceId)?output_format=mp3_44100_128" -Method Post -Headers $headers -Body $body -OutFile $target
      if((Get-Item -LiteralPath $target).Length -lt 512){throw "Invalid audio for $($p.key)"}
      $duration=& ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $target
      if($LASTEXITCODE -ne 0 -or [double]::Parse($duration.Trim(),[Globalization.CultureInfo]::InvariantCulture) -lt 0.35){throw "Audio too short for $($p.key)"}
      break
    }catch{if($attempt -eq 5){throw};Start-Sleep -Seconds ([math]::Pow(2,$attempt))}
  }
} -ThrottleLimit $ThrottleLimit
function TextHash([string]$s){$h=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes(($s -replace '\s+',' ').Trim())))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}}
$entries=foreach($p in $prompts){
  $path=Join-Path $out "$($p.key).mp3"; $d=& ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $path
  [ordered]@{key=$p.key;enabled=$true;locale='vi-VN';text=$p.text;asset="$($p.key).mp3";durationSeconds=[math]::Round([double]::Parse($d.Trim(),[Globalization.CultureInfo]::InvariantCulture),3);sha256=(Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant();modelId='eleven_v3';language='vi';voiceId=$voiceId;speed=$speed;sizeBytes=(Get-Item $path).Length;textHash=(TextHash $p.text)}
}
[ordered]@{schemaVersion=1;pack='listening-vi-refresh';enabled=$true;prompts=@($entries)}|ConvertTo-Json -Depth 6|Set-Content (Join-Path $out 'manifest.json') -Encoding utf8
Write-Output "Created $($entries.Count) requested listening audio files in $out."
