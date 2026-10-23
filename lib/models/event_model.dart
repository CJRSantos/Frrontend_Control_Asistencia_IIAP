// ignore_for_file: constant_identifier_names

enum EventType {
  CAPACITACION,
  REUNION,
  INSTITUCIONAL,
  TALLER,
  CONFERENCIA,
  OTRO;

  static EventType fromString(String? value) {
    switch (value?.toUpperCase()) {
      case 'CAPACITACION':
        return EventType.CAPACITACION;
      case 'REUNION':
        return EventType.REUNION;
      case 'INSTITUCIONAL':
        return EventType.INSTITUCIONAL;
      case 'TALLER':
        return EventType.TALLER;
      case 'CONFERENCIA':
        return EventType.CONFERENCIA;
      case 'OTRO':
      default:
        return EventType.OTRO;
    }
  }

  String get displayName {
    switch (this) {
      case EventType.CAPACITACION:
        return 'Capacitación';
      case EventType.REUNION:
        return 'Reunión';
      case EventType.INSTITUCIONAL:
        return 'Institucional';
      case EventType.TALLER:
        return 'Taller';
      case EventType.CONFERENCIA:
        return 'Conferencia';
      case EventType.OTRO:
        return 'General';
    }
  }
}

enum EventStatus {
  UPCOMING,
  ACTIVE,
  COMPLETED,
  CANCELLED;

  static EventStatus fromString(String? value) {
    switch (value?.toUpperCase()) {
      case 'ACTIVE':
      case 'EN_CURSO':
        return EventStatus.ACTIVE;
      case 'COMPLETED':
      case 'FINALIZADO':
        return EventStatus.COMPLETED;
      case 'CANCELLED':
      case 'CANCELADO':
        return EventStatus.CANCELLED;
      case 'UPCOMING':
      case 'PROGRAMADO':
      default:
        return EventStatus.UPCOMING;
    }
  }

  String get displayName {
    switch (this) {
      case EventStatus.UPCOMING:
        return 'Próximo';
      case EventStatus.ACTIVE:
        return 'En Curso';
      case EventStatus.COMPLETED:
        return 'Finalizado';
      case EventStatus.CANCELLED:
        return 'Cancelado';
    }
  }
}

class EventShift {
  final String name; // 'MANANA', 'TARDE', 'NOCHE'
  final String label; // 'Turno Mañana', 'Turno Tarde', 'Turno Noche'
  final String startTime; // '08:30'
  final String endTime; // '12:30'
  final bool enabled;

  EventShift({
    required this.name,
    required this.label,
    required this.startTime,
    required this.endTime,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'label': label,
    'start_time': startTime,
    'end_time': endTime,
    'enabled': enabled,
  };

  factory EventShift.fromJson(Map<String, dynamic> json) => EventShift(
    name: json['name']?.toString() ?? '',
    label: json['label']?.toString() ?? '',
    startTime: json['start_time']?.toString() ?? json['startTime']?.toString() ?? '',
    endTime: json['end_time']?.toString() ?? json['endTime']?.toString() ?? '',
    enabled: json['enabled'] != false,
  );
}

class EventAttendeeModel {
  final String id;
  final String userId;
  final String userName;
  final String userEmail;
  final String? userPosition;
  final String? userDepartment;
  final String? documentNumber;
  final String? phoneNumber;
  final String? gender;
  final int? age;
  final String? career;
  final String? institution;
  final bool isExternal;
  final DateTime registeredAt;
  final String? notes;
  final String? shift;
  final String? photoUrl;

  EventAttendeeModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userEmail,
    this.userPosition,
    this.userDepartment,
    this.documentNumber,
    this.phoneNumber,
    this.gender,
    this.age,
    this.career,
    this.institution,
    this.isExternal = false,
    required this.registeredAt,
    this.notes,
    this.shift,
    this.photoUrl,
  });

  factory EventAttendeeModel.fromJson(Map<String, dynamic> json) {
    return EventAttendeeModel(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      userName: json['user_name']?.toString() ?? json['userName']?.toString() ?? 'Participante',
      userEmail: json['user_email']?.toString() ?? json['userEmail']?.toString() ?? '',
      userPosition: json['user_position']?.toString() ?? json['userPosition']?.toString(),
      userDepartment: json['user_department']?.toString() ?? json['userDepartment']?.toString(),
      documentNumber: json['document_number']?.toString() ?? json['documentNumber']?.toString() ?? json['dni']?.toString(),
      phoneNumber: json['phone_number']?.toString() ?? json['phoneNumber']?.toString() ?? json['telefono']?.toString(),
      gender: json['gender']?.toString() ?? json['sexo']?.toString(),
      age: (json['age'] as num?)?.toInt() ?? (json['edad'] as num?)?.toInt(),
      career: json['career']?.toString() ?? json['carrera']?.toString(),
      institution: json['institution']?.toString() ?? json['institucion']?.toString() ?? json['user_department']?.toString(),
      isExternal: json['is_external'] == true || json['isExternal'] == true,
      registeredAt: json['registered_at'] != null
          ? (DateTime.tryParse(json['registered_at'].toString())?.toLocal() ?? DateTime.now())
          : (json['registeredAt'] != null
              ? (DateTime.tryParse(json['registeredAt'].toString())?.toLocal() ?? DateTime.now())
              : DateTime.now()),
      notes: json['notes']?.toString(),
      shift: json['shift']?.toString(),
      photoUrl: json['photo_url']?.toString() ??
          json['photoUrl']?.toString() ??
          json['user_photo']?.toString() ??
          json['avatar_url']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'user_name': userName,
      'user_email': userEmail,
      'user_position': userPosition,
      'user_department': userDepartment,
      'document_number': documentNumber,
      'phone_number': phoneNumber,
      'gender': gender,
      'age': age,
      'career': career,
      'institution': institution,
      'is_external': isExternal,
      'registered_at': registeredAt.toIso8601String(),
      'notes': notes,
      'shift': shift,
      'photo_url': photoUrl,
    };
  }
}

class EventModel {
  final String id;
  final String title;
  final String description;
  final String location;
  final DateTime startDate;
  final DateTime endDate;
  final EventType type;
  final bool requiresAttendance;
  final String? qrCode;
  final String createdById;
  final String createdByName;
  final String createdByRole;
  final DateTime createdAt;
  final EventStatus status;
  final int attendeesCount;
  final List<EventAttendeeModel> attendees;
  final List<String> managerIds;
  final String? organizationalUnit;
  final List<EventShift> shifts;
  final String? imageUrl;
  final String? externalSource;
  final String? externalId;

  EventModel({
    required this.id,
    required this.title,
    required this.description,
    required this.location,
    required this.startDate,
    required this.endDate,
    required this.type,
    this.requiresAttendance = true,
    this.qrCode,
    required this.createdById,
    required this.createdByName,
    required this.createdByRole,
    required this.createdAt,
    this.status = EventStatus.UPCOMING,
    this.attendeesCount = 0,
    this.attendees = const [],
    this.managerIds = const [],
    this.organizationalUnit,
    this.shifts = const [],
    this.imageUrl,
    this.externalSource,
    this.externalId,
  });

  /// Identifica si el evento fue creado por el Sistema de Eventos (espejo)
  bool get isEventosMirror =>
      externalSource == 'EVENTOS' || (qrCode != null && qrCode!.startsWith('EVENTOS-'));

  bool canUserManageEvent(String? userId, String? userRole) {
    if (userId == null) return false;
    final r = (userRole ?? '').toUpperCase();
    if (r == 'SUPERADMIN' || r == 'ADMIN' || r == 'SUPERVISOR' || r == 'ADMIN_EVENTO') return true;
    if (createdById == userId) return true;
    return managerIds.contains(userId);
  }

  bool get isActiveNow {
    final now = DateTime.now();
    return now.isAfter(startDate.subtract(const Duration(minutes: 30))) &&
        now.isBefore(endDate.add(const Duration(minutes: 30))) &&
        status != EventStatus.CANCELLED;
  }

  bool isUserRegistered(String userId) {
    return attendees.any((a) => a.userId == userId);
  }

  factory EventModel.fromJson(Map<String, dynamic> json) {
    var rawAttendees = json['attendees'];
    List<EventAttendeeModel> attendeesList = [];
    if (rawAttendees is List) {
      attendeesList = rawAttendees
          .whereType<Map<String, dynamic>>()
          .map((item) => EventAttendeeModel.fromJson(item))
          .toList();
      attendeesList.sort((a, b) => a.registeredAt.compareTo(b.registeredAt));
    }

    final start = json['start_date'] != null
        ? (DateTime.tryParse(json['start_date'].toString())?.toLocal() ?? DateTime.now())
        : (json['startDate'] != null
            ? (DateTime.tryParse(json['startDate'].toString())?.toLocal() ?? DateTime.now())
            : DateTime.now());

    final end = json['end_date'] != null
        ? (DateTime.tryParse(json['end_date'].toString())?.toLocal() ?? start.add(const Duration(hours: 1)))
        : (json['endDate'] != null
            ? (DateTime.tryParse(json['endDate'].toString())?.toLocal() ?? start.add(const Duration(hours: 1)))
            : start.add(const Duration(hours: 1)));

    // Parse manager_ids (simple-array or list)
    List<String> parsedManagerIds = [];
    var rawShifts = json['shifts'];
    List<EventShift> parsedShifts = [];
    if (rawShifts is List) {
      parsedShifts = rawShifts
          .whereType<Map<String, dynamic>>()
          .map((item) => EventShift.fromJson(item))
          .toList();
    }

    final rawManagers = json['manager_ids'] ?? json['managerIds'];
    if (rawManagers is List) {
      parsedManagerIds = rawManagers.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    } else if (rawManagers is String && rawManagers.trim().isNotEmpty) {
      parsedManagerIds = rawManagers.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }

    return EventModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      location: json['location']?.toString() ?? 'IIAP - Sede Central',
      startDate: start,
      endDate: end,
      type: EventType.fromString(json['type']?.toString()),
      requiresAttendance: json['requires_attendance'] == true || json['requiresAttendance'] == true,
      qrCode: json['qr_code']?.toString() ?? json['qrCode']?.toString(),
      createdById: json['created_by_id']?.toString() ?? json['createdById']?.toString() ?? '',
      createdByName: json['created_by_name']?.toString() ?? json['createdByName']?.toString() ?? 'Administrador',
      createdByRole: json['created_by_role']?.toString() ?? json['createdByRole']?.toString() ?? 'ADMIN',
      createdAt: json['created_at'] != null
          ? (DateTime.tryParse(json['created_at'].toString())?.toLocal() ?? DateTime.now())
          : (json['createdAt'] != null
              ? (DateTime.tryParse(json['createdAt'].toString())?.toLocal() ?? DateTime.now())
              : DateTime.now()),
      status: EventStatus.fromString(json['status']?.toString()),
      attendeesCount: (json['attendees_count'] as num?)?.toInt() ??
          (json['attendeesCount'] as num?)?.toInt() ??
          attendeesList.length,
      attendees: attendeesList,
      managerIds: parsedManagerIds,
      organizationalUnit: json['organizational_unit']?.toString() ?? json['organizationalUnit']?.toString(),
      shifts: parsedShifts,
      imageUrl: json['image_url']?.toString() ??
          json['imageUrl']?.toString() ??
          json['cover_image']?.toString() ??
          json['coverImage']?.toString() ??
          json['image']?.toString() ??
          json['photo_url']?.toString() ??
          json['photoUrl']?.toString() ??
          json['banner_url']?.toString(),
      externalSource: json['external_source']?.toString() ?? json['externalSource']?.toString(),
      externalId: json['external_id']?.toString() ?? json['externalId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'location': location,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'type': type.name,
      'requires_attendance': requiresAttendance,
      'qr_code': qrCode,
      'created_by_id': createdById,
      'created_by_name': createdByName,
      'created_by_role': createdByRole,
      'created_at': createdAt.toIso8601String(),
      'status': status.name,
      'attendees_count': attendeesCount,
      'attendees': attendees.map((a) => a.toJson()).toList(),
      'manager_ids': managerIds,
      'organizational_unit': organizationalUnit,
      'shifts': shifts.map((s) => s.toJson()).toList(),
      'image_url': imageUrl,
      if (externalSource != null) 'external_source': externalSource,
      if (externalId != null) 'external_id': externalId,
    };
  }

  EventModel copyWith({
    String? id,
    String? title,
    String? description,
    String? location,
    DateTime? startDate,
    DateTime? endDate,
    EventType? type,
    bool? requiresAttendance,
    String? qrCode,
    String? createdById,
    String? createdByName,
    String? createdByRole,
    DateTime? createdAt,
    EventStatus? status,
    int? attendeesCount,
    List<EventAttendeeModel>? attendees,
    List<String>? managerIds,
    String? organizationalUnit,
    List<EventShift>? shifts,
    String? imageUrl,
    String? externalSource,
    String? externalId,
  }) {
    return EventModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      location: location ?? this.location,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      type: type ?? this.type,
      requiresAttendance: requiresAttendance ?? this.requiresAttendance,
      qrCode: qrCode ?? this.qrCode,
      createdById: createdById ?? this.createdById,
      createdByName: createdByName ?? this.createdByName,
      createdByRole: createdByRole ?? this.createdByRole,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      attendeesCount: attendeesCount ?? this.attendeesCount,
      attendees: attendees ?? this.attendees,
      managerIds: managerIds ?? this.managerIds,
      organizationalUnit: organizationalUnit ?? this.organizationalUnit,
      shifts: shifts ?? this.shifts,
      imageUrl: imageUrl ?? this.imageUrl,
      externalSource: externalSource ?? this.externalSource,
      externalId: externalId ?? this.externalId,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EventModel &&
        other.id == id &&
        other.title == title &&
        other.description == description &&
        other.location == location &&
        other.startDate == startDate &&
        other.endDate == endDate &&
        other.type == type &&
        other.status == status &&
        other.imageUrl == imageUrl &&
        other.attendeesCount == attendeesCount &&
        other.attendees.length == attendees.length &&
        other.managerIds.length == managerIds.length &&
        other.shifts.length == shifts.length;
  }

  @override
  int get hashCode => Object.hash(
        id,
        title,
        description,
        location,
        startDate,
        endDate,
        type,
        status,
        imageUrl,
        attendeesCount,
        attendees.length,
        managerIds.length,
      );
}
