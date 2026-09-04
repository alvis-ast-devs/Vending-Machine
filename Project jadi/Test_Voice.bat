@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ============================================================
echo  TEST VOICE RECOGNITION - jalankan script Python langsung
echo.
echo  Kalau mikrofon / library / internet bermasalah, pesan
echo  errornya akan muncul DI SINI.
echo.
echo  Keluar: Ctrl+C atau tutup jendela ini.
echo ============================================================
echo.
runtime\python\python.exe scripts\voice_recognition.py
echo.
echo Script berhenti (kode: %errorlevel%).
echo Jendela ini sengaja dibiarkan terbuka supaya error di atas bisa dibaca.
pause