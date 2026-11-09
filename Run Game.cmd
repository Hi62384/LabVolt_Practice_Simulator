@echo off
setlocal
cd /d "%~dp0."
if not exist "runtime\Godot_v4.5.1-stable_win64_console.exe" (
 echo Missing Godot runtime in the runtime folder.
 pause
 exit /b 1
)
echo Preparing LabVolt assets...
"runtime\Godot_v4.5.1-stable_win64_console.exe" --headless --path . --import
if errorlevel 1 (
 echo.
 echo LabVolt asset preparation failed. The error is shown above.
 pause
 exit /b 1
)
"runtime\Godot_v4.5.1-stable_win64_console.exe" --path . %*
if errorlevel 1 (
 echo.
 echo LabVolt could not start. The error is shown above.
 pause
)
