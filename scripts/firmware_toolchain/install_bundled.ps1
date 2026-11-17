param([Parameter(Mandatory=$true)][string]$GameDirectory,[string]$InstallRoot=(Join-Path $env:LOCALAPPDATA 'LabVolt\FirmwareToolchain'))
$ErrorActionPreference='Stop'
function Get-FileHash { param([string]$LiteralPath,[string]$Algorithm='SHA256')
    $stream=[IO.File]::OpenRead($LiteralPath)
    try {$sha=[Security.Cryptography.SHA256]::Create();try {$bytes=$sha.ComputeHash($stream)}finally{$sha.Dispose()}}
    finally {$stream.Dispose()}
    return @{Hash=([BitConverter]::ToString($bytes).Replace('-',''))}
}
$folder=Join-Path ([IO.Path]::GetFullPath($GameDirectory)) 'firmware_toolchain'
$InstallRoot=[IO.Path]::GetFullPath($InstallRoot)
$status=Join-Path $InstallRoot 'install-result.json'
[IO.Directory]::CreateDirectory($InstallRoot)|Out-Null
function Record-Result($value){[IO.File]::WriteAllText($status,($value|ConvertTo-Json -Compress -Depth 5),[Text.UTF8Encoding]::new($false))}
$staging=''
try {
    $avr=Join-Path $folder 'avr-gcc.zip';$core=Join-Path $folder 'arduino-core.zip';$arm=Join-Path $folder 'arm-gcc.zip'
    if((Get-FileHash -LiteralPath $avr -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'de4aad501ee42b63d5d262e45470924cd2654f6bc437f0299875efa6b8d8d0fe'){throw 'Bundled AVR compiler checksum mismatch'}
    if((Get-FileHash -LiteralPath $core -Algorithm SHA256).Hash.ToLowerInvariant() -ne '0e0275ef6396210f837a0bddd78205654e1fa6e9cf8e6afed09a90ebfcb4e0e2'){throw 'Bundled Arduino core checksum mismatch'}
    if((Get-FileHash -LiteralPath $arm -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'bae6a3d1667697ce750c3b13d6d26d80973ecedc2cc87bf04869e83447fd93ea'){throw 'Bundled ARM compiler checksum mismatch'}
    $staging=Join-Path $InstallRoot ('staging-'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($staging)|Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    foreach($item in @(@($avr,'avr'),@($core,'core'),@($arm,'arm'))){
        $archive=[IO.Compression.ZipFile]::OpenRead($item[0])
        try {foreach($entry in $archive.Entries){$name=$entry.FullName.Replace('\','/');if($name.StartsWith('/') -or $name -match '^[A-Za-z]:' -or $name -match '(^|/)\.\.(/|$)'){throw 'Unsafe bundled compiler archive entry'}}}
        finally {$archive.Dispose()}
        [IO.Compression.ZipFile]::ExtractToDirectory($item[0],(Join-Path $staging $item[1]))
    }
    foreach($entry in Get-ChildItem -LiteralPath $staging -Recurse -Force){if(($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Bundled compiler links are forbidden'}}
    $avrRoot=Get-ChildItem (Join-Path $staging 'avr') -Directory|Where-Object {Test-Path (Join-Path $_.FullName 'bin\avr-g++.exe')}|Select-Object -First 1
    $coreRoot=Get-ChildItem (Join-Path $staging 'core') -Directory|Where-Object {Test-Path (Join-Path $_.FullName 'cores\arduino\Arduino.h')}|Select-Object -First 1
    $armRoot=Get-ChildItem (Join-Path $staging 'arm') -Directory|Where-Object {Test-Path (Join-Path $_.FullName 'bin\arm-none-eabi-g++.exe')}|Select-Object -First 1
    if(-not $avrRoot -or -not $coreRoot -or -not $armRoot){throw 'Bundled compiler layout is invalid'}
    & (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -NonInteractive -File (Join-Path $folder 'setup_official.ps1') -InstallRoot $InstallRoot -TrustedAvrRoot $avrRoot.FullName -TrustedCoreRoot $coreRoot.FullName -TrustedArmRoot $armRoot.FullName
    if($LASTEXITCODE){throw 'Compiler installation failed'}
    & (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -NonInteractive -File (Join-Path $folder 'run_acceptance.ps1') -InstallRoot $InstallRoot -ProbeExe (Join-Path $folder 'acceptance_probe.exe') -ScriptRoot $folder
    if($LASTEXITCODE){throw 'Compiler acceptance checks failed'}
    Record-Result @{ok=$true;status='ready'}
} catch {
    Record-Result @{ok=$false;status='setup_failed';error=$_.Exception.Message}
    throw
} finally {
    if($staging -and $staging.StartsWith($InstallRoot.TrimEnd('\')+'\staging-',[StringComparison]::OrdinalIgnoreCase) -and [IO.Directory]::Exists($staging)){
        try {[IO.Directory]::Delete($staging,$true)} catch {}
    }
}
