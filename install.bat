@echo off
echo ========================================
echo GromitBot - Installing Dependencies
echo ========================================
echo.

REM Check if Python is installed
python --version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Python is not installed or not in PATH
    echo Please install Python 3.8 or higher from https://www.python.org/downloads/
    pause
    exit /b 1
)

echo Python found. Installing dependencies...
echo.

REM Upgrade pip
python -m pip install --upgrade pip

REM Install required packages
echo Installing pyautogui...
python -m pip install pyautogui

echo Installing numpy...
python -m pip install numpy

echo Installing opencv-python...
python -m pip install opencv-python

echo Installing pillow...
python -m pip install pillow

echo Installing requests...
python -m pip install requests

echo Installing discord.py...
python -m pip install discord.py

echo Installing aiohttp...
python -m pip install aiohttp

echo Installing pynput...
python -m pip install pynput

echo Installing keyboard...
python -m pip install keyboard

echo Installing mouse...
python -m pip install mouse

echo.
echo ========================================
echo Installation Complete!
echo ========================================
echo.
echo Run start.bat to launch GromitBot
echo.
pause
