// ignore_for_file: constant_identifier_names
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/attendance_model.dart';
import '../services/attendance_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static final AudioPlayer _audioPlayer = AudioPlayer();

  static bool _isInitialized = false;

  static const String _keyNotificationsMuted = 'notifications_muted_v1';
  static final ValueNotifier<bool> isMutedNotifier = ValueNotifier<bool>(false);

  static bool _cachedHapticEnabled = true;
  static bool _cachedHighPriorityDoze = true;
  static String _cachedTone = 'institucional';

  static String getRawSoundResource(String tone) {
    switch (tone) {
      case 'campana_suave':
        return 'sonido2';
      case 'alarma_energizada':
        return 'sonido3';
      case 'sistema':
        return 'sonido4';
      case 'institucional':
      default:
        return 'sonido1';
    }
  }

  static String getAssetSoundPath(String tone) {
    switch (tone) {
      case 'campana_suave':
        return 'sounds/sonido2.mp3';
      case 'alarma_energizada':
        return 'sounds/sonido3.mp3';
      case 'sistema':
        return 'sounds/sonido4.mp3';
      case 'institucional':
      default:
        return 'sounds/sonido1.mp3';
    }
  }

  static Future<void> previewTone(String tone) async {
    try {
      await _audioPlayer.stop();
      final soundPath = getAssetSoundPath(tone);
      await _audioPlayer.play(AssetSource(soundPath));
    } catch (e) {
      debugPrint('[NotificationService] Error reproduciendo audio: $e');
    }
  }

  static Future<void> stopAudioPreview() async {
    try {
      await _audioPlayer.stop();
    } catch (_) {}
  }

  static Future<void> reloadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isMutedNotifier.value = prefs.getBool(_keyNotificationsMuted) ?? false;
      _cachedHapticEnabled = prefs.getBool('notif_haptic_enabled') ?? true;
      _cachedHighPriorityDoze = prefs.getBool('notif_high_priority_doze') ?? true;
      _cachedTone = prefs.getString('notif_alert_tone') ?? 'institucional';
    } catch (_) {}
  }

  /// Alterna el modo silencio de notificaciones. Devuelve true si quedó silenciado.
  static Future<bool> toggleMute() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final newMuted = !isMutedNotifier.value;
      isMutedNotifier.value = newMuted;
      await prefs.setBool(_keyNotificationsMuted, newMuted);
      if (newMuted) {
        await cancelAll();
      } else {
        await scheduleAllAttendanceReminders();
      }
      return newMuted;
    } catch (_) {
      return isMutedNotifier.value;
    }
  }

  // IDs de notificaciones del sistema
  static const int ID_MORNING_ENTRY = 1001;
  static const int ID_MORNING_EXIT = 1002;
  static const int ID_AFTERNOON_ENTRY = 1003;
  static const int ID_AFTERNOON_EXIT = 1004;
  static const int ID_TEST = 9999;
  static const int ID_EVENT_BASE = 20000;

  // Canales de notificación Android
  static const String CHANNEL_ATTENDANCE_ID = 'iiap_attendance_reminders_v2';
  static const String CHANNEL_ATTENDANCE_NAME = 'Recordatorios de Asistencia IIAP';
  static const String CHANNEL_ATTENDANCE_DESC =
      'Alertas oportunas de ingreso y salida diaria del personal';

  static const String CHANNEL_EVENTS_ID = 'iiap_events_reminders_v2';
  static const String CHANNEL_EVENTS_NAME = 'Recordatorios de Eventos IIAP';
  static const String CHANNEL_EVENTS_DESC =
      'Avisos anticipados de eventos, talleres y capacitaciones';

  /// Inicializa el motor de notificaciones para Android, iOS y Windows
  static Future<void> init() async {
    if (_isInitialized) return;

    try {
      await reloadPreferences();

      // 1. Inicializar zonas horarias (Perú / América Latina) para programación offline
      tz.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation('America/Lima'));
      } catch (_) {
        // Fallback seguro a UTC si no se encuentra la zona local
      }

      // 2. Inicializar en Windows Desktop si aplica
      if (!kIsWeb && Platform.isWindows) {
        try {
          await localNotifier.setup(
            appName: 'IIAP - Control de Asistencia',
            shortcutPolicy: ShortcutPolicy.requireCreate,
          );
        } catch (e) {
          debugPrint('Aviso localNotifier Windows: $e');
        }
      }

      // 3. Inicializar FlutterLocalNotifications en Android / iOS / Linux
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isLinux)) {
        const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
        const darwinSettings = DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );
        const linuxSettings = LinuxInitializationSettings(
          defaultActionName: 'Abrir App',
        );

        const initSettings = InitializationSettings(
          android: androidSettings,
          iOS: darwinSettings,
          linux: linuxSettings,
        );

        await _notificationsPlugin.initialize(
          initSettings,
          onDidReceiveNotificationResponse: (response) {
            debugPrint('Notificación presionada con payload: ${response.payload}');
          },
        );

        // Solicitar permisos en Android 13+ (Notificaciones y Alarma Exacta)
        if (Platform.isAndroid) {
          final androidPlatform = _notificationsPlugin
              .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
          if (androidPlatform != null) {
            await androidPlatform.requestNotificationsPermission();
            await androidPlatform.requestExactAlarmsPermission();
          }
        }
      }

      _isInitialized = true;

      // 4. Programar automáticamente las alarmas offline del día a día
      await scheduleAllAttendanceReminders();
    } catch (e) {
      debugPrint('Error inicializando NotificationService: $e');
    }
  }

  static AndroidScheduleMode get _activeScheduleMode => _cachedHighPriorityDoze
      ? AndroidScheduleMode.exactAllowWhileIdle
      : AndroidScheduleMode.exact;

  static AndroidScheduleMode get _fallbackScheduleMode => _cachedHighPriorityDoze
      ? AndroidScheduleMode.inexactAllowWhileIdle
      : AndroidScheduleMode.inexact;

  /// Devuelve los detalles de notificación para Android e iOS
  static NotificationDetails _getNotificationDetails({
    String channelId = CHANNEL_ATTENDANCE_ID,
    String channelName = CHANNEL_ATTENDANCE_NAME,
    String channelDescription = CHANNEL_ATTENDANCE_DESC,
    bool? enableVibration,
    bool? highPriorityDoze,
  }) {
    final bool vib = enableVibration ?? _cachedHapticEnabled;
    final bool doze = highPriorityDoze ?? _cachedHighPriorityDoze;

    // Sufijo dinámico de canal para que el SO Android aplique de inmediato los cambios
    // de tono acústico, vibración y prioridad sin quedar atado a la caché inmutable del canal anterior
    final String effectiveChannelId = '${channelId}_${_cachedTone}_${vib ? 'v1' : 'v0'}_${doze ? 'hi' : 'std'}';

    final String rawSound = getRawSoundResource(_cachedTone);
    final RawResourceAndroidNotificationSound androidSound =
        RawResourceAndroidNotificationSound(rawSound);

    final androidDetails = AndroidNotificationDetails(
      effectiveChannelId,
      channelName,
      channelDescription: channelDescription,
      importance: doze ? Importance.max : Importance.defaultImportance,
      priority: doze ? Priority.max : Priority.defaultPriority,
      ticker: 'Control de Asistencia IIAP',
      icon: '@mipmap/ic_launcher',
      enableVibration: vib,
      vibrationPattern: vib ? Int64List.fromList([0, 250, 200, 250]) : null,
      playSound: true,
      sound: androidSound,
      fullScreenIntent: false,
      category: AndroidNotificationCategory.reminder,
    );

    final darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: '$rawSound.mp3',
    );

    return NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );
  }

  /// Muestra una notificación inmediata (Funciona en Android, iOS y Windows)
  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    // Si el usuario silenció las notificaciones en la app, no se emite ninguna alerta
    if (isMutedNotifier.value) {
      debugPrint('Notificaciones silenciadas. Descartando id=$id: $title');
      return;
    }

    try {
      if (!kIsWeb && Platform.isWindows) {
        final notification = LocalNotification(
          title: title,
          body: body,
        );
        await notification.show();
        previewTone(_cachedTone);
        return;
      }

      final details = _getNotificationDetails();
      await _notificationsPlugin.show(id, title, body, details, payload: payload);
    } catch (e) {
      debugPrint('Error mostrando notificación: $e');
    }
  }

  /// Envía una notificación de prueba para que el usuario verifique en su dispositivo
  static Future<void> triggerTestNotification() async {
    await showNotification(
      id: ID_TEST,
      title: 'IIAP • Prueba de Notificaciones',
      body: '¡Todo listo! Las alertas funcionarán aunque estés fuera de la app o sin internet.',
    );
  }

  /// Cancela una notificación programada específica
  static Future<void> cancel(int id) async {
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await _notificationsPlugin.cancel(id);
      }
    } catch (_) {}
  }

  /// Cancela todas las notificaciones programadas
  static Future<void> cancelAll() async {
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await _notificationsPlugin.cancelAll();
      }
    } catch (_) {}
  }

  /// Calcula la siguiente instancia de una hora específica (repite diario)
  static tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  /// Programa una alarma local en el sistema operativo
  /// ESTO FUNCIONA 100% OFFLINE Y CON LA APLICACIÓN COMPLETAMENTE CERRADA
  static Future<void> _scheduleDailyAlarm({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    try {
      final scheduledTime = _nextInstanceOfTime(hour, minute);
      final details = _getNotificationDetails();

      // Intento con scheduleMode dinámico según preferencia de Doze / Modo Reposo
      try {
        await _notificationsPlugin.zonedSchedule(
          id,
          title,
          body,
          scheduledTime,
          details,
          androidScheduleMode: _activeScheduleMode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      } catch (_) {
        // Fallback por si el dispositivo restringe alarmas exactas
        await _notificationsPlugin.zonedSchedule(
          id,
          title,
          body,
          scheduledTime,
          details,
          androidScheduleMode: _fallbackScheduleMode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
      debugPrint('Alarma programada offline id=$id a las $hour:$minute');
    } catch (e) {
      debugPrint('Error programando alarma id=$id: $e');
    }
  }

  /// Programa todas las alertas diarias de asistencia institucional en el SO
  static Future<void> scheduleAllAttendanceReminders() async {
    if (isMutedNotifier.value) {
      await cancelAll();
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    final morningEntryEnabled = prefs.getBool('notif_morning_entry') ?? true;
    final morningExitEnabled = prefs.getBool('notif_morning_exit') ?? true;
    final afternoonEntryEnabled = prefs.getBool('notif_afternoon_entry') ?? true;
    final afternoonExitEnabled = prefs.getBool('notif_afternoon_exit') ?? true;

    // Horarios predeterminados configurados oficialmente por el Inge:
    // Mañana: Alarma 07:45 AM (aviso oportuno antes del ingreso institucional)
    // Salida Mañana: 13:00 PM (01:00 PM - refrigerio)
    // Entrada Tarde: 14:00 PM (02:00 PM - hora oficial actualizada por el Inge)
    // Salida Tarde: 18:30 PM (06:30 PM - fin de jornada laboral diaria)
    final morningEntryTime = prefs.getString('notif_morning_entry_time') ?? '07:45';
    final morningExitTime = prefs.getString('notif_morning_exit_time') ?? '13:00';
    final afternoonEntryTime = prefs.getString('notif_afternoon_entry_time') ?? '14:00';
    final afternoonExitTime = prefs.getString('notif_afternoon_exit_time') ?? '18:30';

    final mInParts = morningEntryTime.split(':');
    final mOutParts = morningExitTime.split(':');
    final aInParts = afternoonEntryTime.split(':');
    final aOutParts = afternoonExitTime.split(':');

    final mInH = int.tryParse(mInParts.first) ?? 7;
    final mInM = int.tryParse(mInParts.length > 1 ? mInParts[1] : '45') ?? 45;

    final mOutH = int.tryParse(mOutParts.first) ?? 13;
    final mOutM = int.tryParse(mOutParts.length > 1 ? mOutParts[1] : '0') ?? 0;

    final aInH = int.tryParse(aInParts.first) ?? 14;
    final aInM = int.tryParse(aInParts.length > 1 ? aInParts[1] : '0') ?? 0;

    final aOutH = int.tryParse(aOutParts.first) ?? 18;
    final aOutM = int.tryParse(aOutParts.length > 1 ? aOutParts[1] : '30') ?? 30;

    // 1. Entrada Mañana
    if (morningEntryEnabled) {
      await _scheduleDailyAlarm(
        id: ID_MORNING_ENTRY,
        title: 'IIAP • Entrada Turno Mañana',
        body: '¡Buenos días! Recuerda registrar tu asistencia de ingreso al IIAP.',
        hour: mInH,
        minute: mInM,
      );
    } else {
      await cancel(ID_MORNING_ENTRY);
    }

    // 2. Salida Mañana
    if (morningExitEnabled) {
      await _scheduleDailyAlarm(
        id: ID_MORNING_EXIT,
        title: 'IIAP • Salida Turno Mañana',
        body: '¡Hora de refrigerio! Recuerda marcar tu salida del turno de la mañana.',
        hour: mOutH,
        minute: mOutM,
      );
    } else {
      await cancel(ID_MORNING_EXIT);
    }

    // 3. Entrada Tarde
    if (afternoonEntryEnabled) {
      await _scheduleDailyAlarm(
        id: ID_AFTERNOON_ENTRY,
        title: 'IIAP • Entrada Turno Tarde',
        body: 'Buenas tardes. Recuerda registrar tu asistencia de ingreso de la tarde.',
        hour: aInH,
        minute: aInM,
      );
    } else {
      await cancel(ID_AFTERNOON_ENTRY);
    }

    // 4. Salida Tarde
    if (afternoonExitEnabled) {
      await _scheduleDailyAlarm(
        id: ID_AFTERNOON_EXIT,
        title: 'IIAP • Salida Turno Tarde',
        body: '¡Fin de jornada laboral! Recuerda marcar tu salida del turno de la tarde.',
        hour: aOutH,
        minute: aOutM,
      );
    } else {
      await cancel(ID_AFTERNOON_EXIT);
    }
  }

  /// Programa recordatorios para un evento institucional (1h antes, 15m antes y cierre)
  /// También se guarda en el SO para dispararse offline y fuera de la app
  static Future<void> scheduleEventReminders({
    required String eventId,
    required String title,
    required String location,
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    if (isMutedNotifier.value) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final eventsEnabled = prefs.getBool('notif_events') ?? true;
      final closeEnabled = prefs.getBool('notif_event_close') ?? true;

      final now = DateTime.now();
      final hash = (eventId.hashCode % 10000).abs();
      final id1Hour = ID_EVENT_BASE + hash;
      final id15Min = ID_EVENT_BASE + 10000 + hash;
      final idClose = ID_EVENT_BASE + 20000 + hash;

      // 1. AVISOS DE CONVOCATORIA (1h antes y anticipación configurada)
      if (!eventsEnabled) {
        await cancel(id1Hour);
        await cancel(id15Min);
      } else {
        final leadMinutes = prefs.getInt('notif_events_lead_minutes') ?? 15;
        final oneHourBefore = startDate.subtract(const Duration(hours: 1));
        final leadBefore = startDate.subtract(Duration(minutes: leadMinutes));

        final details = _getNotificationDetails(
          channelId: CHANNEL_EVENTS_ID,
          channelName: CHANNEL_EVENTS_NAME,
          channelDescription: CHANNEL_EVENTS_DESC,
        );

        // Notificación 1 hora antes
        if (leadMinutes != 60 && oneHourBefore.isAfter(now)) {
          final tzTime = tz.TZDateTime.from(oneHourBefore, tz.local);
          try {
            await _notificationsPlugin.zonedSchedule(
              id1Hour,
              'Evento IIAP en 1 hora',
              'En 1 hora inicia "$title" en $location.',
              tzTime,
              details,
              androidScheduleMode: _activeScheduleMode,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
            );
          } catch (_) {
            await _notificationsPlugin.zonedSchedule(
              id1Hour,
              'Evento IIAP en 1 hora',
              'En 1 hora inicia "$title" en $location.',
              tzTime,
              details,
              androidScheduleMode: _fallbackScheduleMode,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
            );
          }
        }

        // Notificación anticipada según preferencia (por defecto 15 minutos antes)
        if (leadBefore.isAfter(now)) {
          final tzTime = tz.TZDateTime.from(leadBefore, tz.local);
          final leadText = leadMinutes >= 60 ? '${leadMinutes ~/ 60} hora' : '$leadMinutes minutos';
          try {
            await _notificationsPlugin.zonedSchedule(
              id15Min,
              '¡Tu evento IIAP comienza pronto!',
              '"$title" inicia en $leadText en $location.',
              tzTime,
              details,
              androidScheduleMode: _activeScheduleMode,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
            );
          } catch (_) {
            await _notificationsPlugin.zonedSchedule(
              id15Min,
              '¡Tu evento IIAP comienza pronto!',
              '"$title" inicia en $leadText en $location.',
              tzTime,
              details,
              androidScheduleMode: _fallbackScheduleMode,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
            );
          }
        }
      }

      // 2. ROTACIÓN Y CIERRE DE EVENTO
      if (!closeEnabled || endDate == null) {
        await cancel(idClose);
      } else if (closeEnabled && endDate.isAfter(now)) {
        final tzEnd = tz.TZDateTime.from(endDate, tz.local);
        final details = _getNotificationDetails(
          channelId: CHANNEL_EVENTS_ID,
          channelName: CHANNEL_EVENTS_NAME,
          channelDescription: CHANNEL_EVENTS_DESC,
        );
        try {
          await _notificationsPlugin.zonedSchedule(
            idClose,
            'Cierre de Evento IIAP',
            'El evento "$title" ha culminado. Recuerda registrar tu salida o marcado final.',
            tzEnd,
            details,
            androidScheduleMode: _activeScheduleMode,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
        } catch (_) {
          await _notificationsPlugin.zonedSchedule(
            idClose,
            'Cierre de Evento IIAP',
            'El evento "$title" ha culminado. Recuerda registrar tu salida o marcado final.',
            tzEnd,
            details,
            androidScheduleMode: _fallbackScheduleMode,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
        }
      }
    } catch (e) {
      debugPrint('Error programando recordatorio de evento: $e');
    }
  }

  /// Cancela los recordatorios de un evento (apertura y cierre)
  static Future<void> cancelEventReminders(String eventId) async {
    final hash = (eventId.hashCode % 10000).abs();
    await cancel(ID_EVENT_BASE + hash);
    await cancel(ID_EVENT_BASE + 10000 + hash);
    await cancel(ID_EVENT_BASE + 20000 + hash);
  }

  /// Sincroniza y cancela/reprograma de inmediato en el SO al tocar los switches
  static Future<void> syncEventSettings({
    required bool eventsEnabled,
    required bool closeEnabled,
    required List<dynamic> events,
  }) async {
    for (final evt in events) {
      final String id = evt.id.toString();
      final hash = (id.hashCode % 10000).abs();

      if (!eventsEnabled) {
        await cancel(ID_EVENT_BASE + hash);
        await cancel(ID_EVENT_BASE + 10000 + hash);
      }
      if (!closeEnabled) {
        await cancel(ID_EVENT_BASE + 20000 + hash);
      }

      if (eventsEnabled || closeEnabled) {
        final DateTime startDate = evt.startDate as DateTime;
        final DateTime? endDate = evt.endDate as DateTime?;
        final now = DateTime.now();

        if (startDate.isAfter(now) || (endDate != null && endDate.isAfter(now))) {
          await scheduleEventReminders(
            eventId: id,
            title: evt.title.toString(),
            location: evt.location.toString(),
            startDate: startDate,
            endDate: endDate,
          );
        }
      }
    }
  }

  /// Gestiona la respuesta inteligente cuando el usuario marca asistencia en la app
  static Future<void> onAttendanceMarked({
    required AttendanceType type,
    required AttendanceShift shift,
  }) async {
    try {
      if (shift == AttendanceShift.MORNING) {
        if (type == AttendanceType.CHECK_OUT) {
          // Si ya marcó salida de la mañana, cancelar aviso para hoy
          await cancel(ID_MORNING_EXIT);
        } else if (type == AttendanceType.CHECK_IN) {
          // Asegurar que la alarma de salida a las 13:00 esté activa
          await scheduleAllAttendanceReminders();
        }
      } else if (shift == AttendanceShift.AFTERNOON) {
        if (type == AttendanceType.CHECK_OUT) {
          // Si ya marcó salida de la tarde, cancelar aviso para hoy
          await cancel(ID_AFTERNOON_EXIT);
        } else if (type == AttendanceType.CHECK_IN) {
          // Asegurar que la alarma de salida a las 18:30 esté activa
          await scheduleAllAttendanceReminders();
        }
      }
    } catch (e) {
      debugPrint('Aviso onAttendanceMarked: $e');
    }
  }

  /// Mantiene compatibilidad con llamadas existentes
  static Future<void> showCheckoutReminder({
    required int id,
    required String title,
    required String body,
  }) async {
    await showNotification(id: id, title: title, body: body);
  }

  /// Evalúa el estado del día y lanza o reprograma alertas oportunas
  static Future<void> checkAndTriggerCheckoutReminder({
    List<AttendanceModel>? preloadedTodayRecords,
  }) async {
    try {
      final now = DateTime.now();
      final nowTotalMinutes = now.hour * 60 + now.minute;
      final dateKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final records = preloadedTodayRecords ?? await AttendanceService.getTodayRecords();

      final morningCheckIn = records.cast<AttendanceModel?>().firstWhere(
            (r) => r?.shift == AttendanceShift.MORNING && r?.type == AttendanceType.CHECK_IN,
            orElse: () => null,
          );
      final morningCheckOut = records.cast<AttendanceModel?>().firstWhere(
            (r) => r?.shift == AttendanceShift.MORNING && r?.type == AttendanceType.CHECK_OUT,
            orElse: () => null,
          );

      final afternoonCheckIn = records.cast<AttendanceModel?>().firstWhere(
            (r) => r?.shift == AttendanceShift.AFTERNOON && r?.type == AttendanceType.CHECK_IN,
            orElse: () => null,
          );
      final afternoonCheckOut = records.cast<AttendanceModel?>().firstWhere(
            (r) => r?.shift == AttendanceShift.AFTERNOON && r?.type == AttendanceType.CHECK_OUT,
            orElse: () => null,
          );

      final prefs = await SharedPreferences.getInstance();

      // Regla Mañana:
      if (morningCheckIn != null && morningCheckOut == null) {
        if (nowTotalMinutes >= 13 * 60) {
          final morningNotifKey = 'notif_morning_checkout_$dateKey';
          final alreadyNotified = prefs.getBool(morningNotifKey) == true;
          if (!alreadyNotified) {
            await showNotification(
              id: ID_MORNING_EXIT,
              title: 'IIAP • Recordatorio de Salida',
              body: 'Recuerda marcar tu salida del turno de la mañana.',
            );
            await prefs.setBool(morningNotifKey, true);
          }
        }
      } else if (morningCheckOut != null) {
        await cancel(ID_MORNING_EXIT);
      }

      // Regla Tarde:
      if (afternoonCheckIn != null && afternoonCheckOut == null) {
        if (nowTotalMinutes >= 18 * 60 + 30) {
          final afternoonNotifKey = 'notif_afternoon_checkout_$dateKey';
          final alreadyNotified = prefs.getBool(afternoonNotifKey) == true;
          if (!alreadyNotified) {
            await showNotification(
              id: ID_AFTERNOON_EXIT,
              title: 'IIAP • Recordatorio de Salida',
              body: 'Recuerda marcar tu salida del turno de la tarde.',
            );
            await prefs.setBool(afternoonNotifKey, true);
          }
        }
      } else if (afternoonCheckOut != null) {
        await cancel(ID_AFTERNOON_EXIT);
      }
    } catch (e) {
      debugPrint('Aviso en checkAndTriggerCheckoutReminder: $e');
    }
  }
}
