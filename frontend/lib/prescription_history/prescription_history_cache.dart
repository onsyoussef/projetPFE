import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'prescription_history_model.dart';

const _kPrefix = 'prescription_history_v1_';

class PrescriptionHistoryCache {
  PrescriptionHistoryCache({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<List<PrescriptionHistoryEntry>?> read(String conversationId) async {
    final key = '$_kPrefix$conversationId';
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
  }
}
