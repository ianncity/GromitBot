@echo off
echo ========================================
echo GromitBot - Starting
echo ========================================
echo.

REM Check if Python is installed
python --version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Python is not installed or not in PATH
    echo Please run install.bat first to install dependencies
    pause
    exit /b 1
)

echo Starting GromitBot...
echo.
python gromitbot.py

pause
