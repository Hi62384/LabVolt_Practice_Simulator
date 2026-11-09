param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
Add-Type -Path (Join-Path $root 'scripts\firmware_toolchain\windows_sandbox.cs')
Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;
public static class LabVoltArgvTest {
[DllImport("shell32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr CommandLineToArgvW(string command,out int count);
[DllImport("kernel32.dll")] public static extern IntPtr LocalFree(IntPtr p);
}
'@
$checks=0
foreach($argument in @('simple','C:\with spaces\file.cpp','a"b','C:\trailing\','quote"with\\end\')){
    $command='compiler.exe '+[LabVolt.Toolchain.WindowsSandbox]::Quote($argument)
    $count=0;$argv=[LabVoltArgvTest]::CommandLineToArgvW($command,[ref]$count)
    try{$decoded=[Runtime.InteropServices.Marshal]::PtrToStringUni([Runtime.InteropServices.Marshal]::ReadIntPtr($argv,[IntPtr]::Size));if($count -ne 2 -or $decoded -ne $argument){throw 'Windows argument quoting failed'};$checks++}
    finally{[LabVoltArgvTest]::LocalFree($argv)|Out-Null}
}
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($OutputDirectory)|Out-Null
$job=Join-Path $OutputDirectory ([Guid]::NewGuid().ToString('N'))
if(-not $job.StartsWith(($OutputDirectory.TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Test directory escapes intended root'}
[IO.Directory]::CreateDirectory($job)|Out-Null
for($i=0;$i -lt 257;$i++){[IO.File]::WriteAllText((Join-Path $job ('file'+$i+'.txt')),'quota fixture')}
$rejected=$false
try{[LabVolt.Toolchain.WindowsSandbox]::CheckTree($job)}catch{$rejected=$true}
if(-not $rejected){throw 'Workspace entry quota did not reject excess files'};$checks++
[IO.File]::WriteAllText((Join-Path $job 'result.json'),'{}')
if([LabVolt.Toolchain.WindowsSandbox]::ReadText((Join-Path $job 'result.json'),2) -ne '{}'){throw 'Bounded output read failed'};$checks++
$rejected=$false;try{[LabVolt.Toolchain.WindowsSandbox]::ReadText((Join-Path $job 'result.json'),1)|Out-Null}catch{$rejected=$true}
if(-not $rejected){throw 'Oversized compiler output read accepted'};$checks++
[LabVolt.Toolchain.WindowsSandbox]::CleanupJob($job)
if(@([IO.Directory]::GetFileSystemEntries($job)).Count -ne 1 -or -not [IO.File]::Exists((Join-Path $job 'result.json'))){throw 'Bounded job cleanup failed'};$checks++
@{ok=$true;checks=$checks;note='Static boundary helper tests only; does not create profile or execute guest source'}|ConvertTo-Json
