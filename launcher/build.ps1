param([string]$Output = "$PSScriptRoot/dist/LabVoltLauncher.exe")
$ErrorActionPreference = 'Stop'
$compiler = "$env:WINDIR/Microsoft.NET/Framework64/v4.0.30319/csc.exe"
$destination = [IO.Path]::GetFullPath($Output)
New-Item -ItemType Directory -Force ([IO.Path]::GetDirectoryName($destination)) | Out-Null
$references = '/reference:System.Windows.Forms.dll', '/reference:System.Drawing.dll', '/reference:System.Web.Extensions.dll'
$source = Join-Path $PSScriptRoot Launcher.cs
& $compiler /nologo /optimize+ /target:winexe "/out:$destination" @references $source
if ($LASTEXITCODE -ne 0) { throw 'Launcher compilation failed.' }
Write-Output $destination
