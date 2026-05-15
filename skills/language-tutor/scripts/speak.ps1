# speak.ps1 — language-tutor TTS wrapper
# Usage:
#   powershell -ExecutionPolicy Bypass -File speak.ps1 -Text "Hello world" -Lang en-US
#   powershell -ExecutionPolicy Bypass -File speak.ps1 -Text "こんにちは" -Lang ja-JP -Rate -2
#   powershell -ExecutionPolicy Bypass -File speak.ps1 -Text "Bonjour" -Lang fr-FR -Engine edge

[CmdletBinding(DefaultParameterSetName = 'Speak')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Speak')] [string] $Text,
    [Parameter(Mandatory = $true, ParameterSetName = 'Speak')] [string] $Lang,
    [Parameter(ParameterSetName = 'Speak')] [ValidateRange(-10, 10)] [int] $Rate = 0,
    [Parameter(ParameterSetName = 'Speak')] [ValidateSet('sapi', 'edge')] [string] $Engine = 'sapi',
    [Parameter(ParameterSetName = 'Speak')] [int] $Volume = 100,
    [Parameter(Mandatory = $true, ParameterSetName = 'List')] [switch] $ListVoices
)

$ErrorActionPreference = 'Stop'

function Get-SapiVoice {
    param([string]$LangCode, [System.Speech.Synthesis.SpeechSynthesizer]$Synth)

    # Try exact culture match first, then language family fallback.
    $voices = $Synth.GetInstalledVoices() | Where-Object { $_.Enabled }
    if ($voices.Count -eq 0) { return $null }

    $shortLang = $LangCode.Split('-')[0]

    $exact = $voices | Where-Object { $_.VoiceInfo.Culture.Name -ieq $LangCode } | Select-Object -First 1
    if ($exact) { return $exact }

    $family = $voices | Where-Object { $_.VoiceInfo.Culture.TwoLetterISOLanguageName -ieq $shortLang } | Select-Object -First 1
    if ($family) { return $family }

    return $null
}

function Invoke-SapiSpeak {
    param([string]$Text, [string]$Lang, [int]$Rate, [int]$Volume)

    Add-Type -AssemblyName System.Speech
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $synth.Rate = $Rate
    $synth.Volume = $Volume

    $voice = Get-SapiVoice -LangCode $Lang -Synth $synth
    if ($null -eq $voice) {
        $installed = ($synth.GetInstalledVoices() | ForEach-Object { $_.VoiceInfo.Culture.Name }) -join ', '
        Write-Error "No SAPI voice found for '$Lang'. Installed cultures: $installed. Install the Windows language pack for $Lang, or try -Engine edge."
        $synth.Dispose()
        return
    }

    $synth.SelectVoice($voice.VoiceInfo.Name)
    Write-Host "[sapi] $($voice.VoiceInfo.Name) ($($voice.VoiceInfo.Culture.Name)) | rate=$Rate"
    $synth.Speak($Text)
    $synth.Dispose()
}

function Invoke-EdgeSpeak {
    param([string]$Text, [string]$Lang, [int]$Rate)

    # Map BCP-47 + a default neural voice. Override via $env:LANGTUTOR_EDGE_VOICE_<LANG>.
    $voiceMap = @{
        'en-US' = 'en-US-AriaNeural'
        'en-GB' = 'en-GB-LibbyNeural'
        'ja-JP' = 'ja-JP-NanamiNeural'
        'fr-FR' = 'fr-FR-DeniseNeural'
        'de-DE' = 'de-DE-KatjaNeural'
        'es-ES' = 'es-ES-ElviraNeural'
        'es-MX' = 'es-MX-DaliaNeural'
        'it-IT' = 'it-IT-ElsaNeural'
        'ko-KR' = 'ko-KR-SunHiNeural'
        'zh-CN' = 'zh-CN-XiaoxiaoNeural'
        'zh-TW' = 'zh-TW-HsiaoChenNeural'
        'zh-HK' = 'zh-HK-HiuMaanNeural'
        'pt-BR' = 'pt-BR-FranciscaNeural'
        'ru-RU' = 'ru-RU-SvetlanaNeural'
        'th-TH' = 'th-TH-PremwadeeNeural'
        'vi-VN' = 'vi-VN-HoaiMyNeural'
        'id-ID' = 'id-ID-GadisNeural'
    }

    $envKey = "LANGTUTOR_EDGE_VOICE_$($Lang.ToUpper().Replace('-', '_'))"
    $voice = (Get-Item "Env:$envKey" -ErrorAction SilentlyContinue).Value
    if (-not $voice) { $voice = $voiceMap[$Lang] }
    if (-not $voice) {
        Write-Error "No edge-tts voice mapping for '$Lang'. Set $envKey or extend voiceMap in speak.ps1."
        return
    }

    # edge-tts rate is a percentage string. -3..+3 -> -30%..+30%.
    $ratePct = [Math]::Max(-50, [Math]::Min(50, $Rate * 10))
    $rateArg = if ($ratePct -ge 0) { "+${ratePct}%" } else { "${ratePct}%" }

    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
    if (-not $py) {
        Write-Error "Python not found. edge-tts requires Python + 'pip install edge-tts'."
        return
    }

    $helper = Join-Path $PSScriptRoot 'speak-edge.py'
    if (-not (Test-Path $helper)) {
        Write-Error "Helper not found: $helper"
        return
    }

    Write-Host "[edge] $voice | rate=$rateArg"
    # Use --rate=<val> so argparse doesn't read a leading '-' as a new flag.
    & $py.Source $helper --text $Text --voice $voice "--rate=$rateArg"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "edge-tts helper exited with code $LASTEXITCODE"
    }
}

if ($ListVoices) {
    Add-Type -AssemblyName System.Speech
    $s = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $s.GetInstalledVoices() | ForEach-Object {
        [PSCustomObject]@{
            Name    = $_.VoiceInfo.Name
            Culture = $_.VoiceInfo.Culture.Name
            Gender  = $_.VoiceInfo.Gender
            Enabled = $_.Enabled
        }
    } | Format-Table -AutoSize
    $s.Dispose()
    return
}

switch ($Engine) {
    'sapi' { Invoke-SapiSpeak -Text $Text -Lang $Lang -Rate $Rate -Volume $Volume }
    'edge' { Invoke-EdgeSpeak -Text $Text -Lang $Lang -Rate $Rate }
}
