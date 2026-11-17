param([Parameter(Mandatory=$true)][string]$GameDirectory,[string]$AvrArchive='',[string]$CoreArchive='',[string]$ArmArchive='')
$ErrorActionPreference='Stop'
$folder=Join-Path ([IO.Path]::GetFullPath($GameDirectory)) 'firmware_toolchain'
[IO.Directory]::CreateDirectory($folder)|Out-Null
function Stage-Archive([string]$source,[string]$url,[string]$destination,[string]$expected) {
    if($source){Copy-Item -LiteralPath $source -Destination $destination -Force}
    else{Invoke-WebRequest -Uri $url -OutFile $destination -TimeoutSec 180 -UseBasicParsing}
    if((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected){throw ('Bundled compiler archive checksum mismatch: '+$destination)}
}
Stage-Archive $AvrArchive 'https://github.com/ZakKemble/avr-gcc-build/releases/download/v16.1.0-1/avr-gcc-16.1.0-x64-windows.zip' (Join-Path $folder 'avr-gcc.zip') 'de4aad501ee42b63d5d262e45470924cd2654f6bc437f0299875efa6b8d8d0fe'
Stage-Archive $ArmArchive 'https://github.com/xpack-dev-tools/arm-none-eabi-gcc-xpack/releases/download/v15.2.1-1.1/xpack-arm-none-eabi-gcc-15.2.1-1.1-win32-x64.zip' (Join-Path $folder 'arm-gcc.zip') 'bae6a3d1667697ce750c3b13d6d26d80973ecedc2cc87bf04869e83447fd93ea'
$coreTar=Join-Path $folder 'arduino-core.tar.bz2'
Stage-Archive $CoreArchive 'https://downloads.arduino.cc/cores/staging/avr-1.8.6.tar.bz2' $coreTar 'ff1d17274b5a952f172074bd36c3924336baefded0232e10982f8999c2f7c3b6'
& python (Join-Path $PSScriptRoot 'convert_core_archive.py') $coreTar (Join-Path $folder 'arduino-core.zip')
if($LASTEXITCODE -or (Get-FileHash -LiteralPath (Join-Path $folder 'arduino-core.zip') -Algorithm SHA256).Hash.ToLowerInvariant() -ne '0e0275ef6396210f837a0bddd78205654e1fa6e9cf8e6afed09a90ebfcb4e0e2'){throw 'Converted Arduino core checksum mismatch'}
Remove-Item -LiteralPath $coreTar -Force
foreach($name in @('broker.ps1','build_plan.ps1','windows_sandbox.cs','setup_official.ps1','install_bundled.ps1','run_acceptance.ps1','acceptance_probe.exe')){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $folder -Force}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'pico_support') -Destination $folder -Recurse -Force
@{ok=$true;directory=$folder;avr_sha256='de4aad501ee42b63d5d262e45470924cd2654f6bc437f0299875efa6b8d8d0fe';core_sha256='0e0275ef6396210f837a0bddd78205654e1fa6e9cf8e6afed09a90ebfcb4e0e2';arm_sha256='bae6a3d1667697ce750c3b13d6d26d80973ecedc2cc87bf04869e83447fd93ea'}|ConvertTo-Json -Compress
