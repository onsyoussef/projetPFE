import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  const PermissionService._();
  static const PermissionService instance = PermissionService._();

  Future<bool> ensureMicrophonePermission(BuildContext context) async {
    var status = await Permission.microphone.status;
    if (status.isGranted) return true;

    status = await Permission.microphone.request();
    if (status.isGranted) return true;

    if (!context.mounted) return false;
    if (status.isPermanentlyDenied || status.isRestricted) {
      await _showSettingsDialog(context);
      return false;
    }
    await _showDeniedDialog(context);
    return false;
  }

  Future<bool> ensureCameraAndMicrophonePermissions(BuildContext context) async {
    final micOk = await ensureMicrophonePermission(context);
    if (!micOk) return false;
    var cam = await Permission.camera.status;
    if (cam.isGranted) return true;
    cam = await Permission.camera.request();
    if (cam.isGranted) return true;
    if (!context.mounted) return false;
    if (cam.isPermanentlyDenied || cam.isRestricted) {
      await _showSettingsDialog(context);
      return false;
    }
    await _showDeniedDialog(context);
    return false;
  }

  Future<void> _showDeniedDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Microphone requis'),
        content: const Text(
          'Le microphone est nécessaire pour les appels audio de téléconsultation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fermer'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await Permission.microphone.request();
            },
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSettingsDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permission bloquée'),
        content: const Text(
          'La permission microphone est refusée définitivement. '
          'Activez-la dans les paramètres de l’application.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await openAppSettings();
            },
            child: const Text('Ouvrir paramètres'),
          ),
        ],
      ),
    );
  }
}
