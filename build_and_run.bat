@echo off
setlocal EnableDelayedExpansion

:: ================================================================
::  build_and_run.bat  —  Fresh-VM bootstrap, build, launch
::                         and inject GromitBot on Turtle WoW
:: ================================================================
::
::  Run as Administrator the first time on a fresh Windows 10/11
::  machine.  The script installs every missing prerequisite
::  automatically, then builds the DLL, deploys the addon, launches
::  Turtle WoW and injects GromitBot.dll.
::
::  Subsequent runs skip any step whose output already exists.
::
::  Edit the CONFIG block below if your paths differ from defaults.
:: ================================================================

:: ================================================================
:: CONFIG  —  edit these paths to match your installation
:: ================================================================
set "WOW_DIR=C:\TurtleWoW"
set "LUA_DIR=C:\lua51"
set "DXSDK_DIR=C:\DXSDK"
set "GROMITBOT_DIR=C:\GromitBot"

:: Seconds to wait for WoW.exe to appear in the process list
set "WOW_WAIT_SECS=60"
:: ================================================================

:: ---- Derived paths (do not edit) ------------------------------
set "LUA_INCLUDE_DIR=%LUA_DIR%\include"
set "LUA_LIB=%LUA_DIR%\lua51.lib"
set "D3D8_INCLUDE_DIR=%DXSDK_DIR%\include"
set "SCRIPT_DIR=%~dp0"
set "BUILD_DIR=%SCRIPT_DIR%build"
set "DLL_PATH=%BUILD_DIR%\Release\GromitBot.dll"
set "INJECTOR=%BUILD_DIR%\Release\injector.exe"
set "HTTPLIB=%SCRIPT_DIR%dll\include\httplib.h"
set "ADDON_SRC=%SCRIPT_DIR%addon"
set "ADDON_DST=%WOW_DIR%\Interface\AddOns\GromitBot"
set "SWOW_LAUNCHER=%WOW_DIR%\SuperWoWlauncher.exe"

echo ================================================================
echo   GromitBot  --  Fresh-VM Bootstrap, Build, Launch and Inject
echo ================================================================
echo.

:: ================================================================
:: ADMINISTRATOR CHECK
:: ================================================================
net session >nul 2>&1
if errorlevel 1 (
    echo [!] This script must be run as Administrator.
    echo     Right-click build_and_run.bat and choose "Run as administrator".
    pause
    exit /b 1
)
echo [+] Running as Administrator.
echo.

:: ================================================================
:: PHASE 0  --  Install prerequisites
:: ================================================================
echo ================================================================
echo   Phase 0: Installing prerequisites
echo ================================================================
echo.

:: ---- 0a. Ensure winget is available ---------------------------
echo [0a] Checking winget...
where winget >nul 2>&1
if errorlevel 1 (
    echo [*] winget not found.  Attempting to register App Installer...
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe" ^
        2>nul
    where winget >nul 2>&1
    if errorlevel 1 (
        echo [!] Could not enable winget automatically.
        echo     Please install 'App Installer' from the Microsoft Store
        echo     ^(or upgrade to Windows 10 21H1+ / Windows 11^), then re-run.
        goto :error
    )
)
echo [+] winget ready.

:: ---- 0b. Visual Studio 2022 Build Tools + VC++ workload -------
echo.
echo [0b] Checking Visual Studio 2022 Build Tools...
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo [*] VS Build Tools not found.
    echo     Installing -- this may take 10-20 minutes, please wait...
    winget install --id Microsoft.VisualStudio.2022.BuildTools ^
        --silent --accept-package-agreements --accept-source-agreements ^
        --override "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --add Microsoft.VisualStudio.Component.Windows10SDK.19041"
    if errorlevel 1 (
        echo [!] VS Build Tools installation failed.
        goto :error
    )
    echo [+] VS Build Tools installed.
) else (
    echo [+] VS Build Tools already installed.
)

:: ---- 0c. CMake ------------------------------------------------
echo.
echo [0c] Checking CMake...
where cmake >nul 2>&1
if errorlevel 1 (
    echo [*] CMake not found -- installing...
    winget install --id Kitware.CMake ^
        --silent --accept-package-agreements --accept-source-agreements
    if errorlevel 1 (
        echo [!] CMake installation failed.
        goto :error
    )
    :: Add the standard CMake bin path in case PATH has not refreshed yet
    if exist "C:\Program Files\CMake\bin" (
        set "PATH=%PATH%;C:\Program Files\CMake\bin"
    )
    echo [+] CMake installed.
) else (
    echo [+] CMake already installed.
)

:: ---- 0d. Python 3.11 ------------------------------------------
echo.
echo [0d] Checking Python 3.11...
set "PYTHON="
for /f "tokens=*" %%i in ('where python 2^>nul') do (
    if not defined PYTHON set "PYTHON=%%i"
)
:: Verify that the python we found actually works (the Windows Store stub
:: appears on PATH on fresh installs but opens the Store instead of running)
if defined PYTHON (
    "%PYTHON%" --version >nul 2>&1
    if errorlevel 1 (
        echo [*] Python at %PYTHON% is a stub -- will install real Python 3.11...
        set "PYTHON="
    )
)
if not defined PYTHON (
    echo [*] Python not found -- installing Python 3.11...
    winget install --id Python.Python.3.11 ^
        --silent --accept-package-agreements --accept-source-agreements
    if errorlevel 1 (
        echo [!] Python 3.11 installation failed.
        goto :error
    )
    :: Probe the two common install locations for current-user and all-users
    if exist "%LOCALAPPDATA%\Programs\Python\Python311\python.exe" (
        set "PYTHON=%LOCALAPPDATA%\Programs\Python\Python311\python.exe"
        set "PATH=%PATH%;%LOCALAPPDATA%\Programs\Python\Python311;%LOCALAPPDATA%\Programs\Python\Python311\Scripts"
    ) else if exist "C:\Program Files\Python311\python.exe" (
        set "PYTHON=C:\Program Files\Python311\python.exe"
        set "PATH=%PATH%;C:\Program Files\Python311;C:\Program Files\Python311\Scripts"
    ) else (
        for /f "tokens=*" %%i in ('where python 2^>nul') do (
            if not defined PYTHON set "PYTHON=%%i"
        )
    )
    if not defined PYTHON (
        echo [!] Could not locate python.exe after installation.
        echo     Open a new terminal and re-run this script.
        goto :error
    )
    echo [+] Python installed: %PYTHON%
) else (
    echo [+] Python found: %PYTHON%
)

:: ---- 0e. Lua 5.1 headers and static lib -----------------------
echo.
echo [0e] Checking Lua 5.1 ^(headers + static lib^)...
if not exist "%LUA_LIB%" (
    echo [*] Lua 5.1 not found at %LUA_DIR% -- downloading from luabinaries...
    :: Note: %%20 is the batch-escaped form of %20 (URL space encoding).
    :: The /download suffix tells SourceForge to redirect to a mirror.
    set "LUA_URL=https://sourceforge.net/projects/luabinaries/files/5.1.5/Windows%%20Libraries/Static/lua-5.1.5_Win32_vc14_lib.zip/download"
    curl -L --silent --max-redirs 10 "!LUA_URL!" -o "%TEMP%\lua51.zip"
    if errorlevel 1 (
        echo [!] Failed to download Lua 5.1 binaries from SourceForge.
        echo     Download manually:
        echo     https://sourceforge.net/projects/luabinaries/files/5.1.5/
        echo     ^(lua-5.1.5_Win32_vc14_lib.zip^) and extract to %LUA_DIR%
        goto :error
    )
    if not exist "%LUA_DIR%"         mkdir "%LUA_DIR%"
    if not exist "%LUA_INCLUDE_DIR%" mkdir "%LUA_INCLUDE_DIR%"
    if not exist "%TEMP%\lua51_extract" mkdir "%TEMP%\lua51_extract"
    tar -xf "%TEMP%\lua51.zip" -C "%TEMP%\lua51_extract" 2>nul
    if errorlevel 1 (
        echo [!] Failed to extract Lua 5.1 archive.
        goto :error
    )
    :: Copy lua51.lib wherever it landed
    for /r "%TEMP%\lua51_extract" %%f in (lua51.lib) do copy /Y "%%f" "%LUA_DIR%\" >nul
    :: Copy Lua headers
    for /r "%TEMP%\lua51_extract" %%f in (lua.h lualib.h lauxlib.h luaconf.h) do copy /Y "%%f" "%LUA_INCLUDE_DIR%\" >nul
    echo [+] Lua 5.1 installed to %LUA_DIR%
) else (
    echo [+] Lua 5.1 already present.
)

:: ---- 0f. DirectX 8 SDK headers --------------------------------
echo.
echo [0f] Checking DirectX 8 SDK headers...
if not exist "%D3D8_INCLUDE_DIR%\d3d8.h" (
    echo [*] DXSDK headers not found -- downloading from apitrace/dxsdk...
    curl -L --silent "https://github.com/apitrace/dxsdk/archive/refs/heads/master.zip" ^
         -o "%TEMP%\dxsdk.zip"
    if errorlevel 1 (
        echo [!] Failed to download DXSDK headers.
        goto :error
    )
    if not exist "%DXSDK_DIR%"        mkdir "%DXSDK_DIR%"
    if not exist "%D3D8_INCLUDE_DIR%" mkdir "%D3D8_INCLUDE_DIR%"
    if not exist "%TEMP%\dxsdk_extract" mkdir "%TEMP%\dxsdk_extract"
    tar -xf "%TEMP%\dxsdk.zip" -C "%TEMP%\dxsdk_extract" 2>nul
    if errorlevel 1 (
        echo [!] Failed to extract DXSDK headers.
        goto :error
    )
    xcopy /E /Y /Q "%TEMP%\dxsdk_extract\dxsdk-master\Include\*" "%D3D8_INCLUDE_DIR%\" >nul
    echo [+] DXSDK headers installed to %D3D8_INCLUDE_DIR%
) else (
    echo [+] DXSDK headers already present.
)

:: ---- 0g. Python agent dependencies ---------------------------
echo.
echo [0g] Installing Python agent requirements...
"%PYTHON%" -m pip install --quiet -r "%SCRIPT_DIR%agent\requirements.txt"
if errorlevel 1 (
    echo [!] pip install failed.
    goto :error
)
echo [+] Python requirements installed.

echo.
echo [+] All prerequisites satisfied.

:: ================================================================
:: PHASE 1  --  Locate Visual Studio x86 toolset
:: ================================================================
echo.
echo ================================================================
echo   Phase 1-6: Build, Deploy, Launch and Inject
echo ================================================================
echo.

echo [1/6] Locating Visual Studio x86 toolset...
if not exist "%VSWHERE%" (
    echo [!] vswhere.exe not found at %VSWHERE%
    echo     VS Build Tools may still be installing; try re-running the script.
    goto :error
)
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS_PATH=%%i"
if not defined VS_PATH (
    echo [!] Visual Studio with C++ Desktop workload not found.
    goto :error
)
set "VCVARS=%VS_PATH%\VC\Auxiliary\Build\vcvars32.bat"
if not exist "%VCVARS%" (
    echo [!] vcvars32.bat not found: %VCVARS%
    goto :error
)
echo [+] Found: %VS_PATH%
call "%VCVARS%" >nul

:: ================================================================
:: PHASE 2  --  Fetch cpp-httplib
:: ================================================================
echo [2/6] Checking cpp-httplib...
if not exist "%HTTPLIB%" (
    echo [*] httplib.h not found -- downloading ^(v0.14.3^)...
    curl -L --silent "https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.14.3/httplib.h" ^
         -o "%HTTPLIB%"
    if errorlevel 1 (
        echo [!] Failed to download httplib.h.
        goto :error
    )
    echo [+] httplib.h downloaded.
) else (
    echo [+] httplib.h already present.
)

:: ================================================================
:: PHASE 3  --  CMake configure
:: ================================================================
echo [3/6] Configuring CMake ^(32-bit Release^)...
cmake -B "%BUILD_DIR%" -A Win32 ^
    -DLUA_INCLUDE_DIR="%LUA_INCLUDE_DIR%" ^
    -DLUA_LIB="%LUA_LIB%" ^
    -DD3D8_INCLUDE_DIR="%D3D8_INCLUDE_DIR%" ^
    "%SCRIPT_DIR%"
if errorlevel 1 (
    echo [!] CMake configure failed.
    goto :error
)

:: ================================================================
:: PHASE 4  --  Build
:: ================================================================
echo [4/6] Building GromitBot.dll and injector.exe...
cmake --build "%BUILD_DIR%" --config Release
if errorlevel 1 (
    echo [!] Build failed.  See output above.
    goto :error
)
if not exist "%DLL_PATH%" (
    echo [!] GromitBot.dll not found after build: %DLL_PATH%
    goto :error
)
if not exist "%INJECTOR%" (
    echo [!] injector.exe not found after build: %INJECTOR%
    goto :error
)
echo [+] Build successful.

:: ================================================================
:: PHASE 5  --  Deploy addon and SuperWoW files
:: ================================================================
echo [5/6] Deploying addon and SuperWoW files...
if not exist "%WOW_DIR%" (
    echo [!] WoW directory not found: %WOW_DIR%
    echo     Set WOW_DIR at the top of this script to your Turtle WoW folder.
    goto :error
)
if not exist "%ADDON_DST%" mkdir "%ADDON_DST%"
xcopy /E /Y /Q "%ADDON_SRC%\*" "%ADDON_DST%\" >nul
echo [+] Addon copied to %ADDON_DST%
if not exist "%SWOW_LAUNCHER%" (
    echo [*] SuperWoWlauncher.exe not found in WoW dir -- copying...
    copy /Y "%SCRIPT_DIR%superwow\SuperWoWlauncher.exe" "%WOW_DIR%\" >nul
    copy /Y "%SCRIPT_DIR%superwow\SuperWoWhook.dll"     "%WOW_DIR%\" >nul
    echo [+] SuperWoW files copied to %WOW_DIR%
) else (
    echo [+] SuperWoW already present.
)

:: ================================================================
:: PHASE 6  --  Start services, launch WoW, inject
:: ================================================================
echo [6/6] Starting services, launching Turtle WoW, and injecting...

:: Ensure the GromitBot data directory exists (agent log + command files live here)
if not exist "%GROMITBOT_DIR%" mkdir "%GROMITBOT_DIR%"

:: Tell the agent where to store bot files (keeps GROMITBOT_DIR as single source of truth)
set "GROMITBOT_BOT_BASE_DIR=%GROMITBOT_DIR%\bots"

:: Start the Python agent in a new window (per-VM agent on port 9000)
echo [*] Starting Python agent ^(port 9000^)...
start "GromitBot Agent" cmd /k "%PYTHON%" "%SCRIPT_DIR%agent\agent.py"

:: Wait for services to initialise before launching WoW
timeout /t 5 /nobreak >nul

:: Launch WoW via SuperWoW launcher
echo [*] Launching Turtle WoW via SuperWoWlauncher.exe...
start "" "%SWOW_LAUNCHER%"

echo [*] Waiting for WoW.exe to start ^(up to %WOW_WAIT_SECS% seconds^)...
set /a "tries=%WOW_WAIT_SECS%"

:wait_loop
timeout /t 1 /nobreak >nul
tasklist /fi "imagename eq WoW.exe" 2>nul | find /i "WoW.exe" >nul
if not errorlevel 1 goto :wow_running
set /a "tries-=1"
if !tries! LEQ 0 (
    echo [!] WoW.exe did not start within %WOW_WAIT_SECS% seconds.
    goto :error
)
goto :wait_loop

:wow_running
echo [+] WoW.exe is running.
echo.
echo  *** Log in to your character, then press any key to inject GromitBot.dll ***
echo.
pause >nul

echo [*] Injecting GromitBot.dll into WoW.exe...
"%INJECTOR%"
if errorlevel 1 (
    echo [!] Injection failed.  See output above.
    goto :error
)

echo.
echo ================================================================
echo   GromitBot injected successfully!
echo   Start the bot in-game with:  /gbot start
echo   Python agent is running in its own window on port 9000.
echo ================================================================
goto :end

:error
echo.
echo ================================================================
echo   FAILED -- check the errors above.
echo ================================================================
pause
exit /b 1

:end
echo.
pause
endlocal
exit /b 0
