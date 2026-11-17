param(
    [string]$InstallRoot=(Join-Path $env:LOCALAPPDATA 'LabVolt\FirmwareToolchain'),
    [Parameter(Mandatory=$true)][string]$ProbeExe,
    [string]$ScriptRoot=$PSScriptRoot
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
function Get-FileHash { param([string]$LiteralPath,[string]$Algorithm='SHA256')
    $stream=[IO.File]::OpenRead($LiteralPath)
    try {$sha=[Security.Cryptography.SHA256]::Create();try {$bytes=$sha.ComputeHash($stream)}finally{$sha.Dispose()}}
    finally {$stream.Dispose()}
    return @{Hash=([BitConverter]::ToString($bytes).Replace('-',''))}
}
$InstallRoot=[IO.Path]::GetFullPath($InstallRoot)
$ScriptRoot=[IO.Path]::GetFullPath($ScriptRoot)
$ProbeExe=[IO.Path]::GetFullPath($ProbeExe)
$manifest=Join-Path $InstallRoot 'trusted-manifest.json'
$receipt=Join-Path $InstallRoot 'boundary-acceptance.json'
if(Test-Path -LiteralPath $receipt){Remove-Item -LiteralPath $receipt -Force}
if(-not (Test-Path -LiteralPath $manifest) -or -not (Test-Path -LiteralPath $ProbeExe)){throw 'Trusted compiler manifest or native acceptance probe is missing'}
Add-Type -Path (Join-Path $ScriptRoot 'windows_sandbox.cs')
$checks=@{files=$false;network=$false;timeout=$false;output=$false;descendants=$false;resources=$false;compiler_pipeline=$false}
$jobs=Join-Path ([IO.Path]::GetTempPath()) 'LabVoltAcceptance'
[IO.Directory]::CreateDirectory($jobs)|Out-Null
function New-Job {
    $path=Join-Path $jobs ([Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($path)|Out-Null
    [IO.File]::Copy($ProbeExe,(Join-Path $path 'p.exe'))
    return $path
}
function Run-Probe([string]$mode,[string]$target,[int]$timeout=5000) {
    $path=New-Job
    $sandbox=New-Object LabVolt.Toolchain.WindowsSandbox
    try {
        $sandbox.GrantDirectory($path,$true)
        $args=if($target){[string[]]@($mode,$target)}else{[string[]]@($mode)}
        $log=Join-Path $path 'probe.log'
        $code=$sandbox.Run((Join-Path $path 'p.exe'),$args,$path,$log,(Join-Path $path 'cancel'),$timeout)
        return @{code=$code;output=[IO.File]::ReadAllText($log);isolated=$sandbox.IsolationExercised}
    } finally {$sandbox.Dispose()}
}
$canary=Join-Path $jobs ('canary-'+[Guid]::NewGuid().ToString('N')+'.txt')
[IO.File]::WriteAllText($canary,'private acceptance canary')
try {
    $r=Run-Probe 'file' $canary
    $checks.files=$r.isolated -and $r.code -eq 0 -and $r.output.Trim() -eq 'FILE_DENIED' -and [IO.File]::ReadAllText($canary) -eq 'private acceptance canary'
} finally {Remove-Item -LiteralPath $canary -Force}
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
$listener.Start()
try {
    $port=([Net.IPEndPoint]$listener.LocalEndpoint).Port
    $r=Run-Probe 'network' ([string]$port)
    $checks.network=$r.isolated -and $r.code -eq 0 -and $r.output.Trim() -eq 'NETWORK_DENIED' -and -not $listener.Pending()
} finally {$listener.Stop()}
try {Run-Probe 'timeout' '' 250 | Out-Null} catch {$checks.timeout=$_.Exception.ToString().Contains('Compiler wall time exceeded')}
try {Run-Probe 'output' '' 5000 | Out-Null} catch {$checks.output=$_.Exception.ToString().Contains('Compiler diagnostic output limit exceeded')}
$r=Run-Probe 'memory' ''
$checks.resources=$r.isolated -and $r.code -eq 0 -and $r.output.Trim() -eq 'MEMORY_DENIED'
$path=New-Job
$sandbox=New-Object LabVolt.Toolchain.WindowsSandbox
try {
    $sandbox.GrantDirectory($path,$true)
    $probe=Join-Path $path 'p.exe'
    $log=Join-Path $path 'descendant.log'
    $code=$sandbox.Run($probe,[string[]]@('descendant',$probe),$path,$log,(Join-Path $path 'cancel'),5000)
    $output=[IO.File]::ReadAllText($log)
    if($code -eq 0 -and $sandbox.IsolationExercised -and $output -match 'CHILD_PID=(\d+)') {
        $childPid=[int]$Matches[1]
        $running=$null -ne (Get-Process -Id $childPid -ErrorAction SilentlyContinue)
        $sandbox.Stop();Start-Sleep -Milliseconds 200
        $checks.descendants=$running -and $null -eq (Get-Process -Id $childPid -ErrorAction SilentlyContinue)
    }
} finally {$sandbox.Dispose()}
if(@(@('files','network','timeout','output','descendants','resources')|Where-Object {$checks[$_] -ne $true}).Count -eq 0) {
    $passes=@()
    foreach($board in @('uno','nano','pico')) {
        $path=Join-Path $jobs ([Guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($path)|Out-Null
        if($board -eq 'pico'){
            $source='#include "labvolt_pico.h"' + "`n" + 'int main(){lv_gpio_output(25);for(;;){lv_gpio_write(25,1);}}'
            $request=@{schema=1;board=$board;language='pico_cpp';entry='main.cpp';files=@{'main.cpp'=$source};source_sha256='acceptance-fixture'}
        } else {
            $source='void setup(){pinMode(13,OUTPUT);}' + "`n" + 'void loop(){digitalWrite(13,HIGH);}'
            $request=@{schema=1;board=$board;language='arduino_cpp';entry='main.ino';files=@{'main.ino'=$source};source_sha256='acceptance-fixture'}
        }
        [IO.File]::WriteAllText((Join-Path $path 'request.json'),($request|ConvertTo-Json -Compress -Depth 5),[Text.UTF8Encoding]::new($false))
        & (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -NonInteractive -File (Join-Path $ScriptRoot 'broker.ps1') -JobDirectory $path -Manifest $manifest
        $result=Get-Content -LiteralPath (Join-Path $path 'result.json') -Raw|ConvertFrom-Json
        $passes+=($result.ok -eq $true -and $result.status -eq 'compiled' -and $result.isolation_established -eq $true -and $result.dependencies_verified -eq $true)
    }
    $checks.compiler_pipeline=@($passes|Where-Object {$_ -ne $true}).Count -eq 0
}
$failed=@($checks.Keys|Where-Object {$checks[$_] -ne $true})
if($failed.Count){$checks|ConvertTo-Json -Compress;throw ('Native acceptance failed: '+($failed -join ', '))}
$os=[Environment]::OSVersion.Version
$osLabel='Windows:'+([string]$os.Major)+'.'+([string]$os.Minor)+'.'+([string]$os.Build)
$value=@{schema=2;launcher_sha256=(Get-FileHash -LiteralPath (Join-Path $ScriptRoot 'windows_sandbox.cs') -Algorithm SHA256).Hash.ToLowerInvariant();broker_sha256=(Get-FileHash -LiteralPath (Join-Path $ScriptRoot 'broker.ps1') -Algorithm SHA256).Hash.ToLowerInvariant();plan_sha256=(Get-FileHash -LiteralPath (Join-Path $ScriptRoot 'build_plan.ps1') -Algorithm SHA256).Hash.ToLowerInvariant();probe_sha256=(Get-FileHash -LiteralPath $ProbeExe -Algorithm SHA256).Hash.ToLowerInvariant();manifest_sha256=(Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash.ToLowerInvariant();os=$osLabel;checks=$checks}
[IO.File]::WriteAllText($receipt,($value|ConvertTo-Json -Compress -Depth 5),[Text.UTF8Encoding]::new($false))
@{ok=$true;receipt=$receipt;checks=$checks}|ConvertTo-Json -Compress -Depth 5
