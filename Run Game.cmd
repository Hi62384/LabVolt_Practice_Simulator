@echo off
setlocal
cd /d "%~dp0."
where dotnet >nul 2>&1
if errorlevel 1 (
 echo Install the .NET 8 or newer SDK before launching this C# enabled game.
 pause
 exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\setup_dotnet_runtime.ps1"
if errorlevel 1 (
 echo The matching Godot .NET runtime could not be prepared.
 pause
 exit /b 1
)
dotnet build CollegeSimulator.csproj --configuration Debug
if errorlevel 1 (
 echo The circuit simulation C# build failed.
 pause
 exit /b 1
)
echo Preparing LabVolt assets...
"runtime\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe" --headless --path . --import
if errorlevel 1 (
 echo.
 echo LabVolt asset preparation failed. The error is shown above.
 pause
 exit /b 1
)
"runtime\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64_console.exe" --path . %*
if errorlevel 1 (
 echo.
 echo LabVolt could not start. The error is shown above.
 pause
)
