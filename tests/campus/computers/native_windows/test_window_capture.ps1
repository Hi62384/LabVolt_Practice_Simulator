param([string]$FixtureRoot, [switch]$VerifyGpuAndInput, [switch]$LessPrivileged, [switch]$DesktopIsolation)

$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
$broker = Join-Path $project 'scripts/firmware_toolchain/windows_sandbox.cs'

if ($FixtureRoot) {
    Add-Type -Path $broker
    $sandbox = New-Object LabVolt.Toolchain.WindowsSandbox -ArgumentList ([bool]($LessPrivileged -or $DesktopIsolation)),([bool]$LessPrivileged)
    try {
        $payload = Join-Path $FixtureRoot 'payload'
        $sandbox.GrantDirectory($payload, $true)
        $title = Split-Path $FixtureRoot -Leaf
        $privateFile = Join-Path $FixtureRoot 'private.txt'
        $guestArguments = [string[]]@($privateFile, $title)
        if ($VerifyGpuAndInput) { $guestArguments += 'verify-gpu-and-input' }
        exit $sandbox.Run((Join-Path $payload 'window.exe'), $guestArguments, $payload,
            (Join-Path $FixtureRoot 'fixture.log'), (Join-Path $FixtureRoot 'no-cancel'), 15000)
    } finally {
        $sandbox.Dispose()
    }
}

if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
    throw 'Run from the Visual Studio x64 Developer PowerShell.'
}

$root = Join-Path $project ('.godot/native-window-fixture-' + [guid]::NewGuid().ToString('N'))
$payload = Join-Path $root 'payload'
New-Item -ItemType Directory -Path $payload | Out-Null
Set-Content -LiteralPath (Join-Path $root 'private.txt') -Value 'Synthetic host file outside the app scope'
$source = Join-Path $PSScriptRoot 'window_fixture.c'
Push-Location $root
try {
    & cl.exe /nologo /W4 /MT $source /link advapi32.lib user32.lib gdi32.lib d3d11.lib "/OUT:$payload/window.exe"
    if ($LASTEXITCODE -ne 0) { throw 'Could not build the window fixture.' }
} finally {
    Pop-Location
}

Add-Type -AssemblyName System.Drawing.Common
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CampusFixtureCapture {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindow(string className, string title);
    [DllImport("user32.dll")]
    public static extern bool PrintWindow(IntPtr window, IntPtr graphics, uint flags);
    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool PostMessage(IntPtr window, uint message, IntPtr key, IntPtr state);
}
'@

$arguments = @('-NoProfile', '-File', ('"{0}"' -f $PSCommandPath), '-FixtureRoot', ('"{0}"' -f $root))
if ($VerifyGpuAndInput) { $arguments += '-VerifyGpuAndInput' }
if ($LessPrivileged) { $arguments += '-LessPrivileged' }
if ($DesktopIsolation) { $arguments += '-DesktopIsolation' }
$fixtureLog = Join-Path $root 'fixture.log'
$brokerErrors = Join-Path $root 'broker-errors.log'
$process = Start-Process -FilePath powershell.exe -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardError $brokerErrors
$deadline = [DateTime]::UtcNow.AddSeconds(16)
$captured = $false
$sentInput = $false
while (-not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
    if (Test-Path -LiteralPath $fixtureLog) {
        $result = Get-Content -LiteralPath $fixtureLog -Raw
        if ($result -match 'APP_CONTAINER_WINDOW (\d+)') {
            $guest = [uint32]$Matches[1]
            $window = [CampusFixtureCapture]::FindWindow('LabVoltFixtureClass', (Split-Path $root -Leaf))
            if ($window -ne [IntPtr]::Zero) {
                [uint32]$windowOwner = 0
                [void][CampusFixtureCapture]::GetWindowThreadProcessId($window, [ref]$windowOwner)
                if ($windowOwner -ne $guest) { throw 'The window did not belong to the fixture process.' }
                $bitmap = [System.Drawing.Bitmap]::new(340, 230)
                $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
                try {
                    $context = $graphics.GetHdc()
                    try {
                        $drawn = [CampusFixtureCapture]::PrintWindow($window, $context, 2)
                    } finally {
                        $graphics.ReleaseHdc($context)
                    }
                    $pixel = $bitmap.GetPixel(140, 100)
                    if ($sentInput) {
                        $captured = $drawn -and $pixel.R -eq 208 -and $pixel.G -eq 81 -and $pixel.B -eq 38
                        if ($captured) { $bitmap.Save((Join-Path $root 'capture-after-input.png')) }
                    } else {
                        $captured = $drawn -and $pixel.R -eq 19 -and $pixel.G -eq 134 -and $pixel.B -eq 217
                        if ($captured) {
                            $bitmap.Save((Join-Path $root 'capture.png'))
                            if ($VerifyGpuAndInput) {
                                if (-not [CampusFixtureCapture]::PostMessage($window, 0x100, [IntPtr]0x78, [IntPtr]1)) {
                                    throw 'Could not send F9 to the owned fixture window.'
                                }
                                $sentInput = $true
                                $captured = $false
                            }
                        }
                    }
                } finally {
                    $graphics.Dispose()
                    $bitmap.Dispose()
                }
                if ($captured) { break }
            }
        }
    }
    Start-Sleep -Milliseconds 150
}

if (-not $process.WaitForExit(18000)) {
    Stop-Process -Id $process.Id
    throw "The fixture broker timed out. See $root."
}
if (-not $captured -or $process.ExitCode -ne 0) {
    Get-Content -LiteralPath $brokerErrors
    if (Test-Path -LiteralPath $fixtureLog) { Get-Content -LiteralPath $fixtureLog }
    throw "AppContainer graphical capture failed with broker exit $($process.ExitCode). See $root."
}
Write-Output "NATIVE_APPCONTAINER_WINDOW_CAPTURE PASS ($root)"
if ($VerifyGpuAndInput) { Write-Output 'NATIVE_APPCONTAINER_GPU_INPUT PASS' }
