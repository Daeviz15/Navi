param([switch]$ExplicitNaviPronunciation)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech
$output = Join-Path $PSScriptRoot '..\build\voice-validation'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$samples = @{
    greeting = 'Hey Navi.'
    hi = 'Hi Navi.'
    hello = 'Hello Navi.'
    destination = 'Hey Navi, take me to London.'
    lagos = 'Hi Navi, take me to Lagos.'
    negative = 'The weather looks lovely today. Let us go for a walk.'
    negative_names = 'Hey David, the navy blue car looks nice.'
}
foreach ($name in $samples.Keys) {
    $baseName = if ($ExplicitNaviPronunciation) { "$name-nahvee" } else { $name }
    $speaker = New-Object System.Speech.Synthesis.SpeechSynthesizer
    try {
        $wav = Join-Path $output "$baseName.wav"
        $speaker.SetOutputToWaveFile($wav)
        if ($ExplicitNaviPronunciation) {
            $text = [System.Security.SecurityElement]::Escape($samples[$name])
            $text = $text.Replace('Navi', '<phoneme alphabet="ipa" ph="n&#x251;vi">Navi</phoneme>')
            $speaker.SpeakSsml('<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="en-US">' + $text + '</speak>')
        } else {
            $speaker.Speak($samples[$name])
        }
    } finally {
        $speaker.Dispose()
    }
    & ffmpeg -v error -y -i $wav -ac 1 -ar 16000 -c:a pcm_s16le (Join-Path $output "$baseName-16k.wav")
    if ($LASTEXITCODE -ne 0) { throw 'Audio conversion failed' }
}
