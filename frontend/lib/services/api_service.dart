import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:cross_file/cross_file.dart';

import '../prescription_history/prescription_history_model.dart';

class ApiService {
  static const String _apiBaseUrlFromEnv =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');
  static const String _defaultWebBaseUrl = 'http://localhost:3000';
  static const String _defaultMobileBaseUrl = 'https://telemedecine-99yr.onrender.com';

  static String get _baseUrl {
    final configured = _apiBaseUrlFromEnv.trim();
    if (configured.isNotEmpty) return configured;
    return kIsWeb ? _defaultWebBaseUrl : _defaultMobileBaseUrl;
  }

  static String get baseUrl => _baseUrl;

  static String? _jwtToken;

  /// Jeton JWT patient (`auth/login`). À synchroniser avec la clé `patient_jwt` (SharedPreferences).
  static void setJwtToken(String? token) {
    final t = token?.trim() ?? '';
    _jwtToken = t.isEmpty ? null : t;
  }

  static String? get jwtToken => _jwtToken;

  static Map<String, String> _jsonHeadersWithAuth() => {
        'Content-Type': 'application/json',
        if (_jwtToken != null && _jwtToken!.isNotEmpty)
          'Authorization': 'Bearer $_jwtToken',
      };

  static Map<String, String> _headersAuthOnly() => {
        if (_jwtToken != null && _jwtToken!.isNotEmpty)
          'Authorization': 'Bearer $_jwtToken',
      };

  static Map<String, dynamic> _decodeBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }

  static String _extractErrorMessage(
    http.Response response, {
    required String fallback,
  }) {
    final data = _decodeBody(response.body);
    final message = '${data['message'] ?? ''}'.trim();
    if (message.isNotEmpty) return message;

    final contentType = '${response.headers['content-type'] ?? ''}'.toLowerCase();
    if (contentType.contains('text/html') || response.body.trimLeft().startsWith('<!DOCTYPE')) {
      return '$fallback (reponse HTML recue, verifier API_BASE_URL: $baseUrl)';
    }
    return fallback;
  }

  /// URL absolue pour afficher une pièce jointe (Cloudinary `https://...` ou `/uploads/...`).
  static String resolveMediaUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    var p = path.trim();
    if (p.isEmpty) return '';
    if (!p.startsWith('http://') && !p.startsWith('https://')) {
      final base = _baseUrl.endsWith('/')
          ? _baseUrl.substring(0, _baseUrl.length - 1)
          : _baseUrl;
      p = p.startsWith('/') ? '$base$p' : '$base/$p';
    }
    p = _cloudinaryInlineDeliveryUrl(p);
    return _chatImageDeliveryUrl(p);
  }

  /// Comme [resolveMediaUrl] mais `null` si l’URL est vide (évite `NetworkImage("")`).
  static String? resolveMediaUrlOrNull(String? path) {
    final url = resolveMediaUrl(path);
    return url.isEmpty ? null : url;
  }

  /// Optimisation livraison images Cloudinary (alignée backend : q_auto, f_auto, largeur max).
  static String _chatImageDeliveryUrl(String url) {
    if (!url.contains('res.cloudinary.com') || !url.contains('/image/upload/')) {
      return url;
    }
    if (url.contains('q_auto')) return url;
    return url.replaceFirst(
      '/image/upload/',
      '/image/upload/q_auto,f_auto,w_1200,c_limit/',
    );
  }

  /// URL du proxy backend (même origine) pour ouvrir PDF / Office / etc. dans l’onglet sans passer par des visionneurs tiers.
  static String attachmentProxyUrl({
    required String messageId,
    required String conversationId,
  }) {
    final base = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    return '$base/messages/${Uri.encodeComponent(messageId)}/file?conversationId=${Uri.encodeComponent(conversationId)}';
  }

  /// PDF ordonnance via l’API (JWT) : préférable à une URL Cloudinary directe (signatures, pas de 400 `fl_inline`).
  static String prescriptionPdfProxyUrl({
    required String conversationId,
    required String messageId,
  }) {
    final base = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    return '$base/api/conversations/'
        '${Uri.encodeComponent(conversationId)}/prescriptions/by-message/'
        '${Uri.encodeComponent(messageId)}/pdf';
  }

  /// PDF ordonnance par identifiant document (historique / liste).
  static String prescriptionPdfProxyUrlByPrescriptionId({
    required String conversationId,
    required String prescriptionId,
  }) {
    final base = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    return '$base/api/conversations/'
        '${Uri.encodeComponent(conversationId)}/prescriptions/'
        '${Uri.encodeComponent(prescriptionId)}/pdf';
  }

  /// Liste des ordonnances d’une conversation (participant patient ou médecin).
  static Future<List<Map<String, dynamic>>> getConversationPrescriptions({
    required String conversationId,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    final q = <String, String>{
      'limit': '$limit',
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
    };
    final uri = Uri.parse(
      '$_baseUrl/api/conversations/${Uri.encodeComponent(conversationId)}/prescriptions',
    ).replace(queryParameters: q);
    final response = await http.get(uri, headers: _jsonHeadersWithAuth());
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final raw = data['items'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return <Map<String, dynamic>>[];
    }
    throw Exception(
      _extractErrorMessage(
        response,
        fallback: 'Chargement des ordonnances impossible',
      ),
    );
  }

  /// Liste paginée enrichie (`GET /api/prescriptions/conversation/:id`).
  static Future<
      ({
        List<PrescriptionHistoryEntry> data,
        int total,
        int page,
        int limit,
      })> fetchPrescriptionHistory({
    required String conversationId,
    int page = 1,
    int limit = 50,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/api/prescriptions/conversation/'
      '${Uri.encodeComponent(conversationId)}',
    ).replace(queryParameters: {
      'page': '$page',
      'limit': '$limit',
    });
    final response = await http.get(uri, headers: _jsonHeadersWithAuth());
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final rawList = data['data'];
      final list = <PrescriptionHistoryEntry>[];
      if (rawList is List) {
        for (final e in rawList) {
          if (e is Map) {
            list.add(
              PrescriptionHistoryEntry.fromJson(
                Map<String, dynamic>.from(e),
              ),
            );
          }
        }
      }
      final total = _readInt(data['total']) ?? list.length;
      final pageOut = _readInt(data['page']) ?? page;
      final limitOut = _readInt(data['limit']) ?? limit;
      return (
        data: list,
        total: total,
        page: pageOut,
        limit: limitOut,
      );
    }
    throw Exception(
      _extractErrorMessage(
        response,
        fallback: 'Chargement des ordonnances impossible',
      ),
    );
  }

  static int? _readInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// Aligné backend `stripInvalidRawFlInline` : ne pas injecter `fl_inline` sur `/raw/` (PDF → souvent HTTP 400 Cloudinary).
  static String _cloudinaryInlineDeliveryUrl(String url) {
    if (!url.contains('res.cloudinary.com')) {
      return url;
    }
    var u = url;
    if (u.contains('/raw/upload/fl_inline/')) {
      u = u.replaceAll('/raw/upload/fl_inline/', '/raw/upload/');
    }
    if (u.contains('/video/upload/fl_inline/')) {
      u = u.replaceAll('/video/upload/fl_inline/', '/video/upload/');
    }
    return u;
  }

  static Future<Map<String, dynamic>> registerPatient({
    required String fullName,
    required String email,
    required String password,
    required String country,
    required String addressExact,
    required String phone,
  }) async {
    final uri = Uri.parse('$_baseUrl/auth/register');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fullName': fullName,
        'email': email,
        'password': password,
        'country': country,
        'addressExact': addressExact,
        'phone': phone,
      }),
    );

    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    } else {
      throw Exception(
        _extractErrorMessage(response, fallback: 'Erreur lors de l’inscription'),
      );
    }
  }

  static Future<Map<String, dynamic>> loginPatient({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$_baseUrl/auth/login');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    } else {
      throw Exception(
        _extractErrorMessage(response, fallback: 'Erreur lors de la connexion'),
      );
    }
  }

  static Future<void> registerPushDevice({
    required String token,
    required String platform,
    String? voipToken,
  }) async {
    final uri = Uri.parse('$_baseUrl/push/register-device');
    final response = await http.post(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode({
        'token': token,
        'platform': platform,
        'appName': 'patient',
        if (voipToken != null && voipToken.trim().isNotEmpty) 'voipToken': voipToken.trim(),
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        _extractErrorMessage(response, fallback: 'Erreur enregistrement push'),
      );
    }
  }

  /// Refus d’appel depuis CallKit (socket parfois absent).
  static Future<void> reportIncomingCallDeclined({
    required String callId,
    required String roomId,
    required String doctorUserId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/api/patient/calls/${Uri.encodeComponent(callId)}/decline',
    );
    final response = await http.post(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode({
        'roomId': roomId,
        'doctorUserId': doctorUserId,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        _extractErrorMessage(response, fallback: 'Erreur signalement refus appel'),
      );
    }
  }

  static Future<void> reportIncomingCallMissed({required String callId}) async {
    final uri = Uri.parse(
      '$_baseUrl/api/patient/calls/${Uri.encodeComponent(callId)}/missed',
    );
    final response = await http.post(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode(<String, dynamic>{}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        _extractErrorMessage(response, fallback: 'Erreur signalement appel manqué'),
      );
    }
  }

  static Future<void> unregisterPushDevice({
    required String token,
  }) async {
    final uri = Uri.parse('$_baseUrl/push/unregister-device');
    final response = await http.post(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode({'token': token}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        _extractErrorMessage(response, fallback: 'Erreur suppression push'),
      );
    }
  }

  /// Demande d'envoi d'un code de réinitialisation par email.
  static Future<Map<String, dynamic>> requestResetCode({
    required String email,
  }) async {
    final uri = Uri.parse('$_baseUrl/auth/request-reset-code');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );

    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    } else {
      throw Exception(
        _extractErrorMessage(response, fallback: 'Erreur lors de l\'envoi du code'),
      );
    }
  }

  /// Vérification simple du code (sans changer le mot de passe).
  static Future<Map<String, dynamic>> verifyResetCode({
    required String email,
    required String code,
  }) async {
    final uri = Uri.parse('$_baseUrl/auth/verify-reset-code');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'code': code}),
    );

    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    } else {
      throw Exception(
        _extractErrorMessage(response, fallback: 'Code invalide ou expire'),
      );
    }
  }

  /// Enregistrement du formulaire d'urgence (symptômes + alerte éventuelle).
  static Future<Map<String, dynamic>> saveFormulaireUrgence({
    required String patientId,
    required List<String> symptomes,
    bool alerteAcceptee = false,
  }) async {
    final uri = Uri.parse('$_baseUrl/formulaire-urgence');
    final response = await http.post(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode({
        'patientId': patientId,
        'symptomes': symptomes,
        'alerteAcceptee': alerteAcceptee,
      }),
    );

    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    } else {
      throw Exception(
        _extractErrorMessage(
          response,
          fallback: 'Erreur lors de l\'enregistrement.',
        ),
      );
    }
  }

  /// Vérification du code reçu par email et changement du mot de passe.
  static Future<Map<String, dynamic>> verifyAndResetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final uri = Uri.parse('$_baseUrl/auth/verify-reset-password');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'code': code,
        'newPassword': newPassword,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    } else {
      throw Exception(data['message'] ?? 'Erreur lors du changement de mot de passe');
    }
  }

  /// Liste des médecins avec filtres optionnels (spécialité, nom, gouvernorat, position pour tri par distance).
  static Future<List<Map<String, dynamic>>> getDoctors({
    String? specialty,
    String? name,
    String? governorate,
    double? latitude,
    double? longitude,
  }) async {
    final query = <String>[];
    if (specialty != null && specialty.trim().isNotEmpty) {
      query.add('specialty=${Uri.encodeComponent(specialty.trim())}');
    }
    if (name != null && name.trim().isNotEmpty) {
      query.add('name=${Uri.encodeComponent(name.trim())}');
    }
    if (governorate != null && governorate.trim().isNotEmpty) {
      query.add('governorate=${Uri.encodeComponent(governorate.trim())}');
    }
    if (latitude != null && longitude != null) {
      query.add('latitude=$latitude');
      query.add('longitude=$longitude');
    }
    final path = query.isEmpty ? '/doctors' : '/doctors?${query.join('&')}';
    final uri = Uri.parse('$_baseUrl$path');
    final response = await http.get(uri);

    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = data['doctors'];
      return list is List ? List<Map<String, dynamic>>.from(list.map((e) => Map<String, dynamic>.from(e as Map))) : [];
    } else {
      throw Exception(data['message'] ?? 'Erreur lors de la récupération des médecins');
    }
  }

  /// Liste des discussions du patient (conversations patient->médecin).
  static Future<List<Map<String, dynamic>>> getPatientConversations({
    required String patientId,
  }) async {
    final uri = Uri.parse('$_baseUrl/patient/conversations?patientId=${Uri.encodeComponent(patientId)}');
    final response = await http
        .get(uri, headers: _headersAuthOnly())
        .timeout(const Duration(seconds: 12));
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = data['conversations'];
      return list is List
          ? List<Map<String, dynamic>>.from(
              list.map((e) => Map<String, dynamic>.from(e as Map)),
            )
          : [];
    } else {
      throw Exception(data['message'] ?? 'Erreur lors de la récupération des discussions');
    }
  }

  /// Dossier médical personnel (documents uploadés par le patient, hors chat).
  static Future<List<Map<String, dynamic>>> getPatientMedicalDossier({
    required String patientId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/api/patient/dossier-medical?patientId=${Uri.encodeComponent(patientId)}',
    );
    final response = await http.get(uri, headers: _headersAuthOnly());
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = data['items'];
      return list is List
          ? List<Map<String, dynamic>>.from(
              list.map((e) => Map<String, dynamic>.from(e as Map)),
            )
          : [];
    }
    throw Exception(data['message'] ?? 'Erreur lors du chargement du dossier médical');
  }

  /// Supprime un document du dossier médical personnel.
  static Future<void> deletePatientMedicalDocument({
    required String patientId,
    required String documentId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/api/patient/dossier-medical/${Uri.encodeComponent(documentId)}?patientId=${Uri.encodeComponent(patientId)}',
    );
    final response = await http.delete(uri, headers: _headersAuthOnly());
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final data = jsonDecode(response.body);
    throw Exception(data['message'] ?? 'Erreur lors de la suppression');
  }

  /// Upload vers une catégorie du dossier médical (`analyses|ordonnances|fichiers|images`).
  static Future<Map<String, dynamic>> uploadPatientMedicalDocument({
    required String patientId,
    required String category,
    required PlatformFile file,
    String? title,
    DateTime? documentDate,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/patient/dossier-medical');
    final request = http.MultipartRequest('POST', uri)
      ..fields['patientId'] = patientId
      ..fields['category'] = category;
    final tok = _jwtToken;
    if (tok != null && tok.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $tok';
    }
    if (title != null && title.trim().isNotEmpty) {
      request.fields['title'] = title.trim();
    }
    if (documentDate != null) {
      request.fields['documentDate'] = documentDate.toUtc().toIso8601String();
    }
    if (file.bytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name),
      );
    } else if (file.path != null) {
      request.files.add(
        await http.MultipartFile.fromPath('file', file.path!, filename: file.name),
      );
    } else {
      throw Exception('Fichier invalide.');
    }
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final decoded = jsonDecode(response.body);
    final data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(data['message'] ?? 'Erreur upload dossier médical');
  }

  /// Partage des pièces sélectionnées du dossier médical vers un médecin.
  static Future<Map<String, dynamic>> sharePatientMedicalDossier({
    required String patientId,
    required String doctorId,
    required List<String> itemIds,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/patient/dossier-medical/share');
    final response = await http.post(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode({
        'patientId': patientId,
        'doctorId': doctorId,
        'itemIds': itemIds,
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return Map<String, dynamic>.from(data as Map);
    }
    throw Exception(data['message'] ?? 'Erreur lors du partage du dossier');
  }

  /// Tous les créneaux téléconsultation planifiés pour le patient.
  static Future<List<Map<String, dynamic>>> getPatientScheduledTeleconsults({
    required String patientId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/patient/${Uri.encodeComponent(patientId)}/scheduled-teleconsults',
    );
    final response = await http.get(uri, headers: _headersAuthOnly());
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = data['slots'];
      return list is List
          ? List<Map<String, dynamic>>.from(
              list.map((e) => Map<String, dynamic>.from(e as Map)),
            )
          : [];
    }
    throw Exception(data['message'] ?? 'Erreur lors de la récupération des rendez-vous');
  }

  /// Rendez-vous issus de l’agenda médecin (`GET /api/rendezvous/patient`).
  static Future<Map<String, dynamic>> getPatientRendezVousApi({
    required String patientId,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/rendezvous/patient').replace(
      queryParameters: {'patientId': patientId},
    );
    final response = await http.get(uri, headers: _headersAuthOnly());
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return Map<String, dynamic>.from(data as Map);
    }
    throw Exception(data['message'] ?? 'Erreur rendez-vous');
  }

  /// Demandes de téléconsultation du patient (statuts : pending / accepted / rejected).
  static Future<List<Map<String, dynamic>>> getPatientTeleconsultRequests({
    required String patientId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/patient/${Uri.encodeComponent(patientId)}/teleconsult-requests',
    );
    final response = await http.get(uri, headers: _headersAuthOnly());
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = data['items'];
      return list is List
          ? List<Map<String, dynamic>>.from(
              list.map((e) => Map<String, dynamic>.from(e as Map)),
            )
          : [];
    }
    throw Exception(data['message'] ?? 'Erreur lors de la récupération des demandes');
  }

  /// Infos publiques d'un médecin (nom + statut) pour affichage côté patient.
  static Future<Map<String, dynamic>> getDoctor(String doctorId) async {
    final uri = Uri.parse('$_baseUrl/doctor/${Uri.encodeComponent(doctorId)}');
    final response = await http.get(uri, headers: _headersAuthOnly());
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return Map<String, dynamic>.from(data);
    } else {
      throw Exception(data['message'] ?? 'Médecin introuvable');
    }
  }

  /// Évaluation patient -> médecin (satisfaction)
  static Future<Map<String, dynamic>> evaluateDoctor({
    required String doctorId,
    required String patientId,
    required String satisfaction,
  }) async {
    final uri = Uri.parse('$_baseUrl/doctor/${Uri.encodeComponent(doctorId)}/evaluation');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'patientId': patientId,
        'satisfaction': satisfaction,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return Map<String, dynamic>.from(data);
    } else {
      throw Exception(data['message'] ?? 'Erreur lors de l’évaluation du médecin');
    }
  }

  /// Récupérer l'évaluation du patient pour un médecin (retourne `evaluation` ou null)
  static Future<Map<String, dynamic>> getDoctorEvaluation({
    required String doctorId,
    required String patientId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/doctor/${Uri.encodeComponent(doctorId)}/evaluation?patientId=${Uri.encodeComponent(patientId)}',
    );
    final response = await http.get(uri);
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return Map<String, dynamic>.from(data);
    }
    throw Exception(data['message'] ?? 'Erreur lors de la récupération de l’évaluation');
  }

  // 🔹 PROFIL PATIENT
  static Future<Map<String, dynamic>> getPatientProfile({
    required String patientId,
  }) async {
    final uri =
        Uri.parse('$_baseUrl/patient/${Uri.encodeComponent(patientId)}');
    final response = await http.get(uri, headers: _headersAuthOnly());
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return Map<String, dynamic>.from(data);
    }
    throw Exception(data['message'] ?? "Erreur lors du chargement du profil.");
  }

  static Future<Map<String, dynamic>> updatePatientName({
    required String patientId,
    required String fullName,
  }) async {
    final uri = Uri.parse('$_baseUrl/patient/${Uri.encodeComponent(patientId)}/name');
    final response = await http.patch(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode({'fullName': fullName}),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return Map<String, dynamic>.from(data);
    }
    throw Exception(data['message'] ?? "Erreur lors de la mise à jour du nom.");
  }

  static Future<Map<String, dynamic>> uploadPatientPhoto({
    required String patientId,
    required PlatformFile file,
  }) async {
    final uri = Uri.parse('$_baseUrl/patient/${Uri.encodeComponent(patientId)}/photo');
    final request = http.MultipartRequest('POST', uri);
    final tokPhoto = _jwtToken;
    if (tokPhoto != null && tokPhoto.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $tokPhoto';
    }
    if (file.bytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          file.bytes!,
          filename: file.name,
        ),
      );
    } else if (file.path != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'photo',
          file.path!,
          filename: file.name,
        ),
      );
    } else {
      throw Exception('Fichier photo invalide.');
    }

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return Map<String, dynamic>.from(data);
    }
    throw Exception(data['message'] ?? "Erreur lors du chargement de la photo.");
  }

  static Future<Map<String, dynamic>> uploadPatientPhotoXFile({
    required String patientId,
    required XFile file,
  }) async {
    final uri = Uri.parse('$_baseUrl/patient/${Uri.encodeComponent(patientId)}/photo');
    final request = http.MultipartRequest('POST', uri);
    final tokPhoto = _jwtToken;
    if (tokPhoto != null && tokPhoto.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $tokPhoto';
    }
    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      request.files.add(
        http.MultipartFile.fromBytes('photo', bytes, filename: file.name),
      );
    } else {
      request.files.add(
        await http.MultipartFile.fromPath('photo', file.path, filename: file.name),
      );
    }
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return Map<String, dynamic>.from(data);
    }
    throw Exception(data['message'] ?? "Erreur lors du chargement de la photo.");
  }

  static Future<Map<String, dynamic>> changePatientPassword({
    required String patientId,
    required String oldPassword,
    required String newPassword,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/patient/${Uri.encodeComponent(patientId)}/change-password',
    );
    final response = await http.post(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode({
        'oldPassword': oldPassword,
        'newPassword': newPassword,
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return Map<String, dynamic>.from(data);
    }
    throw Exception(data['message'] ?? 'Erreur lors du changement de mot de passe.');
  }

  static Future<Map<String, dynamic>> updatePatientProfile({
    required String patientId,
    required String fullName,
    String? birthDateIso,
    String? sex,
    required String phone,
    required String email,
    required String addressExact,
    String? bloodGroup,
    num? weightKg,
    num? heightCm,
    String? knownAllergies,
  }) async {
    final uri = Uri.parse('$_baseUrl/patient/${Uri.encodeComponent(patientId)}/profile');
    final response = await http.patch(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode({
        'fullName': fullName,
        'birthDate': birthDateIso,
        'sex': sex,
        'phone': phone,
        'email': email,
        'addressExact': addressExact,
        if (bloodGroup != null) 'bloodGroup': bloodGroup,
        if (weightKg != null) 'weightKg': weightKg,
        if (heightCm != null) 'heightCm': heightCm,
        if (knownAllergies != null) 'knownAllergies': knownAllergies,
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return Map<String, dynamic>.from(data);
    }
    throw Exception(data['message'] ?? 'Erreur mise à jour profil');
  }

  // 🔹 CHAT / TÉLÉCONSULTATION

  static Future<Map<String, dynamic>> createConversation({
    required String patientId,
    required String doctorId,
  }) async {
    final uri = Uri.parse('$_baseUrl/conversations');
    final response = await http.post(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode({'patientId': patientId, 'doctorId': doctorId}),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    } else {
      throw Exception(data['message'] ?? 'Erreur lors de la création de la conversation');
    }
  }

  static Future<Map<String, dynamic>> getMessages({
    required String conversationId,
  }) async {
    final uri = Uri.parse('$_baseUrl/messages?conversationId=$conversationId');
    final response = await http.get(uri, headers: _headersAuthOnly());
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    } else {
      throw Exception(data['message'] ?? 'Erreur lors de la récupération des messages');
    }
  }

  /// Clés : `messages` (liste), `sessionStatus` (`open` | `cloture`).
  static Future<Map<String, dynamic>> getMessagesAfter({
    required String conversationId,
    required String afterId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/messages/after?conversationId=${Uri.encodeComponent(conversationId)}&afterId=${Uri.encodeComponent(afterId)}',
    );
    final response = await http.get(uri, headers: _headersAuthOnly());
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = data['messages'];
      final messages = list is List
          ? List<Map<String, dynamic>>.from(
              list.map((e) => Map<String, dynamic>.from(e as Map)),
            )
          : <Map<String, dynamic>>[];
      final ss = data['sessionStatus']?.toString() ?? 'open';
      return {
        'messages': messages,
        'sessionStatus': ss == 'cloture' ? 'cloture' : 'open',
      };
    } else {
      throw Exception(data['message'] ?? 'Erreur lors de la récupération des nouveaux messages');
    }
  }

  static Future<void> markMessagesRead({
    required String conversationId,
    required String readerFromType,
  }) async {
    final uri = Uri.parse('$_baseUrl/messages/mark-read');
    final response = await http.post(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode({
        'conversationId': conversationId,
        'readerFromType': readerFromType,
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw Exception(data['message'] ?? 'Erreur lecture messages');
  }

  static Future<void> sendMessage({
    required String conversationId,
    required String fromType,
    String type = 'text',
    String content = '',
    Map<String, dynamic>? payload,
  }) async {
    final uri = Uri.parse('$_baseUrl/messages');
    final response = await http.post(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode({
        'conversationId': conversationId,
        'fromType': fromType,
        'type': type,
        'content': content,
        'payload': payload ?? {},
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final data = jsonDecode(response.body);
      throw Exception(data['message'] ?? 'Erreur lors de l\'envoi du message');
    }
  }

  static Future<Map<String, dynamic>> sendTeleconsultRequest({
    required String conversationId,
    String? motif,
    String? letterBody,
  }) async {
    final uri = Uri.parse('$_baseUrl/teleconsultations/request');
    final response = await http.post(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode({
        'conversationId': conversationId,
        'motif': motif,
        'letterBody': letterBody?.trim() ?? '',
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    } else {
      throw Exception(data['message'] ?? 'Erreur lors de l\'envoi de la demande');
    }
  }

  static Future<Map<String, dynamic>> sendTeleconsultForm({
    required String conversationId,
    required String motif,
    required String symptomes,
    String? dateDerniereConsultation,
    String? traitements,
    String? allergies,
    bool notifyChat = true,
  }) async {
    final uri = Uri.parse('$_baseUrl/teleconsultations/form');
    final response = await http.post(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode({
        'conversationId': conversationId,
        'motif': motif,
        'symptomes': symptomes,
        'dateDerniereConsultation': dateDerniereConsultation,
        'traitements': traitements,
        'allergies': allergies,
        'notifyChat': notifyChat,
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    } else {
      throw Exception(data['message'] ?? 'Erreur lors de l\'envoi du formulaire');
    }
  }

  /// Ajoute une pièce jointe au dossier téléconsultation (hors fil de chat).
  static Future<Map<String, dynamic>> uploadTeleconsultFormAttachment({
    required String formId,
    required String patientId,
    required PlatformFile file,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/teleconsultations/form/${Uri.encodeComponent(formId)}/attachment',
    );
    final request = http.MultipartRequest('POST', uri)
      ..fields['patientId'] = patientId;
    final tokForm = _jwtToken;
    if (tokForm != null && tokForm.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $tokForm';
    }
    if (file.bytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name),
      );
    } else if (file.path != null) {
      request.files.add(
        await http.MultipartFile.fromPath('file', file.path!, filename: file.name),
      );
    } else {
      throw Exception('Fichier invalide.');
    }
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final decoded = jsonDecode(response.body);
    final data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(data['message'] ?? 'Erreur envoi pièce jointe');
  }

  static Future<Map<String, dynamic>> uploadAttachment({
    required String conversationId,
    required PlatformFile file,
    String? senderId,
  }) async {
    final uri = Uri.parse('$_baseUrl/teleconsultations/upload');
    final request = http.MultipartRequest('POST', uri)
      ..fields['conversationId'] = conversationId
      ..fields['fromType'] = 'patient';
    if (senderId != null && senderId.isNotEmpty) {
      request.fields['senderId'] = senderId;
    }
    final tokUp = _jwtToken;
    if (tokUp != null && tokUp.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $tokUp';
    }

    if (file.bytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          file.bytes!,
          filename: file.name,
        ),
      );
    } else if (file.path != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path!,
          filename: file.name,
        ),
      );
    } else {
      throw Exception('Fichier invalide.');
    }

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final data = jsonDecode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    } else {
      throw Exception(data['message'] ?? 'Erreur lors de l\'envoi du fichier');
    }
  }

  /// HL7: JSON -> HL7 (MSH/PID/OBX) + stockage backend.
  static Future<Map<String, dynamic>> createHl7FromJson({
    required Map<String, dynamic> patient,
    List<Map<String, dynamic>> measures = const [],
    List<Map<String, dynamic>> files = const [],
    String? hl7SharedSecret,
  }) async {
    final uri = Uri.parse('$_baseUrl/hl7/from-json');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (hl7SharedSecret != null && hl7SharedSecret.isNotEmpty) {
      headers['x-hl7-key'] = hl7SharedSecret;
    }
    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({
        'patient': patient,
        'measures': measures,
        'files': files,
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return Map<String, dynamic>.from(data as Map);
    }
    throw Exception(data['message'] ?? 'Erreur génération HL7');
  }

  /// HL7: parse un message HL7 brut reçu puis stockage backend.
  static Future<Map<String, dynamic>> parseHl7Message({
    required String hl7Message,
    String? source,
    String? hl7SharedSecret,
  }) async {
    final uri = Uri.parse('$_baseUrl/hl7/parse');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (hl7SharedSecret != null && hl7SharedSecret.isNotEmpty) {
      headers['x-hl7-key'] = hl7SharedSecret;
    }
    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({
        'hl7Message': hl7Message,
        if (source != null && source.isNotEmpty) 'source': source,
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return Map<String, dynamic>.from(data as Map);
    }
    throw Exception(data['message'] ?? 'Erreur parse HL7');
  }

  /// HL7: génération depuis multipart (patient/measures + fichiers à uploader Cloudinary).
  static Future<Map<String, dynamic>> createHl7FromMultipart({
    required Map<String, dynamic> patient,
    List<Map<String, dynamic>> measures = const [],
    List<PlatformFile> files = const [],
    String? source,
    String? hl7SharedSecret,
  }) async {
    final uri = Uri.parse('$_baseUrl/hl7/from-json-with-files');
    final request = http.MultipartRequest('POST', uri)
      ..fields['patient'] = jsonEncode(patient)
      ..fields['measures'] = jsonEncode(measures);
    if (source != null && source.isNotEmpty) {
      request.fields['source'] = source;
    }
    if (hl7SharedSecret != null && hl7SharedSecret.isNotEmpty) {
      request.headers['x-hl7-key'] = hl7SharedSecret;
    }
    for (final f in files) {
      if (f.bytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'files',
            f.bytes!,
            filename: f.name,
          ),
        );
      } else if (f.path != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'files',
            f.path!,
            filename: f.name,
          ),
        );
      }
    }
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return Map<String, dynamic>.from(data as Map);
    }
    throw Exception(data['message'] ?? 'Erreur génération HL7 multipart');
  }

  /// HL7: liste des messages stockés.
  static Future<List<Map<String, dynamic>>> getHl7Messages({
    String? direction,
    String? patientId,
    int limit = 50,
    String? hl7SharedSecret,
  }) async {
    final qp = <String, String>{
      'limit': '$limit',
      if (direction != null && direction.isNotEmpty) 'direction': direction,
      if (patientId != null && patientId.isNotEmpty) 'patientId': patientId,
    };
    final uri = Uri.parse('$_baseUrl/hl7/messages').replace(queryParameters: qp);
    final headers = <String, String>{};
    if (hl7SharedSecret != null && hl7SharedSecret.isNotEmpty) {
      headers['x-hl7-key'] = hl7SharedSecret;
    }
    final response = await http.get(uri, headers: headers);
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = (data as Map<String, dynamic>)['messages'];
      if (list is List) {
        return List<Map<String, dynamic>>.from(
          list.map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
      return [];
    }
    throw Exception(data['message'] ?? 'Erreur lecture messages HL7');
  }

  /// HL7: détail d'un message par id.
  static Future<Map<String, dynamic>> getHl7MessageById({
    required String id,
    String? hl7SharedSecret,
  }) async {
    final uri = Uri.parse('$_baseUrl/hl7/messages/${Uri.encodeComponent(id)}');
    final headers = <String, String>{};
    if (hl7SharedSecret != null && hl7SharedSecret.isNotEmpty) {
      headers['x-hl7-key'] = hl7SharedSecret;
    }
    final response = await http.get(uri, headers: headers);
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return Map<String, dynamic>.from(data as Map);
    }
    throw Exception(data['message'] ?? 'Erreur lecture message HL7');
  }

  /// WebRTC: récupérer la configuration ICE (STUN/TURN) depuis le backend.
  static Future<List<Map<String, dynamic>>> getIceServers({
    required String userId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/webrtc/ice-config?userId=${Uri.encodeComponent(userId)}',
    );
    final response = await http.get(uri);
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = (data as Map<String, dynamic>)['iceServers'];
      if (list is List) {
        return List<Map<String, dynamic>>.from(
          list.map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
      return [];
    }
    throw Exception(data['message'] ?? 'Erreur récupération ICE servers');
  }

  static Future<Map<String, dynamic>?> getPatientBloodPressureLatest({
    required String patientId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/patient/blood-pressure/latest?patientId=${Uri.encodeComponent(patientId)}',
    );
    final response = await http.get(uri, headers: _headersAuthOnly());
    if (response.statusCode == 404) return null;
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final item = (data as Map<String, dynamic>)['measurement'];
      if (item is Map) return Map<String, dynamic>.from(item);
      return null;
    }
    throw Exception((data as Map<String, dynamic>)['message'] ?? 'Erreur lors du chargement de la mesure');
  }

  static Future<List<Map<String, dynamic>>> getPatientBloodPressureHistory({
    required String patientId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/patient/blood-pressure/history?patientId=${Uri.encodeComponent(patientId)}',
    );
    final response = await http.get(uri, headers: _headersAuthOnly());
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = (data as Map<String, dynamic>)['measurements'];
      if (list is! List) return <Map<String, dynamic>>[];
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    throw Exception((data as Map<String, dynamic>)['message'] ?? 'Erreur historique tension');
  }

  static Future<List<Map<String, dynamic>>> getPatientBloodPressureAlerts({
    required String patientId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/patient/blood-pressure/alerts?patientId=${Uri.encodeComponent(patientId)}',
    );
    final response = await http.get(uri, headers: _headersAuthOnly());
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = (data as Map<String, dynamic>)['alerts'];
      if (list is! List) return <Map<String, dynamic>>[];
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    throw Exception((data as Map<String, dynamic>)['message'] ?? 'Erreur alertes tension');
  }

  static Future<Map<String, dynamic>> postBloodPressureMeasurement({
    required String patientId,
    required int systolic,
    required int diastolic,
    int? meanArterialPressure,
    int? heartRate,
    String source = 'manual',
    String? deviceName,
    DateTime? measuredAt,
  }) async {
    final uri = Uri.parse('$_baseUrl/patient/blood-pressure/measurements');
    final response = await http.post(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode({
        'patientId': patientId,
        'systolic': systolic,
        'diastolic': diastolic,
        if (meanArterialPressure != null) 'meanArterialPressure': meanArterialPressure,
        if (heartRate != null) 'heartRate': heartRate,
        'source': source,
        if (deviceName != null && deviceName.isNotEmpty) 'deviceName': deviceName,
        if (measuredAt != null) 'measuredAt': measuredAt.toUtc().toIso8601String(),
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return Map<String, dynamic>.from(data as Map);
    }
    throw Exception((data as Map<String, dynamic>)['message'] ?? 'Erreur envoi mesure');
  }

}

/// Gouvernorats tunisiens (24).
const List<String> kGovernorates = [
  'Ariana', 'Béja', 'Ben Arous', 'Bizerte', 'Gabès', 'Gafsa', 'Jendouba',
  'Kairouan', 'Kasserine', 'Kébili', 'Le Kef', 'Mahdia', 'La Manouba',
  'Médenine', 'Monastir', 'Nabeul', 'Sfax', 'Sidi Bouzid', 'Siliana',
  'Sousse', 'Tataouine', 'Tozeur', 'Tunis', 'Zaghouan',
];

/// Spécialités médicales pour le filtre.
const List<String> kSpecialties = [
  'Médecine générale',
  'Cardiologie',
  'Dermatologie',
  'Pédiatrie',
  'Gynécologie',
  'ORL',
  'Ophtalmologie',
  'Orthopédie',
  'Psychiatrie',
  'Radiologie',
  'Neurologie',
  'Urologie',
  'Autre',
];

