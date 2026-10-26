import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../config/api_config.dart';
import 'api_client.dart';

class DesktopOAuthService {
  /// Genera una cadena aleatoria criptográficamente segura compatible con Base64 URL sin padding
  static String _generateRandomString(int length) {
    final random = Random.secure();
    final values = List<int>.generate(length, (_) => random.nextInt(256));
    return base64UrlEncode(values).replaceAll('=', '').replaceAll('+', '-').replaceAll('/', '_');
  }

  /// Calcula el Code Challenge S256 para PKCE según RFC 7636
  static String _generateCodeChallenge(String verifier) {
    final bytes = ascii.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '').replaceAll('+', '-').replaceAll('/', '_');
  }

  /// Inicia el flujo de OAuth 2.0 Loopback en Windows / Desktop
  /// Retorna el `id_token` firmado por Google listo para ser enviado a nuestro backend
  static Future<String> signInWithGoogleDesktop() async {
    final port = ApiConfig.googleLoopbackPort;
    final clientId = ApiConfig.googleDesktopClientId;
    final redirectUri = 'http://127.0.0.1:$port';

    HttpServer? server;
    try {
      try {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      } catch (bindErr) {
        debugPrint('[DesktopOAuth] No se pudo abrir puerto $port: $bindErr');
        throw ApiException(
          'No se pudo iniciar el servicio de autenticación local en el puerto $port. '
          'Verifica si otra instancia de la app está abierta o si otro proceso usa el puerto.',
        );
      }

      final state = _generateRandomString(16);
      final codeVerifier = _generateRandomString(64);
      final codeChallenge = _generateCodeChallenge(codeVerifier);

      final authUri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': 'openid email profile',
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'state': state,
        'access_type': 'offline',
        'prompt': 'select_account',
      });

      debugPrint('[DesktopOAuth] Abriendo navegador con URL: $authUri');

      // Abrir el navegador externo por defecto del sistema operativo
      final launched = await launchUrl(authUri, mode: LaunchMode.externalApplication);
      if (!launched) {
        throw ApiException('No se pudo abrir el navegador del sistema para iniciar sesión con Google.');
      }

      // Esperar la respuesta en el loopback con un timeout prudente de 2 minutos
      final Completer<String> codeCompleter = Completer<String>();
      final activeServer = server;
      if (activeServer == null) {
        throw ApiException('No se pudo inicializar el servidor de autenticación local.');
      }

      final subscription = activeServer.listen((HttpRequest request) async {
        final uri = request.uri;
        final params = uri.queryParameters;

        // Si la petición es un favicon o asset secundario, responder vacío
        if (uri.path == '/favicon.ico') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        final incomingState = params['state'];
        final code = params['code'];
        final error = params['error'];

        if (error != null && error.isNotEmpty) {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            ..write(_buildHtmlResponse(
              title: 'Inicio de sesión cancelado',
              message: 'Has cancelado o cerrado el inicio de sesión con Google. Puedes cerrar esta ventana.',
              isSuccess: false,
            ));
          await request.response.close();

          if (!codeCompleter.isCompleted) {
            codeCompleter.completeError(
              ApiException('Inicio de sesión con Google cancelado por el usuario ($error).'),
            );
          }
          return;
        }

        if (incomingState != state) {
          request.response
            ..statusCode = HttpStatus.badRequest
            ..headers.contentType = ContentType.html
            ..write(_buildHtmlResponse(
              title: 'Error de verificación de estado',
              message: 'No coincide el estado de la solicitud (posible ataque CSRF). Inténtalo nuevamente.',
              isSuccess: false,
            ));
          await request.response.close();

          if (!codeCompleter.isCompleted) {
            codeCompleter.completeError(
              ApiException('Error de seguridad OAuth (CSRF state mismatch). Inténtalo de nuevo.'),
            );
          }
          return;
        }

        if (code != null && code.isNotEmpty) {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            ..write(_buildHtmlResponse(
              title: '¡Autenticación Exitosa!',
              message: 'Tu cuenta ha sido verificada correctamente por Google.<br><br><strong>Ya puedes cerrar esta pestaña y volver a la app de Control de Asistencia IIAP.</strong>',
              isSuccess: true,
            ));
          await request.response.close();

          if (!codeCompleter.isCompleted) {
            codeCompleter.complete(code);
          }
          return;
        }

        // Si llegó sin code ni error
        request.response
          ..statusCode = HttpStatus.badRequest
          ..headers.contentType = ContentType.html
          ..write(_buildHtmlResponse(
            title: 'Respuesta incompleta',
            message: 'Google no devolvió ningún código de autorización.',
            isSuccess: false,
          ));
        await request.response.close();
      });

      // Timeout de 120 segundos
      String authCode;
      try {
        authCode = await codeCompleter.future.timeout(
          const Duration(seconds: 120),
          onTimeout: () {
            throw ApiException('El inicio de sesión expiró por inactividad. Por favor intenta de nuevo.');
          },
        );
      } finally {
        await subscription.cancel();
      }

      // Intercambiar authorization code por ID Token con PKCE
      final Map<String, String> tokenBody = {
        'client_id': clientId,
        'code': authCode,
        'code_verifier': codeVerifier,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri,
      };
      if (ApiConfig.googleDesktopClientSecret.isNotEmpty) {
        tokenBody['client_secret'] = ApiConfig.googleDesktopClientSecret;
      }

      final tokenResponse = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: tokenBody,
      );

      final tokenData = jsonDecode(tokenResponse.body) as Map<String, dynamic>;

      if (tokenResponse.statusCode != 200) {
        final errDescription = tokenData['error_description'] ?? tokenData['error'] ?? 'Error desconocido';
        debugPrint('[DesktopOAuth] Error canjeando token: ${tokenResponse.body}');

        if (errDescription.toString().contains('redirect_uri_mismatch')) {
          throw ApiException(
            'Configuración requerida en Google Cloud: El URI "$redirectUri" no está registrado '
            'en las "URIs de redireccionamiento autorizadas" para este Client ID en Google Cloud Console.',
          );
        }

        throw ApiException('Error al obtener token de Google: $errDescription');
      }

      final idToken = tokenData['id_token']?.toString();
      if (idToken == null || idToken.isEmpty) {
        throw ApiException('Google no devolvió un ID Token válido para este usuario.');
      }

      debugPrint('[DesktopOAuth] ID Token obtenido con éxito en Windows.');
      return idToken;
    } finally {
      try {
        await server?.close(force: true);
      } catch (_) {}
    }
  }

  /// Construye una página HTML moderna con identidad visual institucional IIAP
  static String _buildHtmlResponse({
    required String title,
    required String message,
    required bool isSuccess,
  }) {
    final accentColor = isSuccess ? '#10B981' : '#F43F5E';
    final icon = isSuccess ? '✓' : '✕';

    return '''<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>IIAP - $title</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      background: #091417;
      color: #E2E8F0;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      padding: 20px;
    }
    .card {
      background: #112229;
      border: 1px solid rgba(255, 255, 255, 0.08);
      border-radius: 20px;
      padding: 36px 32px;
      max-width: 440px;
      width: 100%;
      text-align: center;
      box-shadow: 0 20px 40px rgba(0, 0, 0, 0.6);
    }
    .icon-badge {
      width: 64px;
      height: 64px;
      margin: 0 auto 20px;
      border-radius: 50%;
      background: ${isSuccess ? 'rgba(16, 185, 129, 0.15)' : 'rgba(244, 63, 94, 0.15)'};
      border: 2px solid $accentColor;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 32px;
      color: $accentColor;
      font-weight: bold;
    }
    h1 {
      font-size: 22px;
      font-weight: 700;
      color: #FFFFFF;
      margin-bottom: 12px;
      letter-spacing: -0.3px;
    }
    p {
      font-size: 14px;
      line-height: 1.6;
      color: #94A3B8;
      margin-bottom: 24px;
    }
    p strong {
      color: #F1F5F9;
    }
    .tag {
      display: inline-block;
      font-size: 12px;
      font-weight: 600;
      color: $accentColor;
      background: ${isSuccess ? 'rgba(16, 185, 129, 0.1)' : 'rgba(244, 63, 94, 0.1)'};
      padding: 6px 14px;
      border-radius: 12px;
      border: 1px solid ${isSuccess ? 'rgba(16, 185, 129, 0.3)' : 'rgba(244, 63, 94, 0.3)'};
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="icon-badge">$icon</div>
    <h1>$title</h1>
    <p>$message</p>
    <div class="tag">Control Asistencia IIAP</div>
  </div>
  ${isSuccess ? '<script>setTimeout(function() { window.close(); }, 3500);</script>' : ''}
</body>
</html>''';
  }
}
