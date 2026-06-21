@echo off
setlocal
REM Lance l'app patient (frontend) sur Windows — BLE via adaptateur Bluetooth du PC.

cd /d "%~dp0frontend"
echo Lancement sur Windows (BLE disponible si Bluetooth PC active)...
echo.
flutter devices
echo.
flutter run -d windows %*
