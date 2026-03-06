@echo off
setlocal EnableDelayedExpansion

:: ================================================================
::  build_and_run.bat  —  Build GromitBot, launch Turtle WoW,
::                         and inject GromitBot.dll
:: ================================================================
::  Edit the CONFIG section below before running for the first time.
:: ================================================================

:: ---- CONFIG (edit these paths to match your machine) ----------
set "WOW_DIR=C:\TurtleWoW"
set "LUA_INCLUDE_DIR=C:\lua51\include"
set "LUA_LIB=C:\lua51\lua51.lib"
set "D3D8_INCLUDE_DIR=C:\DXSDK\include"

:: Seconds to wait for WoW.exe to appear in the process list
set "WOW_WAIT_SECS=60"
:: ---------------------------------------------------------------

set "SCRIPT_DIR=%~dp0"
set "BUILD_DIR=%SCRIPT_DIR%build"
set "DLL_PATH=%BUILD_DIR%\Release\GromitBot.dll"
set "INJECTOR=%BUILD_DIR%\Release\injector.exe"
set "HTTPLIB=%SCRIPT_DIR%dll\include\httplib.h"
set "ADDON_SRC=%SCRIPT_DIR%addon"
set "ADDON_DST=%WOW_DIR%\Interface\AddOns\GromitBot"
set "SWOW_LAUNCHER=%WOW_DIR%\SuperWoWlauncher.exe"

echo ================================================================
echo   GromitBot  —  Build, Launch and Inject
echo ================================================================
echo.

:: ---- Step 1: Locate Visual Studio x86 toolset -----------------
echo [1/6] Locating Visual Studio x86 toolset...

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo [!] vswhere.exe not found. Is Visual Studio 2022 installed?
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

:: ---- Step 2: Fetch cpp-httplib if missing ---------------------
echo [2/6] Checking cpp-httplib...

if not exist "%HTTPLIB%" (
    echo [*] httplib.h not found — downloading...
    curl -L --silent "https://raw.githubusercontent.com/yhirose/cpp-httplib/v0.14.3/httplib.h" ^
         -o "%HTTPLIB%"
    if errorlevel 1 (
        echo [!] Failed to download httplib.h. Check your internet connection.
        goto :error
    )
    echo [+] httplib.h downloaded.
) else (
    echo [+] httplib.h already present.
)

:: ---- Step 3: CMake configure ----------------------------------
echo [3/6] Configuring CMake (32-bit Release)...

cmake -B "%BUILD_DIR%" -A Win32 ^
    -DLUA_INCLUDE_DIR="%LUA_INCLUDE_DIR%" ^
    -DLUA_LIB="%LUA_LIB%" ^
    -DD3D8_INCLUDE_DIR="%D3D8_INCLUDE_DIR%" ^
    "%SCRIPT_DIR%"
if errorlevel 1 (
    echo [!] CMake configure failed.
    goto :error
)

:: ---- Step 4: Build --------------------------------------------
echo [4/6] Building GromitBot.dll and injector.exe...

cmake --build "%BUILD_DIR%" --config Release
if errorlevel 1 (
    echo [!] Build failed. See output above.
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

:: ---- Step 5: Deploy addon and SuperWoW files ------------------
echo [5/6] Deploying addon and SuperWoW files...

if not exist "%WOW_DIR%" (
    echo [!] WoW directory not found: %WOW_DIR%
    echo     Edit WOW_DIR at the top of this script.
    goto :error
)

:: Copy GromitBot Lua addon
if not exist "%ADDON_DST%" mkdir "%ADDON_DST%"
xcopy /E /Y /Q "%ADDON_SRC%\*" "%ADDON_DST%\" >nul
echo [+] Addon copied to %ADDON_DST%

:: Copy SuperWoW binaries if not already present in WoW dir
if not exist "%SWOW_LAUNCHER%" (
    echo [*] SuperWoWlauncher.exe not found in WoW dir — copying...
    copy /Y "%SCRIPT_DIR%superwow\SuperWoWlauncher.exe" "%WOW_DIR%\" >nul
    copy /Y "%SCRIPT_DIR%superwow\SuperWoWhook.dll"     "%WOW_DIR%\" >nul
    echo [+] SuperWoW files copied to %WOW_DIR%
) else (
    echo [+] SuperWoW already present.
)

:: ---- Step 6: Launch WoW and inject ----------------------------
echo [6/6] Launching Turtle WoW via SuperWoWlauncher.exe...

start "" "%SWOW_LAUNCHER%"

echo [*] Waiting for WoW.exe to start (up to %WOW_WAIT_SECS% seconds)...
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
    echo [!] Injection failed. See output above.
    goto :error
)

echo.
echo ================================================================
echo   GromitBot injected successfully!
echo   Start the bot in-game with:  /gbot start
echo ================================================================
goto :end

:error
echo.
echo ================================================================
echo   FAILED — check the errors above.
echo ================================================================
pause
exit /b 1

:end
endlocal
exit /b 0
