import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'storage_service.dart';
import '../config/api_config.dart';
import '../models/attendance_model.dart';
import '../models/qr_model.dart';
import 'api_client.dart';

class AttendanceService {
  static final Dio _dio = Dio();
  static QrGeneratedResponse? _lastActiveQr;
  static QrGeneratedResponse? get lastActiveQr => _lastActiveQr;

  // 1. Generar nuevo QR de asistencia (Admin o Supervisor)
  static Future<QrGeneratedResponse> generateAttendanceQr() async {
    final response = await ApiClient.post(ApiConfig.attendanceGenerateQr);
    final qr = QrGeneratedResponse.fromJson(response as Map<String, dynamic>);
    _lastActiveQr = qr;
    return qr;
  }

  // 1.1 Obtener o refrescar el QR de asistencia activo
  static Future<QrGeneratedResponse> getActiveAttendanceQr() async {
    final response = await ApiClient.get(ApiConfig.attendanceActiveQr);
    final qr = QrGeneratedResponse.fromJson(response as Map<String, dynamic>);
    _lastActiveQr = qr;
    return qr;
  }

  // 2. Generar QR para designar Supervisor (Solo ADMIN)
  static Future<QrGeneratedResponse> generateSupervisorQr() async {
    final response = await ApiClient.post(ApiConfig.attendanceGenerateSupervisorQr);
    return QrGeneratedResponse.fromJson(response as Map<String, dynamic>);
  }

  // 2.1 Generar QR para designar roles jerárquicos (ADMIN, ADMIN_EVENTO, GESTOR_EVENTO, etc.)
  static Future<Map<String, dynamic>> generateAssignmentQr({
    required String targetRole,
    String? targetEventId,
  }) async {
    final body = <String, dynamic>{
      'target_role': targetRole,
    };
    if (targetEventId != null && targetEventId.isNotEmpty) {
      body['target_event_id'] = targetEventId;
    }
    final response = await ApiClient.post(
      ApiConfig.attendanceGenerateAssignmentQr,
      body: body,
    );
    return response as Map<String, dynamic>;
  }

  // 2.2 Escanear QR de asignación de rol o gestor de evento
  static Future<Map<String, dynamic>> scanAssignmentQr(String qrCode) async {
    final response = await ApiClient.post(
      ApiConfig.attendanceScanAssignmentQr,
      body: {'qr_code': qrCode.trim()},
    );
    return response as Map<String, dynamic>;
  }

  // 3. Escaneo de QR de Asistencia para registrar Entrada o Salida
  static Future<AttendanceScanResult> scanAttendanceQr({
    required String qrCode,
    double? latitude,
    double? longitude,
    String? deviceId,
    AttendanceType? type,
    AttendanceShift? shift,
  }) async {
    final body = <String, dynamic>{
      'qr_code': qrCode.trim(),
    };
    if (latitude != null) body['latitude'] = latitude;
    if (longitude != null) body['longitude'] = longitude;
    if (deviceId != null) body['device_id'] = deviceId;
    if (type != null) body['type'] = type.name;
    if (shift != null) body['shift'] = shift.name;

    final response = await ApiClient.post(ApiConfig.attendanceScanQr, body: body);
    return AttendanceScanResult.fromJson(response as Map<String, dynamic>);
  }

  // 4. Escaneo de QR para ascender a Supervisor
  static Future<Map<String, dynamic>> scanSupervisorQr(String qrCode) async {
    final response = await ApiClient.post(
      ApiConfig.attendanceScanSupervisorQr,
      body: {'qr_code': qrCode.trim()},
    );
    return response as Map<String, dynamic>;
  }

  // 4.1 Eliminar un registro puntual de asistencia (Admin, Supervisor, Admin Evento)
  static Future<Map<String, dynamic>> deleteAttendanceRecord(String id) async {
    final response = await ApiClient.delete(ApiConfig.attendanceById(id));
    return response as Map<String, dynamic>;
  }

  static const String _keyCachedToday = 'cached_today_attendance_records_v1';
  static const String _keyCachedMy = 'cached_my_attendance_records_v1';
  static const String _keyCachedAll = 'cached_all_attendance_records_v1';

  static SharedPreferences? _prefs;
  static List<AttendanceModel> _cachedTodayRecords = [];
  static List<AttendanceModel> _cachedMyRecords = [];
  static List<AttendanceModel> _cachedAllRecords = [];

  /// Inicializa los datos cacheados en memoria al arrancar la app para respuesta instantánea (0 ms)
  static Future<void> init() async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;

      final todayStr = prefs.getString(_keyCachedToday);
      if (todayStr != null && todayStr.isNotEmpty) {
        final list = jsonDecode(todayStr) as List;
        _cachedTodayRecords = list
            .whereType<Map<String, dynamic>>()
            .map((e) => AttendanceModel.fromJson(e))
            .toList();
      }

      final myStr = prefs.getString(_keyCachedMy);
      if (myStr != null && myStr.isNotEmpty) {
        final list = jsonDecode(myStr) as List;
        _cachedMyRecords = list
            .whereType<Map<String, dynamic>>()
            .map((e) => AttendanceModel.fromJson(e))
            .toList();
      }

      final allStr = prefs.getString(_keyCachedAll);
      if (allStr != null && allStr.isNotEmpty) {
        final list = jsonDecode(allStr) as List;
        _cachedAllRecords = list
            .whereType<Map<String, dynamic>>()
            .map((e) => AttendanceModel.fromJson(e))
            .toList();
      }
    } catch (e) {
      debugPrint('AttendanceService.init error cargando caché local: $e');
    }
  }

  static List<AttendanceModel> getCachedTodayRecords() => List.unmodifiable(_cachedTodayRecords);
  static List<AttendanceModel> getCachedMyRecords() => List.unmodifiable(_cachedMyRecords);
  static List<AttendanceModel> getCachedAllRecords() => List.unmodifiable(_cachedAllRecords);

  // 5. Historial de asistencias del usuario conectado (Offline-First)
  static Future<List<AttendanceModel>> getMyRecords() async {
    try {
      final response = await ApiClient.get(ApiConfig.attendanceMyRecords);
      if (response is List) {
        final list = response.map((item) => AttendanceModel.fromJson(item as Map<String, dynamic>)).toList();
        final bool changed = list.length != _cachedMyRecords.length ||
            (_cachedMyRecords.isNotEmpty && list.isNotEmpty && _cachedMyRecords.first.id != list.first.id);
        _cachedMyRecords = list;
        if (changed) {
          try {
            final prefs = _prefs ?? await SharedPreferences.getInstance();
            _prefs = prefs;
            await prefs.setString(_keyCachedMy, jsonEncode(list.map((e) => e.toJson()).toList()));
          } catch (_) {}
        }
        return list;
      }
    } catch (e) {
      debugPrint('getMyRecords fallback a caché local offline: $e');
    }
    return _cachedMyRecords;
  }

  // 6. Asistencias de hoy del usuario conectado (Offline-First)
  static Future<List<AttendanceModel>> getTodayRecords() async {
    try {
      final response = await ApiClient.get(ApiConfig.attendanceToday);
      if (response is List) {
        final list = response.map((item) => AttendanceModel.fromJson(item as Map<String, dynamic>)).toList();
        final bool changed = list.length != _cachedTodayRecords.length ||
            (_cachedTodayRecords.isNotEmpty && list.isNotEmpty && _cachedTodayRecords.first.id != list.first.id);
        _cachedTodayRecords = list;
        if (changed) {
          try {
            final prefs = _prefs ?? await SharedPreferences.getInstance();
            _prefs = prefs;
            await prefs.setString(_keyCachedToday, jsonEncode(list.map((e) => e.toJson()).toList()));
          } catch (_) {}
        }
        return list;
      }
    } catch (e) {
      debugPrint('getTodayRecords fallback a caché local offline: $e');
    }
    return _cachedTodayRecords;
  }

  // 7. Todas las asistencias registradas en la institucion (Admin y Supervisores) (Offline-First)
  static Future<List<AttendanceModel>> getAllRecords() async {
    try {
      final response = await ApiClient.get(ApiConfig.attendanceAll);
      if (response is List) {
        final list = response.map((item) => AttendanceModel.fromJson(item as Map<String, dynamic>)).toList();
        final bool changed = list.length != _cachedAllRecords.length ||
            (_cachedAllRecords.isNotEmpty && list.isNotEmpty && _cachedAllRecords.first.id != list.first.id);
        _cachedAllRecords = list;
        if (changed) {
          try {
            final prefs = _prefs ?? await SharedPreferences.getInstance();
            _prefs = prefs;
            await prefs.setString(_keyCachedAll, jsonEncode(list.map((e) => e.toJson()).toList()));
          } catch (_) {}
        }
        return list;
      }
    } catch (e) {
      debugPrint('getAllRecords fallback a caché local offline: $e');
    }
    return _cachedAllRecords;
  }

  // 7.1 Consultar colaboradores con salidas pendientes o no registradas (Admin y Supervisores)
  static Future<List<Map<String, dynamic>>> getPendingCheckouts() async {
    final response = await ApiClient.get(ApiConfig.attendancePendingCheckouts);
    if (response is List) {
      return response.map((item) => item as Map<String, dynamic>).toList();
    }
    return [];
  }

  // 8. Reinicio semanal del historial de asistencias (Solo ADMIN)
  static Future<Map<String, dynamic>> clearWeeklyHistory() async {
    final response = await ApiClient.delete(ApiConfig.attendanceWeeklyReset);
    return response as Map<String, dynamic>;
  }

  /// Registrar asistencia manual de contingencia (Supervisor o Admin)
  static Future<Map<String, dynamic>> registerManualAttendance({
    String? userId,
    String? dni,
    required String type,
    String? shift,
    required String observation,
  }) async {
    final response = await ApiClient.post(
      '${ApiConfig.baseUrl}/attendance/manual-record',
      body: {
        if (userId != null && userId.isNotEmpty) 'user_id': userId,
        if (dni != null && dni.isNotEmpty) 'dni': dni,
        'type': type,
        if (shift != null && shift.isNotEmpty) 'shift': shift,
        'observation': observation,
      },
    );
    return response as Map<String, dynamic>;
  }

  /// Corregir o registrar horarios de entrada y salida de una jornada (Admin o Supervisor)
  static Future<Map<String, dynamic>> correctJourney({
    required String userId,
    required String workDate,
    required AttendanceShift shift,
    String? checkInTime,
    AttendanceStatus? checkInStatus,
    String? checkOutTime,
    String? observation,
  }) async {
    final response = await ApiClient.post(
      ApiConfig.attendanceCorrectJourney,
      body: {
        'user_id': userId,
        'work_date': workDate,
        'shift': shift.name,
        if (checkInTime != null && checkInTime.isNotEmpty) 'check_in_time': checkInTime,
        if (checkInStatus != null) 'check_in_status': checkInStatus.name,
        if (checkOutTime != null && checkOutTime.isNotEmpty) 'check_out_time': checkOutTime,
        if (observation != null && observation.isNotEmpty) 'observation': observation,
      },
    );
    return response as Map<String, dynamic>;
  }

  /// Editar un registro individual de asistencia
  static Future<Map<String, dynamic>> updateRecord(String id, Map<String, dynamic> data) async {
    final response = await ApiClient.patch(
      ApiConfig.attendanceById(id),
      body: data,
    );
    return response as Map<String, dynamic>;
  }

  /// Eliminar un registro de asistencia
  static Future<void> deleteRecord(String id) async {
    await ApiClient.delete(ApiConfig.attendanceById(id));
  }

  /// 9. Escaneo de asistencia mediante camara en tiempo real (OpenCV + InsightFace)
  static Future<Map<String, dynamic>> scanAttendanceWebcam() async {
    final token = await StorageService.getToken();
    final url = Uri.parse(ApiConfig.facialScanWebcam);
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'auth_token': token,
          'camera_index': 0,
        }),
      ).timeout(const Duration(minutes: 5));
      return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      return {
        'success': false,
        'message': 'No se pudo conectar con el servicio facial (${ApiConfig.facialServiceBaseUrl}): $e.\n\n'
            'Verifica que el servicio Python esté activo en la PC y que la red Wi-Fi esté en modo Red Privada en Windows.',
      };
    }
  }

  /// 10. Escaneo de asistencia enviando imagen capturada por la camara
  static Future<Map<String, dynamic>> scanAttendanceImage(String base64Image) async {
    final token = await StorageService.getToken();
    final url = Uri.parse(ApiConfig.facialScanImage);
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'image_base64': base64Image,
          'auth_token': token,
        }),
      ).timeout(const Duration(seconds: 40));
      return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      return {
        'success': false,
        'message': 'No se pudo conectar con el servicio facial (${ApiConfig.facialServiceBaseUrl}): $e.\n\n'
            'Asegúrate de que el servicio Python esté activo en la PC y que el iPad esté conectado a la misma red Wi-Fi.',
      };
    }
  }

  /// 11. Registrar asistencia facial directamente en el Backend (Solo ADMIN)
  static Future<Map<String, dynamic>> recordFacialAttendance({
    required String userIdentifier,
    String? userName,
    double? similarity,
    AttendanceType? type,
    double? latitude,
    double? longitude,
    String? deviceId,
    String? observation,
  }) async {
    final body = <String, dynamic>{
      'user_identifier': userIdentifier,
      if (userName != null) 'user_name': userName,
      if (similarity != null) 'similarity': similarity,
      if (type != null) 'type': type.name,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'device_id': deviceId ?? 'device-camera-scanner',
      if (observation != null) 'observation': observation,
    };

    final response = await ApiClient.post(ApiConfig.attendanceFacialRecord, body: body);
    return response as Map<String, dynamic>;
  }

  /// 12. Procesar frame para reconocimiento facial continuo en backend NestJS
  static Future<Map<String, dynamic>> processFacialRecognition({
    required String base64Image,
    double? latitude,
    double? longitude,
    String? deviceId,
  }) async {
    final body = <String, dynamic>{
      'image_base64': base64Image,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'device_id': deviceId ?? 'flutter-facial-app',
    };

    final response = await ApiClient.post(ApiConfig.attendanceFacialRecognition, body: body);
    return response as Map<String, dynamic>;
  }

  /// 13. Registra asistencia mediante reconocimiento facial (solo admin)
  Future<Map<String, dynamic>> registerFacialAttendance(File imageFile) async {
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(
        imageFile.path,
        filename: 'face.jpg',
      ),
    });

    final token = StorageService.tokenSync ?? await StorageService.getToken();
    final url = ApiConfig.baseUrl.endsWith('/api')
        ? '${ApiConfig.baseUrl}/attendance/facial'
        : '${ApiConfig.baseUrl}/api/attendance/facial';

    final response = await _dio.post(
      url,
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
        headers: token != null && token.isNotEmpty
            ? {'Authorization': 'Bearer $token'}
            : null,
      ),
    );

    return (response.data is Map<String, dynamic>)
        ? response.data as Map<String, dynamic>
        : Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Map<String, dynamic>> registerFacial(File imageFile) =>
      AttendanceService().registerFacialAttendance(imageFile);
}
