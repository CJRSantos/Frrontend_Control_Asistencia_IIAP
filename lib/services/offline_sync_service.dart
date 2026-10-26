import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/attendance_model.dart';
import '../models/qr_model.dart';
import 'storage_service.dart';
import 'attendance_service.dart';
import 'connectivity_service.dart';
import 'api_client.dart';

class OfflineAttendanceRecord {
  final String id;
  final String userId;
  final String? userName;
  final String? userDocument;
  final String qrCode;
  final double? latitude;
  final double? longitude;
  final String? deviceId;
  final DateTime scannedAt;
  final String? type;
  final String? shift;
  int retryCount;
  String? lastError;

  OfflineAttendanceRecord({
    required this.id,
    required this.userId,
    this.userName,
    this.userDocument,
    required this.qrCode,
    this.latitude,
    this.longitude,
    this.deviceId,
    required this.scannedAt,
    this.type,
    this.shift,
    this.retryCount = 0,
    this.lastError,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'user_name': userName,
    'user_document': userDocument,
    'qr_code': qrCode,
    'latitude': latitude,
    'longitude': longitude,
    'device_id': deviceId,
    'scanned_at': scannedAt.toIso8601String(),
    'type': type,
    'shift': shift,
    'retry_count': retryCount,
    'last_error': lastError,
  };

  factory OfflineAttendanceRecord.fromJson(Map<String, dynamic> json) => OfflineAttendanceRecord(
    id: json['id']?.toString() ?? '',
    userId: json['user_id']?.toString() ?? '',
    userName: json['user_name']?.toString(),
    userDocument: json['user_document']?.toString(),
    qrCode: json['qr_code']?.toString() ?? '',
    latitude: json['latitude'] != null ? double.tryParse(json['latitude'].toString()) : null,
    longitude: json['longitude'] != null ? double.tryParse(json['longitude'].toString()) : null,
    deviceId: json['device_id']?.toString(),
    scannedAt: DateTime.tryParse(json['scanned_at']?.toString() ?? '') ?? DateTime.now(),
    type: json['type']?.toString(),
    shift: json['shift']?.toString(),
    retryCount: (json['retry_count'] as num?)?.toInt() ?? 0,
    lastError: json['last_error']?.toString(),
  );
}

class SyncSummary {
  final int total;
  final int successCount;
  final int failedCount;
  final String message;

  SyncSummary({
    required this.total,
    required this.successCount,
    required this.failedCount,
    required this.message,
  });
}

class OfflineSyncService {
  static const String _keyOfflineQueue = 'offline_attendance_queue_v2';
  static SharedPreferences? _prefs;

  static final ValueNotifier<int> pendingCountNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<bool> isSyncingNotifier = ValueNotifier<bool>(false);
  static final ValueNotifier<DateTime?> lastSyncTimeNotifier = ValueNotifier<DateTime?>(null);

  static List<OfflineAttendanceRecord> _pendingQueue = [];
  static List<OfflineAttendanceRecord> get pendingRecords => List.unmodifiable(_pendingQueue);

  /// Inicializa la cola desde disco y escucha el cambio de red para auto-sincronizar
  static Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadQueueFromDisk();

      // Escuchar reconexión a Internet
      ConnectivityService.isOnlineNotifier.addListener(() {
        if (ConnectivityService.isOnline && _pendingQueue.isNotEmpty && !isSyncingNotifier.value) {
          debugPrint('[OfflineSync] Conexión detectada. Auto-sincronizando ${_pendingQueue.length} registros...');
          syncPendingRecords(silent: true);
        }
      });
    } catch (e) {
      debugPrint('[OfflineSync] Error init: $e');
    }
  }

  static Future<void> _loadQueueFromDisk() async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      final raw = prefs.getString(_keyOfflineQueue);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        _pendingQueue = list
            .whereType<Map<String, dynamic>>()
            .map((e) => OfflineAttendanceRecord.fromJson(e))
            .toList();
      } else {
        _pendingQueue = [];
      }
      pendingCountNotifier.value = _pendingQueue.length;
    } catch (e) {
      debugPrint('[OfflineSync] Error cargando cola: $e');
      _pendingQueue = [];
      pendingCountNotifier.value = 0;
    }
  }

  static Future<void> _persistQueue() async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      final jsonList = _pendingQueue.map((e) => e.toJson()).toList();
      await prefs.setString(_keyOfflineQueue, jsonEncode(jsonList));
      pendingCountNotifier.value = _pendingQueue.length;
    } catch (e) {
      debugPrint('[OfflineSync] Error guardando cola en disco: $e');
    }
  }

  /// Guarda una marcación cuando no hay señal o cuando falla la llamada de red
  static Future<AttendanceScanResult> saveOfflineAttendance({
    required String qrCode,
    double? latitude,
    double? longitude,
    String? deviceId,
    AttendanceType? type,
    AttendanceShift? shift,
  }) async {
    final now = DateTime.now();
    final user = StorageService.currentUser;

    final record = OfflineAttendanceRecord(
      id: 'offline_${now.millisecondsSinceEpoch}_${user?.id ?? "u"}',
      userId: user?.id ?? '',
      userName: user?.fullName,
      userDocument: user?.documentNumber,
      qrCode: qrCode.trim(),
      latitude: latitude,
      longitude: longitude,
      deviceId: deviceId,
      scannedAt: now,
      type: type?.name,
      shift: shift?.name,
    );

    _pendingQueue.add(record);
    await _persistQueue();

    // Formatear hora local amigable
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');
    final ampm = now.hour >= 12 ? 'p. m.' : 'a. m.';
    final timeStr = '${hour.toString().padLeft(2, '0')}:$minute:$second $ampm';

    final dateStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    debugPrint('[OfflineSync] Marcaje guardado offline con éxito: ${record.id}');

    return AttendanceScanResult(
      success: true,
      message: '¡Marcaje guardado en tu teléfono (Modo Offline)!\nSe enviará automáticamente cuando recuperes la conexión a Internet.',
      typeLabel: 'REGISTRO SIN CONEXIÓN',
      formattedTime: timeStr,
      formattedDate: dateStr,
      markedByName: user?.fullName ?? 'Registro Local',
    );
  }

  /// Sincroniza todos los marcajes encolados con el servidor backend
  static Future<SyncSummary> syncPendingRecords({bool silent = false}) async {
    if (isSyncingNotifier.value) {
      return SyncSummary(
        total: _pendingQueue.length,
        successCount: 0,
        failedCount: 0,
        message: 'Ya hay una sincronización en curso.',
      );
    }

    if (_pendingQueue.isEmpty) {
      return SyncSummary(
        total: 0,
        successCount: 0,
        failedCount: 0,
        message: 'No hay marcajes pendientes por sincronizar.',
      );
    }

    if (!ConnectivityService.isOnline) {
      return SyncSummary(
        total: _pendingQueue.length,
        successCount: 0,
        failedCount: _pendingQueue.length,
        message: 'Sin conexión a Internet en este momento.',
      );
    }

    isSyncingNotifier.value = true;
    int success = 0;
    int failed = 0;
    final List<OfflineAttendanceRecord> remaining = [];

    try {
      for (final item in _pendingQueue) {
        try {
          await AttendanceService.scanAttendanceQr(
            qrCode: item.qrCode,
            latitude: item.latitude,
            longitude: item.longitude,
            deviceId: item.deviceId,
            type: item.type != null ? AttendanceType.fromString(item.type) : null,
            shift: item.shift != null ? AttendanceShift.fromString(item.shift) : null,
          );
          success++;
          debugPrint('[OfflineSync] Marcaje ${item.id} sincronizado OK con el servidor.');
        } on ApiException catch (apiErr) {
          final errLower = apiErr.message.toLowerCase();
          // Si el servidor indica que ya fue registrado o duplicado en este turno, darlo por completado
          if (errLower.contains('ya registraste') ||
              errLower.contains('ya existe') ||
              errLower.contains('duplicado') ||
              apiErr.statusCode == 409) {
            success++;
            debugPrint('[OfflineSync] Marcaje ${item.id} ya existía en el servidor, removiendo de cola.');
          } else if (apiErr.statusCode >= 400 && apiErr.statusCode < 500) {
            // Error de negocio irrecuperable (ej: QR no válido expirado)
            failed++;
            item.lastError = apiErr.message;
            item.retryCount++;
            if (item.retryCount >= 3) {
              // Descartar tras 3 intentos de error irrecuperable
              debugPrint('[OfflineSync] Marcaje ${item.id} descartado por error persistente: ${apiErr.message}');
            } else {
              remaining.add(item);
            }
          } else {
            // Error de red / servidor 500
            failed++;
            item.retryCount++;
            item.lastError = apiErr.message;
            remaining.add(item);
            break; // Detener lote si el servidor está caído
          }
        } catch (e) {
          failed++;
          item.retryCount++;
          item.lastError = e.toString();
          remaining.add(item);
          break; // Detener lote si se cortó la red
        }
      }

      _pendingQueue = remaining;
      await _persistQueue();
      lastSyncTimeNotifier.value = DateTime.now();

      // Refrescar datos en segundo plano
      if (success > 0) {
        unawaited(AttendanceService.getTodayRecords());
        unawaited(AttendanceService.getMyRecords());
      }
    } finally {
      isSyncingNotifier.value = false;
    }

    final summary = SyncSummary(
      total: success + failed,
      successCount: success,
      failedCount: failed,
      message: success > 0
          ? '¡$success marcaje(s) sincronizado(s) exitosamente!'
          : 'No se pudieron sincronizar los marcajes. Se reintentará automáticamente.',
    );

    return summary;
  }

  /// Verifica si una excepción corresponde a un fallo de red o conectividad
  static bool isNetworkError(dynamic error) {
    if (!ConnectivityService.isOnline) return true;
    if (error is SocketException) return true;
    if (error is TimeoutException) return true;
    if (error is http.ClientException) return true;
    if (error is ApiException) {
      final msg = error.message.toLowerCase();
      return msg.contains('no se pudo conectar') ||
          msg.contains('conexión') ||
          msg.contains('servidor backend') ||
          msg.contains('timeout') ||
          error.statusCode == 502 ||
          error.statusCode == 503 ||
          error.statusCode == 504;
    }
    final str = error.toString().toLowerCase();
    return str.contains('socketexception') ||
        str.contains('timeoutexception') ||
        str.contains('failed host lookup') ||
        str.contains('network is unreachable');
  }
}
