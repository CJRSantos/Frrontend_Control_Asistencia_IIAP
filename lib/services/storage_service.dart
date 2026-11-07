import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';

class StorageService {
  static const String _keyToken = 'auth_token';
  static const String _keyUserData = 'auth_user_data';
  static const String _keyDeviceId = 'unique_device_id_v1';
  static const String _keySavedEmail = 'auth_saved_email';
  static const String _keySavedPassword = 'auth_saved_password';

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Obtiene o genera un identificador único persistente para este celular (Anti-Préstamo)
  static Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(_keyDeviceId);
    if (deviceId == null || deviceId.isEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final rand = (now ^ 0x5DEECE66D).abs().toRadixString(16);
      deviceId = 'device_${now}_$rand';
      await prefs.setString(_keyDeviceId, deviceId);
    }
    return deviceId;
  }

  static String? _cachedToken;
  static String? get tokenSync => _cachedToken;
  static UserModel? get currentUser => currentUserNotifier.value;
  static final ValueNotifier<UserModel?> currentUserNotifier = ValueNotifier<UserModel?>(null);
  static final ValueNotifier<bool> isAuthenticatedNotifier = ValueNotifier<bool>(false);

  static bool get hasSession =>
      currentUserNotifier.value != null &&
      _cachedToken != null &&
      _cachedToken!.isNotEmpty;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_keyToken);
    final userJson = prefs.getString(_keyUserData);
    _cachedToken = token;

    if (userJson != null && userJson.isNotEmpty) {
      try {
        final map = jsonDecode(userJson) as Map<String, dynamic>;
        var user = UserModel.fromJson(map);
        // Si el usuario en caché aún tenía el rol forzado a SUPERVISOR de la prueba previa, revertir a USER
        if (user.role == UserRole.SUPERVISOR &&
            (user.fullName.toLowerCase().contains('christopher') ||
                user.fullName.toLowerCase().contains('rengifo'))) {
          user = user.copyWith(role: UserRole.USER);
          await prefs.setString(_keyUserData, jsonEncode(user.toJson()));
        }
        currentUserNotifier.value = user;
        isAuthenticatedNotifier.value = (token != null && token.isNotEmpty);
      } catch (e) {
        debugPrint('Error decodificando usuario en caché: $e');
        if (token != null && token.isNotEmpty) {
          currentUserNotifier.value = _extractUserFromJwt(token);
          isAuthenticatedNotifier.value = true;
        }
      }
    } else if (token != null && token.isNotEmpty) {
      currentUserNotifier.value = _extractUserFromJwt(token);
      isAuthenticatedNotifier.value = true;
    } else {
      currentUserNotifier.value = null;
      isAuthenticatedNotifier.value = false;
    }
  }

  /// Extrae un usuario de contingencia desde el payload del token JWT si los datos de disco fallan
  static UserModel? _extractUserFromJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      var normalized = base64Url.normalize(parts[1]);
      final payloadString = utf8.decode(base64Url.decode(normalized));
      final map = jsonDecode(payloadString) as Map<String, dynamic>;
      final sub = map['sub']?.toString() ?? '';
      final email = map['email']?.toString() ?? '';
      final role = UserRole.fromString(map['role']?.toString());
      final fullName = map['full_name']?.toString() ?? map['name']?.toString() ?? (email.isNotEmpty ? email.split('@').first : 'Usuario');
      if (sub.isNotEmpty) {
        return UserModel(
          id: sub,
          email: email,
          fullName: fullName,
          role: role,
        );
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> getToken() async {
    if (_cachedToken != null && _cachedToken!.isNotEmpty) {
      return _cachedToken;
    }
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString(_keyToken);
    return _cachedToken;
  }

  static Future<void> updateToken(String newToken) async {
    _cachedToken = newToken;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, newToken);
  }

  static Future<Map<String, String>?> getSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_keySavedEmail);
    final password = prefs.getString(_keySavedPassword);
    if (email != null && email.isNotEmpty && password != null && password.isNotEmpty) {
      return {'email': email, 'password': password};
    }
    return null;
  }

  static Future<void> saveSession({
    required String token,
    required UserModel user,
    String? email,
    String? password,
  }) async {
    _cachedToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
    await prefs.setString(_keyUserData, jsonEncode(user.toJson()));

    if (email != null && email.isNotEmpty) {
      await prefs.setString(_keySavedEmail, email.trim().toLowerCase());
    }
    if (password != null && password.isNotEmpty) {
      await prefs.setString(_keySavedPassword, password);
    }

    currentUserNotifier.value = user;
    isAuthenticatedNotifier.value = true;
  }

  static Future<void> updateCurrentUser(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserData, jsonEncode(user.toJson()));
    currentUserNotifier.value = user;
  }

  /// Limpia la sesión SOLO cuando se cierra sesión voluntariamente o el backend rechaza definitivamente las credenciales
  static Future<void> clearSession() async {
    _cachedToken = null;
    currentUserNotifier.value = null;
    isAuthenticatedNotifier.value = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyUserData);
    await prefs.remove(_keySavedEmail);
    await prefs.remove(_keySavedPassword);
  }
}
