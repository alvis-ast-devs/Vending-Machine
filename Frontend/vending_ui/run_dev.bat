@echo off
rem ============================================================
rem  Dev-mode launcher: same flow as before (conda + flutter run).
rem  Only needed when running from source instead of the build.
rem ============================================================
call conda activate vendingAlpha
cd /d "%~dp0"
flutter run -d windows