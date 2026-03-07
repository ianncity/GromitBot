@echo off
setlocal enabledelayedexpansion

net session >nul 2>&1
if errorlevel 1 (
  echo ERROR: Please run this script as Administrator.
  exit /b 1
)

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "ROOT=%%~fI"
set "PROJECT=%ROOT%\src\GromitBot.Agent\GromitBot.Agent.csproj"
set "PUBLISH_DIR=%ROOT%\publish"
set "APP_EXE=%PUBLISH_DIR%\GromitBot.Agent.exe"
set "SERVICE=GromitBotAgent"
set "DOTNET_CHANNEL=10.0"
set "DOTNET_EXE=dotnet"
set "DOTNET_SYSTEM_DIR=%ProgramFiles%\dotnet"
set "DOTNET_USER_DIR=%USERPROFILE%\.dotnet"
set "DOTNET_INSTALL_SCRIPT=%TEMP%\dotnet-install.ps1"

call :ensure_dotnet
if errorlevel 1 goto :fail

echo [1/6] Ensuring runtime folders...
if not exist "%ROOT%\state" mkdir "%ROOT%\state"
if not exist "%ROOT%\profiles" mkdir "%ROOT%\profiles"
if not exist "%ROOT%\navmeshes" mkdir "%ROOT%\navmeshes"
if not exist "%ROOT%\ipc" mkdir "%ROOT%\ipc"
if not exist "%ROOT%\logs" mkdir "%ROOT%\logs"

echo [2/6] Restoring project...
"%DOTNET_EXE%" restore "%PROJECT%"
if errorlevel 1 goto :fail

echo [3/6] Publishing single-file executable...
"%DOTNET_EXE%" publish "%PROJECT%" -c Release -r win-x64 --self-contained true /p:PublishSingleFile=true -o "%PUBLISH_DIR%"
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

:ensure_dotnet
echo [preflight] Ensuring .NET SDK %DOTNET_CHANNEL% is available...

call :resolve_dotnet_exe
if not errorlevel 1 (
  call :has_required_sdk
  if not errorlevel 1 (
    echo [preflight] Found compatible .NET SDK.
    exit /b 0
  )

  echo [preflight] dotnet exists, but SDK %DOTNET_CHANNEL% is missing.
) else (
  echo [preflight] dotnet not found in PATH.
)

call :install_dotnet
if errorlevel 1 exit /b 1

call :resolve_dotnet_exe
if errorlevel 1 (
  echo ERROR: dotnet executable was not found after installation.
  exit /b 1
)

call :has_required_sdk
if errorlevel 1 (
  echo ERROR: .NET SDK %DOTNET_CHANNEL% is still unavailable after installation.
  exit /b 1
)

echo [preflight] .NET SDK is ready.
exit /b 0

:resolve_dotnet_exe
where dotnet >nul 2>&1
if not errorlevel 1 (
  set "DOTNET_EXE=dotnet"
  exit /b 0
)

if exist "%DOTNET_SYSTEM_DIR%\dotnet.exe" (
  set "DOTNET_EXE=%DOTNET_SYSTEM_DIR%\dotnet.exe"
  set "DOTNET_ROOT=%DOTNET_SYSTEM_DIR%"
  set "PATH=%DOTNET_SYSTEM_DIR%;%PATH%"
  exit /b 0
)

if exist "%DOTNET_USER_DIR%\dotnet.exe" (
  set "DOTNET_EXE=%DOTNET_USER_DIR%\dotnet.exe"
  set "DOTNET_ROOT=%DOTNET_USER_DIR%"
  set "PATH=%DOTNET_USER_DIR%;%PATH%"
  exit /b 0
)

exit /b 1

:has_required_sdk
set "HAS_SDK10="
for /f "delims=" %%S in ('"%DOTNET_EXE%" --list-sdks 2^>nul') do (
  echo %%S | findstr /R "^10\." >nul && set "HAS_SDK10=1"
)

if defined HAS_SDK10 (
  exit /b 0
)

exit /b 1

:install_dotnet
where winget >nul 2>&1
if not errorlevel 1 (
  echo [preflight] Installing .NET SDK %DOTNET_CHANNEL% via winget...
  winget install --id Microsoft.DotNet.SDK.10 --exact --silent --accept-package-agreements --accept-source-agreements
  if not errorlevel 1 exit /b 0
  echo [preflight] Winget install failed. Falling back to dotnet-install script...
)

echo [preflight] Downloading dotnet-install.ps1...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -UseBasicParsing 'https://dot.net/v1/dotnet-install.ps1' -OutFile '%DOTNET_INSTALL_SCRIPT%' } catch { exit 1 }"
if errorlevel 1 (
  echo ERROR: Failed to download dotnet-install.ps1.
  exit /b 1
)

echo [preflight] Installing .NET SDK %DOTNET_CHANNEL% to %DOTNET_USER_DIR%...
powershell -NoProfile -ExecutionPolicy Bypass -File "%DOTNET_INSTALL_SCRIPT%" -Channel %DOTNET_CHANNEL% -InstallDir "%DOTNET_USER_DIR%" -NoPath
if errorlevel 1 (
  echo ERROR: dotnet-install.ps1 failed.
  exit /b 1
)

if exist "%DOTNET_INSTALL_SCRIPT%" del /q "%DOTNET_INSTALL_SCRIPT%"
exit /b 0

:fail
echo.
echo Bootstrap failed with exit code %errorlevel%.
exit /b %errorlevel%
