param([string]$Output = "$PSScriptRoot/dist/LabVoltLauncher.exe")
$ErrorActionPreference = 'Stop'
$compiler = "$env:WINDIR/Microsoft.NET/Framework64/v4.0.30319/csc.exe"
$destination = [IO.Path]::GetFullPath($Output)
New-Item -ItemType Directory -Force ([IO.Path]::GetDirectoryName($destination)) | Out-Null
$references = '/reference:System.Windows.Forms.dll', '/reference:System.Drawing.dll', '/reference:System.Web.Extensions.dll'
$source = Join-Path $PSScriptRoot Launcher.cs
$preview = Join-Path $PSScriptRoot '../docs/laboratory_preview.png'
$campus = Join-Path $PSScriptRoot 'campus_preview.png'
& $compiler /nologo /optimize+ /target:winexe "/out:$destination" "/resource:$preview,CollegeSimulator.Laboratory.png" "/resource:$campus,CollegeSimulator.Campus.png" @references $source
if ($LASTEXITCODE -ne 0) { throw 'Launcher compilation failed.' }
Write-Output $destination
