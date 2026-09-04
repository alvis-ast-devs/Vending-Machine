@echo off
rem ============================================================
rem  Dev-mode launcher: same flow as before (conda + flutter run).
rem  Only needed when running from source instead of the build.
rem
rem  ASSETS_BASE_PATH menunjuk ke folder repo ini, jadi media
rem  (assets/ads, assets/tutorial, dst.) dibaca dari sini dan bisa
rem  dites TANPA build release. Letakkan file media di:
rem    Frontend\vending_ui\assets\<folder>
rem ============================================================
call conda activate vendingAlpha
cd /d "%~dp0"
rem  Argumen dart-define DICUPLIK (path repo mungkin mengandung spasi,
rem  misalnya "Vending Machine\...") dan memakai %CD% (variabel folder
rem  aktif) BUKAN %~dp0, karena %~dp0 berakhir dengan backslash: nilai
rem  yang berakhir backslash membuat tanda kutip bocor lewat flutter.bat
rem  dan merusak path.
flutter run -d windows "--dart-define=ASSETS_BASE_PATH=%CD%"