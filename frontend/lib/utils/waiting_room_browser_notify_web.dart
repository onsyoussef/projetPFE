import 'dart:html' as html;

void notifyWaitingRoomBrowser({
  required String doctorName,
  required String timeLabel,
}) {
  try {
    if (!html.Notification.supported) return;
    if (html.Notification.permission != 'granted') return;
    html.Notification(
      'Téléconsultation',
      body:
          'Votre consultation avec $doctorName commence dans 10 minutes ($timeLabel).',
    );
  } catch (_) {}
}
