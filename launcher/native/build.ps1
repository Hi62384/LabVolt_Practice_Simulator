param([string]$Output = "$PSScriptRoot/../../.godot/LabVoltCampusBroker.exe")
$ErrorActionPreference = 'Stop'
$compiler = "$env:WINDIR/Microsoft.NET/Framework64/v4.0.30319/csc.exe"
$destination = [IO.Path]::GetFullPath($Output)
New-Item -ItemType Directory -Force ([IO.Path]::GetDirectoryName($destination)) | Out-Null
$sandbox = Join-Path $PSScriptRoot '../../scripts/firmware_toolchain/windows_sandbox.cs'
$bundle = Join-Path $PSScriptRoot '../../scripts/campus/computers/CampusWindowsBundle.cs'
& $compiler /nologo /optimize+ /target:exe /platform:x64 /reference:System.Drawing.dll "/out:$destination" (Join-Path $PSScriptRoot 'CampusNativeBroker.cs') $sandbox $bundle
if ($LASTEXITCODE -ne 0) { throw 'Campus OS native broker compilation failed.' }
Write-Output $destination
