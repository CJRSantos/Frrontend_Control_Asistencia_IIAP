import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/event_model.dart';
import 'api_client.dart';
import 'storage_service.dart';
import 'connectivity_service.dart';
import 'notification_service.dart';

class EventService {
  static const String _localEventsKey = 'local_stored_events_v1';
  static const String _pendingOfflineEventsKey = 'pending_offline_events_v2';
  static const String _pendingOfflineAttendeesKey = 'pending_offline_event_attendees_v2';
  static const String _knownEventIdsKey = 'known_event_ids_v2';

  static final ValueNotifier<List<EventModel>> eventsNotifier = ValueNotifier<List<EventModel>>([]);

  /// Notificador reactivo cuando se crea un nuevo evento institucional para avisar a la interfaz en primer plano
  static final ValueNotifier<EventModel?> newEventAlertNotifier = ValueNotifier<EventModel?>(null);

  static Timer? _liveSyncTimer;
  static bool _isSyncing = false;

  /// Inicia la sincronización continua en tiempo real (cada 10 segundos)
  static void startLiveSync({Duration interval = const Duration(seconds: 10)}) {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = Timer.periodic(interval, (_) async {
      if (_isSyncing) return;
      _isSyncing = true;
      try {
        if (ConnectivityService.isOnline) {
          await getEvents();
        }
      } catch (_) {
      } finally {
        _isSyncing = false;
      }
    });

    // Sincronización inmediata al arrancar
    if (ConnectivityService.isOnline) {
      getEvents();
    }
  }

  /// Detiene la sincronización en tiempo real al suspender la app
  static void stopLiveSync() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = null;
  }

  /// Agrega o actualiza un evento en la memoria local y lo persiste de inmediato
  static void addOrUpdateLocalEvent(EventModel event) {
    _updateLocalList(event);
  }

  /// Inicializa los eventos desde el almacenamiento local (offline-first) y sincroniza en segundo plano
  static Future<List<EventModel>> getEvents({bool forceRefresh = false}) async {
    // 1. Carga inmediata desde la caché local si aún no hay eventos en memoria
    if (eventsNotifier.value.isEmpty || forceRefresh) {
      final localList = await _loadFromLocalCache();
      final cleanList = localList.where((e) => !e.id.startsWith('evt_seed_')).toList();
      cleanList.sort((a, b) => b.startDate.compareTo(a.startDate));
      if (cleanList.isNotEmpty && eventsNotifier.value.isEmpty) {
        eventsNotifier.value = cleanList;
      }
    }

    // 2. Consulta y sincronización en segundo plano con el backend
    try {
      final response = await ApiClient.get(ApiConfig.eventsAll);
      List<dynamic>? rawList;
      if (response is List) {
        rawList = response;
      } else if (response is Map<String, dynamic>) {
        if (response['data'] is List) {
          rawList = response['data'] as List;
        } else if (response['events'] is List) {
          rawList = response['events'] as List;
        } else if (response['items'] is List) {
          rawList = response['items'] as List;
        }
      }

      if (rawList != null) {
        final list = rawList
            .whereType<Map<String, dynamic>>()
            .map((json) {
              var ev = EventModel.fromJson(json);
              final existing = eventsNotifier.value.cast<EventModel?>().firstWhere(
                (e) => e?.id == ev.id,
                orElse: () => null,
              );
              if ((ev.imageUrl == null || ev.imageUrl!.isEmpty) &&
                  existing?.imageUrl != null &&
                  existing!.imageUrl!.isNotEmpty) {
                ev = ev.copyWith(imageUrl: existing.imageUrl);
              }
              return ev;
            })
            .where((e) => !e.id.startsWith('evt_seed_'))
            .toList();

        // Preservar eventos locales creados recientemente que aún no estén en el servidor
        final pendingLocals = eventsNotifier.value.where((e) => e.id.startsWith('evt_') && !list.any((serverE) => serverE.id == e.id)).toList();
        final merged = [...pendingLocals, ...list];
        merged.sort((a, b) => b.startDate.compareTo(a.startDate));

        // Solo notificar si la lista ha cambiado de contenido para evitar parpadeos y re-renders continuos
        final currentList = eventsNotifier.value;
        bool hasChanges = currentList.length != merged.length;
        if (!hasChanges) {
          for (int i = 0; i < currentList.length; i++) {
            if (currentList[i] != merged[i]) {
              hasChanges = true;
              break;
            }
          }
        }

        if (hasChanges) {
          eventsNotifier.value = merged;
          await _saveToLocalCache(merged);
        }

        // Detección y notificación automática de eventos creados por otros roles
        _checkAndNotifyNewEvents(merged);

        // Programar recordatorios offline en el SO solo cuando la lista cambia
        final now = DateTime.now();
        for (final evt in list) {
          if (evt.startDate.isAfter(now) || evt.endDate.isAfter(now)) {
            NotificationService.scheduleEventReminders(
              eventId: evt.id,
              title: evt.title,
              location: evt.location,
              startDate: evt.startDate,
              endDate: evt.endDate,
            );
          }
        }

        // Sincronizar en segundo plano eventos o asistencias generadas offline
        syncPendingEventData();

        return merged;
      }
    } catch (e) {
      debugPrint('EventService: backend no disponible o sin endpoint (/api/events). Usando caché local: $e');
    }

    return eventsNotifier.value;
  }

  /// Detecta eventos nuevos y emite notificación del sistema a todos los roles
  static Future<void> _checkAndNotifyNewEvents(List<EventModel> events) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final knownIds = prefs.getStringList(_knownEventIdsKey)?.toSet() ?? <String>{};

      // Si es la primera instalación/inicialización, registramos los eventos actuales sin disparar alertas masivas
      if (!prefs.containsKey(_knownEventIdsKey)) {
        await prefs.setStringList(_knownEventIdsKey, events.map((e) => e.id).toList());
        return;
      }

      final newEvents = events.where((e) => !knownIds.contains(e.id)).toList();
      if (newEvents.isNotEmpty) {
        for (final ev in newEvents) {
          knownIds.add(ev.id);
          final dayStr = '${ev.startDate.day.toString().padLeft(2, '0')}/${ev.startDate.month.toString().padLeft(2, '0')}';
          final hour = ev.startDate.hour % 12 == 0 ? 12 : ev.startDate.hour % 12;
          final minute = ev.startDate.minute.toString().padLeft(2, '0');
          final ampm = ev.startDate.hour >= 12 ? 'PM' : 'AM';
          final timeStr = '$hour:$minute $ampm';

          NotificationService.showNotification(
            id: ev.id.hashCode,
            title: '📢 Nuevo Evento: ${ev.title}',
            body: '${ev.location} • Inicia el $dayStr a las $timeStr. ¡Participa!',
          );

          // Emitir a la interfaz para mostrar aviso visual reactivo en pantalla a cualquier rol conectado
          newEventAlertNotifier.value = ev;
        }
        await prefs.setStringList(_knownEventIdsKey, knownIds.toList());
      }
    } catch (e) {
      debugPrint('EventService: Error al procesar notificaciones de eventos nuevos: $e');
    }
  }

  /// Obtiene los detalles actualizados de un evento individual (incluye lista completa de asistentes)
  static Future<EventModel?> getEventById(String eventId) async {
    try {
      final response = await ApiClient.get(ApiConfig.eventById(eventId));
      if (response != null && response is Map<String, dynamic>) {
        var serverEvent = EventModel.fromJson(response);
        final existing = eventsNotifier.value.cast<EventModel?>().firstWhere(
          (e) => e?.id == eventId,
          orElse: () => null,
        );
        if ((serverEvent.imageUrl == null || serverEvent.imageUrl!.isEmpty) &&
            existing?.imageUrl != null &&
            existing!.imageUrl!.isNotEmpty) {
          serverEvent = serverEvent.copyWith(imageUrl: existing.imageUrl);
        }
        _updateLocalList(serverEvent);
        return serverEvent;
      }
    } catch (e) {
      debugPrint('EventService.getEventById: Error al consultar backend ($eventId): $e');
    }
    return null;
  }

  /// Crea un nuevo evento (Solo Admin o Supervisor)
  static Future<EventModel> createEvent({
    required String title,
    required String description,
    required String location,
    required DateTime startDate,
    required DateTime endDate,
    required EventType type,
    required bool requiresAttendance,
    String? organizationalUnit,
    List<EventShift>? shifts,
    String? imageUrl,
  }) async {
    final currentUser = StorageService.currentUser;
    if (currentUser == null || !currentUser.canManageAttendanceQr) {
      throw ApiException('Solo los Administradores y Supervisores pueden crear eventos.', 403);
    }

    final newId = 'evt_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    final qrToken = 'IIAP-EVT-$newId';

    final event = EventModel(
      id: newId,
      title: title.trim(),
      description: description.trim(),
      location: location.trim(),
      startDate: startDate,
      endDate: endDate,
      type: type,
      requiresAttendance: requiresAttendance,
      qrCode: qrToken,
      createdById: currentUser.id,
      createdByName: currentUser.fullName,
      createdByRole: currentUser.role.name,
      createdAt: DateTime.now(),
      status: EventStatus.UPCOMING,
      attendeesCount: 0,
      attendees: [],
      organizationalUnit: organizationalUnit?.trim(),
      shifts: shifts ?? [],
      imageUrl: imageUrl,
    );

    // Notificación inmediata al usuario creador
    NotificationService.showNotification(
      id: newId.hashCode,
      title: '📅 Evento Creado Exitosamente',
      body: 'Se ha creado el evento institucional "${event.title}".',
    );

    // Marcar como conocido localmente para no re-notificar al creador
    try {
      final prefs = await SharedPreferences.getInstance();
      final knownIds = prefs.getStringList(_knownEventIdsKey) ?? [];
      if (!knownIds.contains(newId)) {
        knownIds.add(newId);
        await prefs.setStringList(_knownEventIdsKey, knownIds);
      }
    } catch (_) {}

    // Intentar guardar en backend
    bool savedInBackend = false;
    try {
      final createPayload = {
        'title': title.trim(),
        'description': description.trim(),
        'location': location.trim(),
        'start_date': startDate.toIso8601String(),
        'end_date': endDate.toIso8601String(),
        'type': type.name,
        'requires_attendance': requiresAttendance,
        'qr_code': qrToken,
        if (organizationalUnit != null && organizationalUnit.trim().isNotEmpty)
          'organizational_unit': organizationalUnit.trim(),
        if (shifts != null && shifts.isNotEmpty)
          'shifts': shifts.map((s) => s.toJson()).toList(),
        if (imageUrl != null && imageUrl.isNotEmpty)
          'image_url': imageUrl,
      };
      final res = await ApiClient.post(
        ApiConfig.eventsAll,
        body: createPayload,
      );
      if (res is Map<String, dynamic>) {
        var serverEvent = EventModel.fromJson(res);
        if ((serverEvent.imageUrl == null || serverEvent.imageUrl!.isEmpty) &&
            imageUrl != null &&
            imageUrl.isNotEmpty) {
          serverEvent = serverEvent.copyWith(imageUrl: imageUrl);
        }
        final current = List<EventModel>.from(eventsNotifier.value);
        current.insert(0, serverEvent);
        eventsNotifier.value = current;
        await _saveToLocalCache(current);

        // Marcar el ID retornado por el servidor como conocido para evitar auto-notificación
        try {
          final prefs = await SharedPreferences.getInstance();
          final knownIds = prefs.getStringList(_knownEventIdsKey) ?? [];
          if (!knownIds.contains(serverEvent.id)) {
            knownIds.add(serverEvent.id);
            await prefs.setStringList(_knownEventIdsKey, knownIds);
          }
        } catch (_) {}

        return serverEvent;
      }
    } catch (e) {
      debugPrint('EventService: Guardando evento de forma local (fallback backend): $e');
    }

    // Guardado local si el backend falló o estamos offline
    final current = List<EventModel>.from(eventsNotifier.value);
    current.insert(0, event);
    eventsNotifier.value = current;
    await _saveToLocalCache(current);

    // Encolar para sincronizar en segundo plano cuando vuelva Internet
    _queueOfflineCreatedEvent(event);

    return event;
  }

  /// Actualiza un evento
  static Future<EventModel> updateEvent(EventModel event) async {
    if (event.isEventosMirror) {
      throw ApiException('Este evento se administra desde el Sistema de Eventos.', 409);
    }

    try {
      final updatePayload = {
        'title': event.title,
        'description': event.description,
        'location': event.location,
        'start_date': event.startDate.toIso8601String(),
        'end_date': event.endDate.toIso8601String(),
        'type': event.type.name,
        'requires_attendance': event.requiresAttendance,
        'status': event.status.name,
        if (event.organizationalUnit != null)
          'organizational_unit': event.organizationalUnit,
        if (event.shifts.isNotEmpty)
          'shifts': event.shifts.map((s) => s.toJson()).toList(),
        if (event.imageUrl != null && event.imageUrl!.isNotEmpty) ...{
          'image_url': event.imageUrl,
          'imageUrl': event.imageUrl,
          'cover_image': event.imageUrl,
          'image': event.imageUrl,
        } else ...{
          'image_url': null,
          'imageUrl': null,
          'cover_image': null,
          'image': null,
        },
      };
      final res = await ApiClient.patch(
        ApiConfig.eventById(event.id),
        body: updatePayload,
      );
      if (res is Map<String, dynamic>) {
        var updated = EventModel.fromJson(res);
        if ((updated.imageUrl == null || updated.imageUrl!.isEmpty) &&
            event.imageUrl != null &&
            event.imageUrl!.isNotEmpty) {
          updated = updated.copyWith(imageUrl: event.imageUrl);
        }
        _updateLocalList(updated);
        return updated;
      }
    } catch (e) {
      if (e is ApiException) rethrow;
    }

    _updateLocalList(event);
    return event;
  }

  static void _updateLocalList(EventModel updated) {
    final list = List<EventModel>.from(eventsNotifier.value);
    final idx = list.indexWhere((e) => e.id == updated.id);
    if (idx != -1) {
      if (list[idx] == updated) {
        // Ningún campo del evento cambió: evitamos notificar a listeners para prevenir parpadeos en pantalla
        return;
      }
      list[idx] = updated;
    } else {
      list.insert(0, updated);
    }
    eventsNotifier.value = list;
    _saveToLocalCache(list);
  }

  /// Elimina o cancela un evento
  static Future<void> deleteEvent(String eventId) async {
    final currentUser = StorageService.currentUser;
    if (currentUser == null || !currentUser.canManageAttendanceQr) {
      throw ApiException('Solo Administradores y Supervisores pueden eliminar eventos.', 403);
    }

    final existingEvent = eventsNotifier.value.where((e) => e.id == eventId).firstOrNull;
    if (existingEvent != null && existingEvent.isEventosMirror) {
      throw ApiException('Este evento se administra desde el Sistema de Eventos.', 409);
    }

    try {
      await ApiClient.delete(ApiConfig.eventById(eventId));
    } catch (e) {
      if (e is ApiException) rethrow;
    }

    final list = List<EventModel>.from(eventsNotifier.value);
    list.removeWhere((e) => e.id == eventId);
    eventsNotifier.value = list;
    await _saveToLocalCache(list);
  }

  /// Elimina a un participante de un evento (Solo Administrador y Supervisor)
  static Future<EventModel> removeAttendee({
    required String eventId,
    required String attendeeId,
  }) async {
    final currentUser = StorageService.currentUser;
    if (currentUser == null || !currentUser.canManageAttendanceQr) {
      throw ApiException('Solo Administradores y Supervisores pueden eliminar participantes.', 403);
    }

    // 1. Intentar llamada al backend
    try {
      final res = await ApiClient.delete(
        ApiConfig.eventDeleteAttendee(eventId, attendeeId),
      );
      if (res is Map<String, dynamic>) {
        final updated = EventModel.fromJson(res);
        _updateLocalList(updated);
        return updated;
      }
    } catch (e) {
      debugPrint('EventService: Falló eliminación en backend, aplicando fallback local: $e');
    }

    // 2. Fallback de eliminación local
    var list = List<EventModel>.from(eventsNotifier.value);
    var idx = list.indexWhere((e) => e.id == eventId);
    if (idx != -1) {
      final targetEvent = list[idx];
      final updatedAttendees = targetEvent.attendees
          .where((a) => a.id != attendeeId && a.userId != attendeeId)
          .toList();
      final updatedEvent = targetEvent.copyWith(
        attendees: updatedAttendees,
        attendeesCount: updatedAttendees.length,
      );
      list[idx] = updatedEvent;
      eventsNotifier.value = list;
      await _saveToLocalCache(list);
      return updatedEvent;
    }

    throw ApiException('No se encontró el evento para eliminar al participante.');
  }

  /// Registra manualmente a un participante en un evento (Solo Administrador y Supervisor)
  static Future<EventModel> registerManualAttendee({
    required String eventId,
    required String fullName,
    required String documentNumber,
    required String phoneNumber,
    required String email,
    String? gender,
    int? age,
    String? career,
    String? institution,
    String? position,
    String? notes,
    String? shift,
  }) async {
    final currentUser = StorageService.currentUser;
    if (currentUser == null || !currentUser.canManageAttendanceQr) {
      throw ApiException('Solo Administradores y Supervisores pueden registrar participantes manualmente.', 403);
    }

    final body = {
      'user_name': fullName.trim(),
      'document_number': documentNumber.trim(),
      'phone_number': phoneNumber.trim(),
      'user_email': email.trim().toLowerCase(),
      if (gender != null && gender.isNotEmpty) 'gender': gender.trim(),
      if (age != null) 'age': age,
      if (career != null && career.isNotEmpty) 'career': career.trim(),
      if (institution != null && institution.isNotEmpty) 'institution': institution.trim(),
      if (position != null && position.isNotEmpty) 'user_position': position.trim(),
      if (notes != null && notes.isNotEmpty) 'notes': notes.trim(),
      if (shift != null && shift.isNotEmpty) 'shift': shift.trim(),
      'is_external': true,
      'registered_at': DateTime.now().toUtc().toIso8601String(),
    };

    // 1. Intentar en el backend
    try {
      final res = await ApiClient.post(
        ApiConfig.eventRegisterAttendance(eventId),
        body: body,
      );
      if (res is Map<String, dynamic>) {
        final updated = EventModel.fromJson(res);
        _updateLocalList(updated);
        return updated;
      }
    } on ApiException catch (e) {
      if (e.statusCode == 400 || e.statusCode == 409 || e.statusCode == 403) {
        rethrow;
      }
      debugPrint('EventService: Error de red o 404 al registrar asistente en backend, aplicando fallback local: $e');
    } catch (e) {
      debugPrint('EventService: Fallback a registro manual local: $e');
    }

    // 2. Fallback local (resiliente para eventos creados offline)
    var list = List<EventModel>.from(eventsNotifier.value);
    var idx = list.indexWhere((e) => e.id == eventId);
    if (idx != -1) {
      final targetEvent = list[idx];
      final docTrimmed = documentNumber.trim();
      final emailTrimmed = email.trim().toLowerCase();
      final exists = targetEvent.attendees.any(
        (a) => (shift != null && shift.isNotEmpty ? a.shift == shift : true) &&
               ((docTrimmed.isNotEmpty && a.documentNumber == docTrimmed) ||
                (emailTrimmed.isNotEmpty && a.userEmail.toLowerCase() == emailTrimmed)),
      );
      if (exists) {
        throw ApiException('El participante ya se encuentra registrado con este DNI o correo.');
      }

      final newAtt = EventAttendeeModel(
        id: 'att_manual_${DateTime.now().millisecondsSinceEpoch}',
        userId: '',
        userName: fullName.trim(),
        userEmail: email.trim().toLowerCase(),
        documentNumber: documentNumber.trim(),
        phoneNumber: phoneNumber.trim(),
        gender: gender?.trim(),
        age: age,
        career: career?.trim(),
        institution: institution?.trim(),
        userPosition: position?.trim(),
        notes: notes?.trim() ?? 'Registro manual por Administrador',
        shift: shift,
        isExternal: true,
        registeredAt: DateTime.now(),
      );
      final updatedAttendees = List<EventAttendeeModel>.from(targetEvent.attendees)..insert(0, newAtt);
      final updatedEvent = targetEvent.copyWith(
        attendees: updatedAttendees,
        attendeesCount: updatedAttendees.length,
      );
      list[idx] = updatedEvent;
      eventsNotifier.value = list;
      await _saveToLocalCache(list);

      // Encolar para sincronizar cuando haya conexión
      _queueOfflineEventAttendance(eventId, newAtt);

      return updatedEvent;
    }

    throw ApiException('No se encontró el evento para registrar al participante.');
  }

  /// Registra la asistencia de un colaborador a un evento (Soporte Offline y Multi-Dispositivo)
  static Future<EventModel> registerAttendance({
    required String eventId,
    String? qrCode,
    String? shift,
    String? eventTitle,
    String? eventLocation,
    String? organizationalUnit,
    String? eventType,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final currentUser = StorageService.currentUser;
    if (currentUser == null) {
      throw ApiException('Debes iniciar sesión para marcar asistencia.', 401);
    }

    final safeEmail = (currentUser.email.isNotEmpty && currentUser.email.contains('@'))
        ? currentUser.email.trim().toLowerCase()
        : '${(currentUser.documentNumber?.isNotEmpty == true ? currentUser.documentNumber : currentUser.id)}@iiap.gob.pe';

    // 1. Intentar llamada al backend si hay conectividad
    if (ConnectivityService.isOnline) {
      try {
        final body = {
          'user_id': currentUser.id,
          'user_name': currentUser.fullName,
          'user_email': safeEmail,
          'user_position': currentUser.position ?? '',
          'user_department': currentUser.department ?? '',
          'document_number': currentUser.documentNumber ?? '',
          'phone_number': currentUser.phoneNumber ?? '',
          'is_external': false,
          if (shift != null && shift.isNotEmpty) 'shift': shift.trim(),
          'registered_at': DateTime.now().toUtc().toIso8601String(),
        };
        final res = await ApiClient.post(
          ApiConfig.eventRegisterAttendance(eventId),
          body: body,
        );
        if (res is Map<String, dynamic>) {
          final updated = EventModel.fromJson(res);
          _updateLocalList(updated);
          return updated;
        }
      } on ApiException catch (e) {
        // Propagar duplicados de negocio informativos
        if (e.statusCode == 409 ||
            e.message.toLowerCase().contains('ya se encuentra') ||
            e.message.toLowerCase().contains('ya registraste')) {
          rethrow;
        }
        debugPrint('EventService: Backend reportó error o 404, aplicando fallback offline inmediato: $e');
      } catch (e) {
        debugPrint('EventService: Fallback a registro de evento local offline: $e');
      }
    }

    // 2. Fallback de registro local (Offline-First o evento no sincronizado en backend aún)
    var list = List<EventModel>.from(eventsNotifier.value);
    var idx = list.indexWhere((e) => e.id == eventId);
    if (idx == -1) {
      if (ConnectivityService.isOnline) {
        try {
          await getEvents(forceRefresh: true);
        } catch (_) {}
      }
      list = List<EventModel>.from(eventsNotifier.value);
      idx = list.indexWhere((e) => e.id == eventId);
    }

    // Si el evento no existía en este teléfono, lo reconstruimos al instante con la información del QR
    if (idx == -1) {
      final reconstructed = EventModel(
        id: eventId,
        title: (eventTitle != null && eventTitle.isNotEmpty) ? eventTitle : 'Evento Institucional IIAP',
        description: 'Evento registrado mediante código QR institucional.',
        location: (eventLocation != null && eventLocation.isNotEmpty) ? eventLocation : 'IIAP - Sede Central',
        startDate: startDate ?? DateTime.now(),
        endDate: endDate ?? DateTime.now().add(const Duration(hours: 3)),
        type: EventType.fromString(eventType),
        requiresAttendance: true,
        qrCode: qrCode ?? 'IIAP-EVT-$eventId',
        createdById: 'SYNC',
        createdByName: 'Administración IIAP',
        createdByRole: 'ADMIN',
        createdAt: DateTime.now(),
        status: EventStatus.UPCOMING,
        attendeesCount: 0,
        attendees: [],
        organizationalUnit: organizationalUnit,
      );
      list.insert(0, reconstructed);
      idx = 0;
    }

    final targetEvent = list[idx];

    // Verificar si ya registró asistencia en este dispositivo
    if (targetEvent.isUserModelRegistered(currentUser, shift: shift)) {
      throw ApiException(
        shift != null && shift.isNotEmpty
            ? 'Ya registraste tu asistencia para el turno "$shift" en este evento.'
            : 'Ya registraste tu asistencia para este evento previamente.',
      );
    }

    final newAttendee = EventAttendeeModel(
      id: 'att_${currentUser.id}_${DateTime.now().millisecondsSinceEpoch}',
      userId: currentUser.id,
      userName: currentUser.fullName,
      userEmail: safeEmail,
      userPosition: currentUser.position,
      userDepartment: currentUser.department,
      documentNumber: currentUser.documentNumber,
      phoneNumber: currentUser.phoneNumber,
      isExternal: false,
      shift: shift,
      registeredAt: DateTime.now(),
      notes: 'Asistencia confirmada exitosamente',
    );

    final updatedAttendees = List<EventAttendeeModel>.from(targetEvent.attendees)..insert(0, newAttendee);
    final updatedEvent = targetEvent.copyWith(
      attendees: updatedAttendees,
      attendeesCount: max(targetEvent.attendeesCount + 1, updatedAttendees.length),
    );

    list[idx] = updatedEvent;
    eventsNotifier.value = list;
    await _saveToLocalCache(list);

    // Encolar para auto-sincronizar con el servidor en cuanto haya red
    _queueOfflineEventAttendance(eventId, newAttendee);

    return updatedEvent;
  }

  static Future<void> _queueOfflineCreatedEvent(EventModel event) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentList = prefs.getStringList(_pendingOfflineEventsKey) ?? [];
      final encoded = jsonEncode(event.toJson());
      if (!currentList.contains(encoded)) {
        currentList.add(encoded);
        await prefs.setStringList(_pendingOfflineEventsKey, currentList);
      }
    } catch (e) {
      debugPrint('Error encolando evento offline: $e');
    }
  }

  static Future<void> _queueOfflineEventAttendance(String eventId, EventAttendeeModel attendee) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentList = prefs.getStringList(_pendingOfflineAttendeesKey) ?? [];
      final item = {
        'event_id': eventId,
        'attendee': attendee.toJson(),
      };
      currentList.add(jsonEncode(item));
      await prefs.setStringList(_pendingOfflineAttendeesKey, currentList);
    } catch (e) {
      debugPrint('Error encolando asistencia de evento offline: $e');
    }
  }

  static bool _isSyncingEvents = false;

  /// Sincroniza eventos creados y asistencias pendientes cuando hay conexión a Internet
  static Future<void> syncPendingEventData() async {
    if (_isSyncingEvents) return;
    _isSyncingEvents = true;
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Sincronizar eventos creados offline
      final pendingEvents = prefs.getStringList(_pendingOfflineEventsKey) ?? [];
      if (pendingEvents.isNotEmpty) {
        final List<String> remainingEvents = [];
        for (final raw in pendingEvents) {
          try {
            final json = jsonDecode(raw);
            await ApiClient.post(
              ApiConfig.eventsAll,
              body: {
                'title': json['title'],
                'description': json['description'],
                'location': json['location'],
                'start_date': json['start_date'] ?? json['startDate'],
                'end_date': json['end_date'] ?? json['endDate'],
                'type': json['type'],
                'requires_attendance': json['requires_attendance'] ?? json['requiresAttendance'] ?? true,
                'qr_code': json['qr_code'] ?? json['qrCode'],
                if (json['organizational_unit'] != null) 'organizational_unit': json['organizational_unit'],
                if (json['shifts'] != null) 'shifts': json['shifts'],
                if (json['image_url'] != null) 'image_url': json['image_url'],
              },
            );
            debugPrint('[EventSync] Evento ${json['id']} sincronizado con éxito al backend.');
          } catch (e) {
            remainingEvents.add(raw);
            debugPrint('[EventSync] No se pudo subir evento offline: $e');
          }
        }
        await prefs.setStringList(_pendingOfflineEventsKey, remainingEvents);
      }

      // 2. Sincronizar asistencias a eventos creadas offline
      final pendingAttendees = prefs.getStringList(_pendingOfflineAttendeesKey) ?? [];
      if (pendingAttendees.isNotEmpty) {
        final List<String> remainingAttendees = [];
        for (final raw in pendingAttendees) {
          try {
            final item = jsonDecode(raw);
            final eventId = item['event_id'];
            final att = item['attendee'];
            String attEmail = (att['user_email'] ?? att['userEmail'] ?? '').toString().trim();
            if (!attEmail.contains('@')) {
              final doc = (att['document_number'] ?? att['documentNumber'] ?? 'participante').toString().trim();
              attEmail = '$doc@iiap.gob.pe';
            }
            await ApiClient.post(
              ApiConfig.eventRegisterAttendance(eventId),
              body: {
                'user_id': att['user_id'] ?? att['userId'] ?? '',
                'user_name': att['user_name'] ?? att['userName'] ?? 'Participante',
                'user_email': attEmail,
                'document_number': att['document_number'] ?? att['documentNumber'] ?? '',
                'phone_number': att['phone_number'] ?? att['phoneNumber'] ?? '',
                'user_position': att['user_position'] ?? att['userPosition'] ?? '',
                'user_department': att['user_department'] ?? att['userDepartment'] ?? '',
                'is_external': att['is_external'] ?? att['isExternal'] ?? false,
                if (att['shift'] != null) 'shift': att['shift'],
                if (att['gender'] != null) 'gender': att['gender'],
                if (att['age'] != null) 'age': att['age'],
                if (att['career'] != null) 'career': att['career'],
                if (att['institution'] != null) 'institution': att['institution'],
                if (att['notes'] != null) 'notes': att['notes'],
                'registered_at': att['registered_at'] ?? att['registeredAt'] ?? DateTime.now().toUtc().toIso8601String(),
              },
            );
            debugPrint('[EventSync] Asistencia de participante ${att['user_name']} sincronizada con éxito.');
          } catch (e) {
            remainingAttendees.add(raw);
            debugPrint('[EventSync] No se pudo sincronizar asistencia a evento: $e');
          }
        }
        await prefs.setStringList(_pendingOfflineAttendeesKey, remainingAttendees);
      }
    } catch (e) {
      debugPrint('Error en syncPendingEventData: $e');
    } finally {
      _isSyncingEvents = false;
    }
  }

  /// Obtiene los gestores asignados al evento
  static Future<List<Map<String, dynamic>>> getEventManagers(String eventId) async {
    try {
      final response = await ApiClient.get(ApiConfig.eventManagers(eventId));
      if (response != null && response is List) {
        return response.whereType<Map<String, dynamic>>().toList();
      }
    } catch (e) {
      debugPrint('Error obteniendo gestores de evento: $e');
    }
    return [];
  }

  /// Asigna un nuevo gestor al evento (sin límite)
  static Future<void> addEventManager(String eventId, String userId) async {
    await ApiClient.post(ApiConfig.eventManagers(eventId), body: {
      'user_id': userId,
    });
    final list = List<EventModel>.from(eventsNotifier.value);
    final idx = list.indexWhere((e) => e.id == eventId);
    if (idx != -1) {
      final evt = list[idx];
      if (!evt.managerIds.contains(userId)) {
        final updated = evt.copyWith(managerIds: [...evt.managerIds, userId]);
        list[idx] = updated;
        eventsNotifier.value = list;
        await _saveToLocalCache(list);
      }
    }
  }

  /// Remueve un gestor asignado al evento
  static Future<void> removeEventManager(String eventId, String userId) async {
    await ApiClient.delete(ApiConfig.eventRemoveManager(eventId, userId));
    final list = List<EventModel>.from(eventsNotifier.value);
    final idx = list.indexWhere((e) => e.id == eventId);
    if (idx != -1) {
      final evt = list[idx];
      final updated = evt.copyWith(
        managerIds: evt.managerIds.where((id) => id != userId).toList(),
      );
      list[idx] = updated;
      eventsNotifier.value = list;
      await _saveToLocalCache(list);
    }
  }

  // --- Helpers de Caché Local ---

  static DateTime? _lastSaveTime;

  static Future<void> _saveToLocalCache(List<EventModel> events, {bool force = false}) async {
    final now = DateTime.now();
    if (!force && _lastSaveTime != null && now.difference(_lastSaveTime!).inSeconds < 4) {
      // Evitar saturar el disco con I/O repetitivo durante sondeos en vivo
      return;
    }
    _lastSaveTime = now;
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(events.map((e) => e.toJson()).toList());
      await prefs.setString(_localEventsKey, encoded);
    } catch (e) {
      debugPrint('Error guardando eventos en caché: $e');
    }
  }

  static Future<List<EventModel>> _loadFromLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_localEventsKey);
      if (str != null && str.isNotEmpty) {
        final decoded = jsonDecode(str);
        if (decoded is List) {
          return decoded
              .whereType<Map<String, dynamic>>()
              .map((json) => EventModel.fromJson(json))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('Error cargando eventos desde caché: $e');
    }
    return [];
  }
}
