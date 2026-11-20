@echo off
setlocal EnableExtensions

rem Noctis Live V5 - portable Windows launcher.
rem Optional: set GODOT_EXE to the full path of your Godot 4.6+ executable.

set "YEDAMAR_ENGINE="

if defined GODOT_EXE if exist "%GODOT_EXE%" set "YEDAMAR_ENGINE=%GODOT_EXE%"
if defined YEDAMAR_ENGINE goto engine_found

for %%G in (
  "%~dp0Godot_v4.7.2-stable_win64.exe"
  "%~dp0Godot_v4.6.2-stable_win64.exe"
  "%~dp0Godot_v4.7.2-stable_win64_console.exe"
  "%~dp0Godot_v4.6.2-stable_win64_console.exe"
  "%~dp0godot.exe"
  "%~dp0godot_console.exe"
) do (
  if exist "%%~G" (
    set "YEDAMAR_ENGINE=%%~G"
    goto engine_found
  )
)

where godot.exe >nul 2>nul
if not errorlevel 1 (
  set "YEDAMAR_ENGINE=godot.exe"
  goto engine_found
)

where godot >nul 2>nul
if not errorlevel 1 (
  set "YEDAMAR_ENGINE=godot"
  goto engine_found
)

echo.
echo Godot 4.6 or newer was not found.
echo Install Godot 4.6/4.7, or set GODOT_EXE to its executable path.
echo Example:
echo   set GODOT_EXE=C:\Tools\Godot\Godot_v4.7.2-stable_win64.exe
echo Then run Play.cmd again.
echo.
pause
exit /b 1

:engine_found
echo Using: "%YEDAMAR_ENGINE%"
echo.
echo Importing project resources. The first import can take several minutes...
"%YEDAMAR_ENGINE%" --headless --editor --path "%~dp0." --import --quit
if errorlevel 1 (
  echo.
  echo Resource import failed. Open project.godot in Godot and inspect the errors.
  pause
  exit /b 1
)

echo Starting Noctis Live V5...
start "" "%YEDAMAR_ENGINE%" --path "%~dp0."
endlocal
