# iOS — CallKit, PushKit (VoIP) et APNs

## 1. Capabilities Xcode

1. Ouvrir `ios/Runner.xcworkspace`.
2. Cible **Runner** → **Signing & Capabilities** → **+ Capability** :
   - **Push Notifications**
   - **Background Modes** : cocher **Voice over IP** et **Remote notifications**
   - **Voice over IP** (capability dédiée si proposée selon la version de Xcode)

## 2. Certificat / clé APNs VoIP

Les notifications **VoIP** ne passent **pas** par FCM : Apple exige une livraison APNs avec `apns-push-type: voip` vers le topic `\<Bundle ID\>.voip`.

1. [Apple Developer](https://developer.apple.com/account) → **Certificates, Identifiers & Profiles** → **Keys** → créer une clé avec **Apple Push Notifications service (APNs)** et **VoIP Services**.
2. Télécharger la clé `.p8`, noter **Key ID** et **Team ID**.
3. Sur le backend (Node), variables d’environnement prévues dans `pushNotificationService.js` :
   - `APNS_VOIP_TOPIC` = `com.votre.bundle.voip`
   - `APNS_VOIP_KEY_ID`, `APNS_VOIP_TEAM_ID`, `APNS_VOIP_PRIVATE_KEY` (contenu PEM de la `.p8`)

Implémenter l’envoi HTTP/2 vers `api.push.apple.com` ou utiliser le package npm `apn` / `@parse/node-apn` dans `trySendVoipIncomingPush`.

## 3. Info.plist

Vérifier au minimum :

- `NSMicrophoneUsageDescription`
- `NSCameraUsageDescription` (visio)

## 4. Token PushKit côté Flutter

`flutter_callkit_incoming` émet `Event.actionDidUpdateDevicePushTokenVoip` ; l’app enregistre le couple **FCM + voipToken** via `POST /push/register-device` (champ `voipToken`).

## 5. Intégration WebRTC après acceptation

Le flux actuel appelle `WebRtcService.handleIncomingCallFromNotification` puis ouvre `ChatOpenerFromPush` pour rejoindre la salle (SDP via `call:request_pending_offer`).

Pour basculer vers **Agora / Jitsi** : remplacer dans `callkit_service.dart`, méthode `_onAccept`, l’appel à `WebRtcService` par l’initialisation du SDK choisi (`joinChannel` / `build` Jitsi) en utilisant `roomId` / `callId` du payload `extra`.
