import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'storage_service.dart';

class ApiException implements Exception {
  final String message;
  final int statusCode;

  ApiException(this.message, [this.statusCode = 400]);

  @override
  String toString() => message;
}

class ApiClient {
  // Cliente HTTP compartido y persistente para reutilizar conexiones TCP y TLS (Keep-Alive)
  static final http.Client _client = http.Client();

  static Future<Map<String, String>> _headers({bool requiresAuth = true}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (requiresAuth) {
      // Priorizar token en RAM (0 ms) sin bloquear el hilo de I/O
      final token = StorageService.tokenSync ?? await StorageService.getToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  static dynamic _processResponse(http.Response response) {
    dynamic body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      body = null;
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    String errorMessage = 'Ocurrió un error en el servidor (${response.statusCode})';
    if (body is Map && body.containsKey('message')) {
      final msg = body['message'];
      if (msg is List) {
        errorMessage = msg.join('\n');
      } else if (msg != null && msg.toString().trim().isNotEmpty) {
        errorMessage = msg.toString().trim();
      }
    } else if (response.statusCode == 401) {
      errorMessage = 'Sesión no autorizada o expirada. Inicia sesión nuevamente.';
    }

    // NUNCA cerramos sesión automáticamente por un 401. La cuenta del usuario se preserva siempre (estilo redes sociales).
    throw ApiException(errorMessage, response.statusCode);
  }

  static Future<dynamic> get(String url, {bool requiresAuth = true}) async {
    try {
      final headers = await _headers(requiresAuth: requiresAuth);
      final response = await _client
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));

      // Si el token expiró, re-autenticar de fondo silenciosamente y reintentar 1 vez
      if (response.statusCode == 401 && requiresAuth) {
        final reauthenticated = await AuthService.trySilentRelogin();
        if (reauthenticated) {
          final retryHeaders = await _headers(requiresAuth: requiresAuth);
          final retryResponse = await _client
              .get(Uri.parse(url), headers: retryHeaders)
              .timeout(const Duration(seconds: 15));
          return _processResponse(retryResponse);
        }
      }

      return _processResponse(response);
    } on SocketException {
      throw ApiException('No se pudo conectar con el servidor backend. Verifique que esté encendido.');
    } on http.ClientException {
      throw ApiException('Error de conexión con la red o el servidor.');
    }
  }

  static Future<dynamic> post(
    String url, {
    Map<String, dynamic>? body,
    bool requiresAuth = true,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      final headers = await _headers(requiresAuth: requiresAuth);
      final response = await _client
          .post(
            Uri.parse(url),
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeout);

      // Si el token expiró, re-autenticar de fondo silenciosamente y reintentar 1 vez
      if (response.statusCode == 401 && requiresAuth) {
        final reauthenticated = await AuthService.trySilentRelogin();
        if (reauthenticated) {
          final retryHeaders = await _headers(requiresAuth: requiresAuth);
          final retryResponse = await _client
              .post(
                Uri.parse(url),
                headers: retryHeaders,
                body: body != null ? jsonEncode(body) : null,
              )
              .timeout(timeout);
          return _processResponse(retryResponse);
        }
      }

      return _processResponse(response);
    } on SocketException {
      throw ApiException('No se pudo conectar con el servidor backend. Verifique que esté encendido.');
    } on http.ClientException {
      throw ApiException('Error de conexión con la red o el servidor.');
    }
  }

  static Future<dynamic> patch(String url, {Map<String, dynamic>? body, bool requiresAuth = true}) async {
    try {
      final headers = await _headers(requiresAuth: requiresAuth);
      final response = await _client
          .patch(
            Uri.parse(url),
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 15));

      // Si el token expiró, re-autenticar de fondo silenciosamente y reintentar 1 vez
      if (response.statusCode == 401 && requiresAuth) {
        final reauthenticated = await AuthService.trySilentRelogin();
        if (reauthenticated) {
          final retryHeaders = await _headers(requiresAuth: requiresAuth);
          final retryResponse = await _client
              .patch(
                Uri.parse(url),
                headers: retryHeaders,
                body: body != null ? jsonEncode(body) : null,
              )
              .timeout(const Duration(seconds: 15));
          return _processResponse(retryResponse);
        }
      }

      return _processResponse(response);
    } on SocketException {
      throw ApiException('No se pudo conectar con el servidor backend. Verifique que esté encendido.');
    } on http.ClientException {
      throw ApiException('Error de conexión con la red o el servidor.');
    }
  }

  static Future<dynamic> delete(String url, {Map<String, dynamic>? body, bool requiresAuth = true}) async {
    try {
      final headers = await _headers(requiresAuth: requiresAuth);
      final response = await _client
          .delete(
            Uri.parse(url),
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 15));

      // Si el token expiró, re-autenticar de fondo silenciosamente y reintentar 1 vez
      if (response.statusCode == 401 && requiresAuth) {
        final reauthenticated = await AuthService.trySilentRelogin();
        if (reauthenticated) {
          final retryHeaders = await _headers(requiresAuth: requiresAuth);
          final retryResponse = await _client
              .delete(
                Uri.parse(url),
                headers: retryHeaders,
                body: body != null ? jsonEncode(body) : null,
              )
              .timeout(const Duration(seconds: 15));
          return _processResponse(retryResponse);
        }
      }

      return _processResponse(response);
    } on SocketException {
      throw ApiException('No se pudo conectar con el servidor backend. Verifique que esté encendido.');
    } on http.ClientException {
      throw ApiException('Error de conexión con la red o el servidor.');
    }
  }
}
