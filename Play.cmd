@echo off
setlocal
set "YEDAMAR_ENGINE=E:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
if exist "%YEDAMAR_ENGINE%" goto launch
set "YEDAMAR_ENGINE=%~dp0..\..\work\godot-bin\Godot_v4.6.2-stable_win64.exe"
if exist "%YEDAMAR_ENGINE%" goto launch
echo Open project.godot with Godot 4.6 or newer, then press F5.
pause
exit /b 1
:launch
echo Noctis Live V5 - preparing resources. First import can take several minutes...
start "" /wait "%YEDAMAR_ENGINE%" --headless --editor --path "%~dp0." --import --quit
if not "%ERRORLEVEL%"=="0" (
    echo Resource import failed. Open project.godot in the editor to inspect the error.
    pause
    exit /b 1
)
start "" "%YEDAMAR_ENGINE%" --path "%~dp0."
endlocal
