import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import '../models/user_model.dart';
import 'api_client.dart';
import 'storage_service.dart';
import 'desktop_oauth_service.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    final response = await ApiClient.post(
      ApiConfig.authLogin,
      body: {
        'email': email.trim().toLowerCase(),
        'password': password,
      },
      requiresAuth: false,
    );

    final token = response['access_token']?.toString() ?? '';
    final userJson = response['user'] as Map<String, dynamic>;
    final user = UserModel.fromJson(userJson);

    await StorageService.saveSession(
      token: token,
      user: user,
      email: email,
      password: password,
    );
    return user;
  }

  static Future<UserModel> register({
    required String fullName,
    required String email,
    required String password,
    String? documentNumber,
    String? phoneNumber,
  }) async {
    final body = <String, dynamic>{
      'full_name': fullName.trim(),
      'email': email.trim().toLowerCase(),
      'password': password,
    };

    if (documentNumber != null && documentNumber.trim().isNotEmpty) {
      body['document_number'] = documentNumber.trim();
    }
    if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
      body['phone_number'] = phoneNumber.trim();
    }

    final response = await ApiClient.post(
      ApiConfig.authRegister,
      body: body,
      requiresAuth: false,
    );

    final token = response['access_token']?.toString() ?? '';
    final userJson = response['user'] as Map<String, dynamic>;
    final user = UserModel.fromJson(userJson);

    await StorageService.saveSession(
      token: token,
      user: user,
      email: email,
      password: password,
    );
    return user;
  }

  static bool _isSilentLoggingIn = false;

  /// Re-autentica de forma transparente en segundo plano si el token expiró (estilo redes sociales)
  static Future<bool> trySilentRelogin() async {
    if (_isSilentLoggingIn) return false;
    _isSilentLoggingIn = true;
    try {
      final creds = await StorageService.getSavedCredentials();
      if (creds == null) return false;

      final email = creds['email'];
      final password = creds['password'];
      if (email == null || password == null) return false;

      final response = await ApiClient.post(
        ApiConfig.authLogin,
        body: {
          'email': email.trim().toLowerCase(),
          'password': password,
        },
        requiresAuth: false,
      );

      final token = response['access_token']?.toString() ?? '';
      final userJson = response['user'] as Map<String, dynamic>;
      final user = UserModel.fromJson(userJson);

      await StorageService.saveSession(
        token: token,
        user: user,
        email: email,
        password: password,
      );
      debugPrint('Sesión revalidada silenciosamente con éxito');
      return true;
    } catch (e) {
      debugPrint('Re-autenticación silenciosa en espera de conexión: $e');
      return false;
    } finally {
      _isSilentLoggingIn = false;
    }
  }

  /// Valida o refresca el token en segundo plano de manera no bloqueante.
  /// Si el backend responde 401/403 (sesión revocada o credenciales cambiadas) y falla el re-login silencioso,
  /// limpia la sesión y retorna false para que la app redirija al login.
  /// Si el dispositivo no tiene internet o hay un error de red/servidor, retorna true y mantiene la sesión offline.
  static Future<bool> validateSessionInBackground() async {
    try {
      final token = await StorageService.getToken();
      if (token == null || token.isEmpty) {
        return false;
      }

      final response = await http
          .get(
            Uri.parse(ApiConfig.authMe),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final user = UserModel.fromJson(data);
        final String? currentPhoto = StorageService.currentUser?.photoUrl;
        final String? effectivePhoto = (user.photoUrl != null && user.photoUrl!.trim().isNotEmpty)
            ? user.photoUrl
            : ((currentPhoto != null && currentPhoto.trim().isNotEmpty) ? currentPhoto : null);
        final preservedUser = user.copyWith(photoUrl: effectivePhoto);
        await StorageService.updateCurrentUser(preservedUser);
        return true;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        final reauthenticated = await trySilentRelogin();
        if (reauthenticated) {
          return true;
        }
        // Preservar la sesión localmente estilo redes sociales (no cerrar sesión automáticamente)
        return false;
      }

      // Códigos de error de servidor (500, 502, etc.): preservar sesión offline
      return true;
    } on SocketException {
      // Dispositivo offline: preservar sesión localmente
      return true;
    } on http.ClientException {
      return true;
    } on TimeoutException {
      return true;
    } catch (e) {
      debugPrint('validateSessionInBackground ignorado por offline/red: $e');
      return true;
    }
  }

  static Future<UserModel> getProfile() async {
    final response = await ApiClient.get(ApiConfig.authMe);
    final user = UserModel.fromJson(response as Map<String, dynamic>);
    final String? currentPhoto = StorageService.currentUser?.photoUrl;
    final String? effectivePhoto = (user.photoUrl != null && user.photoUrl!.trim().isNotEmpty)
        ? user.photoUrl
        : ((currentPhoto != null && currentPhoto.trim().isNotEmpty) ? currentPhoto : null);
    final preservedUser = user.copyWith(photoUrl: effectivePhoto);
    await StorageService.updateCurrentUser(preservedUser);
    return preservedUser;
  }

  static String? get _configuredClientId {
    if (kIsWeb) return ApiConfig.googleServerClientId;
    try {
      if (Platform.isIOS) return ApiConfig.googleIosClientId;
    } catch (_) {}
    return null;
  }

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: _configuredClientId,
    serverClientId: ApiConfig.googleServerClientId,
    scopes: ['email', 'profile'],
  );

  /// Inicia sesion o registra al usuario mediante Google OAuth2 con blindaje multiplataforma (Android, iOS, Web y Windows Desktop)
  static Future<UserModel?> loginWithGoogle() async {
    String? idToken;

    // 1. En plataformas de escritorio (Windows, Linux, macOS), usar OAuth 2.0 Loopback con PKCE
    bool isDesktop = false;
    if (!kIsWeb) {
      try {
        isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
      } catch (_) {}
    }

    if (isDesktop) {
      debugPrint('[AuthService] Iniciando OAuth 2.0 Loopback para Escritorio...');
      idToken = await DesktopOAuthService.signInWithGoogleDesktop();
    } else {
      // 2. En móviles (Android / iOS) y Web, usar el SDK oficial de google_sign_in
      try {
        try {
          await _googleSignIn.signOut();
        } catch (_) {}
        final googleUser = await _googleSignIn.signIn();
        if (googleUser == null) return null; // Cancelado por el usuario
        final googleAuth = await googleUser.authentication;
        idToken = googleAuth.idToken;
      } catch (e) {
        if (e is ApiException) rethrow;
        final errorStr = e.toString();
        debugPrint('Error en login con Google (Mobile/Web): $e');
        if (errorStr.contains('10') || errorStr.contains('DEVELOPER_ERROR')) {
          throw ApiException(
            'Configuración de Google no reconocida (SHA-1 no registrado para este dispositivo). Ingrese con correo o DNI y contraseña.',
          );
        }
        if (errorStr.contains('12500') || errorStr.contains('SIGN_IN_FAILED')) {
          throw ApiException(
            'No se pudo iniciar sesión con Google en este dispositivo. Verifica que tenga Servicios de Google Play actualizados o una cuenta de Google activa.',
          );
        }
        if (errorStr.contains('network') || errorStr.contains('SocketException') || errorStr.contains('Failed to connect')) {
          throw ApiException(
            'Error de red al conectar con Google. Verifica tu conexión a internet.',
          );
        }
        throw ApiException('Error al iniciar sesión con Google: ${errorStr.replaceAll('Exception:', '').replaceAll('PlatformException(', '').trim()}');
      }
    }

    if (idToken == null || idToken.isEmpty) {
      throw ApiException('No se pudo obtener el token de verificación de Google. Inténtalo nuevamente.');
    }

    // 3. Enviar el ID Token verificado de Google a nuestro backend
    final response = await ApiClient.post(
      ApiConfig.authGoogle,
      body: {'idToken': idToken},
      requiresAuth: false,
    );
    final token = response['access_token']?.toString() ?? '';
    final userJson = response['user'] as Map<String, dynamic>;
    final user = UserModel.fromJson(userJson);
    await StorageService.saveSession(
      token: token,
      user: user,
      email: user.email,
    );
    return user;
  }

  static Future<void> logout() async {
    if (!kIsWeb) {
      try {
        if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
          await _googleSignIn.signOut();
        }
      } catch (_) {}
    } else {
      try { await _googleSignIn.signOut(); } catch (_) {}
    }
    await StorageService.clearSession();
  }

  static Future<String> forgotPassword(String email) async {
    final response = await ApiClient.post(
      ApiConfig.authForgotPassword,
      body: {
        'email': email.trim().toLowerCase(),
      },
      requiresAuth: false,
    );
    return response['message']?.toString() ?? 'Código de recuperación enviado a tu correo.';
  }

  static Future<String> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final response = await ApiClient.post(
      ApiConfig.authResetPassword,
      body: {
        'email': email.trim().toLowerCase(),
        'code': code.trim(),
        'new_password': newPassword,
      },
      requiresAuth: false,
    );
    return response['message']?.toString() ?? 'Contraseña actualizada exitosamente.';
  }

  /// 1. Solicitar código OTP para cambio de correo electrónico
  static Future<Map<String, dynamic>> requestEmailChange(String newEmail) async {
    final cleanEmail = newEmail.trim().toLowerCase();

    final response = await ApiClient.post(
      '${ApiConfig.baseUrl}/auth/request-email-change',
      body: {
        'new_email': cleanEmail,
      },
    );

    return {
      'direct_success': false,
      'message': response['message']?.toString() ?? 'Código de verificación de 6 dígitos enviado al nuevo correo.',
    };
  }

  /// 2. Confirmar cambio de correo electrónico con código de 6 dígitos
  static Future<UserModel> confirmEmailChange({
    required String newEmail,
    required String code,
  }) async {
    final cleanEmail = newEmail.trim().toLowerCase();

    final response = await ApiClient.post(
      '${ApiConfig.baseUrl}/auth/confirm-email-change',
      body: {
        'new_email': cleanEmail,
        'code': code.trim(),
      },
    );

    final data = response as Map<String, dynamic>;
    final userMap = (data['user'] is Map) ? (data['user'] as Map<String, dynamic>) : data;
    final updatedUser = UserModel.fromJson(userMap);
    final finalUser = updatedUser.email.isNotEmpty
        ? updatedUser
        : (StorageService.currentUser?.copyWith(email: cleanEmail) ?? updatedUser);

    if (data['access_token'] != null) {
      await StorageService.saveSession(
        token: data['access_token'].toString(),
        user: finalUser,
      );
    } else {
      await StorageService.updateCurrentUser(finalUser);
    }
    return finalUser;
  }

  /// 3. Eliminar la cuenta propia del usuario (disponible para USER, SUPERVISOR y ADMIN)
  static Future<String> deleteMyAccount(String password) async {
    final currentUser = StorageService.currentUser;
    final userId = currentUser?.id ?? '';

    dynamic response;
    dynamic lastError;

    // 1. Intentar endpoint oficial DELETE /api/auth/delete-account con confirmación de password
    try {
      response = await ApiClient.delete(
        '${ApiConfig.baseUrl}/auth/delete-account',
        body: {
          'password': password,
        },
      );
    } catch (e0) {
      lastError = e0;
      // 2. Intentar endpoint alternativo DELETE /api/users/me/account
      try {
        response = await ApiClient.delete(
          '${ApiConfig.baseUrl}/users/me/account',
          body: {
            'password': password,
          },
        );
      } catch (e1) {
        lastError = e1;
        // 3. Intentar DELETE por ID
        if (userId.isNotEmpty) {
          try {
            response = await ApiClient.delete(
              ApiConfig.userById(userId),
              body: {
                'password': password,
              },
            );
          } catch (e2) {
            lastError = e2;
            try {
              response = await ApiClient.delete(ApiConfig.userById(userId));
            } catch (e3) {
              lastError = e3;
            }
          }
        }
      }
    }

    // Si el servidor backend rechazó la eliminación, no cerramos sesión falsamente
    if (response == null) {
      final errorMsg = lastError?.toString().replaceAll('Exception: ', '') ??
          'No se pudo eliminar la cuenta en el servidor backend.';
      throw ApiException(errorMsg);
    }

    // Solo si el servidor confirmó la eliminación en la BD, cerramos la sesión local
    await StorageService.clearSession();
    if (response is Map<String, dynamic>) {
      return response['message']?.toString() ?? 'Tu cuenta ha sido eliminada con éxito de la base de datos.';
    }
    return 'Tu cuenta ha sido eliminada con éxito de la base de datos.';
  }

  /// 4. Cambiar contraseña estando autenticado (POST /api/auth/change-password)
  static Future<String> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final currentUser = StorageService.currentUser;
    final body = {
      'current_password': currentPassword,
      'new_password': newPassword,
    };

    dynamic response;
    try {
      response = await ApiClient.post(
        ApiConfig.authChangePassword,
        body: body,
      );
    } catch (e) {
      // Fallback a PATCH /api/users/me solo si falla
      try {
        response = await ApiClient.patch(
          ApiConfig.usersMe,
          body: {'password': newPassword},
        );
      } catch (_) {
        rethrow;
      }
    }

    // Actualizar la contraseña guardada para mantener el auto-relogin al día
    final creds = await StorageService.getSavedCredentials();
    if (creds != null && currentUser != null) {
      final token = await StorageService.getToken();
      if (token != null) {
        await StorageService.saveSession(
          token: token,
          user: currentUser,
          email: creds['email'],
          password: newPassword,
        );
      }
    }

    if (response is Map<String, dynamic>) {
      return response['message']?.toString() ?? 'Contraseña actualizada exitosamente.';
    }
    return 'Contraseña actualizada exitosamente.';
  }
}
