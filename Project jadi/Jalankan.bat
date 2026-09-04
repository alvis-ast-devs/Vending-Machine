@echo off
rem ============================================================
rem  One-click launcher for the built vending machine app.
rem  The app already uses the bundled Python next to this exe
rem  (runtime\python\python.exe) - conda / flutter are NOT needed.
rem ============================================================
cd /d "%~dp0"
start "" "%~dp0vending_ui.exe"