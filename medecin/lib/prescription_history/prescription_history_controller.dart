import 'dart:developer' as dev;

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

  List<PrescriptionHistoryEntry> items = const [];
  String? errorMessage;
  bool loading = true;

  Future<void> load({bool forceRefresh = false}) async {
    final tag = 'PrescriptionHistoryController($conversationId)';
    final jwt = ApiService.jwtToken?.trim() ?? '';
    debugPrint('[$tag] load(forceRefresh: $forceRefresh) start');
    if (jwt.isEmpty) {
      debugPrint('[$tag] warning: ApiService.jwtToken absent');
    }
    dev.log(
      'Chargement historique ordonnance',
      name: 'PrescriptionHistoryController',
      error: {'conversationId': conversationId, 'forceRefresh': forceRefresh},
    );

    loading = true;
    errorMessage = null;
    notifyListeners();

    List<PrescriptionHistoryEntry>? cached;
    if (!forceRefresh) {
      try {
        cached = await _cache.read(conversationId);
        debugPrint('[$tag] cache read: ${cached?.length ?? 0} item(s)');
        if (cached != null && cached.isNotEmpty) {
          items = _sorted(cached);
          loading = false;
          notifyListeners();
        }
      } catch (e, st) {
        debugPrint('[$tag] cache read error: $e');
        dev.log(
          'Erreur lecture cache historique',
          name: 'PrescriptionHistoryController',
          error: e,
          stackTrace: st,
        );
      }
    } else {
      debugPrint('[$tag] bypass cache (force refresh)');
    }

    try {
      final page = await ApiService.fetchPrescriptionHistory(
        conversationId: conversationId,
        page: 1,
        limit: 100,
      );
      items = _sorted(page.data);
      debugPrint('[$tag] API success: ${items.length} item(s)');
      await _cache.write(conversationId, items);
      errorMessage = null;
    } catch (e, st) {
      debugPrint('[$tag] API error: $e');
      dev.log(
        'Erreur API historique ordonnance',
        name: 'PrescriptionHistoryController',
        error: e,
        stackTrace: st,
      );
      errorMessage = e.toString().replaceFirst('Exception: ', '');
      if (items.isEmpty) {
        items = cached != null ? _sorted(cached) : const [];
        debugPrint('[$tag] fallback -> cache/local: ${items.length} item(s)');
      }
    } finally {
      loading = false;
      debugPrint(
        '[$tag] load done; items=${items.length}, error=${errorMessage ?? 'none'}',
      );
      notifyListeners();
    }
  }

  Future<void> refresh() => load(forceRefresh: true);

  Future<void> clearCacheForDebug() async {
    await _cache.clear(conversationId);
    debugPrint('[PrescriptionHistoryController($conversationId)] cache cleared');
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
