import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  static const String _customHostKey = 'custom_backend_host';
  static const String _customFacialHostKey = 'custom_facial_host';

  // Variables de Entorno (inyección vía .env o --dart-define)
  // API principal NestJS (por defecto en red local)
  static const String defaultLocalBaseUrl = 'http://192.168.1.100:3000/api';

  // Microservicio facial (acceso directo desde Flutter para extraer embeddings)
  static const String defaultFacialServiceUrl = 'http://192.168.1.100:8000';

  // Variables de Entorno (inyección vía .env o --dart-define para producción o flavors)
  static const String envBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: defaultLocalBaseUrl,
  );

  static const String envFacialBaseUrl = String.fromEnvironment(
    'FACIAL_SERVICE_BASE_URL',
    defaultValue: defaultFacialServiceUrl,
  );

  static const String envGoogleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '546116812966-hr7pd2htl3e2na61skqmihg7jkbdf9m8.apps.googleusercontent.com',
  );

  static const String envGoogleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '546116812966-aijkt8hrbhaue2uaj2d5cbem1nlspa9v.apps.googleusercontent.com',
  );

  static const String envGoogleDesktopClientId = String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_ID',
    defaultValue: '',
  );

  static const int googleLoopbackPort = 8585;

  static const String envAppPackageNameAndroid = String.fromEnvironment(
    'APP_PACKAGE_NAME_ANDROID',
    defaultValue: 'pe.gob.iiap.attendance',
  );

  static const String envAppPackageNameIos = String.fromEnvironment(
    'APP_PACKAGE_NAME_IOS',
    defaultValue: 'pe.gob.iiap.attendance',
  );

  // Dominio independiente para el formulario público de registro de asistencia a eventos
  static const String defaultPublicRegistrationUrl = 'https://dev-registro-eventos.iiap.gob.pe';

  static const String envPublicRegistrationUrl = String.fromEnvironment(
    'EVENT_PUBLIC_REGISTRATION_URL',
    defaultValue: defaultPublicRegistrationUrl,
  );

  // Obtiene la URL base adecuada según el entorno de ejecución
  static String get defaultBaseUrl => envBaseUrl;
  static const String localWifiUrl = 'http://192.168.1.100:3000/api';
  static const String localWifiFacialUrl = 'http://192.168.1.100:8000';
  static const String androidEmulatorUrl = 'http://10.0.2.2:3000/api';
  static String get defaultFacialBaseUrl => envFacialBaseUrl;

  static String _currentBaseUrl = defaultBaseUrl;
  static String _currentFacialBaseUrl = defaultFacialBaseUrl;

  // API principal NestJS
  static String get baseUrl => _currentBaseUrl;

  // Microservicio facial (acceso directo desde Flutter para extraer embeddings)
  static String get facialServiceUrl => _currentFacialBaseUrl;
  static String get facialServiceBaseUrl => _currentFacialBaseUrl;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_customHostKey);
    if (saved != null && saved.trim().isNotEmpty) {
      _currentBaseUrl = saved.trim();
    } else {
      _currentBaseUrl = defaultBaseUrl;
    }

    final savedFacial = prefs.getString(_customFacialHostKey);
    if (savedFacial != null && savedFacial.trim().isNotEmpty) {
      _currentFacialBaseUrl = savedFacial.trim();
    } else {
      _currentFacialBaseUrl = defaultFacialBaseUrl;
    }
  }

  static Future<void> setCustomBaseUrl(String url) async {
    final trimmed = url.trim();
    _currentBaseUrl = trimmed.isEmpty ? defaultBaseUrl : trimmed;
    final prefs = await SharedPreferences.getInstance();
    if (trimmed.isEmpty) {
      await prefs.remove(_customHostKey);
    } else {
      await prefs.setString(_customHostKey, trimmed);
    }
  }

  static Future<void> setCustomFacialBaseUrl(String url) async {
    final trimmed = url.trim();
    _currentFacialBaseUrl = trimmed.isEmpty ? defaultFacialBaseUrl : trimmed;
    final prefs = await SharedPreferences.getInstance();
    if (trimmed.isEmpty) {
      await prefs.remove(_customFacialHostKey);
    } else {
      await prefs.setString(_customFacialHostKey, trimmed);
    }
  }

  // Rutas de la API
  static String get authRegister => '$baseUrl/auth/register';
  static String get authLogin => '$baseUrl/auth/login';
  static String get authMe => '$baseUrl/auth/me';
  static String get authForgotPassword => '$baseUrl/auth/forgot-password';
  static String get authResetPassword => '$baseUrl/auth/reset-password';
  static String get authGoogle => '$baseUrl/auth/google';
  static String get authChangePassword => '$baseUrl/auth/change-password';
  static String get authDeleteAccount => '$baseUrl/auth/delete-account';
  static String get authRequestEmailChange => '$baseUrl/auth/request-email-change';
  static String get authConfirmEmailChange => '$baseUrl/auth/confirm-email-change';
  static String get googleServerClientId => envGoogleServerClientId;
  static String get googleIosClientId => envGoogleIosClientId;
  static String get googleDesktopClientId =>
      envGoogleDesktopClientId.isNotEmpty ? envGoogleDesktopClientId : envGoogleServerClientId;
  static String get appPackageNameAndroid => envAppPackageNameAndroid;
  static String get appPackageNameIos => envAppPackageNameIos;

  static String get usersMe => '$baseUrl/users/me';
  static String get usersAll => '$baseUrl/users';
  static String get usersSupervisors => '$baseUrl/users/supervisors';
  static String userById(String id) => '$baseUrl/users/$id';
  static String userRevokeSupervisor(String id) => '$baseUrl/users/supervisors/$id';
  static String userRole(String id) => '$baseUrl/users/$id/role';
  static String userDevice(String id) => '$baseUrl/users/$id/device';
  static String get uploadPhotoBase64 => '$baseUrl/users/me/photo-base64';

  static String get attendanceGenerateQr => '$baseUrl/attendance/generate-qr';
  static String get attendanceActiveQr => '$baseUrl/attendance/active-qr';
  static String get attendanceGenerateSupervisorQr => '$baseUrl/attendance/generate-supervisor-qr';
  static String get attendanceScanQr => '$baseUrl/attendance/scan-qr';
  static String get attendanceScanSupervisorQr => '$baseUrl/attendance/scan-supervisor-qr';
  static String get attendanceMyRecords => '$baseUrl/attendance/my-records';
  static String get attendanceToday => '$baseUrl/attendance/today';
  static String get attendanceAll => '$baseUrl/attendance/all';
  static String get attendanceManualRecord => '$baseUrl/attendance/manual-record';
  static String get attendancePendingCheckouts => '$baseUrl/attendance/pending-checkouts';
  static String get attendanceWeeklyReset => '$baseUrl/attendance/weekly-reset';
  static String get attendanceCorrectJourney => '$baseUrl/attendance/correct-journey';
  static String attendanceById(String id) => '$baseUrl/attendance/$id';

  static String get attendanceGenerateAssignmentQr => '$baseUrl/attendance/generate-assignment-qr';
  static String get attendanceScanAssignmentQr => '$baseUrl/attendance/scan-assignment-qr';
  static String get attendanceFacialRecord => '$baseUrl/attendance/facial-record';
  static String get attendanceFacialRecognition => '$baseUrl/attendance/facial-recognition';

  // Rutas del Servicio Biometrico Facial (Python - InsightFace & OpenCV)
  static String get facialScanWebcam => '$facialServiceBaseUrl/api/scan/webcam';
  static String get facialScanImage => '$facialServiceBaseUrl/api/scan/image';
  static String get facialStatus => '$facialServiceBaseUrl/api/status';

  // Rutas de Eventos
  static String get eventsAll => '$baseUrl/events';
  static String eventById(String id) => '$baseUrl/events/$id';
  static String eventRegisterAttendance(String id) => '$baseUrl/events/$id/attendance';
  static String eventGenerateQr(String id) => '$baseUrl/events/$id/qr';
  static String eventAttendees(String id) => '$baseUrl/events/$id/attendees';
  static String eventDeleteAttendee(String eventId, String attendeeId) => '$baseUrl/events/$eventId/attendees/$attendeeId';
  static String eventManagers(String id) => '$baseUrl/events/$id/managers';
  static String eventRemoveManager(String eventId, String userId) => '$baseUrl/events/$eventId/managers/$userId';

  /// URL web pública independiente para que cualquier persona sin la app escanee con la cámara de su celular
  static String eventPublicRegistrationUrl(String eventId) {
    final domain = envPublicRegistrationUrl.replaceAll(RegExp(r'/$'), '');
    return '$domain/registro.html?id=$eventId';
  }
}


