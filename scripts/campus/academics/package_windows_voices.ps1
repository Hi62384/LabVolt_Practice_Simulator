param(
    [string]$GameDirectory = ''
)
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$voices = Join-Path $project 'assets/campus/faculty/voices'
$model = Join-Path $voices 'en_US-libritts_r-medium.onnx'
$config = "$model.json"
$expectedModel = '10BB85E071D616FCF4071F369F1799D0491492AB3C5D552EC19FB548FAC13195'
$expectedPiper = 'F3C58906402B24F3A96D92145F58ACBA6D86C9B5DB896D207F78DC80811EFCEA'
if (!(Test-Path -LiteralPath $model) -or !(Test-Path -LiteralPath $config)) { throw 'Voice model or config is missing' }
if ((Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash -ne $expectedModel) { throw 'Voice model checksum mismatch' }
$dependencies = Join-Path $project '.deps'
New-Item -ItemType Directory -Force -Path $dependencies | Out-Null
$zip = Join-Path $dependencies 'piper_windows_amd64.zip'
if (!(Test-Path -LiteralPath $zip)) {
    Invoke-WebRequest -Uri 'https://github.com/rhasspy/piper/releases/download/2023.11.14-2/piper_windows_amd64.zip' -OutFile $zip -TimeoutSec 120
}
if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $expectedPiper) { throw 'Piper runtime checksum mismatch' }
$expanded = Join-Path $dependencies 'piper-standalone'
if (!(Test-Path -LiteralPath (Join-Path $expanded 'piper/piper.exe'))) {
    New-Item -ItemType Directory -Force -Path $expanded | Out-Null
    Expand-Archive -LiteralPath $zip -DestinationPath $expanded -Force
}
if ([string]::IsNullOrWhiteSpace($GameDirectory)) {
    Write-Output 'Development instructor voices are ready.'
    return
}
$game = (Resolve-Path -LiteralPath $GameDirectory).Path
if (!(Test-Path -LiteralPath (Join-Path $game 'LabVolt.exe'))) { throw 'Windows game executable is missing' }
$runtime = Join-Path $game 'piper'
New-Item -ItemType Directory -Force -Path $runtime | Out-Null
Copy-Item -Path (Join-Path $expanded 'piper/*') -Destination $runtime -Recurse -Force
$sidecar = Join-Path $game 'teacher_voices'
New-Item -ItemType Directory -Force -Path $sidecar | Out-Null
Copy-Item -LiteralPath $model,$config,(Join-Path $voices 'MODEL_CARD'),(Join-Path $voices 'PIPER_LICENSE.md'),(Join-Path $voices 'VOICE_NOTICE.md') -Destination $sidecar -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'piper_runner.ps1') -Destination $sidecar -Force
Write-Output 'Windows instructor voices packaged.'
