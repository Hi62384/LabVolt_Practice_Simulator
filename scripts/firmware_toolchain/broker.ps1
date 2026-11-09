param([Parameter(Mandatory=$true)][string]$JobDirectory,[string]$Manifest,[switch]$ProbeOnly)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
$utf8=New-Object System.Text.UTF8Encoding($false)
$sandbox=$null
$dependenciesVerified=$false
$result=@{ok=$false;status='broker_failed';error='Compiler did not run';diagnostics=@()}
function Write-Result { param($Value) [IO.File]::WriteAllText((Join-Path $JobDirectory 'result.json'),($Value | ConvertTo-Json -Depth 25 -Compress),$utf8) }
function Safe-Name { param([string]$Name)
    return $Name.Length -le 48 -and $Name -match '^[A-Za-z0-9][A-Za-z0-9_.-]*\.(ino|cpp|c|h|hpp)$' -and -not $Name.Contains('..') -and $Name.Split('.')[0] -notmatch '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$'
}
function Under-Root { param([string]$Root,[string]$Relative)
    if([IO.Path]::IsPathRooted($Relative)){throw 'Absolute tool manifest paths are forbidden'}
    $resolved=[IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if(-not $resolved.StartsWith(([IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Tool path escapes trusted root'}
    return $resolved
}
try {
    $JobDirectory=[IO.Path]::GetFullPath($JobDirectory)
    if(-not [IO.Directory]::Exists($JobDirectory)){throw 'Host job directory missing'}
    if(([IO.File]::GetAttributes($JobDirectory) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Job directory cannot be a reparse point'}
    Add-Type -Path (Join-Path $PSScriptRoot 'windows_sandbox.cs')
    try { $sandbox=New-Object LabVolt.Toolchain.WindowsSandbox }
    catch { $result.status='sandbox_unavailable';$result.error=$_.Exception.GetBaseException().Message;throw }
    if($ProbeOnly){$result=@{ok=$true;status='profile_created_runtime_unverified';isolation=$sandbox.Isolation;diagnostics=@()};Write-Result $result;exit 0}
    if(-not [IO.File]::Exists($Manifest)){$result.status='dependencies_missing';throw 'Run the host-owned official dependency setup; no trusted compiler manifest is installed'}
    if((Get-Item -LiteralPath $Manifest).Length -gt 8388608){throw 'Trusted manifest exceeds bounds'}
    $hostManifest=Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
    if($hostManifest.schema -ne 1){throw 'Unsupported trusted toolchain manifest'}
    $tools=Under-Root (Split-Path -Parent $Manifest) ([string]$hostManifest.tools_root)
    $knownFiles=@{}
    foreach($record in $hostManifest.files){
        $file=Under-Root $tools ([string]$record.path)
        if($knownFiles.ContainsKey($file)){throw 'Duplicate dependency manifest entry'}
        $knownFiles[$file]=$true
        if(-not [IO.File]::Exists($file) -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne ([string]$record.sha256).ToLowerInvariant()){throw ('Trusted dependency changed or is missing: '+$record.path)}
    }
    foreach($file in Get-ChildItem -LiteralPath $tools -Recurse -File){if(-not $knownFiles.ContainsKey($file.FullName)){throw 'Unlisted file in trusted compiler root'}}
    $dependenciesVerified=$true
    $requestPath=Join-Path $JobDirectory 'request.json'
    if((Get-Item -LiteralPath $requestPath).Length -gt 2097152){throw 'Compile request exceeds bounds'}
    $request=Get-Content -LiteralPath $requestPath -Raw | ConvertFrom-Json
    foreach($property in $request.PSObject.Properties.Name){if($property -notin @('schema','board','language','entry','files','source_sha256')){throw 'Unknown compile option'}}
    if($request.schema -ne 1 -or $request.board -notin @('uno','nano','pico')){throw 'Invalid compile target'}
    if($request.language -ne $(if($request.board -in @('uno','nano')){'arduino_cpp'}else{'pico_cpp'})){throw 'Unsupported source language/runtime'}
    if([string]$request.board -notin @($hostManifest.targets.PSObject.Properties.Name)){$result.status='dependencies_missing';throw ('No trusted '+$request.board+' toolchain is installed')}
    $target=$hostManifest.targets.($request.board)
    if($null -eq $target){$result.status='dependencies_missing';throw ('No trusted '+$request.board+' toolchain is installed')}
    $files=@($request.files.PSObject.Properties)
    if($files.Count -lt 1 -or $files.Count -gt 16){throw 'Project requires 1-16 files'}
    $names=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $total=0
    foreach($file in $files){
        if(-not (Safe-Name $file.Name) -or -not ($file.Value -is [string]) -or -not $names.Add($file.Name)){throw 'Unsafe or duplicate source filename'}
        $size=$utf8.GetByteCount($file.Value);$total+=$size
        if($size -gt 65536 -or $file.Value.Contains([char]0)){throw 'Source file exceeds bounds'}
    }
    if($total -gt 1048576 -or -not $names.Contains([string]$request.entry)){throw 'Invalid source project size or entry'}
    $source=Join-Path $JobDirectory 'src';$build=Join-Path $JobDirectory 'build'
    [IO.Directory]::CreateDirectory($source)|Out-Null;[IO.Directory]::CreateDirectory($build)|Out-Null
    foreach($file in $files){[IO.File]::WriteAllText((Join-Path $source $file.Name),$file.Value,$utf8)}
    $sandbox.GrantDirectory($tools,$false);$sandbox.GrantDirectory($JobDirectory,$true)
    . (Join-Path $PSScriptRoot 'build_plan.ps1')
    $plan=New-LabVoltCompilePlan -ToolRoot $tools -Target $target -Board $request.board -SourceDirectory $source -BuildDirectory $build -SupportDirectory (Join-Path $PSScriptRoot 'pico_support')
    $elf=$plan.elf;$image=$plan.image;$objdump=$plan.objdump
    $allOutput='';$step=0
    foreach($command in $plan.commands){
        $log=Join-Path $build ('step'+$step+'.log');$step++
        $code=$sandbox.Run($command.exe,[string[]]$command.args,$JobDirectory,$log,(Join-Path $JobDirectory 'cancel'),30000)
        if([IO.File]::Exists($log)){$allOutput+=[LabVolt.Toolchain.WindowsSandbox]::ReadText($log,262144)}
        if($allOutput.Length -gt 262144){throw 'Aggregate compiler diagnostics exceed limit'}
        if($code -ne 0){$result.status='compile_failed';$result.error='Compilation failed; see source diagnostics';$result.output=$allOutput;$result.compiler_exit_code=$code;$result.stage=$step;throw 'Compiler returned non-zero exit status'}
    }
    $lineLog=Join-Path $build 'source-map.log'
    $code=$sandbox.Run($objdump,@('--dwarf=decodedline',$elf),$JobDirectory,$lineLog,(Join-Path $JobDirectory 'cancel'),10000)
    $sandbox.Stop() # Quiesce every descendant before the privileged broker reads artifacts.
    [LabVolt.Toolchain.WindowsSandbox]::CheckTree($JobDirectory)
    $map=New-Object 'System.Collections.Generic.List[object]'
    if($code -eq 0 -and (Get-Item -LiteralPath $lineLog).Length -le 262144){
        foreach($line in ([LabVolt.Toolchain.WindowsSandbox]::ReadText($lineLog,262144)).Split("`n")){
            if($line -match '^\s*(\S+)\s+(\d+)\s+(0x[0-9a-fA-F]+)'){
                $name=[IO.Path]::GetFileName($Matches[1]);if($name.EndsWith('.ino.cpp')){$name=$name.Substring(0,$name.Length-4)}
                if($names.Contains($name) -and $map.Count -lt 16384){$map.Add(@{file=$name;line=[int]$Matches[2];pc=[Convert]::ToInt64($Matches[3].Substring(2),16)})}
            }
        }
    }
    $bytes=[LabVolt.Toolchain.WindowsSandbox]::ReadBytes($image,$(if($request.board -in @('uno','nano')){131072}else{2097152}))
    if($bytes.Length -gt $(if($request.board -in @('uno','nano')){131072}else{2097152})){throw 'Firmware exceeds board image bound'}
    $firmware=@{schema=1;board=[string]$request.board;format=$(if($request.board -in @('uno','nano')){'intel_hex'}else{'bin_base64'});image=$(if($request.board -in @('uno','nano')){$utf8.GetString($bytes)}else{[Convert]::ToBase64String($bytes)})}
    if($request.board -eq 'pico'){$firmware.vector_offset=256}
    $result=@{ok=$true;status='compiled';firmware=$firmware;source_map=$map.ToArray();output=$allOutput;diagnostics=@();artifact=@{source_sha256=[string]$request.source_sha256;toolchain_id=[string]$hostManifest.id;isolation=$sandbox.Isolation;language=[string]$request.language;pico_mode='bare-metal C/C++, no general SDK/USB/bootROM/MicroPython claim'}}
} catch {
    if($result.status -eq 'broker_failed'){$result.error=$_.Exception.GetBaseException().Message}
    elseif(-not $result.ContainsKey('output') -and $result.status -ne 'sandbox_unavailable'){$result.error=$_.Exception.GetBaseException().Message}
} finally {
    $result.isolation_established=($null -ne $sandbox -and $sandbox.IsolationExercised)
    $result.dependencies_verified=$dependenciesVerified
    if($null -ne $sandbox){$sandbox.Dispose()}
    Write-Result $result
    try { [LabVolt.Toolchain.WindowsSandbox]::CleanupJob($JobDirectory) }
    catch { $result.ok=$false;$result.status='cleanup_failed';$result.error='Compiler scratch cleanup failed; artifact not accepted';Write-Result $result }
}
if($result.ok){exit 0}else{exit 1}
