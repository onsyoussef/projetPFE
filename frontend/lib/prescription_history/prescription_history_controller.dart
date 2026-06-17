import 'package:flutter/foundation.dart';

import '../services/api_service.dart';
import 'prescription_history_cache.dart';
import 'prescription_history_model.dart';

class PrescriptionHistoryController extends ChangeNotifier {
  PrescriptionHistoryController(
    this.conversationId, {
    PrescriptionHistoryCache? cache,
  }) : _cache = cache ?? PrescriptionHistoryCache();

  final String conversationId;
  final PrescriptionHistoryCache _cache;

  List<PrescriptionHistoryEntry>? items;
  String? errorMessage;
  bool loading = true;

  Future<void> load() async {
    loading = true;
    errorMessage = null;
    notifyListeners();

    List<PrescriptionHistoryEntry>? cached;
    try {
      cached = await _cache.read(conversationId);
      if (cached != null && cached.isNotEmpty) {
        items = _sorted(cached);
        loading = false;
        notifyListeners();
      }
    } catch (_) {}

    try {
      final page = await ApiService.fetchPrescriptionHistory(
        conversationId: conversationId,
        page: 1,
        limit: 100,
      );
      items = _sorted(page.data);
      await _cache.write(conversationId, items!);
      errorMessage = null;
    } catch (e) {
      errorMessage = e.toString().replaceFirst('Exception: ', '');
      if (items == null || items!.isEmpty) {
        items = cached != null ? _sorted(cached) : items;
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  List<PrescriptionHistoryEntry> _sorted(List<PrescriptionHistoryEntry> raw) {
    final copy = List<PrescriptionHistoryEntry>.from(raw);
    copy.sort((a, b) {
      final ca = a.createdAt;
      final cb = b.createdAt;
      if (ca == null && cb == null) return 0;
      if (ca == null) return 1;
      if (cb == null) return -1;
      return cb.compareTo(ca);
    });
    return copy;
  }
}
