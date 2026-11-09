param([string]$InstallRoot=(Join-Path $env:APPDATA 'Godot\app_userdata\LabVolt Cooperative Lab\firmware_toolchain'),[switch]$InstallOfficialAvr,[switch]$DiscoverOnly,[string]$TrustedAvrRoot,[string]$TrustedCoreRoot,[string]$TrustedArmRoot)
$ErrorActionPreference='Stop'
$utf8=New-Object Text.UTF8Encoding($false)
function Find-Install {
    $avr=@();$arm=@();$core=@()
    $packages=Join-Path $env:LOCALAPPDATA 'Arduino15\packages\arduino'
    $avrBase=Join-Path $packages 'tools\avr-gcc'
    if(Test-Path -LiteralPath $avrBase){foreach($v in Get-ChildItem -LiteralPath $avrBase -Directory){if(Test-Path -LiteralPath (Join-Path $v.FullName 'bin\avr-g++.exe')){$avr+=$v.FullName}}}
    $legacy=Join-Path ${env:ProgramFiles(x86)} 'Arduino\hardware\tools\avr'
    if(Test-Path -LiteralPath (Join-Path $legacy 'bin\avr-g++.exe')){$avr+=$legacy}
    $coreBase=Join-Path $packages 'hardware\avr'
    if(Test-Path -LiteralPath $coreBase){foreach($v in Get-ChildItem -LiteralPath $coreBase -Directory){if(Test-Path -LiteralPath (Join-Path $v.FullName 'cores\arduino\Arduino.h')){$core+=$v.FullName}}}
    $legacyCore=Join-Path ${env:ProgramFiles(x86)} 'Arduino\hardware\arduino\avr'
    if(Test-Path -LiteralPath (Join-Path $legacyCore 'cores\arduino\Arduino.h')){$core+=$legacyCore}
    foreach($base in @($env:ProgramFiles,${env:ProgramFiles(x86)})){
        foreach($candidate in Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue | Where-Object {$_.Name -match '^(GNU Arm Embedded Toolchain|Arm GNU Toolchain)'}){
            if(Test-Path -LiteralPath (Join-Path $candidate.FullName 'bin\arm-none-eabi-g++.exe')){$arm+=$candidate.FullName}
            foreach($version in Get-ChildItem -LiteralPath $candidate.FullName -Directory){if(Test-Path -LiteralPath (Join-Path $version.FullName 'bin\arm-none-eabi-g++.exe')){$arm+=$version.FullName}}
        }
    }
    return @{avr=@($avr|Sort-Object -Descending);core=@($core|Sort-Object -Descending);arm=@($arm|Sort-Object -Descending)}
}
function Download-Official { param($Record,[string]$Destination)
    $uri=[Uri]$Record.url
    if($uri.Scheme -ne 'https' -or $uri.Host -ne 'downloads.arduino.cc'){throw 'Dependency URL is not the official Arduino download host'}
    if(([string]$Record.checksum) -notmatch '^SHA-256:([a-fA-F0-9]{64})$'){throw 'Official dependency lacks SHA256 metadata'}
    $expected=$Matches[1]
    Invoke-WebRequest -Uri $uri.AbsoluteUri -OutFile $Destination -TimeoutSec 120 -UseBasicParsing
    if((Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -ne $expected){throw 'Official archive checksum mismatch'}
}
function Expand-Official { param([string]$Archive,[string]$Destination)
    [IO.Directory]::CreateDirectory($Destination)|Out-Null
    $tar=Join-Path $env:WINDIR 'System32\tar.exe'
    $entries=& $tar -tf $Archive
    if($LASTEXITCODE -ne 0){throw 'Cannot inspect official archive'}
    foreach($entry in $entries){if($entry -match '(^[/\\]|^[A-Za-z]:|(^|[/\\])\.\.([/\\]|$))'){throw 'Unsafe archive path'}}
    & $tar -xf $Archive -C $Destination
    if($LASTEXITCODE -ne 0){throw 'Cannot extract official toolchain'}
    foreach($file in Get-ChildItem -LiteralPath $Destination -Recurse -Force){if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Dependency reparse points are not permitted'}}
}
$discovered=Find-Install
# These parameters are trusted host setup input only. The compile service never
# accepts them, and neither sources nor player saves can choose these locations.
foreach($pair in @(@('avr',$TrustedAvrRoot,'bin\avr-g++.exe'),@('core',$TrustedCoreRoot,'cores\arduino\Arduino.h'),@('arm',$TrustedArmRoot,'bin\arm-none-eabi-g++.exe'))){
    if(-not [string]::IsNullOrEmpty($pair[1])){
        if(-not [IO.Path]::IsPathRooted($pair[1]) -or -not (Test-Path -LiteralPath (Join-Path $pair[1] $pair[2]))){throw 'Invalid trusted host installation root'}
        foreach($item in Get-ChildItem -LiteralPath $pair[1] -Recurse -Force){if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Trusted installation cannot contain reparse points'}}
        $discovered[$pair[0]]=@([IO.Path]::GetFullPath($pair[1]))
    }
}
if($DiscoverOnly){$discovered|ConvertTo-Json -Depth 5;exit 0}
$InstallRoot=[IO.Path]::GetFullPath($InstallRoot)
[IO.Directory]::CreateDirectory($InstallRoot)|Out-Null
$staging=Join-Path $InstallRoot ('.setup-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($staging)|Out-Null
if($InstallOfficialAvr -and ($discovered.avr.Count -eq 0 -or $discovered.core.Count -eq 0)){
    # Metadata and archives are retrieved by the trusted installer, never by a
    # player source project or the offline compiler process.
    $index=Invoke-RestMethod -Uri 'https://downloads.arduino.cc/packages/package_index.json' -TimeoutSec 30
    $package=$index.packages|Where-Object name -EQ 'arduino'
    $platform=$package.platforms|Where-Object {$_.architecture -eq 'avr' -and $_.version -eq '1.8.6'}|Select-Object -First 1
    if($null -eq $platform){throw 'Pinned official Arduino AVR core1.8.6 missing from index'}
    $version=($platform.toolsDependencies|Where-Object name -EQ 'avr-gcc').version
    $compiler=$package.tools|Where-Object {$_.name -eq 'avr-gcc' -and $_.version -eq $version}|Select-Object -First 1
    $system=$compiler.systems|Where-Object host -EQ 'i686-mingw32'|Select-Object -First 1
    if($null -eq $system){throw 'Official Windows AVR GCC archive unavailable'}
    $avrArchive=Join-Path $staging 'avr.tar.bz2';$coreArchive=Join-Path $staging 'core.tar.bz2'
    Download-Official $system $avrArchive;Download-Official $platform $coreArchive
    Expand-Official $avrArchive (Join-Path $staging 'avr');Expand-Official $coreArchive (Join-Path $staging 'core')
    $discovered.avr=@((Get-ChildItem -LiteralPath (Join-Path $staging 'avr') -Directory|Select-Object -First 1).FullName)
    $discovered.core=@((Get-ChildItem -LiteralPath (Join-Path $staging 'core') -Directory|Select-Object -First 1).FullName)
    [IO.File]::WriteAllText((Join-Path $staging 'official-provenance.json'),(@{index='https://downloads.arduino.cc/packages/package_index.json';platform=$platform;compiler=$system}|ConvertTo-Json -Depth 12),$utf8)
}
$relativeRoot='tools/toolchain-'+[Guid]::NewGuid().ToString('N')
$tools=Join-Path $InstallRoot $relativeRoot
[IO.Directory]::CreateDirectory($tools)|Out-Null
$targets=@{}
if($discovered.avr.Count -gt 0 -and $discovered.core.Count -gt 0){
    Copy-Item -LiteralPath $discovered.avr[0] -Destination (Join-Path $tools 'avr') -Recurse
    Copy-Item -LiteralPath $discovered.core[0] -Destination (Join-Path $tools 'arduino-core') -Recurse
    $targets.uno=@{cxx='avr/bin/avr-g++.exe';cc='avr/bin/avr-gcc.exe';objcopy='avr/bin/avr-objcopy.exe';objdump='avr/bin/avr-objdump.exe';core='arduino-core/cores/arduino';variant='arduino-core/variants/standard'}
    if([IO.Directory]::Exists((Join-Path $tools 'arduino-core/variants/eightanaloginputs'))){$targets.nano=$targets.uno.Clone();$targets.nano.variant='arduino-core/variants/eightanaloginputs'}
}
if($discovered.arm.Count -gt 0){
    Copy-Item -LiteralPath $discovered.arm[0] -Destination (Join-Path $tools 'arm') -Recurse
    $targets.pico=@{cxx='arm/bin/arm-none-eabi-g++.exe';cc='arm/bin/arm-none-eabi-gcc.exe';objcopy='arm/bin/arm-none-eabi-objcopy.exe';objdump='arm/bin/arm-none-eabi-objdump.exe'}
}
if($targets.Count -eq 0){throw 'No trusted official local toolchain found. Official dependency installation is required; no compiler enabled.'}
$records=@()
foreach($file in Get-ChildItem -LiteralPath $tools -Recurse -File){
    if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Trusted toolchain contains a reparse point'}
    $records+=@{path=$file.FullName.Substring($tools.Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$manifest=@{schema=1;id='official-local-'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmss');tools_root=$relativeRoot;targets=$targets;files=$records;provenance=$discovered}
$temporary=Join-Path $InstallRoot 'trusted-manifest.json.tmp'
[IO.File]::WriteAllText($temporary,($manifest|ConvertTo-Json -Depth 12 -Compress),$utf8)
Move-Item -LiteralPath $temporary -Destination (Join-Path $InstallRoot 'trusted-manifest.json') -Force
@{ok=$true;targets=@($targets.Keys);manifest=(Join-Path $InstallRoot 'trusted-manifest.json');note='Compilation still requires a successful Windows isolation probe.'}|ConvertTo-Json
