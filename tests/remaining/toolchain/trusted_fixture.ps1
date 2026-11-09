param([Parameter(Mandatory=$true)][string]$Manifest,[Parameter(Mandatory=$true)][string]$OutputDirectory,[switch]$ExecuteTrustedFixture)
$ErrorActionPreference='Stop'
$sourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$planner=Join-Path $sourceRoot 'scripts\firmware_toolchain\build_plan.ps1'
function Under-Root { param([string]$Root,[string]$Relative)
    $path=[IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if([IO.Path]::IsPathRooted($Relative) -or -not $path.StartsWith(([IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Tool path escapes root'}
    return $path
}
. $planner
$metadata=Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
$tools=Under-Root (Split-Path -Parent $Manifest) $metadata.tools_root
foreach($record in $metadata.files){$path=Under-Root $tools $record.path;if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.sha256){throw 'Trusted dependency mismatch'}}
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
$source=Join-Path $OutputDirectory 'src';$build=Join-Path $OutputDirectory 'build'
[IO.Directory]::CreateDirectory($source)|Out-Null;[IO.Directory]::CreateDirectory($build)|Out-Null
# This test accepts no source argument and copies only the immutable shipped
# trusted UnoBlink fixture. Never expose its execution switch to player projects.
$fixture=Join-Path $sourceRoot 'assets\workers\firmware\UnoBlink.ino'
Copy-Item -LiteralPath $fixture -Destination (Join-Path $source 'sketch.ino') -Force
$plan=New-LabVoltCompilePlan -ToolRoot $tools -Target $metadata.targets.uno -Board uno -SourceDirectory $source -BuildDirectory $build -SupportDirectory (Join-Path $sourceRoot 'scripts\firmware_toolchain\pico_support')
$checks=0
foreach($command in $plan.commands){
    if(-not (Test-Path -LiteralPath $command.exe)){throw 'Build planner chose missing executable'}
    if(@($command.args | Where-Object {$_ -like '-I*'}).Count -lt 3 -and $command.exe.EndsWith('g++.exe') -and '-c' -in $command.args){throw 'Missing independent include arguments'}
    foreach($argument in $command.args){if([string]$argument -match '-I.*-I'){throw 'Merged include arguments'}}
    $checks++
}
$plan | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'build-plan.json') -Encoding UTF8
if($ExecuteTrustedFixture){
    foreach($command in $plan.commands){$arguments=[string[]]$command.args;& $command.exe @arguments;if($LASTEXITCODE -ne 0){throw ('Trusted fixture compiler exit '+$LASTEXITCODE)}}
    & $plan.objdump '--dwarf=decodedline' $plan.elf | Set-Content -LiteralPath (Join-Path $OutputDirectory 'source-map.txt') -Encoding utf8
    if($LASTEXITCODE -ne 0){throw 'Trusted fixture line-map extraction failed'}
    @{ok=$true;checks=$checks;image=$plan.image;image_sha256=(Get-FileHash -LiteralPath $plan.image -Algorithm SHA256).Hash;note='Only shipped trusted fixture compiled; untrusted source compile remains LPAC-gated'}|ConvertTo-Json
}else{@{ok=$true;checks=$checks;status='plan_validated_no_compiler_executed'}|ConvertTo-Json}
