import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../../utils/responsive.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/attendance_service.dart';
import '../../services/auth_service.dart';
import '../../services/api_client.dart';
import '../../services/storage_service.dart';
import '../../services/notification_service.dart';
import '../../services/event_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/offline_sync_service.dart';
import '../../models/qr_model.dart';
import '../../models/event_model.dart';
import '../../widgets/app_button.dart';

enum ScanTarget {
  attendance,
  supervisorPromotion,
  eventAttendance,
  roleAssignment,
}

class QrScannerScreen extends StatefulWidget {
  final ScanTarget target;
  final String? eventId;

  const QrScannerScreen({
    super.key,
    this.target = ScanTarget.attendance,
    this.eventId,
  });

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  MobileScannerController? _scannerController;
  final TextEditingController _windowsInputCtrl = TextEditingController();

  bool _isProcessing = false;
  bool _torchEnabled = false;

  @override
  void initState() {
    super.initState();
    if (!Platform.isWindows) {
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
    }
  }

  @override
  void dispose() {
    _windowsInputCtrl.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> _handleBarcodeDetected(String rawCode) async {
    if (_isProcessing) return;
    final cleanCode = rawCode.trim();
    if (cleanCode.isEmpty) return;

    _isProcessing = true;
    try {
      await _scannerController?.stop();
    } catch (_) {}
    if (mounted) setState(() {});

    try {
      // 0. Si es un código de Constancia de Asistencia / Certificado Digital emitido por el IIAP
      if (cleanCode.contains('CONSTANCIA DE ASISTENCIA') ||
          cleanCode.contains('cert=') ||
          cleanCode.startsWith('IIAP_CERT:') ||
          cleanCode.contains('IIAP-CERT-')) {
        await _showCertificateValidationDialog(cleanCode);
        if (mounted) {
          try {
            await _scannerController?.start();
          } catch (_) {}
          setState(() => _isProcessing = false);
        }
        return;
      }

      // 1. Si el target es evento o el código es de un evento institucional IIAP (formato código, URL pública oficial o enlace web de registro)
      final uri = Uri.tryParse(cleanCode);
      final hasEventIdParam = uri != null &&
          (uri.queryParameters.containsKey('id') || uri.queryParameters.containsKey('event_id'));

      final looksLikeUuid = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(cleanCode);

      final isEventPattern = cleanCode.startsWith('IIAP-EVT-') ||
          cleanCode.startsWith('IIAP-EVENT-') ||
          cleanCode.toUpperCase().startsWith('EVENTOS-') ||
          cleanCode.startsWith('event_') ||
          cleanCode.startsWith('evt_') ||
          cleanCode.contains('registro.html') ||
          cleanCode.contains('/registro') ||
          cleanCode.toLowerCase().contains('event') ||
          cleanCode.toLowerCase().contains('evento') ||
          (hasEventIdParam &&
              (cleanCode.contains('iiap') ||
                  cleanCode.contains('gob.pe') ||
                  cleanCode.contains('localhost') ||
                  cleanCode.contains('192.168')));

      final matchesKnownEvent = EventService.eventsNotifier.value.any(
        (e) =>
            e.id == cleanCode ||
            e.qrCode == cleanCode ||
            e.externalId == cleanCode ||
            (cleanCode.contains(e.id) &&
                !cleanCode.startsWith('IIAP-ASSIGN-') &&
                !cleanCode.startsWith('IIAP-SHA-')),
      );

      final isEventCode = widget.target == ScanTarget.eventAttendance ||
          isEventPattern ||
          matchesKnownEvent ||
          cleanCode.toUpperCase().startsWith('EVENTOS-') ||
          (widget.target != ScanTarget.roleAssignment &&
              widget.target != ScanTarget.supervisorPromotion &&
              looksLikeUuid);

      if (isEventCode) {
        String? targetEventId = widget.eventId;
        if (targetEventId == null) {
          if (cleanCode.startsWith('IIAP-EVT-') || cleanCode.startsWith('IIAP-EVENT-')) {
            final prefix = cleanCode.startsWith('IIAP-EVT-') ? 'IIAP-EVT-' : 'IIAP-EVENT-';
            final withoutPrefix = cleanCode.substring(prefix.length);
            final withoutQuery = withoutPrefix.split('?').first;

            // 1. Buscar en la lista de eventos en memoria
            final events = EventService.eventsNotifier.value;
            for (final ev in events) {
              if (ev.id == withoutQuery ||
                  withoutQuery.startsWith(ev.id) ||
                  ev.id.startsWith(withoutQuery) ||
                  (ev.qrCode != null && (ev.qrCode == cleanCode || cleanCode.contains(ev.qrCode!)))) {
                targetEventId = ev.id;
                break;
              }
            }
            // 2. Si tiene sufijo (ej: evt_123_456-1728399), extraer el ID real del evento
            if (targetEventId == null) {
              final match = RegExp(r'^(evt_\d+_\d+)').firstMatch(withoutQuery);
              targetEventId = match != null ? match.group(1) : withoutQuery;
            }
          } else if (cleanCode.toUpperCase().startsWith('EVENTOS-')) {
            final events = EventService.eventsNotifier.value;
            for (final ev in events) {
              if (ev.qrCode == cleanCode ||
                  ev.externalId == cleanCode ||
                  ev.id == cleanCode ||
                  (ev.qrCode != null && ev.qrCode!.toUpperCase() == cleanCode.toUpperCase())) {
                targetEventId = ev.id;
                break;
              }
            }
            targetEventId ??= cleanCode;
          } else if (hasEventIdParam && uri != null) {
            targetEventId = uri.queryParameters['id'] ??
                uri.queryParameters['event_id'] ??
                uri.queryParameters['evento'];
          } else if (cleanCode.startsWith('event_')) {
            targetEventId = cleanCode.substring('event_'.length).split('?').first;
          } else if (cleanCode.startsWith('evt_')) {
            targetEventId = cleanCode.split('?').first;
          } else if (looksLikeUuid) {
            targetEventId = cleanCode;
          } else {
            final events = EventService.eventsNotifier.value;
            for (final ev in events) {
              if (ev.id == cleanCode ||
                  ev.qrCode == cleanCode ||
                  ev.externalId == cleanCode ||
                  (ev.qrCode != null && cleanCode.contains(ev.qrCode!))) {
                targetEventId = ev.id;
                break;
              }
            }
            targetEventId ??= cleanCode.split('?').first;
          }
        }

        // Si todavía no lo encontramos en memoria, sincronizamos con backend
        if (targetEventId == null || !EventService.eventsNotifier.value.any((e) => e.id == targetEventId)) {
          if (ConnectivityService.isOnline) {
            try {
              await EventService.getEvents(forceRefresh: true);
            } catch (_) {}
          }
          final events = EventService.eventsNotifier.value;
          for (final ev in events) {
            if (ev.qrCode == cleanCode ||
                cleanCode.contains(ev.id) ||
                (ev.qrCode != null && cleanCode.contains(ev.qrCode!)) ||
                (targetEventId != null &&
                    (ev.id == targetEventId ||
                        ev.id.contains(targetEventId) ||
                        ev.externalId == targetEventId ||
                        ev.qrCode == targetEventId))) {
              targetEventId = ev.id;
              break;
            }
          }

          // Si aún no está en la lista en memoria, consultar directamente el endpoint por ID o QR
          if (ConnectivityService.isOnline && (targetEventId == null || !EventService.eventsNotifier.value.any((e) => e.id == targetEventId))) {
            if (targetEventId != null && targetEventId.isNotEmpty) {
              try {
                final fetched = await EventService.getEventById(targetEventId);
                if (fetched != null) {
                  targetEventId = fetched.id;
                }
              } catch (_) {}
            }
            if ((targetEventId == null || !EventService.eventsNotifier.value.any((e) => e.id == targetEventId)) && cleanCode != targetEventId) {
              try {
                final fetched = await EventService.getEventById(cleanCode);
                if (fetched != null) {
                  targetEventId = fetched.id;
                }
              } catch (_) {}
            }
          }
        }

        if (targetEventId != null) {
          String? shiftParam;
          if (cleanCode.contains('shift=')) {
            if (uri != null && uri.queryParameters.containsKey('shift')) {
              shiftParam = uri.queryParameters['shift'];
            } else {
              final shiftMatch = RegExp(r'shift=([a-zA-Z0-9_-]+)').firstMatch(cleanCode);
              if (shiftMatch != null) {
                shiftParam = shiftMatch.group(1);
              }
            }
          }

          String? titleParam;
          String? locParam;
          String? uoParam;
          String? typeParam;
          DateTime? startParam;
          DateTime? endParam;

          if (uri != null) {
            if (uri.queryParameters.containsKey('title')) {
              titleParam = Uri.decodeComponent(uri.queryParameters['title']!);
            }
            if (uri.queryParameters.containsKey('loc')) {
              locParam = Uri.decodeComponent(uri.queryParameters['loc']!);
            }
            if (uri.queryParameters.containsKey('uo')) {
              uoParam = Uri.decodeComponent(uri.queryParameters['uo']!);
            }
            if (uri.queryParameters.containsKey('type')) {
              typeParam = uri.queryParameters['type'];
            }
            if (uri.queryParameters.containsKey('start')) {
              final ms = int.tryParse(uri.queryParameters['start']!);
              if (ms != null) startParam = DateTime.fromMillisecondsSinceEpoch(ms);
            }
            if (uri.queryParameters.containsKey('end')) {
              final ms = int.tryParse(uri.queryParameters['end']!);
              if (ms != null) endParam = DateTime.fromMillisecondsSinceEpoch(ms);
            }
          }

          // Fallbacks por expresión regular si Uri.tryParse no los capturó
          if (titleParam == null && cleanCode.contains('title=')) {
            final m = RegExp(r'title=([^&]+)').firstMatch(cleanCode);
            if (m != null) titleParam = Uri.decodeComponent(m.group(1)!);
          }
          if (locParam == null && cleanCode.contains('loc=')) {
            final m = RegExp(r'loc=([^&]+)').firstMatch(cleanCode);
            if (m != null) locParam = Uri.decodeComponent(m.group(1)!);
          }
          if (uoParam == null && cleanCode.contains('uo=')) {
            final m = RegExp(r'uo=([^&]+)').firstMatch(cleanCode);
            if (m != null) uoParam = Uri.decodeComponent(m.group(1)!);
          }
          if (typeParam == null && cleanCode.contains('type=')) {
            final m = RegExp(r'type=([^&]+)').firstMatch(cleanCode);
            if (m != null) typeParam = m.group(1);
          }

          final updatedEvent = await EventService.registerAttendance(
            eventId: targetEventId,
            qrCode: cleanCode,
            shift: shiftParam,
            eventTitle: titleParam,
            eventLocation: locParam,
            organizationalUnit: uoParam,
            eventType: typeParam,
            startDate: startParam,
            endDate: endParam,
          );
          if (!mounted) return;
          await _showSuccessDialog(
            title: '¡Asistencia al Evento Confirmada!',
            message: 'Tu asistencia ha sido registrada exitosamente para el evento institucional:\n"${updatedEvent.title}".',
            detail: 'Participante: ${StorageService.currentUser?.fullName ?? ""}',
            isShaVerified: true,
          );
          if (mounted) Navigator.of(context).pop(true);
          return;
        } else if (widget.target == ScanTarget.eventAttendance || isEventCode) {
          throw ApiException(
            'El código QR escaneado corresponde a un evento institucional, pero no se encontró un evento activo asociado o ya ha concluido.',
          );
        }
      }

      // 1. Asignación de Roles o Gestor de Eventos por QR (IIAP-ASSIGN-)
      if (cleanCode.startsWith('IIAP-ASSIGN-') || widget.target == ScanTarget.roleAssignment) {
        final result = await AttendanceService.scanAssignmentQr(cleanCode);
        await AuthService.getProfile();
        if (!mounted) return;
        final roleName = result['new_role'] ?? result['role'] ?? 'Asignado';
        final eventTitle = result['event_title'];
        String msg = '¡Tu nuevo rol institucional es $roleName!';
        if (eventTitle != null && eventTitle.toString().isNotEmpty) {
          msg += '\nHas sido designado exitosamente como Gestor del evento:\n"$eventTitle".';
        }
        await _showSuccessDialog(
          title: '¡Designación Confirmada!',
          message: msg,
          detail: 'Usuario: ${StorageService.currentUser?.fullName ?? ""}',
          isShaVerified: true,
        );
        if (mounted) Navigator.of(context).pop(true);
        return;
      }

      // 1.1 Si el target es explícitamente supervisorPromotion
      if (widget.target == ScanTarget.supervisorPromotion) {
        final result = await AttendanceService.scanSupervisorQr(cleanCode);
        await AuthService.getProfile();
        if (!mounted) return;

        await _showSupervisorSuccessDialog(result['message']?.toString());
        if (mounted) Navigator.of(context).pop(true);
        return;
      }

      // 2. Modo Asistencia o General: Intentar registrar asistencia con GPS y Dispositivo
      try {
        double? lat;
        double? lng;
        try {
          final serviceEnabled = await Geolocator.isLocationServiceEnabled();
          if (serviceEnabled) {
            var permission = await Geolocator.checkPermission();
            if (permission == LocationPermission.denied) {
              permission = await Geolocator.requestPermission();
            }
            if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
              final pos = await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.high,
                  timeLimit: Duration(seconds: 4),
                ),
              );
              lat = pos.latitude;
              lng = pos.longitude;
            }
          }
        } catch (e) {
          debugPrint('Aviso GPS: $e');
        }

        final deviceId = await StorageService.getOrCreateDeviceId();

        AttendanceScanResult result;
        bool isOffline = false;

        if (!ConnectivityService.isOnline) {
          result = await OfflineSyncService.saveOfflineAttendance(
            qrCode: cleanCode,
            latitude: lat,
            longitude: lng,
            deviceId: deviceId,
          );
          isOffline = true;
        } else {
          try {
            result = await AttendanceService.scanAttendanceQr(
              qrCode: cleanCode,
              latitude: lat,
              longitude: lng,
              deviceId: deviceId,
            );
          } catch (netErr) {
            if (OfflineSyncService.isNetworkError(netErr)) {
              result = await OfflineSyncService.saveOfflineAttendance(
                qrCode: cleanCode,
                latitude: lat,
                longitude: lng,
                deviceId: deviceId,
              );
              isOffline = true;
            } else {
              rethrow;
            }
          }
        }

        NotificationService.checkAndTriggerCheckoutReminder();
        if (!mounted) return;

        final scanNow = DateTime.now();
        final hour = scanNow.hour % 12 == 0 ? 12 : scanNow.hour % 12;
        final minute = scanNow.minute.toString().padLeft(2, '0');
        final second = scanNow.second.toString().padLeft(2, '0');
        final ampm = scanNow.hour >= 12 ? 'p. m.' : 'a. m.';
        final localFormattedTime = '${hour.toString().padLeft(2, '0')}:$minute:$second $ampm';

        await _showSuccessDialog(
          title: isOffline ? '¡Asistencia Guardada (Sin Conexión)!' : '¡Asistencia Registrada!',
          message: result.message,
          detail: 'Marca: ${result.typeLabel ?? "REGISTRO"} • $localFormattedTime',
          isShaVerified: true,
        );
        if (mounted) Navigator.of(context).pop(true);
        return;
      } on ApiException catch (attendanceError) {
        // 3. Detección automática de respaldo: si el código no fue de asistencia diaria, verificar si es de Evento o Supervisor
        if (attendanceError.message.contains('no es válido o ya fue dado de baja')) {
          // 3.1 Probar si coincide con un evento institucional conocido
          try {
            final events = EventService.eventsNotifier.value;
            EventModel? matchedEvt;
            for (final ev in events) {
              if (ev.qrCode == cleanCode ||
                  cleanCode.contains(ev.id) ||
                  (ev.qrCode != null && cleanCode.contains(ev.qrCode!))) {
                matchedEvt = ev;
                break;
              }
            }
            if (matchedEvt != null) {
              final updated = await EventService.registerAttendance(
                eventId: matchedEvt.id,
                qrCode: cleanCode,
              );
              if (!mounted) return;
              await _showSuccessDialog(
                title: '¡Asistencia al Evento Confirmada!',
                message: 'Tu asistencia ha sido registrada exitosamente para el evento institucional:\n"${updated.title}".',
                detail: 'Participante: ${StorageService.currentUser?.fullName ?? ""}',
                isShaVerified: true,
              );
              if (mounted) Navigator.of(context).pop(true);
              return;
            }
          } catch (_) {}

          // 3.2 Probar si es QR de ascenso a Supervisor
          try {
            final supervisorResult = await AttendanceService.scanSupervisorQr(cleanCode);
            await AuthService.getProfile();
            if (!mounted) return;

            await _showSupervisorSuccessDialog(supervisorResult['message']?.toString());
            if (mounted) Navigator.of(context).pop(true);
            return;
          } catch (_) {
            // Si tampoco fue QR de evento ni supervisor, propagamos el error original de asistencia
            throw attendanceError;
          }
        }
        // Para cualquier otro error (GPS, fuera de horario, dispositivo, expirado, etc.), relanzar el error real
        rethrow;
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      await _showErrorDialog(e.message);
      if (mounted) {
        try {
          await _scannerController?.start();
        } catch (_) {}
        setState(() => _isProcessing = false);
      }
    } catch (e) {
      if (!mounted) return;
      await _showErrorDialog('Error al procesar el código: $e');
      if (mounted) {
        try {
          await _scannerController?.start();
        } catch (_) {}
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _showSuccessDialog({
    required String title,
    required String message,
    String? detail,
    bool isShaVerified = false,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        iconPadding: const EdgeInsets.only(top: 16, bottom: 6),
        titlePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        icon: Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: Color(0xFFDCFCE7),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 40),
        ),
        title: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
              if (isShaVerified) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF16A34A).withValues(alpha: 0.4)),
                  ),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_rounded, size: 14, color: Color(0xFF16A34A)),
                        SizedBox(width: 5),
                        Text(
                          'Código Criptográfico SHA-256 Verificado',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF16A34A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (detail != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    detail,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          Center(
            child: AppButton(
              text: 'Aceptar',
              width: 140,
              height: 42,
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCertificateValidationDialog(String rawPayload) async {
    List<String> lines = [];
    if (rawPayload.startsWith('http://') || rawPayload.startsWith('https://')) {
      final uri = Uri.tryParse(rawPayload);
      if (uri != null) {
        final cert = uri.queryParameters['cert'] ?? '';
        final name = uri.queryParameters['name'] ?? '';
        final dni = uri.queryParameters['dni'] ?? '';
        final evt = uri.queryParameters['event'] ?? '';
        final time = uri.queryParameters['time'] ?? '';

        if (name.isNotEmpty) lines.add('Participante: $name');
        if (dni.isNotEmpty) lines.add('Documento: $dni');
        if (evt.isNotEmpty) lines.add('Evento: $evt');
        if (time.isNotEmpty) lines.add('Acreditación: $time');
        if (cert.isNotEmpty) lines.add('Código Validación: $cert');
      }
    }

    if (lines.isEmpty) {
      lines = rawPayload
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('---'))
          .toList();
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: Color(0xFFDCFCE7),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.verified_rounded, color: Color(0xFF16A34A), size: 40),
        ),
        title: const Text('Constancia Oficial IIAP', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF16A34A).withValues(alpha: 0.4)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 16),
                    SizedBox(width: 6),
                    Text(
                      'CERTIFICADO AUTÉNTICO Y VÁLIDO',
                      style: TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ...lines.map((line) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.5),
                    child: Text(
                      line,
                      style: const TextStyle(fontSize: 12.5, height: 1.3),
                    ),
                  )),
            ],
          ),
        ),
        actions: [
          Center(
            child: AppButton(
              text: 'Entendido',
              width: 140,
              height: 42,
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSupervisorSuccessDialog(String? serverMessage) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        iconPadding: const EdgeInsets.only(top: 16, bottom: 6),
        titlePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        icon: Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: Color(0xFFF3E8FF),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.shield_rounded, color: Color(0xFF9333EA), size: 40),
        ),
        title: const Text(
          '¡Ya eres Supervisor!',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                serverMessage ?? '¡Felicitaciones! Has sido designado exitosamente como Supervisor.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF5FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE9D5FF)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.qr_code_2_rounded, color: Color(0xFF9333EA), size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Tu vista se ha actualizado. Ahora podrás Generar Códigos QR de Asistencia y también Escanear para registrar tus marcas personales.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF6B21A8), fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF9333EA),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Aceptar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showErrorDialog(String error) async {
    final isUnauthorized = error.toLowerCase().contains('unauthorized') || error.contains('401');

    if (isUnauthorized) {
      AuthService.trySilentRelogin();
    }

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        icon: Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: Color(0xFFFEE2E2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isUnauthorized ? Icons.sync_problem_rounded : Icons.error_outline_rounded,
            color: const Color(0xFFEF4444),
            size: 40,
          ),
        ),
        title: Text(
          isUnauthorized ? 'Revalidando Asistencia' : 'No se pudo procesar',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        content: Text(
          isUnauthorized
              ? 'Se está sincronizando tu credencial institucional en segundo plano. Por favor vuelve a escanear el código QR.'
              : error,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          Center(
            child: AppButton(
              text: 'Aceptar y Reintentar',
              height: 40,
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ),
        ],
      ),
    );
  }

  void _openManualInputDialog() {
    final textCtrl = TextEditingController();

    final String manualTitle = widget.target == ScanTarget.eventAttendance
        ? 'Ingreso de Código de Evento'
        : (widget.target == ScanTarget.attendance
            ? 'Ingreso de Código QR / Hash'
            : 'Código de Designación');

    final String manualDescription = widget.target == ScanTarget.eventAttendance
        ? 'Ingresa o pega el código QR, URL o ID del evento institucional:'
        : 'Pega el Hash SHA-256 o código emitido por el Administrador / Supervisor:';

    final String manualHint = widget.target == ScanTarget.eventAttendance
        ? 'Pega el código o enlace QR del evento aquí...'
        : 'Pega el código QR o Hash SHA-256 aquí...';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Text(
              manualTitle,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  manualDescription,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: textCtrl,
                  maxLines: 2,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: manualHint,
                    hintStyle: TextStyle(
                      fontSize: 12,
                      color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                    ),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFF16A34A),
                        width: 1.8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  'Cancelar',
                  style: TextStyle(
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  final code = textCtrl.text.trim();
                  if (code.isNotEmpty) {
                    Navigator.of(ctx).pop();
                    _handleBarcodeDetected(code);
                  }
                },
                child: const Text('Validar Marca'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String title;
    final String instructionText;
    switch (widget.target) {
      case ScanTarget.attendance:
        title = 'Escanear QR de Asistencia';
        instructionText = 'Enfoca el código QR emitido por el supervisor o del evento';
        break;
      case ScanTarget.eventAttendance:
        title = 'Escanear QR del Evento';
        instructionText = 'Enfoca el código QR proyectado en el evento';
        break;
      case ScanTarget.supervisorPromotion:
        title = 'Escanear Ascenso a Supervisor';
        instructionText = 'Enfoca el QR otorgado por el Administrador';
        break;
      case ScanTarget.roleAssignment:
        title = 'Escanear Asignación de Rol';
        instructionText = 'Enfoca el QR de designación o rol';
        break;
    }
    final isAttendance = widget.target == ScanTarget.attendance;
    final scanBoxSize = Responsive.isTablet(context) ? 360.0 : 260.0;

    if (Platform.isWindows) {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;

      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.qr_code_scanner_rounded,
                          color: Color(0xFF16A34A),
                          size: 48,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        isAttendance ? 'Registro de Asistencia' : 'Ascenso a Supervisor',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'En Windows puedes registrar tu asistencia pegando el Hash SHA-256 o el enlace/código oficial del evento, o usando una lectora USB de códigos QR.',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _windowsInputCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Pega el código QR, Hash SHA o URL del evento aquí...',
                          hintStyle: const TextStyle(fontSize: 12),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.paste_rounded),
                            tooltip: 'Pegar del portapapeles',
                            onPressed: () async {
                              final data = await Clipboard.getData(Clipboard.kTextPlain);
                              if (data?.text != null && data!.text!.isNotEmpty) {
                                _windowsInputCtrl.text = data.text!.trim();
                              }
                            },
                          ),
                        ),
                        onSubmitted: (val) {
                          if (val.trim().isNotEmpty && !_isProcessing) {
                            _handleBarcodeDetected(val.trim());
                          }
                        },
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: AppButton(
                          text: _isProcessing ? 'Validando...' : 'Registrar Asistencia',
                          isLoading: _isProcessing,
                          onPressed: () {
                            final code = _windowsInputCtrl.text.trim();
                            if (code.isNotEmpty && !_isProcessing) {
                              _handleBarcodeDetected(code);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _torchEnabled ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              color: _torchEnabled ? const Color(0xFFFBBF24) : Colors.white,
            ),
            tooltip: 'Linterna',
            onPressed: () {
              setState(() => _torchEnabled = !_torchEnabled);
              _scannerController?.toggleTorch();
            },
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_alt_outlined),
            tooltip: 'Ingresar Hash Manual',
            onPressed: _openManualInputDialog,
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Vista de la cámara de escaneo
          if (_scannerController != null)
            MobileScanner(
              controller: _scannerController!,
              onDetect: (capture) {
                final barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  final rawValue = barcode.rawValue;
                  if (rawValue != null && rawValue.isNotEmpty) {
                    _handleBarcodeDetected(rawValue);
                    break;
                  }
                }
              },
            ),

          // Máscara y marco de encuadre visual del QR
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.65),
              BlendMode.srcOut,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    backgroundBlendMode: BlendMode.dstOut,
                  ),
                ),
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    height: scanBoxSize,
                    width: scanBoxSize,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Marco con esquinas redondeadas
          Container(
            height: scanBoxSize,
            width: scanBoxSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF22C55E), width: 3),
            ),
          ),

          // Indicador de procesamiento
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.75),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF22C55E)),
                    ),
                    SizedBox(height: 18),
                    Text(
                      'Validando código SHA-256 en el servidor...',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),

          // Instrucciones al pie de pantalla
          Positioned(
            bottom: 40,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF4ADE80), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    instructionText,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}