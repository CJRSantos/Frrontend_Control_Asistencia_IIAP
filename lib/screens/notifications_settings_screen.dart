import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/theme_service.dart';
import '../services/wallpaper_service.dart';
import '../models/user_model.dart';
import '../utils/responsive.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_cached_avatar.dart';
import '../services/event_service.dart';

class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() => _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState extends State<NotificationsSettingsScreen> {
  bool _isMasterEnabled = true;
  bool _notifMorningEntry = true;
  bool _notifMorningExit = true;
  bool _notifAfternoonEntry = true;
  bool _notifAfternoonExit = true;
  bool _notifEvents = true;
  bool _notifEventClose = true;
  bool _notifHapticEnabled = true;
  bool _notifHighPriorityDoze = true;

  String _morningEntryTime = '07:45';
  String _morningExitTime = '13:00';
  String _afternoonEntryTime = '14:00';
  String _afternoonExitTime = '18:30';
  int _leadMinutes = 15;
  String _alertToneId = 'institucional';

  bool _isLoading = true;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    NotificationService.isMutedNotifier.addListener(_onMutedChanged);
    _loadSettings();
  }

  void _onMutedChanged() {
    if (mounted) {
      final master = !NotificationService.isMutedNotifier.value;
      if (_isMasterEnabled != master) {
        setState(() => _isMasterEnabled = master);
      }
    }
  }

  @override
  void dispose() {
    NotificationService.isMutedNotifier.removeListener(_onMutedChanged);
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isMuted = prefs.getBool('notifications_muted_v1') ?? false;

      if (mounted) {
        setState(() {
          _isMasterEnabled = !isMuted;
          _notifMorningEntry = prefs.getBool('notif_morning_entry') ?? true;
          _notifMorningExit = prefs.getBool('notif_morning_exit') ?? true;
          _notifAfternoonEntry = prefs.getBool('notif_afternoon_entry') ?? true;
          _notifAfternoonExit = prefs.getBool('notif_afternoon_exit') ?? true;
          _notifEvents = prefs.getBool('notif_events') ?? true;
          _notifEventClose = prefs.getBool('notif_event_close') ?? true;
          _notifHapticEnabled = prefs.getBool('notif_haptic_enabled') ?? true;
          _notifHighPriorityDoze = prefs.getBool('notif_high_priority_doze') ?? true;

          _morningEntryTime = prefs.getString('notif_morning_entry_time') ?? '07:45';
          _morningExitTime = prefs.getString('notif_morning_exit_time') ?? '13:00';
          _afternoonEntryTime = prefs.getString('notif_afternoon_entry_time') ?? '14:00';
          _afternoonExitTime = prefs.getString('notif_afternoon_exit_time') ?? '18:30';
          _leadMinutes = prefs.getInt('notif_events_lead_minutes') ?? 15;
          _alertToneId = prefs.getString('notif_alert_tone') ?? 'institucional';

          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  int get _activeCount {
    if (!_isMasterEnabled) return 0;
    int count = 0;
    if (_notifMorningEntry) count++;
    if (_notifMorningExit) count++;
    if (_notifAfternoonEntry) count++;
    if (_notifAfternoonExit) count++;
    if (_notifEvents) count++;
    if (_notifEventClose) count++;
    return count;
  }

  String _formatTimeBadge(String time24) {
    try {
      final parts = time24.split(':');
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final period = h >= 12 ? 'PM' : 'AM';
      final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
      final hStr = h12.toString().padLeft(2, '0');
      final mStr = m.toString().padLeft(2, '0');
      return '$hStr:$mStr $period';
    } catch (_) {
      return time24;
    }
  }

  String get _leadMinutesBadgeText {
    if (_leadMinutes >= 60) {
      final h = _leadMinutes ~/ 60;
      return '$h HORA${h > 1 ? 'S' : ''} ANTES';
    }
    return '$_leadMinutes MIN ANTES';
  }

  String get _alertToneLabel {
    switch (_alertToneId) {
      case 'campana_suave':
        return 'Campana Suave Institucional';
      case 'alarma_energizada':
        return 'Alerta Enérgica de Marcado';
      case 'sistema':
        return 'Predeterminado del Sistema (Móvil)';
      case 'institucional':
      default:
        return 'Sonido institucional predeterminado (IIAP Core)';
    }
  }

  Future<void> _toggleMasterSwitch(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() => _isMasterEnabled = value);
      await prefs.setBool('notifications_muted_v1', !value);
      NotificationService.isMutedNotifier.value = !value;

      if (!value) {
        await NotificationService.cancelAll();
      } else {
        await NotificationService.scheduleAllAttendanceReminders();
        await NotificationService.syncEventSettings(
          eventsEnabled: _notifEvents,
          closeEnabled: _notifEventClose,
          events: EventService.eventsNotifier.value,
        );
      }

      if (_notifHapticEnabled) {
        HapticFeedback.lightImpact();
      }
    } catch (_) {}
  }

  Future<void> _toggleSetting(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
      if (mounted) {
        setState(() {
          if (key == 'notif_morning_entry') _notifMorningEntry = value;
          if (key == 'notif_morning_exit') _notifMorningExit = value;
          if (key == 'notif_afternoon_entry') _notifAfternoonEntry = value;
          if (key == 'notif_afternoon_exit') _notifAfternoonExit = value;
          if (key == 'notif_events') _notifEvents = value;
          if (key == 'notif_event_close') _notifEventClose = value;
          if (key == 'notif_haptic_enabled') _notifHapticEnabled = value;
          if (key == 'notif_high_priority_doze') _notifHighPriorityDoze = value;
        });
      }

      if (_notifHapticEnabled) {
        HapticFeedback.selectionClick();
      }

      if (key == 'notif_haptic_enabled' || key == 'notif_high_priority_doze') {
        await NotificationService.reloadPreferences();
        if (_isMasterEnabled) {
          await NotificationService.scheduleAllAttendanceReminders();
          await NotificationService.syncEventSettings(
            eventsEnabled: _notifEvents,
            closeEnabled: _notifEventClose,
            events: EventService.eventsNotifier.value,
          );
        }
        if (mounted) {
          final isVib = key == 'notif_haptic_enabled';
          AppToast.show(
            context,
            title: isVib
                ? (value ? 'Vibración háptica activada' : 'Vibración háptica silenciada')
                : (value ? 'Prioridad alta en reposo activa' : 'Modo ahorro de energía activo'),
            subtitle: isVib
                ? (value ? 'Doble pulsación táctil al sonar la alarma' : 'Alarmas silenciosas sin vibrar')
                : (value ? 'Omite suspensión Doze del SO para máxima puntualidad' : 'Respeta optimizaciones de batería del SO'),
            icon: isVib ? Icons.vibration_rounded : Icons.alarm_on_rounded,
            accentColor: ThemeService.primaryColor(context),
          );
        }
      } else if (_isMasterEnabled) {
        if (key.startsWith('notif_morning_') || key.startsWith('notif_afternoon_')) {
          await NotificationService.scheduleAllAttendanceReminders();
        } else if (key == 'notif_events' || key == 'notif_event_close') {
          await NotificationService.syncEventSettings(
            eventsEnabled: key == 'notif_events' ? value : _notifEvents,
            closeEnabled: key == 'notif_event_close' ? value : _notifEventClose,
            events: EventService.eventsNotifier.value,
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _editTime({
    required String key,
    required String currentTime24,
    required String title,
  }) async {
    final parts = currentTime24.split(':');
    final initialH = int.tryParse(parts.first) ?? 8;
    final initialM = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialH, minute: initialM),
      helpText: 'HORARIO: $title'.toUpperCase(),
      cancelText: 'CANCELAR',
      confirmText: 'GUARDAR',
      builder: (context, child) {
        return Theme(
          data: (isDark ? ThemeData.dark() : ThemeData.light()).copyWith(
            colorScheme: isDark
                ? const ColorScheme.dark(
                    primary: Color(0xFF10B981),
                    onPrimary: Colors.white,
                    surface: Color(0xFF132228),
                    onSurface: Colors.white,
                  )
                : const ColorScheme.light(
                    primary: Color(0xFF10B981),
                    onPrimary: Colors.white,
                  ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final hStr = picked.hour.toString().padLeft(2, '0');
      final mStr = picked.minute.toString().padLeft(2, '0');
      final newTimeStr = '$hStr:$mStr';

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, newTimeStr);

      if (mounted) {
        setState(() {
          if (key == 'notif_morning_entry_time') _morningEntryTime = newTimeStr;
          if (key == 'notif_morning_exit_time') _morningExitTime = newTimeStr;
          if (key == 'notif_afternoon_entry_time') _afternoonEntryTime = newTimeStr;
          if (key == 'notif_afternoon_exit_time') _afternoonExitTime = newTimeStr;
        });
      }

      if (_isMasterEnabled) {
        await NotificationService.scheduleAllAttendanceReminders();
      }

      if (_notifHapticEnabled) {
        HapticFeedback.mediumImpact();
      }

      if (mounted) {
        AppToast.show(
          context,
          title: 'Alarma reprogramada',
          subtitle: 'Nuevo horario establecido a las ${_formatTimeBadge(newTimeStr)}',
          icon: Icons.access_time_rounded,
          accentColor: ThemeService.primaryColor(context),
        );
      }
    }
  }

  Future<void> _selectLeadMinutes() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = ThemeService.primaryColor(context);
    final cardBg = ThemeService.cardBg(context);
    final options = [
      {'label': '10 MIN ANTES', 'minutes': 10},
      {'label': '15 MIN ANTES (Predeterminado)', 'minutes': 15},
      {'label': '30 MIN ANTES', 'minutes': 30},
      {'label': '45 MIN ANTES', 'minutes': 45},
      {'label': '1 HORA ANTES', 'minutes': 60},
      {'label': '2 HORAS ANTES', 'minutes': 120},
    ];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? cardBg : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Responsive.constrained(
            context,
            maxTabletWidth: 500,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Anticipación de Aviso para Eventos',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Selecciona con cuánta anticipación deseas recibir la alarma previa a una capacitación o evento.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...options.map((opt) {
                      final mins = opt['minutes'] as int;
                      final isSelected = mins == _leadMinutes;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                          color: isSelected ? primaryColor : (isDark ? Colors.white38 : Colors.black38),
                        ),
                        title: Text(
                          opt['label'] as String,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        onTap: () async {
                          Navigator.pop(ctx);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setInt('notif_events_lead_minutes', mins);
                          if (mounted) setState(() => _leadMinutes = mins);
                          if (_isMasterEnabled && _notifEvents) {
                            await NotificationService.syncEventSettings(
                              eventsEnabled: _notifEvents,
                              closeEnabled: _notifEventClose,
                              events: EventService.eventsNotifier.value,
                            );
                          }
                          if (_notifHapticEnabled) HapticFeedback.selectionClick();
                        },
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _selectTone() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = ThemeService.primaryColor(context);
    final cardBg = ThemeService.cardBg(context);
    final tones = [
      {
        'id': 'institucional',
        'title': 'Sonido Institucional (IIAP Core)',
        'desc': 'Tono oficial sobrio y armónico optimizado para el personal',
      },
      {
        'id': 'campana_suave',
        'title': 'Campana Suave de Entrada',
        'desc': 'Sonido acústico tenue para alertas amigables de jornada',
      },
      {
        'id': 'alarma_energizada',
        'title': 'Alerta Enérgica de Marcado',
        'desc': 'Máxima perceptibilidad para no olvidar tu marcación diaria',
      },
      {
        'id': 'sistema',
        'title': 'Predeterminado del Sistema Móvil',
        'desc': 'Utiliza el timbre de notificaciones nativo de tu teléfono',
      },
    ];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? cardBg : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return SafeArea(
              child: Responsive.constrained(
                context,
                maxTabletWidth: 500,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.85,
                  ),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white24 : Colors.black12,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Tono de Alerta y Notificación',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Toca cualquier tono para escuchar su sonido acústico y elegir tu preferido.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...tones.map((t) {
                          final isSelected = t['id'] == _alertToneId;
                          return ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            tileColor: isSelected
                                ? (isDark ? primaryColor.withValues(alpha: 0.18) : primaryColor.withValues(alpha: 0.12))
                                : Colors.transparent,
                            contentPadding: const EdgeInsets.symmetric(vertical: 2, horizontal: 12),
                            leading: Icon(
                              isSelected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
                              color: isSelected ? primaryColor : (isDark ? Colors.white38 : Colors.black38),
                              size: 22,
                            ),
                            title: Text(
                              t['title']!,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                            subtitle: Text(
                              t['desc']!,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              ),
                            ),
                            trailing: isSelected
                                ? Icon(Icons.volume_up_rounded, color: primaryColor, size: 20)
                                : null,
                            onTap: () async {
                              setModalState(() => _alertToneId = t['id']!);
                              if (mounted) setState(() => _alertToneId = t['id']!);

                              // 1. Reproducir sonido de inmediato al tocar
                              await NotificationService.previewTone(t['id']!);

                              // 2. Vibración háptica si está habilitada
                              if (_notifHapticEnabled) {
                                if (t['id'] == 'alarma_energizada') {
                                  HapticFeedback.heavyImpact();
                                } else if (t['id'] == 'campana_suave') {
                                  HapticFeedback.lightImpact();
                                } else {
                                  HapticFeedback.selectionClick();
                                }
                              }

                              // 3. Persistir selección
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setString('notif_alert_tone', t['id']!);
                              await NotificationService.reloadPreferences();
                              if (_isMasterEnabled) {
                                await NotificationService.scheduleAllAttendanceReminders();
                                await NotificationService.syncEventSettings(
                                  eventsEnabled: _notifEvents,
                                  closeEnabled: _notifEventClose,
                                  events: EventService.eventsNotifier.value,
                                );
                              }
                            },
                          );
                        }),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: () {
                              NotificationService.stopAudioPreview();
                              Navigator.pop(ctx);
                            },
                            child: const Text('Aceptar y Guardar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) => NotificationService.stopAudioPreview());
  }

  void _showInfoModal() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = ThemeService.primaryColor(context);
    final cardBg = ThemeService.cardBg(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? cardBg : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Responsive.constrained(
            context,
            maxTabletWidth: 500,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.shield_outlined,
                          color: primaryColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recordatorios Offline IIAP',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Sincronización Nativa con el Sistema',
                              style: TextStyle(
                                fontSize: 12,
                                color: primaryColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '• 100% Sin Internet: Las alertas se programan en el Administrador de Alarmas exactas del sistema operativo (Android AlarmManager / iOS BGTasks).\n\n'
                    '• Fuera de la App: Se dispararán con precisión exacta incluso si la aplicación está cerrada o tu teléfono está en reposo profundo (Doze Mode).\n\n'
                    '• Horarios Oficiales: Sincronizados con las horas de entrada matutina y vespertina oficiales del IIAP.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: _isTesting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        _isTesting ? 'Enviando prueba...' : 'Enviar Alerta de Prueba Ahora',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      onPressed: _isTesting
                          ? null
                          : () async {
                              Navigator.pop(ctx);
                              _triggerTest();
                            },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

  Future<void> _triggerTest() async {
    setState(() => _isTesting = true);
    try {
      await NotificationService.triggerTestNotification();
      if (_notifHapticEnabled) {
        HapticFeedback.heavyImpact();
      }
      if (!mounted) return;
      AppToast.show(
        context,
        title: '¡Notificación de prueba enviada!',
        subtitle: 'Revisa la barra superior de tu dispositivo.',
        icon: Icons.check_circle_rounded,
        accentColor: ThemeService.primaryColor(context),
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.show(
        context,
        title: 'Error enviando prueba',
        subtitle: '$e',
        icon: Icons.error_outline_rounded,
        accentColor: const Color(0xFFEF4444),
      );
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        ThemeService.accentColorNotifier,
        WallpaperService.wallpaperNotifier,
      ]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final hasWallpaper = WallpaperService.currentWallpaper.hasWallpaper;
        final primaryColor = ThemeService.primaryColor(context);

        final scaffoldBg = hasWallpaper ? Colors.transparent : ThemeService.scaffoldBg(context);
        final cardBg = hasWallpaper
            ? ThemeService.cardBg(context).withValues(alpha: 0.82)
            : ThemeService.cardBg(context);
        final cardBorder = ThemeService.cardBorder(context);
        final textWhite = isDark ? Colors.white : const Color(0xFF0F172A);
        final textSub = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

        return Scaffold(
          backgroundColor: scaffoldBg,
          appBar: AppBar(
            backgroundColor: hasWallpaper ? Colors.transparent : scaffoldBg,
            elevation: 0,
            titleSpacing: 0,
            centerTitle: false,
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: textWhite,
                size: 20,
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              'Notificaciones',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: textWhite,
                letterSpacing: -0.2,
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  Icons.info_outline_rounded,
                  color: textWhite.withValues(alpha: 0.8),
                  size: 22,
                ),
                tooltip: 'Información y Diagnóstico',
                onPressed: _showInfoModal,
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: _isLoading
              ? Center(child: CircularProgressIndicator(color: primaryColor))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 620;

                    return SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Responsive.constrained(
                        context,
                        maxTabletWidth: 780,
                        maxDesktopWidth: 880,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // --- 1. BANNER PRINCIPAL: RECORDATORIOS LOCALES ---
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: cardBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Badges superiores responsivos con Wrap anti-overflow
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 6,
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          children: [
                                            // Badge 1: 100% OFFLINE
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: primaryColor.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(20),
                                                border: Border.all(color: primaryColor.withValues(alpha: 0.4)),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Container(
                                                    width: 6,
                                                    height: 6,
                                                    decoration: BoxDecoration(
                                                      color: primaryColor,
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    '100% OFFLINE',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: primaryColor,
                                                      letterSpacing: 0.4,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // Badge 2: IIAP Core
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.6) : const Color(0xFFF1F5F9),
                                                borderRadius: BorderRadius.circular(20),
                                                border: Border.all(color: cardBorder),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.shield_outlined, size: 12, color: primaryColor),
                                                  const SizedBox(width: 5),
                                                  const Text(
                                                    'IIAP Core',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                      color: Color(0xFF94A3B8),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.fact_check_outlined,
                                        size: 18,
                                        color: textSub.withValues(alpha: 0.6),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),

                                  Text(
                                    'Recordatorios Locales',
                                    style: TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.bold,
                                      color: textWhite,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 6),

                                  Text(
                                    'Las alarmas programadas se activarán con precisión milimétrica incluso sin conexión a internet.',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: textSub,
                                      height: 1.45,
                                    ),
                                  ),
                                  const SizedBox(height: 16),

                                  // Switch Maestro
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? (hasWallpaper
                                              ? ThemeService.containerColor(context).withValues(alpha: 0.28)
                                              : ThemeService.containerColor(context).withValues(alpha: 0.45))
                                          : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: cardBorder.withValues(alpha: 0.7)),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: primaryColor.withValues(alpha: 0.18),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.notifications_active_rounded,
                                            color: primaryColor,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Activar todos los recordatorios',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: textWhite,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _isMasterEnabled
                                                    ? '$_activeCount activos en este dispositivo'
                                                    : 'Recordatorios en pausa (0 activos)',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: _isMasterEnabled ? primaryColor : const Color(0xFFEF4444),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        CupertinoSwitch(
                                          value: _isMasterEnabled,
                                          activeTrackColor: primaryColor,
                                          inactiveTrackColor: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                          onChanged: _toggleMasterSwitch,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 24),

                            // --- 2. SECCIÓN: JORNADA LABORAL Y REFRIGERIO ---
                            _buildSectionHeader(
                              title: 'Jornada Laboral y Refrigerio',
                              badge: 'TURNO REGULAR',
                              isDark: isDark,
                              textWhite: textWhite,
                              primaryColor: primaryColor,
                            ),
                            const SizedBox(height: 10),

                            // Renderizado responsivo (2 columnas en Tablets/Laptops, 1 columna en móviles)
                            if (isWide) ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _buildScheduleCard(
                                      title: 'Entrada Mañana',
                                      timeBadge: _formatTimeBadge(_morningEntryTime),
                                      subtitle: 'Aviso para registrar ingreso matutino',
                                      icon: Icons.wb_sunny_rounded,
                                      iconColor: const Color(0xFFF59E0B),
                                      value: _notifMorningEntry && _isMasterEnabled,
                                      onToggle: (val) => _toggleSetting('notif_morning_entry', val),
                                      onTimeTap: () => _editTime(
                                        key: 'notif_morning_entry_time',
                                        currentTime24: _morningEntryTime,
                                        title: 'Entrada Mañana',
                                      ),
                                      isDark: isDark,
                                      cardBg: cardBg,
                                      cardBorder: cardBorder,
                                      textWhite: textWhite,
                                      textSub: textSub,
                                      primaryColor: primaryColor,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildScheduleCard(
                                      title: 'Salida Mañana',
                                      timeBadge: _formatTimeBadge(_morningExitTime),
                                      subtitle: 'Recordatorio para refrigerio y colación',
                                      icon: Icons.restaurant_rounded,
                                      iconColor: primaryColor,
                                      value: _notifMorningExit && _isMasterEnabled,
                                      onToggle: (val) => _toggleSetting('notif_morning_exit', val),
                                      onTimeTap: () => _editTime(
                                        key: 'notif_morning_exit_time',
                                        currentTime24: _morningExitTime,
                                        title: 'Salida Mañana (Refrigerio)',
                                      ),
                                      isDark: isDark,
                                      cardBg: cardBg,
                                      cardBorder: cardBorder,
                                      textWhite: textWhite,
                                      textSub: textSub,
                                      primaryColor: primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _buildScheduleCard(
                                      title: 'Entrada Tarde',
                                      timeBadge: _formatTimeBadge(_afternoonEntryTime),
                                      subtitle: 'Reingreso puntual de jornada vespertina',
                                      icon: Icons.access_time_filled_rounded,
                                      iconColor: primaryColor,
                                      value: _notifAfternoonEntry && _isMasterEnabled,
                                      onToggle: (val) => _toggleSetting('notif_afternoon_entry', val),
                                      onTimeTap: () => _editTime(
                                        key: 'notif_afternoon_entry_time',
                                        currentTime24: _afternoonEntryTime,
                                        title: 'Entrada Tarde',
                                      ),
                                      isDark: isDark,
                                      cardBg: cardBg,
                                      cardBorder: cardBorder,
                                      textWhite: textWhite,
                                      textSub: textSub,
                                      primaryColor: primaryColor,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildScheduleCard(
                                      title: 'Salida Tarde',
                                      timeBadge: _formatTimeBadge(_afternoonExitTime),
                                      subtitle: 'Cierre oficial y firma de salida diaria',
                                      icon: Icons.nightlight_round,
                                      iconColor: const Color(0xFF94A3B8),
                                      value: _notifAfternoonExit && _isMasterEnabled,
                                      onToggle: (val) => _toggleSetting('notif_afternoon_exit', val),
                                      onTimeTap: () => _editTime(
                                        key: 'notif_afternoon_exit_time',
                                        currentTime24: _afternoonExitTime,
                                        title: 'Salida Tarde (Fin de Jornada)',
                                      ),
                                      isDark: isDark,
                                      cardBg: cardBg,
                                      cardBorder: cardBorder,
                                      textWhite: textWhite,
                                      textSub: textSub,
                                      primaryColor: primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              _buildScheduleCard(
                                title: 'Entrada Mañana',
                                timeBadge: _formatTimeBadge(_morningEntryTime),
                                subtitle: 'Aviso para registrar ingreso matutino',
                                icon: Icons.wb_sunny_rounded,
                                iconColor: const Color(0xFFF59E0B),
                                value: _notifMorningEntry && _isMasterEnabled,
                                onToggle: (val) => _toggleSetting('notif_morning_entry', val),
                                onTimeTap: () => _editTime(
                                  key: 'notif_morning_entry_time',
                                  currentTime24: _morningEntryTime,
                                  title: 'Entrada Mañana',
                                ),
                                isDark: isDark,
                                cardBg: cardBg,
                                cardBorder: cardBorder,
                                textWhite: textWhite,
                                textSub: textSub,
                                primaryColor: primaryColor,
                              ),
                              _buildScheduleCard(
                                title: 'Salida Mañana',
                                timeBadge: _formatTimeBadge(_morningExitTime),
                                subtitle: 'Recordatorio para refrigerio y colación',
                                icon: Icons.restaurant_rounded,
                                iconColor: primaryColor,
                                value: _notifMorningExit && _isMasterEnabled,
                                onToggle: (val) => _toggleSetting('notif_morning_exit', val),
                                onTimeTap: () => _editTime(
                                  key: 'notif_morning_exit_time',
                                  currentTime24: _morningExitTime,
                                  title: 'Salida Mañana (Refrigerio)',
                                ),
                                isDark: isDark,
                                cardBg: cardBg,
                                cardBorder: cardBorder,
                                textWhite: textWhite,
                                textSub: textSub,
                                primaryColor: primaryColor,
                              ),
                              _buildScheduleCard(
                                title: 'Entrada Tarde',
                                timeBadge: _formatTimeBadge(_afternoonEntryTime),
                                subtitle: 'Reingreso puntual de jornada vespertina',
                                icon: Icons.access_time_filled_rounded,
                                iconColor: primaryColor,
                                value: _notifAfternoonEntry && _isMasterEnabled,
                                onToggle: (val) => _toggleSetting('notif_afternoon_entry', val),
                                onTimeTap: () => _editTime(
                                  key: 'notif_afternoon_entry_time',
                                  currentTime24: _afternoonEntryTime,
                                  title: 'Entrada Tarde',
                                ),
                                isDark: isDark,
                                cardBg: cardBg,
                                cardBorder: cardBorder,
                                textWhite: textWhite,
                                textSub: textSub,
                                primaryColor: primaryColor,
                              ),
                              _buildScheduleCard(
                                title: 'Salida Tarde',
                                timeBadge: _formatTimeBadge(_afternoonExitTime),
                                subtitle: 'Cierre oficial y firma de salida diaria',
                                icon: Icons.nightlight_round,
                                iconColor: const Color(0xFF94A3B8),
                                value: _notifAfternoonExit && _isMasterEnabled,
                                onToggle: (val) => _toggleSetting('notif_afternoon_exit', val),
                                onTimeTap: () => _editTime(
                                  key: 'notif_afternoon_exit_time',
                                  currentTime24: _afternoonExitTime,
                                  title: 'Salida Tarde (Fin de Jornada)',
                                ),
                                isDark: isDark,
                                cardBg: cardBg,
                                cardBorder: cardBorder,
                                textWhite: textWhite,
                                textSub: textSub,
                                primaryColor: primaryColor,
                              ),
                            ],

                            const SizedBox(height: 24),

                            // --- 3. SECCIÓN: EVENTOS Y CAPACITACIONES ---
                            _buildSectionHeader(
                              title: 'Eventos y Capacitaciones',
                              badge: 'INSTITUCIONAL',
                              isDark: isDark,
                              textWhite: textWhite,
                              primaryColor: primaryColor,
                            ),
                            const SizedBox(height: 10),

                            if (isWide) ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _buildEventCard(
                                      title: 'Avisos de Convocatoria',
                                      badgeText: _leadMinutesBadgeText,
                                      subtitle: 'Alerta previa de apertura de sala y a...',
                                      icon: Icons.calendar_today_rounded,
                                      value: _notifEvents && _isMasterEnabled,
                                      onToggle: (val) => _toggleSetting('notif_events', val),
                                      onBadgeTap: _selectLeadMinutes,
                                      isDark: isDark,
                                      cardBg: cardBg,
                                      cardBorder: cardBorder,
                                      textWhite: textWhite,
                                      textSub: textSub,
                                      primaryColor: primaryColor,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildSimpleCard(
                                      title: 'Rotación y Cierre de Evento',
                                      subtitle: 'Recordar marcado final al concluir ponencia',
                                      icon: Icons.notification_important_rounded,
                                      iconColor: const Color(0xFF94A3B8),
                                      value: _notifEventClose && _isMasterEnabled,
                                      onToggle: (val) => _toggleSetting('notif_event_close', val),
                                      isDark: isDark,
                                      cardBg: cardBg,
                                      cardBorder: cardBorder,
                                      textWhite: textWhite,
                                      textSub: textSub,
                                      primaryColor: primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              _buildEventCard(
                                title: 'Avisos de Convocatoria',
                                badgeText: _leadMinutesBadgeText,
                                subtitle: 'Alerta previa de apertura de sala y a...',
                                icon: Icons.calendar_today_rounded,
                                value: _notifEvents && _isMasterEnabled,
                                onToggle: (val) => _toggleSetting('notif_events', val),
                                onBadgeTap: _selectLeadMinutes,
                                isDark: isDark,
                                cardBg: cardBg,
                                cardBorder: cardBorder,
                                textWhite: textWhite,
                                textSub: textSub,
                                primaryColor: primaryColor,
                              ),
                              _buildSimpleCard(
                                title: 'Rotación y Cierre de Evento',
                                subtitle: 'Recordar marcado final al concluir ponencia',
                                icon: Icons.notification_important_rounded,
                                iconColor: const Color(0xFF94A3B8),
                                value: _notifEventClose && _isMasterEnabled,
                                onToggle: (val) => _toggleSetting('notif_event_close', val),
                                isDark: isDark,
                                cardBg: cardBg,
                                cardBorder: cardBorder,
                                textWhite: textWhite,
                                textSub: textSub,
                                primaryColor: primaryColor,
                              ),
                            ],

                            const SizedBox(height: 24),

                            // --- 4. SECCIÓN: PREFERENCIAS DEL DISPOSITIVO ---
                            _buildSectionHeader(
                              title: 'Preferencias del Dispositivo',
                              isDark: isDark,
                              textWhite: textWhite,
                              primaryColor: primaryColor,
                            ),
                            const SizedBox(height: 10),

                            if (isWide) ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _buildActionTile(
                                      title: 'Tono de Alerta',
                                      subtitle: _alertToneLabel,
                                      icon: Icons.volume_up_rounded,
                                      onTap: _selectTone,
                                      isDark: isDark,
                                      cardBg: cardBg,
                                      cardBorder: cardBorder,
                                      textWhite: textWhite,
                                      textSub: textSub,
                                      primaryColor: primaryColor,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildSimpleCard(
                                      title: 'Vibración Háptica',
                                      subtitle: 'Resonancia táctil doble al sonar alarma',
                                      icon: Icons.vibration_rounded,
                                      value: _notifHapticEnabled,
                                      onToggle: (val) async {
                                        await _toggleSetting('notif_haptic_enabled', val);
                                        if (val) HapticFeedback.heavyImpact();
                                      },
                                      isDark: isDark,
                                      cardBg: cardBg,
                                      cardBorder: cardBorder,
                                      textWhite: textWhite,
                                      textSub: textSub,
                                      primaryColor: primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                              _buildSimpleCard(
                                title: 'Prioridad Alta en Modo Reposo',
                                subtitle: 'Omite optimizaciones de batería del SO para alarmas exactas',
                                icon: Icons.alarm_on_rounded,
                                value: _notifHighPriorityDoze,
                                onToggle: (val) => _toggleSetting('notif_high_priority_doze', val),
                                isDark: isDark,
                                cardBg: cardBg,
                                cardBorder: cardBorder,
                                textWhite: textWhite,
                                textSub: textSub,
                                primaryColor: primaryColor,
                              ),
                            ] else ...[
                              _buildActionTile(
                                title: 'Tono de Alerta',
                                subtitle: _alertToneLabel,
                                icon: Icons.volume_up_rounded,
                                onTap: _selectTone,
                                isDark: isDark,
                                cardBg: cardBg,
                                cardBorder: cardBorder,
                                textWhite: textWhite,
                                textSub: textSub,
                                primaryColor: primaryColor,
                              ),
                              _buildSimpleCard(
                                title: 'Vibración Háptica',
                                subtitle: 'Resonancia táctil doble al sonar alarma',
                                icon: Icons.vibration_rounded,
                                value: _notifHapticEnabled,
                                onToggle: (val) async {
                                  await _toggleSetting('notif_haptic_enabled', val);
                                  if (val) HapticFeedback.heavyImpact();
                                },
                                isDark: isDark,
                                cardBg: cardBg,
                                cardBorder: cardBorder,
                                textWhite: textWhite,
                                textSub: textSub,
                                primaryColor: primaryColor,
                              ),
                              _buildSimpleCard(
                                title: 'Prioridad Alta en Modo Reposo',
                                subtitle: 'Omite optimizaciones de batería del SO para alarmas exactas',
                                icon: Icons.alarm_on_rounded,
                                value: _notifHighPriorityDoze,
                                onToggle: (val) => _toggleSetting('notif_high_priority_doze', val),
                                isDark: isDark,
                                cardBg: cardBg,
                                cardBorder: cardBorder,
                                textWhite: textWhite,
                                textSub: textSub,
                                primaryColor: primaryColor,
                              ),
                            ],

                            const SizedBox(height: 28),

                            // --- 5. FOOTER: SINCRONIZADO NATIVAMENTE ---
                            Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.shield_outlined,
                                    size: 15,
                                    color: primaryColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'Sincronizado nativamente con el Administrador de Alarmas del SO',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: textSub.withValues(alpha: 0.9),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  // --- WIDGET HELPERS RESPONSIVOS ---

  Widget _buildSectionHeader({
    required String title,
    String? badge,
    required bool isDark,
    required Color textWhite,
    required Color primaryColor,
  }) {
    return Row(
      children: [
        Container(
          width: 3.5,
          height: 15,
          decoration: BoxDecoration(
            color: primaryColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: textWhite,
              letterSpacing: -0.2,
            ),
          ),
        ),
        if (badge != null) ...[
          const SizedBox(width: 8),
          Text(
            badge,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFF64748B),
              letterSpacing: 0.8,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildScheduleCard({
    required String title,
    required String timeBadge,
    required String subtitle,
    required IconData icon,
    Color? iconColor,
    required bool value,
    required ValueChanged<bool> onToggle,
    required VoidCallback onTimeTap,
    required bool isDark,
    required Color cardBg,
    required Color cardBorder,
    required Color textWhite,
    required Color textSub,
    required Color primaryColor,
  }) {
    final effectiveIconColor = iconColor ?? primaryColor;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isDark ? primaryColor.withValues(alpha: 0.16) : primaryColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: effectiveIconColor, size: 20),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: textWhite,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: onTimeTap,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: isDark ? primaryColor.withValues(alpha: 0.16) : primaryColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: primaryColor.withValues(alpha: 0.40),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              timeBadge,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: primaryColor,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Icon(
                              Icons.edit_rounded,
                              size: 11,
                              color: primaryColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: textSub,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),
          CupertinoSwitch(
            value: value,
            activeTrackColor: primaryColor,
            inactiveTrackColor: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
            onChanged: onToggle,
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard({
    required String title,
    required String badgeText,
    required String subtitle,
    required IconData icon,
    Color? iconColor,
    required bool value,
    required ValueChanged<bool> onToggle,
    required VoidCallback onBadgeTap,
    required bool isDark,
    required Color cardBg,
    required Color cardBorder,
    required Color textWhite,
    required Color textSub,
    required Color primaryColor,
  }) {
    final effectiveIconColor = iconColor ?? primaryColor;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isDark ? primaryColor.withValues(alpha: 0.16) : primaryColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: effectiveIconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: textWhite,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: onBadgeTap,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: isDark ? primaryColor.withValues(alpha: 0.16) : primaryColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: primaryColor.withValues(alpha: 0.40),
                          ),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: primaryColor,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: textSub,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          CupertinoSwitch(
            value: value,
            activeTrackColor: primaryColor,
            inactiveTrackColor: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
            onChanged: onToggle,
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    Color? iconColor,
    required bool value,
    required ValueChanged<bool> onToggle,
    required bool isDark,
    required Color cardBg,
    required Color cardBorder,
    required Color textWhite,
    required Color textSub,
    required Color primaryColor,
  }) {
    final effectiveIconColor = iconColor ?? primaryColor;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isDark ? primaryColor.withValues(alpha: 0.16) : primaryColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: effectiveIconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: textWhite,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: textSub,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          CupertinoSwitch(
            value: value,
            activeTrackColor: primaryColor,
            inactiveTrackColor: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
            onChanged: onToggle,
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    Color? iconColor,
    required VoidCallback onTap,
    required bool isDark,
    required Color cardBg,
    required Color cardBorder,
    required Color textWhite,
    required Color textSub,
    required Color primaryColor,
  }) {
    final effectiveIconColor = iconColor ?? primaryColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cardBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isDark ? primaryColor.withValues(alpha: 0.16) : primaryColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: effectiveIconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: textWhite,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: textSub,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: textSub,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
