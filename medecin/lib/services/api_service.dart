import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../prescription_history/prescription_history_model.dart';

/// Gouvernorats tunisiens (24).
const List<String> kGovernorates = [
  'Ariana',
  'Béja',
  'Ben Arous',
  'Bizerte',
  'Gabès',
  'Gafsa',
  'Jendouba',
  'Kairouan',
  'Kasserine',
  'Kébili',
  'Le Kef',
  'Mahdia',
  'La Manouba',
  'Médenine',
  'Monastir',
  'Nabeul',
  'Sfax',
  'Sidi Bouzid',
  'Siliana',
  'Sousse',
  'Tataouine',
  'Tozeur',
  'Tunis',
  'Zaghouan',
];

/// Spécialités médicales (liste alignée sur l’app patient).
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

class ApiService {
  static const String _apiBaseUrlFromEnv =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');
  static const String _defaultBaseUrl = 'https://projetpfe-8vrx.onrender.com';

  static String get _baseUrl {
    final configured = _apiBaseUrlFromEnv.trim();
    assert(() {
      if (configured.toLowerCase().contains('localhost') && kReleaseMode) {
        debugPrint(
          '[ApiService][WARN] API_BASE_URL pointe vers localhost en release: $configured',
        );
      }
      return true;
    }());
    if (configured.isNotEmpty) return configured;
    return _defaultBaseUrl;
  }

  static String get baseUrl => _baseUrl;

  static String? _jwtToken;

  /// Jeton JWT (connexion médecin). À synchroniser avec [kSessionDoctorTokenKey].
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

  /// URL absolue pour une photo ou média (`/uploads/...` ou Cloudinary).
  static String resolveMediaUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    var p = path.trim();
    if (!p.startsWith('http://') && !p.startsWith('https://')) {
      final base =
          _baseUrl.endsWith('/') ? _baseUrl.substring(0, _baseUrl.length - 1) : _baseUrl;
      p = p.startsWith('/') ? '$base$p' : '$base/$p';
    }
    return p;
  }

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
      debugPrint(
        '[ApiService] HTML response on ${response.request?.url} - status ${response.statusCode}',
      );
      return '$fallback (reponse HTML recue, verifier API_BASE_URL: $baseUrl)';
    }
    return fallback;
  }

  /// Connexion compte médecin (`POST /auth/doctor/login`).
  static Future<Map<String, dynamic>> loginUser({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$_baseUrl/auth/doctor/login');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
      }),
    );

    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(
      _extractErrorMessage(response, fallback: 'Erreur lors de la connexion'),
    );
  }

  static Future<void> registerPushDevice({
    required String token,
    required String platform,
  }) async {
    final uri = Uri.parse('$_baseUrl/push/register-device');
    final response = await http.post(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode({
        'token': token,
        'platform': platform,
        'appName': 'doctor',
      }),
    );
    final data = _decodeBody(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        _extractErrorMessage(response, fallback: 'Erreur enregistrement push'),
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
    final data = _decodeBody(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        _extractErrorMessage(response, fallback: 'Erreur suppression push'),
      );
    }
  }

  /// Inscription médecin (`POST /auth/doctor/register`).
  static Future<Map<String, dynamic>> registerDoctor({
    required String fullName,
    required String email,
    required String password,
    required String specialty,
    required String governorate,
    required String address,
    required String phone,
    String? orderNumber,
    String? country,
    XFile? diploma,
  }) async {
    final uri = Uri.parse('$_baseUrl/auth/doctor/register');
    final request = http.MultipartRequest('POST', uri);
    request.fields['fullName'] = fullName.trim();
    request.fields['email'] = email.trim();
    request.fields['password'] = password;
    request.fields['specialty'] = specialty.trim();
    request.fields['governorate'] = governorate.trim();
    request.fields['address'] = address.trim();
    request.fields['phone'] = phone.replaceAll(' ', '');
    if (orderNumber != null && orderNumber.trim().isNotEmpty) {
      request.fields['orderNumber'] = orderNumber.trim();
    }
    if (country != null && country.trim().isNotEmpty) {
      request.fields['country'] = country.trim();
    }
    if (diploma != null) {
      if (kIsWeb) {
        final bytes = await diploma.readAsBytes();
        request.files.add(
          http.MultipartFile.fromBytes(
            'diploma',
            bytes,
            filename: diploma.name,
          ),
        );
      } else {
        request.files.add(
          await http.MultipartFile.fromPath(
            'diploma',
            diploma.path,
            filename: diploma.name,
          ),
        );
      }
    }

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(
      _extractErrorMessage(response, fallback: 'Erreur lors de l’inscription'),
    );
  }

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
    }
    throw Exception(
      _extractErrorMessage(response, fallback: 'Erreur lors de l\'envoi du code'),
    );
  }

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
    }
    throw Exception(
      _extractErrorMessage(response, fallback: 'Code invalide ou expire'),
    );
  }

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

    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(
        data['message'] ?? 'Erreur lors du changement de mot de passe');
  }

  static Future<Map<String, dynamic>> getDoctorProfile(String doctorId) async {
    final uri = Uri.parse(
        '$_baseUrl/doctor/${Uri.encodeComponent(doctorId)}/profile');
    final response = await http.get(uri, headers: _jsonHeadersWithAuth());
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(data['message'] ?? 'Profil introuvable');
  }

  static Future<Map<String, dynamic>> patchDoctorProfile({
    required String doctorId,
    String? fullName,
    String? specialty,
    String? governorate,
    String? address,
    String? phone,
    String? orderNumber,
    String? country,
    int? yearsExperience,
    String? hospitalOrClinic,
  }) async {
    final uri = Uri.parse(
        '$_baseUrl/doctor/${Uri.encodeComponent(doctorId)}/profile');
    final body = <String, dynamic>{};
    if (fullName != null) body['fullName'] = fullName;
    if (specialty != null) body['specialty'] = specialty;
    if (governorate != null) body['governorate'] = governorate;
    if (address != null) body['address'] = address;
    if (phone != null) body['phone'] = phone;
    if (orderNumber != null) body['orderNumber'] = orderNumber;
    if (country != null) body['country'] = country;
    if (yearsExperience != null) body['yearsExperience'] = yearsExperience;
    if (hospitalOrClinic != null) body['hospitalOrClinic'] = hospitalOrClinic;

    final response = await http.patch(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode(body),
    );
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(data['message'] ?? 'Mise à jour impossible');
  }

  static Future<Map<String, dynamic>> uploadDoctorPhoto({
    required String doctorId,
    required PlatformFile file,
  }) async {
    final uri = Uri.parse(
        '$_baseUrl/doctor/${Uri.encodeComponent(doctorId)}/photo');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_jsonHeadersWithAuth());
    if (file.bytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes('photo', file.bytes!, filename: file.name),
      );
    } else if (file.path != null) {
      request.files.add(
        await http.MultipartFile.fromPath('photo', file.path!, filename: file.name),
      );
    } else {
      throw Exception('Fichier photo invalide.');
    }
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(data['message'] ?? 'Échec envoi photo');
  }

  static Future<Map<String, dynamic>> uploadDoctorPhotoXFile({
    required String doctorId,
    required XFile file,
  }) async {
    final uri = Uri.parse(
        '$_baseUrl/doctor/${Uri.encodeComponent(doctorId)}/photo');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_jsonHeadersWithAuth());
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
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(data['message'] ?? 'Échec envoi photo');
  }

  static Future<List<Map<String, dynamic>>> getDoctorConversations({
    required String doctorId,
    String filter = 'all',
  }) async {
    final uri = Uri.parse('$_baseUrl/doctor/conversations').replace(
      queryParameters: {
        'doctorId': doctorId,
        'filter': filter,
      },
    );
    final response = await http.get(uri, headers: _jsonHeadersWithAuth());
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = data['conversations'];
      if (list is List) {
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    }
    throw Exception(data['message'] ?? 'Erreur conversations');
  }

  static Future<Map<String, dynamic>> getDoctorNotifications({
    required String doctorId,
    int limit = 50,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/doctor/${Uri.encodeComponent(doctorId)}/notifications?limit=$limit',
    );
    final response = await http
        .get(uri, headers: _jsonHeadersWithAuth())
        .timeout(const Duration(seconds: 12));
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(data['message'] ?? 'Erreur lors de la récupération des notifications');
  }

  static Future<void> markDoctorNotificationRead({
    required String doctorId,
    required String notificationId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/doctor/${Uri.encodeComponent(doctorId)}/notifications/${Uri.encodeComponent(notificationId)}/read',
    );
    final response = await http.patch(uri, headers: _jsonHeadersWithAuth());
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final data = _decodeBody(response.body);
      throw Exception(data['message'] ?? 'Erreur lors de la mise à jour');
    }
  }

  static Future<void> markAllDoctorNotificationsRead({
    required String doctorId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/doctor/${Uri.encodeComponent(doctorId)}/notifications/read-all',
    );
    final response = await http.patch(uri, headers: _jsonHeadersWithAuth());
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final data = _decodeBody(response.body);
      throw Exception(data['message'] ?? 'Erreur lors de la mise à jour');
    }
  }

  /// Patients en salle d’attente (persisté côté serveur, utile après redémarrage app).
  static Future<List<Map<String, dynamic>>> getDoctorWaitingRooms({
    required String doctorId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/doctor/${Uri.encodeComponent(doctorId)}/waiting-rooms',
    );
    final response = await http.get(uri, headers: _jsonHeadersWithAuth());
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = data['items'];
      if (list is List) {
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    }
    throw Exception(data['message'] ?? 'Erreur salle d’attente');
  }

  /// État salle d’attente pour une conversation (`waiting`, `enteredAt` ISO si oui).
  static Future<Map<String, dynamic>> getConversationWaitingRoom(
    String conversationId,
  ) async {
    final uri = Uri.parse(
      '$_baseUrl/waiting-room/${Uri.encodeComponent(conversationId)}',
    );
    final response = await http.get(uri, headers: _jsonHeadersWithAuth());
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(data['message'] ?? 'Erreur état salle d’attente');
  }

  static Future<List<Map<String, dynamic>>> getMedecinRendezVous({
    required String medecinId,
    String? date,
  }) async {
    final q = <String, String>{'medecinId': medecinId};
    if (date != null && date.isNotEmpty) q['date'] = date;
    final uri = Uri.parse('$_baseUrl/api/medecin/rendez-vous')
        .replace(queryParameters: q);
    final response = await http.get(uri, headers: _jsonHeadersWithAuth());
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = data['rendezVous'];
      if (list is List) {
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    }
    throw Exception(data['message'] ?? 'Erreur agenda');
  }

  /// Agenda médecin : uniquement la collection serveur `RendezVous` (plus de messages chat).
  static Future<List<Map<String, dynamic>>> getDoctorAgendaRendezVous({
    required String doctorId,
  }) {
    return getMedecinRendezVous(medecinId: doctorId);
  }

  /// Même source que [getDoctorAgendaRendezVous] (format `slots` pour compatibilité).
  static Future<List<Map<String, dynamic>>> getDoctorScheduledTeleconsults({
    required String doctorId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/doctor/${Uri.encodeComponent(doctorId)}/scheduled-teleconsults',
    );
    final response = await http.get(uri, headers: _jsonHeadersWithAuth());
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final slots = data['slots'];
      if (slots is List) {
        return slots.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    }
    throw Exception(data['message'] ?? 'Erreur créneaux téléconsultation');
  }

  /// Retourne `messages` (liste) et `sessionStatus` (`open` | `cloture`).
  static Future<Map<String, dynamic>> getMessages({
    required String conversationId,
  }) async {
    final uri = Uri.parse('$_baseUrl/messages').replace(
      queryParameters: {'conversationId': conversationId},
    );
    final response = await http.get(uri, headers: _jsonHeadersWithAuth());
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = data['messages'];
      final messages = list is List
          ? list.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];
      final ss = data['sessionStatus']?.toString() ?? 'open';
      return {
        'messages': messages,
        'sessionStatus': ss == 'cloture' ? 'cloture' : 'open',
      };
    }
    throw Exception(data['message'] ?? 'Erreur messages');
  }

  /// Messages plus récents que [afterId] (ObjectId Mongo) + `sessionStatus`.
  static Future<Map<String, dynamic>> getMessagesAfter({
    required String conversationId,
    required String afterId,
  }) async {
    final uri = Uri.parse('$_baseUrl/messages/after').replace(
      queryParameters: {
        'conversationId': conversationId,
        'afterId': afterId,
      },
    );
    final response = await http.get(uri, headers: _jsonHeadersWithAuth());
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = data['messages'];
      final messages = list is List
          ? list.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];
      final ss = data['sessionStatus']?.toString() ?? 'open';
      return {
        'messages': messages,
        'sessionStatus': ss == 'cloture' ? 'cloture' : 'open',
      };
    }
    throw Exception(data['message'] ?? 'Erreur messages');
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
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw Exception(data['message'] ?? 'Erreur lecture messages');
  }

  static Future<void> cloturerConversation({
    required String conversationId,
    required String doctorId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/api/conversations/${Uri.encodeComponent(conversationId)}/cloturer',
    );
    final response = await http.put(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode({'doctorId': doctorId}),
    );
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw Exception(data['message'] ?? 'Clôture impossible');
  }

  static Future<void> rouvrirConversation({
    required String conversationId,
    required String doctorId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/api/conversations/${Uri.encodeComponent(conversationId)}/rouvrir',
    );
    final response = await http.put(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode({'doctorId': doctorId}),
    );
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw Exception(data['message'] ?? 'Réouverture impossible');
  }

  /// URL du proxy fichier chat (PDF, etc.) ; ajouter `&download=1` pour forcer le téléchargement.
  static String attachmentProxyUrl({
    required String messageId,
    required String conversationId,
  }) {
    final base =
        _baseUrl.endsWith('/') ? _baseUrl.substring(0, _baseUrl.length - 1) : _baseUrl;
    return '$base/messages/${Uri.encodeComponent(messageId)}/file?conversationId=${Uri.encodeComponent(conversationId)}';
  }

  /// Message générique médecin (`POST /messages`).
  static Future<Map<String, dynamic>> sendDoctorMessage({
    required String conversationId,
    required String doctorId,
    required String type,
    required String content,
    Map<String, dynamic>? payload,
  }) async {
    final uri = Uri.parse('$_baseUrl/messages');
    final body = <String, dynamic>{
      'conversationId': conversationId,
      'fromType': 'doctor',
      'from': doctorId,
      'type': type,
      'content': content,
    };
    if (payload != null && payload.isNotEmpty) body['payload'] = payload;
    final response = await http.post(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode(body),
    );
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(data['message'] ?? 'Envoi impossible');
  }

  static Future<Map<String, dynamic>> postDoctorTextMessage({
    required String conversationId,
    required String doctorId,
    required String content,
  }) async {
    return sendDoctorMessage(
      conversationId: conversationId,
      doctorId: doctorId,
      type: 'text',
      content: content,
    );
  }

  /// Message générique (`POST /messages`) — ex. `fromType: system` pour journaux d’appel.
  /// Dernière ordonnance envoyée dans la conversation (404 si aucune).
  static Future<Map<String, dynamic>> getLatestPrescription({
    required String conversationId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/api/conversations/${Uri.encodeComponent(conversationId)}/prescriptions/latest',
    );
    final response = await http.get(uri, headers: _jsonHeadersWithAuth());
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(
      _extractErrorMessage(response, fallback: 'Aucune ordonnance'),
    );
  }

  /// Liste des ordonnances d'une conversation, filtrable par plage date/heure ISO.
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
      _extractErrorMessage(response, fallback: 'Chargement des ordonnances impossible'),
    );
  }

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
      final total = _readIntPH(data['total']) ?? list.length;
      final pageOut = _readIntPH(data['page']) ?? page;
      final limitOut = _readIntPH(data['limit']) ?? limit;
      return (
        data: list,
        total: total,
        page: pageOut,
        limit: limitOut,
      );
    }
    throw Exception(
      _extractErrorMessage(response, fallback: 'Chargement des ordonnances impossible'),
    );
  }

  static int? _readIntPH(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// Crée le PDF d’ordonnance, enregistre en base et envoie le message dans la conversation.
  static Future<Map<String, dynamic>> createPrescription({
    required String conversationId,
    required String city,
    required List<Map<String, String>> medications,
    String? notes,
    required String source,
    String? consultationCallRoomId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/api/conversations/${Uri.encodeComponent(conversationId)}/prescriptions',
    );
    final body = <String, dynamic>{
      'city': city.trim(),
      'medications': medications,
      'source': source,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (consultationCallRoomId != null &&
          consultationCallRoomId.trim().isNotEmpty)
        'consultationCallRoomId': consultationCallRoomId.trim(),
    };
    final response = await http.post(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode(body),
    );
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(
      _extractErrorMessage(response, fallback: 'Création ordonnance impossible'),
    );
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
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    final data = _decodeBody(response.body);
    throw Exception(data['message'] ?? 'Envoi impossible');
  }

  /// Pièce jointe chat (`POST /teleconsultations/upload`).
  static Future<void> uploadChatAttachment({
    required String conversationId,
    required String senderId,
    required PlatformFile file,
  }) async {
    final uri = Uri.parse('$_baseUrl/teleconsultations/upload');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_jsonHeadersWithAuth());
    request.fields['conversationId'] = conversationId;
    request.fields['fromType'] = 'doctor';
    request.fields['senderId'] = senderId;
    if (kIsWeb && file.bytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name),
      );
    } else if (!kIsWeb && file.path != null) {
      request.files.add(
        await http.MultipartFile.fromPath('file', file.path!, filename: file.name),
      );
    } else if (file.bytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name),
      );
    } else {
      throw Exception('Fichier illisible (chemin ou octets manquants).');
    }
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw Exception(data['message'] ?? 'Envoi du fichier impossible');
  }

  static Future<Map<String, dynamic>> getDoctorSettings(String doctorId) async {
    final uri = Uri.parse(
        '$_baseUrl/doctor/${Uri.encodeComponent(doctorId)}/settings');
    final response = await http.get(uri, headers: _jsonHeadersWithAuth());
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(data['message'] ?? 'Erreur réglages');
  }

  static Future<Map<String, dynamic>> patchDoctorSettings({
    required String doctorId,
    String? workingHoursStart,
    String? workingHoursEnd,
    List<Map<String, String>>? workingTimeSlots,
    List<int>? availableDays,
    String? absenceMessage,
    bool? autoReplyEnabled,
    bool? absenceEmergencyOnly,
  }) async {
    final uri = Uri.parse(
        '$_baseUrl/doctor/${Uri.encodeComponent(doctorId)}/settings');
    final body = <String, dynamic>{};
    if (workingHoursStart != null) body['workingHoursStart'] = workingHoursStart;
    if (workingHoursEnd != null) body['workingHoursEnd'] = workingHoursEnd;
    if (workingTimeSlots != null) body['workingTimeSlots'] = workingTimeSlots;
    if (availableDays != null) body['availableDays'] = availableDays;
    if (absenceMessage != null) body['absenceMessage'] = absenceMessage;
    if (autoReplyEnabled != null) body['autoReplyEnabled'] = autoReplyEnabled;
    if (absenceEmergencyOnly != null) {
      body['absenceEmergencyOnly'] = absenceEmergencyOnly;
    }

    final response = await http.patch(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode(body),
    );
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(data['message'] ?? 'Erreur sauvegarde');
  }

  static Future<Map<String, dynamic>> updateDoctorSettings({
    required String doctorId,
    String? workingHoursStart,
    String? workingHoursEnd,
    List<Map<String, String>>? workingTimeSlots,
    List<int>? availableDays,
    String? absenceMessage,
    bool? autoReplyEnabled,
    bool? absenceEmergencyOnly,
  }) {
    return patchDoctorSettings(
      doctorId: doctorId,
      workingHoursStart: workingHoursStart,
      workingHoursEnd: workingHoursEnd,
      workingTimeSlots: workingTimeSlots,
      availableDays: availableDays,
      absenceMessage: absenceMessage,
      autoReplyEnabled: autoReplyEnabled,
      absenceEmergencyOnly: absenceEmergencyOnly,
    );
  }

  static Future<Map<String, dynamic>> changeDoctorPassword({
    required String doctorId,
    required String oldPassword,
    required String newPassword,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/doctor/${Uri.encodeComponent(doctorId)}/change-password',
    );
    final response = await http.post(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode({
        'oldPassword': oldPassword,
        'newPassword': newPassword,
      }),
    );
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(data['message'] ?? 'Erreur lors du changement de mot de passe.');
  }

  static Future<Map<String, dynamic>> patchDoctorStatus({
    required String doctorId,
    required String status,
  }) async {
    final uri = Uri.parse(
        '$_baseUrl/doctor/${Uri.encodeComponent(doctorId)}/status');
    final response = await http.patch(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode({'status': status}),
    );
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(data['message'] ?? 'Erreur statut');
  }

  static Future<Map<String, dynamic>> updateDoctorStatus({
    required String doctorId,
    required String status,
  }) {
    return patchDoctorStatus(doctorId: doctorId, status: status);
  }

  /// Statistiques téléconsultation (demandes / formulaires par statut).
  static Future<Map<String, dynamic>> getDoctorTeleconsultStats(
      String doctorId) async {
    final uri = Uri.parse(
        '$_baseUrl/doctor/${Uri.encodeComponent(doctorId)}/teleconsult-stats');
    final response = await http.get(uri, headers: _jsonHeadersWithAuth());
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(data['message'] ?? 'Erreur statistiques téléconsultation');
  }

  static Future<List<Map<String, dynamic>>> getDoctorTeleconsultRequests(
      String doctorId) async {
    final uri = Uri.parse(
        '$_baseUrl/doctor/${Uri.encodeComponent(doctorId)}/teleconsult-requests');
    final response = await http.get(uri, headers: _jsonHeadersWithAuth());
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = data['items'];
      if (list is List) {
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    }
    throw Exception(data['message'] ?? 'Erreur demandes');
  }

  static Future<Map<String, dynamic>> getTeleconsultRequestForDoctor({
    required String requestId,
    required String doctorId,
  }) async {
    final uri = Uri.parse(
            '$_baseUrl/teleconsultations/request/${Uri.encodeComponent(requestId)}/for-doctor')
        .replace(queryParameters: {'doctorId': doctorId});
    final response = await http.get(uri, headers: _jsonHeadersWithAuth());
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(data['message'] ?? 'Demande introuvable');
  }

  /// PUT `/demandes/:id/accepter` ou `/demandes/:id/refuser` (voir `teleconsultationRoutes.js`).
  /// Ne pas préfixer par `/api` : les routes modulaires sont montées à la racine du serveur.
  static Future<Map<String, dynamic>> decideTeleconsultRequest({
    required String requestId,
    required String doctorId,
    required bool accept,
    String? rejectionMotif,
  }) async {
    if (accept) {
      final uri = Uri.parse(
        '$_baseUrl/demandes/${Uri.encodeComponent(requestId)}/accepter',
      );
      final response = await http.put(
        uri,
        headers: _jsonHeadersWithAuth(),
        body: jsonEncode({'doctorId': doctorId}),
      );
      final data = _decodeBody(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return data;
      }
      throw Exception(data['message'] ?? 'Action impossible');
    }
    final uri = Uri.parse(
      '$_baseUrl/demandes/${Uri.encodeComponent(requestId)}/refuser',
    );
    final body = <String, dynamic>{'doctorId': doctorId};
    final m = rejectionMotif?.trim();
    if (m != null && m.isNotEmpty) {
      body['motif'] = m;
    }
    final response = await http.put(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode(body),
    );
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(data['message'] ?? 'Action impossible');
  }

  static Future<List<Map<String, dynamic>>> getDoctorTeleconsultForms(
      String doctorId) async {
    final uri = Uri.parse(
        '$_baseUrl/doctor/${Uri.encodeComponent(doctorId)}/teleconsult-forms');
    final response = await http.get(uri, headers: _jsonHeadersWithAuth());
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = data['items'];
      if (list is List) {
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    }
    throw Exception(data['message'] ?? 'Erreur formulaires');
  }

  static Future<Map<String, dynamic>> getTeleconsultFormForDoctor({
    required String formId,
    required String doctorId,
  }) async {
    final uri = Uri.parse(
            '$_baseUrl/teleconsultations/form/${Uri.encodeComponent(formId)}/for-doctor')
        .replace(queryParameters: {'doctorId': doctorId});
    final response = await http.get(uri, headers: _jsonHeadersWithAuth());
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(data['message'] ?? 'Formulaire introuvable');
  }

  static Future<Map<String, dynamic>> patchTeleconsultFormWorkflow({
    required String formId,
    required String doctorId,
    required String status,
  }) async {
    final uri = Uri.parse(
        '$_baseUrl/teleconsultations/form/${Uri.encodeComponent(formId)}/workflow');
    final response = await http.patch(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode({'doctorId': doctorId, 'status': status}),
    );
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(data['message'] ?? 'Mise à jour impossible');
  }

  static Future<Map<String, dynamic>> decideTeleconsultForm({
    required String formId,
    required String doctorId,
    required bool accept,
  }) async {
    final uri = Uri.parse(
        '$_baseUrl/teleconsultations/form/${Uri.encodeComponent(formId)}/decision');
    final response = await http.patch(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode({
        'doctorId': doctorId,
        'decision': accept ? 'accept' : 'reject',
      }),
    );
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(data['message'] ?? 'Action impossible');
  }

  /// Créneau téléconsultation (message `teleconsult_scheduled`).
  static Future<Map<String, dynamic>> postDoctorTeleconsultScheduled({
    required String conversationId,
    required String doctorId,
    required DateTime scheduledAtUtc,
    String content = 'Téléconsultation planifiée.',
  }) async {
    final uri = Uri.parse('$_baseUrl/messages');
    final response = await http.post(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode({
        'conversationId': conversationId,
        'fromType': 'doctor',
        'from': doctorId,
        'type': 'teleconsult_scheduled',
        'content': content,
        'payload': {
          'scheduledAt': scheduledAtUtc.toUtc().toIso8601String(),
        },
      }),
    );
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    throw Exception(
      data['message']?.toString() ?? 'Planification impossible',
    );
  }

  /// Agenda RDV API (`GET /api/rendezvous`).
  static Future<Map<String, dynamic>> getRendezVousMonth({
    required String medecinId,
    required String moisYYYYMM,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/rendezvous').replace(
      queryParameters: {
        'medecinId': medecinId,
        'mois': moisYYYYMM,
      },
    );
    final response = await http.get(uri, headers: _jsonHeadersWithAuth());
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return Map<String, dynamic>.from(data as Map);
    }
    throw Exception(data['message']?.toString() ?? 'Erreur agenda');
  }

  static Future<Map<String, dynamic>> getRendezVousForDate({
    required String medecinId,
    required String dateYYYYMMDD,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/api/rendezvous/date/${Uri.encodeComponent(dateYYYYMMDD)}',
    ).replace(queryParameters: {'medecinId': medecinId});
    final response = await http.get(uri, headers: _jsonHeadersWithAuth());
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return Map<String, dynamic>.from(data as Map);
    }
    throw Exception(data['message']?.toString() ?? 'Erreur agenda');
  }

  static Future<Map<String, dynamic>> postRendezVous({
    required String medecinId,
    required String patientId,
    String? formulaireId,
    required String dateYYYYMMDD,
    required String heureHHmm,
    required String startAtIsoUtc,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/rendezvous');
    final body = <String, dynamic>{
      'medecinId': medecinId,
      'patientId': patientId,
      'date': dateYYYYMMDD,
      'heure': heureHHmm,
      'startAt': startAtIsoUtc,
      'type': 'teleconsultation',
    };
    if (formulaireId != null && formulaireId.isNotEmpty) {
      body['formulaireId'] = formulaireId;
    }
    final response = await http.post(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode(body),
    );
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return Map<String, dynamic>.from(data as Map);
    }
    if (response.statusCode == 409) {
      throw RendezVousConflictException(
        Map<String, dynamic>.from(data as Map),
      );
    }
    throw Exception(data['message']?.toString() ?? 'Création impossible');
  }

  static Future<Map<String, dynamic>> putRendezVous({
    required String rendezvousId,
    required String medecinId,
    required String dateYYYYMMDD,
    required String heureHHmm,
    required String startAtIsoUtc,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/api/rendezvous/${Uri.encodeComponent(rendezvousId)}',
    );
    final response = await http.put(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode({
        'medecinId': medecinId,
        'date': dateYYYYMMDD,
        'heure': heureHHmm,
        'startAt': startAtIsoUtc,
      }),
    );
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return Map<String, dynamic>.from(data as Map);
    }
    if (response.statusCode == 409) {
      throw RendezVousConflictException(
        Map<String, dynamic>.from(data as Map),
      );
    }
    throw Exception(data['message']?.toString() ?? 'Modification impossible');
  }

  static Future<void> deleteRendezVous({
    required String rendezvousId,
    required String medecinId,
    String motif = '',
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/api/rendezvous/${Uri.encodeComponent(rendezvousId)}',
    );
    final response = await http.delete(
      uri,
      headers: _jsonHeadersWithAuth(),
      body: jsonEncode({'medecinId': medecinId, 'motif': motif}),
    );
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw Exception(data['message']?.toString() ?? 'Annulation impossible');
  }

  static Future<List<Map<String, dynamic>>> getDoctorTensiometerPatients({
    required String doctorId,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/doctor/blood-pressure/patients')
        .replace(queryParameters: {'doctorId': doctorId});
    final response = await http.get(uri, headers: _jsonHeadersWithAuth());
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = (data['patients'] as List?) ?? const [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    throw Exception(data['message']?.toString() ?? 'Erreur patients tensiomètre');
  }

  static Future<List<Map<String, dynamic>>> getDoctorBloodPressureMeasurements({
    required String doctorId,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/doctor/blood-pressure/measurements')
        .replace(queryParameters: {'doctorId': doctorId});
    final response = await http.get(uri, headers: _jsonHeadersWithAuth());
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = (data['measurements'] as List?) ?? const [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    throw Exception(data['message']?.toString() ?? 'Erreur mesures tensiomètre');
  }

  static Future<List<Map<String, dynamic>>> getDoctorBloodPressureAlerts({
    required String doctorId,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/doctor/blood-pressure/alerts')
        .replace(queryParameters: {'doctorId': doctorId});
    final response = await http.get(uri, headers: _jsonHeadersWithAuth());
    final data = _decodeBody(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final list = (data['alerts'] as List?) ?? const [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    throw Exception(data['message']?.toString() ?? 'Erreur alertes tensiomètre');
  }
}

class RendezVousConflictException implements Exception {
  RendezVousConflictException(this.payload);
  final Map<String, dynamic> payload;

  String? get patientNom =>
      (payload['conflictWith'] as Map?)?['patientNom']?.toString();
  String? get date =>
      (payload['conflictWith'] as Map?)?['date']?.toString();
  String? get heure =>
      (payload['conflictWith'] as Map?)?['heure']?.toString();

  @override
  String toString() =>
      payload['message']?.toString() ?? 'Créneau déjà réservé';
}
