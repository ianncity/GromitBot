@echo off
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "ROOT=%%~fI"
set "PROJECT=%ROOT%\src\GromitBot.Agent\GromitBot.Agent.csproj"
set "PUBLISH_DIR=%ROOT%\publish"
set "APP_EXE=%PUBLISH_DIR%\GromitBot.Agent.exe"
set "SERVICE=GromitBotAgent"

echo [1/6] Ensuring runtime folders...
if not exist "%ROOT%\state" mkdir "%ROOT%\state"
if not exist "%ROOT%\profiles" mkdir "%ROOT%\profiles"
if not exist "%ROOT%\navmeshes" mkdir "%ROOT%\navmeshes"
if not exist "%ROOT%\ipc" mkdir "%ROOT%\ipc"
if not exist "%ROOT%\logs" mkdir "%ROOT%\logs"

echo [2/6] Restoring project...
dotnet restore "%PROJECT%"
if errorlevel 1 goto :fail

echo [3/6] Publishing single-file executable...
dotnet publish "%PROJECT%" -c Release -r win-x64 --self-contained true /p:PublishSingleFile=true -o "%PUBLISH_DIR%"
if errorlevel 1 goto :fail

if not exist "%APP_EXE%" (
  echo ERROR: Published executable not found: %APP_EXE%
  goto :fail
)

echo [4/6] Creating/updating Windows service...
sc.exe query "%SERVICE%" >nul 2>&1
if errorlevel 1 (
  sc.exe create "%SERVICE%" binPath= "\"%APP_EXE%\" --contentRoot \"%ROOT%\"" start= auto
  if errorlevel 1 goto :fail
) else (
  sc.exe stop "%SERVICE%" >nul 2>&1
  sc.exe config "%SERVICE%" binPath= "\"%APP_EXE%\" --contentRoot \"%ROOT%\"" start= auto
  if errorlevel 1 goto :fail
)

echo [5/6] Configuring recovery policy...
sc.exe failure "%SERVICE%" reset= 0 actions= restart/60000/restart/60000/restart/60000
if errorlevel 1 goto :fail

echo [6/6] Starting service...
sc.exe start "%SERVICE%"
if errorlevel 1 goto :fail

echo.
echo Bootstrap completed successfully.
echo Service: %SERVICE%
echo Root: %ROOT%
goto :eof

:fail
echo.
echo Bootstrap failed with exit code %errorlevel%.
exit /b %errorlevel%
