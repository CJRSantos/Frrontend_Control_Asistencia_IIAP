import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:quick_actions/quick_actions.dart';
import '../models/user_model.dart';
import 'storage_service.dart';
import '../screens/home_screen.dart';
import '../screens/qr/qr_scanner_screen.dart';
import '../screens/qr/qr_display_screen.dart';

class QuickActionsService {
  static const String actionScanQr = 'action_scan_qr';
  static const String actionMyAttendance = 'action_my_attendance';
  static const String actionDisplayQr = 'action_display_qr';
  static const String actionSupervision = 'action_supervision';

  static final QuickActions _quickActions = const QuickActions();
  static String? _pendingAction;
  static bool _isInitialized = false;

  /// Inicializa los atajos y escucha cambios de sesión para adaptar los atajos al rol
  static Future<void> init() async {
    // Quick actions solo está disponible en plataformas móviles (Android e iOS)
    if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }

    if (_isInitialized) return;
    _isInitialized = true;

    try {
      _quickActions.initialize((String shortcutType) {
        handleShortcut(shortcutType);
      });

      // Configurar atajos iniciales según el usuario actual
      await updateShortcutsForUser(StorageService.currentUser);

      // Re-configurar atajos automáticamente cuando inicie sesión, cambie de rol o cierre sesión
      StorageService.currentUserNotifier.addListener(() {
        updateShortcutsForUser(StorageService.currentUser);
      });
    } catch (e) {
      debugPrint('[QuickActions] Error inicializando: $e');
    }
  }

  /// Configura dinámicamente los atajos según el rol del usuario conectado
  static Future<void> updateShortcutsForUser(UserModel? user) async {
    if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }

    try {
      final List<ShortcutItem> items = [];

      final bool canManage = user != null && user.canManageAttendanceQr;

      if (canManage) {
        // ROLES: SUPERVISOR, ADMIN, SUPERADMIN, ADMIN_EVENTO, GESTOR_EVENTO
        items.addAll([
          const ShortcutItem(
            type: actionDisplayQr,
            localizedTitle: 'Generar QR de Asistencia',
            icon: 'ic_shortcut_display_qr',
          ),
          const ShortcutItem(
            type: actionScanQr,
            localizedTitle: 'Escanear QR',
            icon: 'ic_shortcut_qr',
          ),
          ShortcutItem(
            type: actionSupervision,
            localizedTitle: (user.isAdmin) ? 'Supervisión de Personal' : 'Horarios y Cuadrilla',
            icon: 'ic_shortcut_supervision',
          ),
          const ShortcutItem(
            type: actionMyAttendance,
            localizedTitle: 'Mi Asistencia Hoy',
            icon: 'ic_shortcut_attendance',
          ),
        ]);
      } else {
        // ROLES: USER / EMPLEADO REGULAR (o sin sesión iniciada)
        items.addAll([
          const ShortcutItem(
            type: actionScanQr,
            localizedTitle: 'Escanear QR',
            icon: 'ic_shortcut_qr',
          ),
          const ShortcutItem(
            type: actionMyAttendance,
            localizedTitle: 'Mi Asistencia Hoy',
            icon: 'ic_shortcut_attendance',
          ),
        ]);
      }

      await _quickActions.setShortcutItems(items);
      debugPrint('[QuickActions] Atajos actualizados para rol: ${user?.role.displayName ?? "Sin sesión"} (${items.length} atajos)');
    } catch (e) {
      debugPrint('[QuickActions] Error al actualizar atajos: $e');
    }
  }

  /// Procesa la acción seleccionada desde el launcher
  static void handleShortcut(String shortcutType) {
    debugPrint('[QuickActions] Atajo presionado: $shortcutType');

    final navState = StorageService.navigatorKey.currentState;
    if (navState == null || !StorageService.hasSession) {
      _pendingAction = shortcutType;
      return;
    }

    _executeAction(shortcutType, navState);
  }

  /// Ejecuta la acción cuando la navegación está lista
  static void _executeAction(String shortcutType, NavigatorState navState) {
    if (!StorageService.hasSession) return;
    final user = StorageService.currentUser;

    if (shortcutType == actionScanQr) {
      navState.push(
        MaterialPageRoute(
          builder: (_) => const QrScannerScreen(target: ScanTarget.attendance),
        ),
      );
    } else if (shortcutType == actionDisplayQr) {
      if (user != null && user.canManageAttendanceQr) {
        navState.push(
          MaterialPageRoute(
            builder: (_) => const QrDisplayScreen(mode: QrMode.attendance),
          ),
        );
      } else {
        // Fallback a escaneo si no tiene permiso de emitir QR
        navState.push(
          MaterialPageRoute(
            builder: (_) => const QrScannerScreen(target: ScanTarget.attendance),
          ),
        );
      }
    } else if (shortcutType == actionSupervision) {
      navState.popUntil((route) => route.isFirst);
      if (user != null && user.canManageAttendanceQr) {
        // Pestaña Personal / Horarios (índice 2)
        HomeScreen.currentTabNotifier.value = 2;
      } else {
        HomeScreen.currentTabNotifier.value = 1;
      }
    } else if (shortcutType == actionMyAttendance) {
      navState.popUntil((route) => route.isFirst);
      // Pestaña Asistencias del empleado (índice 1)
      HomeScreen.currentTabNotifier.value = 1;
    }
  }

  /// Verifica y consume cualquier acción pendiente (ej. si la app se abrió desde frío con el atajo)
  static void checkAndConsumePendingAction() {
    final action = _pendingAction;
    if (action != null) {
      _pendingAction = null;
      final navState = StorageService.navigatorKey.currentState;
      if (navState != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _executeAction(action, navState);
        });
      }
    }
  }
}
