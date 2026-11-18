param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$engineDirectory = Join-Path $ProjectRoot 'runtime/Godot_v4.5.1-stable_mono_win64'
$engine = Join-Path $engineDirectory 'Godot_v4.5.1-stable_mono_win64_console.exe'
if (Test-Path -LiteralPath $engine) { return }
$runtimeDirectory = Split-Path -Parent $engineDirectory
New-Item -ItemType Directory -Force -Path $runtimeDirectory | Out-Null
$archive = Join-Path $ProjectRoot 'runtime/Godot_v4.5.1-stable_mono_win64.zip'
$url = 'https://github.com/godotengine/godot-builds/releases/download/4.5.1-stable/Godot_v4.5.1-stable_mono_win64.zip'
try {
	if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
	$curl = Get-Command 'curl.exe' -ErrorAction SilentlyContinue
	if ($null -ne $curl) {
		& $curl.Source --fail --location --retry 3 --retry-delay 2 --connect-timeout 20 --output $archive $url
		if ($LASTEXITCODE -ne 0) { throw "curl exited with code $LASTEXITCODE" }
	} else {
		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
		Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing -TimeoutSec 300
	}
	if (!(Test-Path -LiteralPath $archive) -or (Get-Item -LiteralPath $archive).Length -lt 1) {
		throw 'The runtime download was empty.'
	}
	Expand-Archive -LiteralPath $archive -DestinationPath $runtimeDirectory -Force
	if (!(Test-Path -LiteralPath $engine)) { throw 'The downloaded archive did not contain the expected Godot runtime.' }
} catch {
	if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
	throw "Could not prepare the Godot 4.5.1 .NET runtime. Check your internet connection and try launching again. Details: $($_.Exception.Message)"
}
