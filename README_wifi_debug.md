# Debug Flutter Android en Wi-Fi (Windows)

Ce guide explique comment lancer votre application Flutter sur un telephone Android sans cable USB.

## 1) Configuration initiale sur le telephone (une seule fois)

1. Ouvrir `Parametres > A propos du telephone`.
2. Taper 7 fois sur `Numero de build` pour activer les options developpeur.
3. Aller dans `Parametres > Options developpeur`.
4. Activer:
   - `Debogage USB` (utile pour certaines phases d'appairage)
   - `Debogage sans fil` (Wireless debugging)
5. Verifier que le telephone et le PC sont sur le meme reseau Wi-Fi local.

## 2) Connexion ADB en Wi-Fi (Windows)

### Verifier ADB

Dans PowerShell:

```powershell
adb version
```

Si la commande n'existe pas, ajoutez `platform-tools` au PATH, ou utilisez le chemin complet:

```powershell
& "C:\Users\onsyo\AppData\Local\Android\Sdk\platform-tools\adb.exe" version
```

### Trouver IP et port du telephone

Sur Android:

- `Parametres > Options developpeur > Debogage sans fil`
- Ouvrir la section qui affiche l'`Adresse IP et port`
- Exemple: `192.168.1.50:5555`

### Se connecter

```powershell
adb connect <IP_TELEPHONE>:<PORT>
adb devices
```

Exemple:

```powershell
adb connect 192.168.1.50:5555
adb devices
```

Le device doit apparaitre en `device`.

## 3) Lancer Flutter sur le telephone en Wi-Fi

```powershell
flutter devices
flutter run
```

Si plusieurs appareils sont detectes:

```powershell
flutter run -d <DEVICE_ID>
```

Le hot reload fonctionne aussi en Wi-Fi (`r` dans le terminal Flutter).

## 4) Script d'automatisation

Le fichier `connect_wifi.bat` (a la racine du projet) permet de:

1. Verifier ADB
2. Afficher les devices actuels
3. Connecter automatiquement `PHONE_IP:PHONE_PORT`
4. Re-verifier la connexion

### Utilisation

1. Ouvrir `connect_wifi.bat`
2. Modifier:
   - `set PHONE_IP=...`
   - `set PHONE_PORT=...`
3. Si ADB n'est pas dans PATH, modifier:
   - `set ADB_EXE=C:\...\platform-tools\adb.exe`
4. Double-cliquer le `.bat` (ou lancer depuis CMD/PowerShell)

## 5) Erreurs courantes et solutions

### `adb: error: failed to connect`

- Verifier que PC + telephone sont sur le meme Wi-Fi
- Verifier IP/port affiches sur le telephone
- Desactiver temporairement VPN/proxy/firewall strict

### `unauthorized`

- Sur Android: `Options developpeur > Revoquer les autorisations de debogage USB`
- Refaire l'appairage/autorisation
- Accepter la popup RSA sur le telephone

### Connexion coupee apres veille

- Activer `Wi-Fi actif en veille` dans les options developpeur
- Eviter l'economie d'energie agressive de l'appareil pendant les tests

### Flutter ne detecte pas le device

```powershell
adb kill-server
adb start-server
adb devices
flutter devices
```

Puis relancer:

```powershell
flutter run -d <DEVICE_ID>
```
