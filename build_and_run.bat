@echo off
setlocal EnableDelayedExpansion

:: ================================================================
::  build_and_run.bat -- Fresh-VM bootstrap, build, launch
::                       and inject GromitBot on Turtle WoW
:: ================================================================
::  Run as Administrator the first time on a fresh Windows 10/11
::  machine.  Installs every missing prerequisite, builds the DLL,
::  deploys the addon, launches Turtle WoW and injects GromitBot.dll.
::  Subsequent runs skip any step whose output already exists.
::  Edit the CONFIG block below if your paths differ from defaults.
:: ================================================================

:: ---- Safety net: guarantee the window never closes silently ----
:: call :main does all the work; no matter how it exits we pause.
call :main
set "MAIN_EC=!ERRORLEVEL!"
echo.
if !MAIN_EC! NEQ 0 (
    echo ================================================================
    echo   FAILED -- check the errors above.
    echo ================================================================
) else (
    echo ================================================================
    echo   Done.
    echo ================================================================
)
pause
endlocal
exit /b !MAIN_EC!

:: ================================================================
:: :main -- all real work lives here
:: ================================================================
:main

:: ================================================================
:: CONFIG -- edit these paths to match your installation
:: ================================================================
set "WOW_DIR=C:\TurtleWoW"
set "LUA_DIR=C:\lua51"
set "DXSDK_DIR=C:\DXSDK"
set "GROMITBOT_DIR=C:\GromitBot"
set "WOW_WAIT_SECS=60"

:: ---- Derived paths (do not edit) ------------------------------
set "LUA_INCLUDE_DIR=!LUA_DIR!\include"
set "LUA_LIB=!LUA_DIR!\lua51.lib"
set "D3D8_INCLUDE_DIR=!DXSDK_DIR!\include"
set "SCRIPT_DIR=%~dp0"
:: Strip trailing backslash so quoted paths never end with \"
if "!SCRIPT_DIR:~-1!"=="\" set "SCRIPT_DIR=!SCRIPT_DIR:~0,-1!"
set "BUILD_DIR=!SCRIPT_DIR!\build"
set "DLL_PATH=!BUILD_DIR!\Release\GromitBot.dll"
set "INJECTOR=!BUILD_DIR!\Release\injector.exe"
set "HTTPLIB=!SCRIPT_DIR!\dll\include\httplib.h"
set "ADDON_SRC=!SCRIPT_DIR!\addon"
set "ADDON_DST=!WOW_DIR!\Interface\AddOns\GromitBot"
set "SWOW_LAUNCHER=!WOW_DIR!\SuperWoWlauncher.exe"

echo ================================================================
echo   GromitBot -- Fresh-VM Bootstrap, Build, Launch and Inject
echo ================================================================
echo.

:: ================================================================
:: ADMINISTRATOR CHECK -- auto-elevate if not already admin
:: ================================================================
fsutil dirty query %SystemDrive% >nul 2>&1
if errorlevel 1 (
    echo [*] Not running as Administrator -- requesting elevation...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b 0
)
echo [+] Running as Administrator.
echo.

:: ================================================================
:: PHASE 0 -- Install prerequisites
:: ================================================================
echo ================================================================
echo   Phase 0: Installing prerequisites
echo ================================================================
echo.

call :install_vs
if errorlevel 1 exit /b 1

call :install_cmake
if errorlevel 1 exit /b 1

call :install_python
if errorlevel 1 exit /b 1

call :install_lua
if errorlevel 1 exit /b 1

call :install_dxsdk
if errorlevel 1 exit /b 1

call :install_pip_deps
if errorlevel 1 exit /b 1

echo.
echo [+] All prerequisites satisfied.
echo.

:: ================================================================
:: PHASE 1 -- Locate Visual Studio x86 toolset
:: ================================================================
echo ================================================================
echo   Phases 1-6: Build, Deploy, Launch and Inject
echo ================================================================
echo.

call :locate_vs_toolset
if errorlevel 1 exit /b 1

call :fetch_httplib
if errorlevel 1 exit /b 1

call :cmake_configure
if errorlevel 1 exit /b 1

call :cmake_build
if errorlevel 1 exit /b 1

call :deploy_addon
if errorlevel 1 exit /b 1

call :launch_and_inject
if errorlevel 1 exit /b 1

echo.
echo ================================================================
echo   GromitBot injected successfully!
echo   Start the bot in-game with:  /gbot start
echo   Python agent is running in its own window on port 9000.
echo ================================================================
exit /b 0

:: ================================================================
:: SUBROUTINES
:: ================================================================

:: ----------------------------------------------------------------
:install_vs
:: ----------------------------------------------------------------
echo [0a] Checking Visual Studio 2022 Build Tools...
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if exist "!VSWHERE!" (
    echo [+] VS Build Tools already installed.
    exit /b 0
)
echo [*] VS Build Tools not found.
echo     Downloading installer -- this may take 10-20 minutes...
curl -L --silent "https://aka.ms/vs/17/release/vs_BuildTools.exe" -o "%TEMP%\vs_BuildTools.exe"
if errorlevel 1 (
    echo [!] Failed to download VS Build Tools installer.
    exit /b 1
)
echo [*] Installing VS Build Tools -- a progress window will appear...
"%TEMP%\vs_BuildTools.exe" --passive --wait --norestart ^
    --add Microsoft.VisualStudio.Workload.VCTools ^
    --includeRecommended ^
    --add Microsoft.VisualStudio.Component.Windows10SDK.19041
set "VS_EC=!ERRORLEVEL!"
if !VS_EC! EQU 3010 (
    echo [+] VS Build Tools installed -- a reboot is required.
    echo     Please reboot and re-run this script.
    exit /b 1
)
if !VS_EC! NEQ 0 (
    echo [!] VS Build Tools installation failed (exit code !VS_EC!).
    exit /b 1
)
echo [+] VS Build Tools installed.
exit /b 0

:: ----------------------------------------------------------------
:install_cmake
:: ----------------------------------------------------------------
echo.
echo [0b] Checking CMake...
set "CMAKE_DIR=C:\cmake"
:: Check if cmake is already on PATH or in our known install location
where cmake >nul 2>&1
if not errorlevel 1 (
    echo [+] CMake already installed.
    exit /b 0
)
if exist "!CMAKE_DIR!\bin\cmake.exe" (
    set "PATH=!PATH!;!CMAKE_DIR!\bin"
    echo [+] CMake found at !CMAKE_DIR!
    exit /b 0
)
echo [*] CMake not found -- downloading portable zip...
set "CMAKE_ZIP=%TEMP%\cmake.zip"
set "CMAKE_EXTRACT=%TEMP%\cmake_extract"
curl -L --silent "https://github.com/Kitware/CMake/releases/download/v3.28.3/cmake-3.28.3-windows-x86_64.zip" -o "!CMAKE_ZIP!"
if errorlevel 1 (
    echo [^^!] Failed to download CMake.
    exit /b 1
)
echo [*] Extracting CMake...
if not exist "!CMAKE_EXTRACT!" mkdir "!CMAKE_EXTRACT!"
tar -xf "!CMAKE_ZIP!" -C "!CMAKE_EXTRACT!" 2>nul
if errorlevel 1 (
    echo [^^!] Failed to extract CMake archive.
    exit /b 1
)
:: Move the extracted folder to C:\cmake
if exist "!CMAKE_DIR!" rmdir /s /q "!CMAKE_DIR!"
move "!CMAKE_EXTRACT!\cmake-3.28.3-windows-x86_64" "!CMAKE_DIR!" >nul
if errorlevel 1 (
    echo [^^!] Failed to move CMake to !CMAKE_DIR!
    exit /b 1
)
set "PATH=!PATH!;!CMAKE_DIR!\bin"
echo [+] CMake installed to !CMAKE_DIR!
exit /b 0

:: ----------------------------------------------------------------
:install_python
:: ----------------------------------------------------------------
echo.
echo [0c] Checking Python...
set "PYTHON="
for /f "tokens=*" %%i in ('where python 2^>nul') do (
    if not defined PYTHON set "PYTHON=%%i"
)
:: Verify the found python is real (Windows Store stub just opens the Store)
if defined PYTHON (
    "!PYTHON!" --version >nul 2>&1
    if errorlevel 1 set "PYTHON="
)
if defined PYTHON (
    echo [+] Python found: !PYTHON!
    exit /b 0
)
echo [*] Python not found -- downloading Python 3.11 installer...
curl -L --silent "https://www.python.org/ftp/python/3.11.9/python-3.11.9.exe" -o "%TEMP%\python311_installer.exe"
if errorlevel 1 (
    echo [!] Failed to download Python 3.11 installer.
    exit /b 1
)
"%TEMP%\python311_installer.exe" /quiet InstallAllUsers=1 PrependPath=1 Include_test=0
if errorlevel 1 (
    echo [!] Python 3.11 installation failed.
    exit /b 1
)
:: Probe the common install locations
if exist "%LOCALAPPDATA%\Programs\Python\Python311\python.exe" (
    set "PYTHON=%LOCALAPPDATA%\Programs\Python\Python311\python.exe"
    set "PATH=!PATH!;%LOCALAPPDATA%\Programs\Python\Python311;%LOCALAPPDATA%\Programs\Python\Python311\Scripts"
)
if not defined PYTHON if exist "C:\Program Files\Python311\python.exe" (
    set "PYTHON=C:\Program Files\Python311\python.exe"
    set "PATH=!PATH!;C:\Program Files\Python311;C:\Program Files\Python311\Scripts"
)
if not defined PYTHON (
    for /f "tokens=*" %%i in ('where python 2^>nul') do (
        if not defined PYTHON set "PYTHON=%%i"
    )
)
if not defined PYTHON (
    echo [!] Could not locate python.exe after installation.
    echo     Open a new terminal and re-run this script.
    exit /b 1
)
echo [+] Python installed: !PYTHON!
exit /b 0

:: ----------------------------------------------------------------
:install_lua
:: ----------------------------------------------------------------
echo.
echo [0d] Checking Lua 5.1...
if exist "!LUA_LIB!" (
    echo [+] Lua 5.1 already present.
    exit /b 0
)
echo [*] Lua 5.1 not found at !LUA_DIR! -- downloading from luabinaries...
set "LUA_URL=https://sourceforge.net/projects/luabinaries/files/5.1.5/Windows%%20Libraries/Static/lua-5.1.5_Win32_vc14_lib.zip/download"
curl -L --silent --max-redirs 10 "!LUA_URL!" -o "%TEMP%\lua51.zip"
if errorlevel 1 (
    echo [!] Failed to download Lua 5.1 binaries from SourceForge.
    exit /b 1
)
if not exist "!LUA_DIR!" mkdir "!LUA_DIR!"
if not exist "!LUA_INCLUDE_DIR!" mkdir "!LUA_INCLUDE_DIR!"
if not exist "%TEMP%\lua51_extract" mkdir "%TEMP%\lua51_extract"
tar -xf "%TEMP%\lua51.zip" -C "%TEMP%\lua51_extract" 2>nul
if errorlevel 1 (
    echo [!] Failed to extract Lua 5.1 archive.
    exit /b 1
)
for /r "%TEMP%\lua51_extract" %%f in (lua51.lib) do copy /Y "%%f" "!LUA_DIR!\" >nul
for /r "%TEMP%\lua51_extract" %%f in (lua.h lualib.h lauxlib.h luaconf.h) do copy /Y "%%f" "!LUA_INCLUDE_DIR!\" >nul
echo [+] Lua 5.1 installed to !LUA_DIR!
exit /b 0

:: ----------------------------------------------------------------
:install_dxsdk
:: ----------------------------------------------------------------
echo.
echo [0e] Checking DirectX 8 SDK headers...
if exist "!D3D8_INCLUDE_DIR!\d3d8.h" (
    echo [+] DXSDK headers already present.
    exit /b 0
)
echo [*] DXSDK headers not found -- downloading from apitrace/dxsdk...
curl -L --silent "https://github.com/apitrace/dxsdk/archive/refs/heads/master.zip" -o "%TEMP%\dxsdk.zip"
if errorlevel 1 (
    echo [!] Failed to download DXSDK headers.
    exit /b 1
)
if not exist "!DXSDK_DIR!" mkdir "!DXSDK_DIR!"
if not exist "!D3D8_INCLUDE_DIR!" mkdir "!D3D8_INCLUDE_DIR!"
if not exist "%TEMP%\dxsdk_extract" mkdir "%TEMP%\dxsdk_extract"
tar -xf "%TEMP%\dxsdk.zip" -C "%TEMP%\dxsdk_extract" 2>nul
if errorlevel 1 (
    echo [!] Failed to extract DXSDK headers.
    exit /b 1
)
xcopy /E /Y /Q "%TEMP%\dxsdk_extract\dxsdk-master\Include\*" "!D3D8_INCLUDE_DIR!\" >nul
echo [+] DXSDK headers installed to !D3D8_INCLUDE_DIR!
exit /b 0

:: ----------------------------------------------------------------
:install_pip_deps
:: ----------------------------------------------------------------
echo.
echo [0f] Installing Python agent requirements...
"!PYTHON!" -m pip install --quiet -r "!SCRIPT_DIR!\agent\requirements.txt"
if errorlevel 1 (
    echo [!] pip install failed.
    exit /b 1
)
echo [+] Python requirements installed.
exit /b 0

:: ----------------------------------------------------------------
:locate_vs_toolset
:: ----------------------------------------------------------------
echo [1/6] Locating Visual Studio x86 toolset...
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "!VSWHERE!" (
    echo [!] vswhere.exe not found.
    echo     VS Build Tools may still be installing; try re-running.
    exit /b 1
)
set "VS_PATH="
for /f "usebackq tokens=*" %%i in (`"!VSWHERE!" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS_PATH=%%i"
if not defined VS_PATH (
    echo [!] Visual Studio with C++ Desktop workload not found.
    exit /b 1
)
set "VCVARS=!VS_PATH!\VC\Auxiliary\Build\vcvars32.bat"
if not exist "!VCVARS!" (
    echo [!] vcvars32.bat not found: !VCVARS!
    exit /b 1
)
echo [+] Found: !VS_PATH!
call "!VCVARS!" >nul
exit /b 0

:: ----------------------------------------------------------------
:fetch_httplib
:: ----------------------------------------------------------------
echo [2/6] Checking cpp-httplib...
if exist "!HTTPLIB!" (
    echo [+] httplib.h already present.
    exit /b 0
)
echo [*] httplib.h not found -- downloading v0.14.3...
curl -L --silent "https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.14.3/httplib.h" -o "!HTTPLIB!"
if errorlevel 1 (
    echo [!] Failed to download httplib.h.
    exit /b 1
)
echo [+] httplib.h downloaded.
exit /b 0

:: ----------------------------------------------------------------
:cmake_configure
:: ----------------------------------------------------------------
echo [3/6] Configuring CMake (32-bit Release)...
cmake -B "!BUILD_DIR!" -A Win32 ^
    -DLUA_INCLUDE_DIR="!LUA_INCLUDE_DIR!" ^
    -DLUA_LIB="!LUA_LIB!" ^
    -DD3D8_INCLUDE_DIR="!D3D8_INCLUDE_DIR!" ^
    "!SCRIPT_DIR!"
if errorlevel 1 (
    echo [!] CMake configure failed.
    exit /b 1
)
exit /b 0

:: ----------------------------------------------------------------
:cmake_build
:: ----------------------------------------------------------------
echo [4/6] Building GromitBot.dll and injector.exe...
cmake --build "!BUILD_DIR!" --config Release
if errorlevel 1 (
    echo [!] Build failed. See output above.
    exit /b 1
)
if not exist "!DLL_PATH!" (
    echo [!] GromitBot.dll not found after build: !DLL_PATH!
    exit /b 1
)
if not exist "!INJECTOR!" (
    echo [!] injector.exe not found after build: !INJECTOR!
    exit /b 1
)
echo [+] Build successful.
exit /b 0

:: ----------------------------------------------------------------
:deploy_addon
:: ----------------------------------------------------------------
echo [5/6] Deploying addon and SuperWoW files...
if not exist "!WOW_DIR!" (
    echo [!] WoW directory not found: !WOW_DIR!
    echo     Set WOW_DIR at the top of this script to your Turtle WoW folder.
    exit /b 1
)
if not exist "!ADDON_DST!" mkdir "!ADDON_DST!"
xcopy /E /Y /Q "!ADDON_SRC!\*" "!ADDON_DST!\" >nul
echo [+] Addon copied to !ADDON_DST!
if not exist "!SWOW_LAUNCHER!" (
    echo [*] SuperWoWlauncher.exe not found in WoW dir -- copying...
    copy /Y "!SCRIPT_DIR!\superwow\SuperWoWlauncher.exe" "!WOW_DIR!\" >nul
    copy /Y "!SCRIPT_DIR!\superwow\SuperWoWhook.dll"     "!WOW_DIR!\" >nul
    echo [+] SuperWoW files copied to !WOW_DIR!
) else (
    echo [+] SuperWoW already present.
)
exit /b 0

:: ----------------------------------------------------------------
:launch_and_inject
:: ----------------------------------------------------------------
echo [6/6] Starting services, launching Turtle WoW, and injecting...
if not exist "!GROMITBOT_DIR!" mkdir "!GROMITBOT_DIR!"
set "GROMITBOT_BOT_BASE_DIR=!GROMITBOT_DIR!\bots"

echo [*] Starting Python agent (port 9000)...
start "GromitBot Agent" cmd /k "!PYTHON!" "!SCRIPT_DIR!\agent\agent.py"
timeout /t 5 /nobreak >nul

echo [*] Launching Turtle WoW via SuperWoWlauncher.exe...
start "" "!SWOW_LAUNCHER!"

echo [*] Waiting for WoW.exe to start (up to !WOW_WAIT_SECS! seconds)...
set /a "tries=!WOW_WAIT_SECS!"
:_wait_loop
timeout /t 1 /nobreak >nul
tasklist /fi "imagename eq WoW.exe" 2>nul | find /i "WoW.exe" >nul
if not errorlevel 1 goto :_wow_running
set /a "tries-=1"
if !tries! LEQ 0 (
    echo [!] WoW.exe did not start within !WOW_WAIT_SECS! seconds.
    exit /b 1
)
goto :_wait_loop

:_wow_running
echo [+] WoW.exe is running.
echo.
echo  *** Log in to your character, then press any key to inject GromitBot.dll ***
echo.
pause >nul

echo [*] Injecting GromitBot.dll into WoW.exe...
"!INJECTOR!"
if errorlevel 1 (
    echo [!] Injection failed. See output above.
    exit /b 1
)
exit /b 0
