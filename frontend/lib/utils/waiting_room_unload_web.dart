import 'dart:async';
import 'dart:html' as html;

StreamSubscription<html.Event>? _beforeUnloadSub;

/// Notifie le serveur (sync) avant fermeture / rechargement de l’onglet.
void registerPatientWaitingUnloadSync(void Function() onUnload) {
  unregisterPatientWaitingUnloadSync();
  _beforeUnloadSub = html.window.onBeforeUnload.listen((_) {
    onUnload();
  });
}

void unregisterPatientWaitingUnloadSync() {
  _beforeUnloadSub?.cancel();
  _beforeUnloadSub = null;
}
