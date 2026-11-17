param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$engineDirectory = Join-Path $ProjectRoot 'runtime/Godot_v4.5.1-stable_mono_win64'
$engine = Join-Path $engineDirectory 'Godot_v4.5.1-stable_mono_win64_console.exe'
if (Test-Path -LiteralPath $engine) { return }
$archive = Join-Path $ProjectRoot 'runtime/Godot_v4.5.1-stable_mono_win64.zip'
$url = 'https://github.com/godotengine/godot-builds/releases/download/4.5.1-stable/Godot_v4.5.1-stable_mono_win64.zip'
Invoke-WebRequest -Uri $url -OutFile $archive
Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $ProjectRoot 'runtime') -Force
if (!(Test-Path -LiteralPath $engine)) { throw 'Godot 4.5.1 .NET runtime could not be installed.' }
