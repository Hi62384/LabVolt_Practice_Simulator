param([Parameter(Mandatory=$true)][string]$Manifest,[Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
function Under-Root {param($Root,$Relative) $resolved=[IO.Path]::GetFullPath((Join-Path $Root $Relative));if(-not $resolved.StartsWith(($Root.TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Escaping tool path'};return $resolved}
. (Join-Path $root 'scripts\firmware_toolchain\build_plan.ps1')
$metadata=Get-Content -LiteralPath $Manifest -Raw|ConvertFrom-Json
$tools=Under-Root (Split-Path -Parent $Manifest) $metadata.tools_root
$source=Join-Path $OutputDirectory 'src';$build=Join-Path $OutputDirectory 'build'
[IO.Directory]::CreateDirectory($source)|Out-Null;[IO.Directory]::CreateDirectory($build)|Out-Null
[IO.File]::WriteAllText((Join-Path $source 'sketch.ino'),"#include <SPI.h>`n#include <Wire.h>`n#include <EEPROM.h>`nvoid setup(){} void loop(){}")
$plan=New-LabVoltCompilePlan -ToolRoot $tools -Target $metadata.targets.uno -Board uno -SourceDirectory $source -BuildDirectory $build
$inputs=@($plan.commands |ForEach-Object {$_.args}|Where-Object {$_ -match '\.(cpp|c)$'})
foreach($required in @('SPI.cpp','Wire.cpp','twi.c')){if(@($inputs|Where-Object {[IO.Path]::GetFileName($_) -eq $required}).Count -ne 1){throw ('Missing official library translation unit '+$required)}}
@{ok=$true;checks=3;status='Official SPI/Wire/EEPROM planner, no compiler executed';command_count=$plan.commands.Count}|ConvertTo-Json
