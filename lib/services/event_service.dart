import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/event_model.dart';
import 'api_client.dart';
import 'storage_service.dart';

import 'notification_service.dart';

class EventService {
  static const String _localEventsKey = 'local_stored_events_v1';
  static final ValueNotifier<List<EventModel>> eventsNotifier = ValueNotifier<List<EventModel>>([]);

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
      if (response != null && response is List) {
        final list = response
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
        if (true) {

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
        }

        return list;
      }
    } catch (e) {
      debugPrint('EventService: backend no disponible o sin endpoint (/api/events). Usando caché local: $e');
    }

    return eventsNotifier.value;
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

    // Intentar guardar en backend
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
        return serverEvent;
      }
    } catch (e) {
      debugPrint('EventService: Guardando evento de forma local (fallback backend): $e');
    }

    // Guardado local
    final current = List<EventModel>.from(eventsNotifier.value);
    current.insert(0, event);
    eventsNotifier.value = current;
    await _saveToLocalCache(current);
    return event;
  }

  /// Actualiza un evento
  static Future<EventModel> updateEvent(EventModel event) async {
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
    } catch (_) {}

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

    try {
      await ApiClient.delete(ApiConfig.eventById(eventId));
    } catch (_) {}

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
      if (e.statusCode == 400 || e.statusCode == 409 || e.statusCode == 403 || e.statusCode == 404) {
        rethrow;
      }
      debugPrint('EventService: Error de red al registrar asistente en backend: $e');
    } catch (e) {
      debugPrint('EventService: Fallback a registro manual local: $e');
    }

    // 2. Fallback local
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
      return updatedEvent;
    }

    throw ApiException('No se encontró el evento para registrar al participante.');
  }

  /// Registra la asistencia de un colaborador a un evento
  static Future<EventModel> registerAttendance({
    required String eventId,
    String? qrCode,
    String? shift,
  }) async {
    final currentUser = StorageService.currentUser;
    if (currentUser == null) {
      throw ApiException('Debes iniciar sesión para marcar asistencia.', 401);
    }

    // 1. Intentar llamada al backend
    try {
      final body = {
        'user_id': currentUser.id,
        'user_name': currentUser.fullName,
        'user_email': currentUser.email,
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
      // Propagar errores de validación de negocio del backend (ej: duplicados, evento cerrado, etc.)
      if (e.statusCode == 400 || e.statusCode == 409 || e.statusCode == 403 || e.statusCode == 404) {
        rethrow;
      }
      debugPrint('EventService: Backend reportó error de red/servidor, evaluando fallback local: $e');
    } catch (e) {
      debugPrint('EventService: Registro de asistencia en backend falló/no existe, procesando local: $e');
    }

    // 2. Fallback de registro local
    var list = List<EventModel>.from(eventsNotifier.value);
    var idx = list.indexWhere((e) => e.id == eventId);
    if (idx == -1) {
      await getEvents(forceRefresh: true);
      list = List<EventModel>.from(eventsNotifier.value);
      idx = list.indexWhere((e) => e.id == eventId);
    }
    if (idx == -1) {
      throw ApiException('El evento seleccionado no existe o ya no está disponible.');
    }

    final targetEvent = list[idx];

    // Verificar si ya registró asistencia
    if (targetEvent.isUserModelRegistered(currentUser)) {
      throw ApiException('Ya registraste tu asistencia para este evento previamente.');
    }

    // Si requiere QR y se suministró un código, validar coincidencia básica
    if (targetEvent.requiresAttendance && qrCode != null && qrCode.isNotEmpty) {
      final matches = targetEvent.qrCode == null ||
          targetEvent.qrCode == qrCode ||
          qrCode.contains(targetEvent.id) ||
          qrCode.contains('id=${targetEvent.id}') ||
          qrCode.startsWith('IIAP-EVT-${targetEvent.id}');
      if (!matches) {
        throw ApiException('El código QR no corresponde a este evento institucional.');
      }
    }

    final newAttendee = EventAttendeeModel(
      id: 'att_${DateTime.now().millisecondsSinceEpoch}',
      userId: currentUser.id,
      userName: currentUser.fullName,
      userEmail: currentUser.email,
      userPosition: currentUser.position,
      userDepartment: currentUser.department,
      documentNumber: currentUser.documentNumber,
      phoneNumber: currentUser.phoneNumber,
      isExternal: false,
      shift: shift,
      registeredAt: DateTime.now(),
      notes: 'Asistencia registrada con éxito',
    );

    final updatedAttendees = List<EventAttendeeModel>.from(targetEvent.attendees)..add(newAttendee);
    final updatedEvent = targetEvent.copyWith(
      attendees: updatedAttendees,
      attendeesCount: updatedAttendees.length,
    );

    list[idx] = updatedEvent;
    eventsNotifier.value = list;
    await _saveToLocalCache(list);
    return updatedEvent;
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
