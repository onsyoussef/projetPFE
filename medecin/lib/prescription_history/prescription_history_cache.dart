import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'prescription_history_model.dart';

const _kPrefix = 'prescription_history_v2_';

class PrescriptionHistoryCache {
  PrescriptionHistoryCache({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<List<PrescriptionHistoryEntry>?> read(String conversationId) async {
    final key = '$_kPrefix$conversationId';
    dev.log(
      'Lecture cache historique',
      name: 'PrescriptionHistoryCache',
      error: key,
    );
    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final out = <PrescriptionHistoryEntry>[];
      for (final e in decoded) {
        if (e is Map) {
          out.add(
            PrescriptionHistoryEntry.fromJson(Map<String, dynamic>.from(e)),
          );
        }
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(
    String conversationId,
    List<PrescriptionHistoryEntry> items,
  ) async {
    final key = '$_kPrefix$conversationId';
    final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
    await _storage.write(key: key, value: encoded);
    dev.log(
      'Cache historique ecrit',
      name: 'PrescriptionHistoryCache',
      error: {'key': key, 'count': items.length},
    );
  }

  Future<void> clear(String conversationId) async {
    final key = '$_kPrefix$conversationId';
    await _storage.delete(key: key);
    dev.log(
      'Cache historique supprime',
      name: 'PrescriptionHistoryCache',
      error: key,
    );
  }

  Future<void> clearAllVersionedEntries() async {
    final all = await _storage.readAll();
    final keys = all.keys.where((k) => k.startsWith(_kPrefix)).toList();
    for (final key in keys) {
      await _storage.delete(key: key);
    }
    dev.log(
      'Nettoyage complet cache historique',
      name: 'PrescriptionHistoryCache',
      error: {'entries': keys.length, 'prefix': _kPrefix},
    );
  }
}
