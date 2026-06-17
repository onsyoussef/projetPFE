@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ===== Configuration =====
set PHONE_IP=192.168.100.100
set PHONE_PORT=44799
REM Optionnel: renseigner le chemin complet si adb n'est pas dans le PATH
set ADB_EXE=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
REM Exemple:
REM set ADB_EXE=C:\Users\onsyo\AppData\Local\Android\Sdk\platform-tools\adb.exe

echo.
echo [1/4] Verification de ADB...
where "%ADB_EXE%" >nul 2>nul
if errorlevel 1 (
  "%ADB_EXE%" version >nul 2>nul
  if errorlevel 1 (
    echo [ERREUR] ADB introuvable.
    echo - Ajoute platform-tools au PATH Windows, ou
    echo - Modifie ADB_EXE dans ce fichier avec le chemin complet de adb.exe
    exit /b 1
  )
)

echo [2/4] Etat actuel des appareils:
"%ADB_EXE%" devices

echo.
echo [3/4] Connexion a %PHONE_IP%:%PHONE_PORT% ...
"%ADB_EXE%" connect %PHONE_IP%:%PHONE_PORT%
if errorlevel 1 (
  echo [ERREUR] Echec de connexion ADB.
  echo Verifie IP/PORT, meme reseau Wi-Fi, et debogage sans fil actif.
  exit /b 1
)

echo.
echo [4/4] Verification finale:
"%ADB_EXE%" devices
echo.
echo [OK] Connexion Wi-Fi terminee.
echo Lance maintenant: flutter devices
echo Puis: flutter run -d ^<DEVICE_ID^>

endlocal
