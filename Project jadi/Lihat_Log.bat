@echo off
cd /d "%~dp0"
if not exist voice_log.txt (
    echo Belum ada voice_log.txt.
    echo Jalankan dulu Jalankan.bat, coba voice payment, lalu buka lagi file ini.
    pause
    exit /b
)
notepad voice_log.txt