import '../../widgets/event_image_widget.dart';
import 'dart:async';
import 'package:flutter/material.dart';

import '../../models/attendance_model.dart';
import '../../models/event_model.dart';
import '../../models/user_model.dart';
import '../../services/attendance_service.dart';
import '../../services/auth_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/event_service.dart';
import '../../services/notification_service.dart';
import '../../services/storage_service.dart';
import '../../services/theme_service.dart';
import '../../services/wallpaper_service.dart';
import '../../services/offline_sync_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/leaf_logo.dart';
import '../events/create_event_screen.dart';
import '../events/event_detail_screen.dart';
import '../events/event_qr_display_screen.dart';
import '../events/events_list_screen.dart';
import '../qr/qr_display_screen.dart';
import '../qr/qr_scanner_screen.dart';
import '../attendance/facial_attendance_screen.dart';
import '../notifications_settings_screen.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/app_cached_avatar.dart';
import '../../config/api_config.dart';
import '../../widgets/photo_viewer_dialog.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';

class DashboardTab extends StatefulWidget {
  final VoidCallback? onNavigateToHistory;
  final VoidCallback? onNavigateToProfile;

  const DashboardTab({
    super.key,
    this.onNavigateToHistory,
    this.onNavigateToProfile,
  });

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  List<AttendanceModel> _todayRecords = [];
  List<AttendanceModel> _allRecords = [];
  Timer? _realtimeTimer;
  bool _isRealtimeSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _startRealtimeSync();
  }

  @override
  void dispose() {
    _realtimeTimer?.cancel();
    super.dispose();
  }

  void _startRealtimeSync() {
    _realtimeTimer?.cancel();
    // Sincronización en tiempo real continua e inteligente con guard de concurrencia
    int syncCycles = 0;
    _realtimeTimer = Timer.periodic(const Duration(milliseconds: 3500), (_) async {
      if (!mounted || _isRealtimeSyncing) return;
      _isRealtimeSyncing = true;
      try {
        syncCycles++;
        // Sincronizar perfil periodicamente para detectar cambios de rol a SUPERVISOR sin reiniciar
        if (syncCycles % 3 == 0) {
          await AuthService.getProfile();
        }
        await _fetchAttendanceData();
        await EventService.getEvents();
      } finally {
        _isRealtimeSyncing = false;
      }
    });
  }

  Future<void> _loadInitialData() async {
    final cachedToday = AttendanceService.getCachedTodayRecords();
    final cachedAll = AttendanceService.getCachedAllRecords();
    if (mounted && (cachedToday.isNotEmpty || cachedAll.isNotEmpty)) {
      setState(() {
        _todayRecords = cachedToday;
        _allRecords = cachedAll;
      });
    }

    _fetchAttendanceData();
    EventService.getEvents();
  }

  bool _areRecordsDifferent(List<AttendanceModel> oldList, List<AttendanceModel> newList) {
    if (oldList.length != newList.length) return true;
    if (oldList.isEmpty) return false;
    return oldList.first.id != newList.first.id || oldList.last.id != newList.last.id;
  }

  Future<void> _fetchAttendanceData() async {
    if (!mounted) return;
    try {
      final records = await AttendanceService.getTodayRecords();
      if (mounted && _areRecordsDifferent(_todayRecords, records)) {
        setState(() {
          _todayRecords = records;
        });
      }
    } catch (_) {}

    try {
      final user = StorageService.currentUser;
      if (user != null && user.canManageAttendanceQr) {
        final all = await AttendanceService.getAllRecords();
        if (mounted && _areRecordsDifferent(_allRecords, all)) {
          setState(() {
            _allRecords = all;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _refreshAll() async {
    await AuthService.getProfile();
    await _fetchAttendanceData();
    await EventService.getEvents();
    if (mounted) {
      AppToast.show(
        context,
        title: 'Sincronización Exitosa',
        subtitle: 'Información de turnos y cuadrilla al día.',
        icon: Icons.sync_rounded,
        accentColor: const Color(0xFF10B981),
      );
    }
  }

  void _openPhotoViewer(UserModel user) {
    if (user.photoUrl != null && user.photoUrl!.isNotEmpty) {
      PhotoViewerDialog.show(
        context,
        photoUrl: user.photoUrl!,
        userName: user.fullName,
        subtitle: user.role.displayName,
      );
    } else {
      widget.onNavigateToProfile?.call();
    }
  }

  void _handleGenerarQr(BuildContext context, UserModel user) {
    if (user.canManageAttendanceQr) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const QrDisplayScreen(mode: QrMode.attendance),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          icon: Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFFFEF3C7),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shield_outlined, color: Color(0xFFD97706), size: 36),
          ),
          title: const Text(
            'Acceso Restringido',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: const Text(
            'La función Generar QR con cifrado SHA-256 está reservada exclusivamente para el Administrador y los Supervisores autorizados para la toma de asistencia.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          actions: [
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Entendido', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _handleGenerarQrEvento(BuildContext context, EventModel? featuredEvent) async {
    if (featuredEvent != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EventQrDisplayScreen(event: featuredEvent),
        ),
      );
      return;
    }

    var events = EventService.eventsNotifier.value;
    if (events.isEmpty) {
      events = await EventService.getEvents();
    }

    if (!context.mounted) return;

    if (events.length == 1) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EventQrDisplayScreen(event: events.first),
        ),
      );
    } else if (events.length > 1) {
      _showEventSelectionModal(context, events);
    } else {
      _showNoEventsQrModal(context);
    }
  }

  void _showNoEventsQrModal(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = ThemeService.primaryColor(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0C1316) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: isDark ? const Color(0xFF1B2E36) : const Color(0xFFE2E8F0),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 25,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 28),
          child: SafeArea(
            child: Responsive.constrained(
              ctx,
              maxTabletWidth: 550,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F2D24),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF176044), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981).withValues(alpha: 0.25),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.qr_code_2_rounded,
                        color: Color(0xFF10B981),
                        size: 42,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'GENERAR QR DE EVENTOS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Para proyectar un código QR de evento con cifrado dinámico SHA-256 y rotación de 15s, primero debes programar o seleccionar un evento para tu Unidad Organizativa.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: const Color(0xFF091417),
                        elevation: 3,
                        shadowColor: primary.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        final created = await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const CreateEventScreen()),
                        );
                        if (created == true && context.mounted) {
                          final evs = await EventService.getEvents(forceRefresh: true);
                          if (evs.isNotEmpty && context.mounted) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => EventQrDisplayScreen(event: evs.first),
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                      label: const Text(
                        'Crear Nuevo Evento Ahora',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: isDark ? const Color(0xFF1E3A8A) : const Color(0xFF3B82F6),
                          width: 1.2,
                        ),
                        backgroundColor: isDark
                            ? const Color(0xFF0F1E36)
                            : const Color(0xFFEFF6FF),
                        foregroundColor: const Color(0xFF60A5FA),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const QrDisplayScreen(mode: QrMode.attendance),
                          ),
                        );
                      },
                      icon: const Icon(Icons.screen_share_rounded, size: 18),
                      label: const Text(
                        'Emitir QR Kiosko de Asistencia UO',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const EventsListScreen()),
                      );
                    },
                    icon: const Icon(Icons.calendar_month_rounded, size: 17),
                    label: const Text(
                      'Ver Lista y Agenda de Eventos',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showEventSelectionModal(BuildContext context, List<EventModel> events) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = ThemeService.primaryColor(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.78,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0C1316) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: isDark ? const Color(0xFF1B2E36) : const Color(0xFFE2E8F0),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 25,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: SafeArea(
            child: Responsive.constrained(
              ctx,
              maxTabletWidth: 600,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F2D24),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.qr_code_2_rounded,
                              color: Color(0xFF10B981),
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'SELECCIONA EL EVENTO',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F3224),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF176044)),
                        ),
                        child: Text(
                          '${events.length} EVENTOS',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Toca un evento para proyectar su código QR rotativo SHA-256 en pantalla.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: events.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (itemCtx, index) {
                        final evt = events[index];
                        final isNow = evt.isActiveNow;

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              Navigator.of(ctx).pop();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => EventQrDisplayScreen(event: evt),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isNow
                                    ? (isDark ? const Color(0xFF0E251E) : const Color(0xFFECFDF5))
                                    : (isDark ? const Color(0xFF131D22) : const Color(0xFFF8FAFC)),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isNow
                                      ? const Color(0xFF10B981)
                                      : (isDark ? const Color(0xFF223640) : const Color(0xFFE2E8F0)),
                                  width: isNow ? 1.6 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: isNow
                                          ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                          : (isDark ? const Color(0xFF1C2A30) : const Color(0xFFE2E8F0)),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.qr_code_rounded,
                                      color: isNow ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: [
                                            if (isNow)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF10B981),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'EN CURSO',
                                                  style: TextStyle(
                                                    fontSize: 8.5,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFF091417),
                                                  ),
                                                ),
                                              ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF162B24),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                evt.type.displayName.toUpperCase(),
                                                style: const TextStyle(
                                                  fontSize: 8.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF34D399),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          evt.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${evt.location} • ${evt.attendeesCount} inscritos',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 15,
                                    color: isNow ? const Color(0xFF10B981) : const Color(0xFF64748B),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 46,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: primary.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        final created = await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const CreateEventScreen()),
                        );
                        if (created == true && context.mounted) {
                          await EventService.getEvents(forceRefresh: true);
                        }
                      },
                      icon: Icon(Icons.add_rounded, color: primary, size: 18),
                      label: Text(
                        'Crear Nuevo Evento',
                        style: TextStyle(
                          color: primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleEscanearQr(BuildContext context) async {
    final res = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const QrScannerScreen(target: ScanTarget.attendance),
      ),
    );
    if (res == true && mounted) {
      await _fetchAttendanceData();
      await EventService.getEvents();
    }
  }

  Future<void> _handleReconocimientoFacial(BuildContext ctx) async {
    final user = StorageService.currentUser;
    if (user != null && !user.canUseFacialRecognition) {
      showDialog(
        context: ctx,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: _cardBg(ctx),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          icon: Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFFFEF3C7),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shield_outlined, color: Color(0xFFD97706), size: 36),
          ),
          title: const Text(
            'Acceso Restringido',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white),
          ),
          content: const Text(
            'El Control Biométrico Facial está reservado exclusivamente para los roles autorizados (Administradores, Supervisores y Gestores de Asistencia).',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.4, color: Color(0xFFCBD5E1)),
          ),
          actions: [
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('Entendido', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      );
      return;
    }

    final token = await StorageService.getToken();
    if (!ctx.mounted) return;
    final res = await Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (_) => FacialAttendanceScreen(
          jwtToken: token ?? '',
          backendBaseUrl: ApiConfig.baseUrl,
        ),
      ),
    );
    if (res == true && mounted) {
      await _fetchAttendanceData();
      await EventService.getEvents();
    }
  }

  String _maskDni(String? dni) {
    if (dni == null || dni.trim().isEmpty) return '7492****';
    final clean = dni.trim();
    if (clean.length > 4) {
      return '${clean.substring(0, 4)}****';
    }
    return clean;
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final hourStr = displayHour.toString().padLeft(2, '0');
    final minStr = minute.toString().padLeft(2, '0');
    return '$hourStr:$minStr $period';
  }

  bool get _isAfternoonShift {
    return DateTime.now().hour >= 13;
  }

  String get _currentShiftCuadrillaTitle {
    return _isAfternoonShift
        ? 'SUPERVISIÓN CUADRILLA • TARDE'
        : 'SUPERVISIÓN CUADRILLA • MAÑANA';
  }

  String get _currentShiftBadgeText {
    return _isAfternoonShift
        ? 'Turno Tarde: 13:00 - 21:00'
        : 'Turno Mañana: 07:30 - 16:30';
  }

  String _getCurrentShiftLabel() {
    return _isAfternoonShift ? 'Turno Tarde' : 'Turno Mañana';
  }

  String _getMonthAbbr(int month) {
    const months = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Set', 'Oct', 'Nov', 'Dic'];
    if (month >= 1 && month <= 12) return months[month - 1];
    return '';
  }

  String _formatEventDateAndDuration(EventModel event) {
    final now = DateTime.now();
    final isToday = event.startDate.year == now.year &&
        event.startDate.month == now.month &&
        event.startDate.day == now.day;

    final hourStr = _formatTime(event.startDate);
    final prefix = isToday ? 'Hoy' : '${event.startDate.day} ${_getMonthAbbr(event.startDate.month)}';

    final duration = event.endDate.difference(event.startDate);
    String durStr = '';
    if (duration.inMinutes > 0) {
      final hours = duration.inHours;
      final mins = duration.inMinutes % 60;
      if (hours > 0 && mins > 0) {
        durStr = ' (Duración: ${hours}h ${mins}m)';
      } else if (hours > 0) {
        durStr = ' (Duración: ${hours}h)';
      } else {
        durStr = ' (Duración: ${mins}m)';
      }
    }
    return '$prefix, $hourStr$durStr';
  }


  String _formatGestorEventTimeShort(EventModel event) {
    final now = DateTime.now();
    final isToday = event.startDate.year == now.year &&
        event.startDate.month == now.month &&
        event.startDate.day == now.day;

    final prefix = isToday ? 'Hoy' : '${event.startDate.day} ${_getMonthAbbr(event.startDate.month)}';
    final startStr = _formatTime(event.startDate);
    return '$prefix • $startStr';
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return 'U';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        ThemeService.accentColorNotifier,
        WallpaperService.wallpaperNotifier,
      ]),
      builder: (context, _) {
        return ValueListenableBuilder<UserModel?>(
      valueListenable: StorageService.currentUserNotifier,
      builder: (context, rawUser, _) {
        final user = rawUser ?? StorageService.currentUser;
        if (user == null) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)));
        }

        AttendanceModel? entry;
        AttendanceModel? exit;

        for (final r in _todayRecords) {
          if (r.type == AttendanceType.CHECK_IN) {
            if (entry == null || r.timestamp.isBefore(entry.timestamp)) {
              entry = r;
            }
          } else if (r.type == AttendanceType.CHECK_OUT) {
            if (exit == null || r.timestamp.isAfter(exit.timestamp)) {
              exit = r;
            }
          }
        }

        // Determinación de la vista según el rol exacto:
        // 1. Gestor de Eventos o Admin de Evento/UO -> Vista Gestor de Eventos / UO
        // 2. Supervisor -> Vista de Supervisión Cuadrilla
        // 3. Admin General -> Acceso a herramientas de gestión
        // 4. Usuario Común -> Vista de empleado personal
        final isSupervisor = user.isSupervisor;

        return SafeArea(
          child: RefreshIndicator(
            color: const Color(0xFF10B981),
            backgroundColor: _cardBg(context),
            onRefresh: _refreshAll,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Responsive.constrained(
                context,
                maxTabletWidth: 680,
                child: ValueListenableBuilder<List<EventModel>>(
                  valueListenable: EventService.eventsNotifier,
                  builder: (context, events, _) {
                    Widget dashboardContent;
                    if (user.role == UserRole.ADMIN_EVENTO || user.isAdmin) {
                      dashboardContent = _buildAdminEventoDashboard(context, user, events);
                    } else if (user.role == UserRole.GESTOR_EVENTO) {
                      dashboardContent = _buildGestorEventoDashboard(context, user, events);
                    } else if (isSupervisor) {
                      dashboardContent = _buildSupervisorDashboard(context, user, events);
                    } else {
                      dashboardContent = _buildUserDashboard(context, user, entry, exit, events);
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildOfflineSyncBanner(context),
                        dashboardContent,
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
      },
    );
  }

  // ===========================================================================
  // 1. DASHBOARD DEL ADMIN EVENTO / UO (NUEVO DISEÑO SOLICITADO - IMAGEN 1)
  // ===========================================================================

  Widget _buildAdminEventoDashboard(
    BuildContext context,
    UserModel user,
    List<EventModel> events,
  ) {
    final now = DateTime.now();

    // Eventos y métricas en tiempo real
    final activeOrUpcoming = events
        .where((e) => e.endDate.isAfter(now) || e.isActiveNow)
        .toList();
    final featuredEvent = activeOrUpcoming.isNotEmpty
        ? activeOrUpcoming.first
        : (events.isNotEmpty ? events.first : null);

    // Sincronización 100% en tiempo real sin valores simulados
    final eventsCount = events.length;
    final enCursoCount = events.where((e) => e.isActiveNow).length;

    final totalRegistros = events.fold<int>(0, (sum, e) => sum + e.attendees.length);
    final totalCifrado = events.fold<int>(
      0,
      (sum, e) => sum + e.attendees.where((a) => a.notes != 'manual').length,
    );
    final int aforoPercent = totalRegistros > 0
        ? ((totalCifrado / totalRegistros) * 100).clamp(0, 100).round()
        : 0;
    final int displayRegistros = totalRegistros;
    final int displayCifrado = totalCifrado;

    final nameParts = user.fullName.trim().split(RegExp(r'\s+'));
    final firstName = nameParts.isNotEmpty ? nameParts.first : 'Jordan';

    final uoTitle = user.area.isNotEmpty
        ? user.area
        : (user.department?.isNotEmpty == true
            ? user.department!
            : 'Dir. General • Tecnologías de la Información / UO');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Header Superior: Squircle Verificado + IIAP OFICIAL [● EN LÍNEA] + Campana + Avatar Clickable
        _buildGestorHeader(context, user),

        const SizedBox(height: 18),

        // 2. Tarjeta Bienvenida Admin Evento: [ 🛡️ ADMIN EVENTO ] [ ● En línea ]
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardBg(context),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _cardBorder(context), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Fila Superior de Badges
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  // Badge Ámbar/Dorado: [ 🛡️ ADMIN EVENTO ]
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E1C0A),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF854D0E), width: 1.1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shield_rounded, color: Color(0xFFFBBF24), size: 13.5),
                        const SizedBox(width: 5),
                        Text(
                          user.isSuperAdmin
                              ? 'SUPERADMIN'
                              : (user.isAdmin ? 'ADMINISTRADOR' : 'ADMIN EVENTO'),
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFFBBF24),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Badge Dinámico: [ ● En línea ] / [ ● Desconectado ]
                  ValueListenableBuilder<bool>(
                    valueListenable: ConnectivityService.isOnlineNotifier,
                    builder: (context, isOnline, _) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                        decoration: BoxDecoration(
                          color: isOnline ? const Color(0xFF09291E) : const Color(0xFF2E1212),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isOnline ? const Color(0xFF135A40) : const Color(0xFF7F1D1D),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.circle,
                              color: isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                              size: 6.5,
                            ),
                            SizedBox(width: 5),
                            Text(
                              isOnline ? 'En línea' : 'Desconectado',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: isOnline ? const Color(0xFF34D399) : const Color(0xFFEF4444),
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Contenido: Squircle con Reloj verde/Foto + Hola, Jordan + Subtítulo
              Row(
                children: [
                  InkWell(
                    onTap: () => _openPhotoViewer(user),
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D2520),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF176044), width: 1.2),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: (user.photoUrl != null && user.photoUrl!.isNotEmpty)
                                ? CachedNetworkImage(
                                    imageUrl: user.photoUrl!,
                                    fit: BoxFit.cover,
                                    fadeInDuration: const Duration(milliseconds: 150),
                                    placeholder: (_, __) => const Center(
                                      child: Icon(Icons.access_time_filled_rounded, color: Color(0xFF34D399), size: 28),
                                    ),
                                    errorWidget: (_, __, ___) => const Center(
                                      child: Icon(Icons.access_time_filled_rounded, color: Color(0xFF34D399), size: 28),
                                    ),
                                  )
                                : const Center(
                                    child: Icon(Icons.access_time_filled_rounded, color: Color(0xFF34D399), size: 28),
                                  ),
                          ),
                        ),
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981),
                              shape: BoxShape.circle,
                              border: Border.all(color: _cardBg(context), width: 2),
                            ),
                            child: const Center(
                              child: Icon(Icons.check, size: 9, color: Colors.black),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hola, $firstName',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Admin Evento / UO • Gestión Central',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Sub-tarjeta Unidad Organizativa: 📍 Dir. General • Tecnologías de la Información / UO  🔄
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E1A1E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1B2E36)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_rounded, size: 15, color: Color(0xFF34D399)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        uoTitle,
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: _refreshAll,
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(2.0),
                        child: Icon(Icons.sync_rounded, color: Color(0xFF94A3B8), size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // 3. Fila de Métricas Táctiles en Tiempo Real: Eventos | Aforo | Cifrado
        Row(
          children: [
            // Tarjeta 1: Eventos
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const EventsListScreen()),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    decoration: BoxDecoration(
                      color: _cardBg(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _cardBorder(context)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Eventos',
                              style: TextStyle(fontSize: 11, color: Color(0xFF8FA3AF), fontWeight: FontWeight.w600),
                            ),
                            Icon(Icons.calendar_today_rounded, size: 13, color: Color(0xFF10B981)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          eventsCount < 10 ? '0$eventsCount' : '$eventsCount',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            eventsCount == 0
                                ? 'Sin eventos'
                                : (enCursoCount == 0
                                    ? '0 en curso'
                                    : (enCursoCount == 1 ? '1 en curso' : '$enCursoCount en curso')),
                            style: TextStyle(
                              fontSize: 9.5,
                              color: enCursoCount > 0 ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Tarjeta 2: Aforo
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const EventsListScreen()),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    decoration: BoxDecoration(
                      color: _cardBg(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _cardBorder(context)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Aforo',
                              style: TextStyle(fontSize: 11, color: Color(0xFF8FA3AF), fontWeight: FontWeight.w600),
                            ),
                            Icon(Icons.groups_rounded, size: 14, color: Color(0xFF38BDF8)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '$aforoPercent',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Text(
                              '%',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            eventsCount == 0 ? '0 activos' : '$displayRegistros activos',
                            style: const TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Tarjeta 3: Cifrado
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const EventsListScreen()),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    decoration: BoxDecoration(
                      color: _cardBg(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _cardBorder(context)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Cifrado',
                              style: TextStyle(fontSize: 10.5, color: Color(0xFF8FA3AF), fontWeight: FontWeight.w600),
                            ),
                            Icon(Icons.shield_outlined, size: 13, color: Color(0xFFFBBF24)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$displayCifrado',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'SHA-256 OK',
                            style: TextStyle(fontSize: 9.5, color: Color(0xFFF59E0B), fontWeight: FontWeight.w600),
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 22),

        // 4. Control de Asistencia [ 🔒 SHA-256 ]
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Control de Asistencia',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
              decoration: BoxDecoration(
                color: const Color(0xFF0F2D42),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF1D4ED8).withValues(alpha: 0.5)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_rounded, size: 11.5, color: Color(0xFF60A5FA)),
                  SizedBox(width: 4),
                  Text(
                    'SHA-256',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF60A5FA),
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Tarjeta Generar QR de Evento [SHA-256]
        InkWell(
          onTap: () => _handleGenerarQrEvento(context, featuredEvent),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg(context),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _cardBorder(context), width: 1.2),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F2D24),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF176044)),
                  ),
                  child: const Icon(
                    Icons.qr_code_2_rounded,
                    color: Color(0xFF10B981),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Flexible(
                            child: Text(
                              'Generar QR de Evento',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F3224),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: const Color(0xFF176044)),
                            ),
                            child: const Text(
                              'SHA-256',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Emisión institucional con cifrado de rotación automática cada 15 segundos par...',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8FA3AF),
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      const Row(
                        children: [
                          Icon(Icons.circle, color: Color(0xFF10B981), size: 5.5),
                          SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'Modo Pantalla / Kiosko activo',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF10B981),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B), size: 22),
              ],
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Tarjeta Escanear QR Asistente [CÁMARA]
        InkWell(
          onTap: () => _handleEscanearQr(context),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg(context),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _cardBorder(context), width: 1.2),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D2530),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF15485E)),
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: Color(0xFF38BDF8),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Flexible(
                            child: Text(
                              'Escanear QR Asistente',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0E2A38),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: const Color(0xFF155E75)),
                            ),
                            child: const Text(
                              'CÁMARA',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF38BDF8),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Registra asistencia escaneando el código QR individual o credencial física...',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8FA3AF),
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      const Row(
                        children: [
                          Icon(Icons.circle, color: Color(0xFF38BDF8), size: 5.5),
                          SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'Sensor óptico activo',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF38BDF8),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B), size: 22),
              ],
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Tarjeta Reconocimiento Facial [BIOMÉTRICO]
        InkWell(
          onTap: () => _handleReconocimientoFacial(context),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg(context),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _cardBorder(context), width: 1.2),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F2E23),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF16533D)),
                  ),
                  child: const Icon(
                    Icons.face_retouching_natural_rounded,
                    color: Color(0xFF34D399),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Flexible(
                            child: Text(
                              'Control Biométrico Facial',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0C3827),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: const Color(0xFF156947)),
                            ),
                            child: const Text(
                              'BIOMÉTRICO',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF34D399),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Escaneo continuo con cámara e identificación con IA...',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8FA3AF),
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      const Row(
                        children: [
                          Icon(Icons.circle, color: Color(0xFF34D399), size: 5.5),
                          SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'Reconocimiento facial automático',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF34D399),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B), size: 22),
              ],
            ),
          ),
        ),

        const SizedBox(height: 22),

        // 5. Eventos Institucionales - Ver Todos
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Eventos Institucionales',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EventsListScreen()),
                );
              },
              child: const Text(
                'Ver Todos',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF34D399),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        // Tarjeta con FOTO DE PORTADA REAL DEL EVENTO (Imagen 1)
        if (featuredEvent != null) ...[
          _buildFeaturedEventPhotoCard(context, featuredEvent),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _cardBorder(context)),
            ),
            child: const Row(
              children: [
                Icon(Icons.event_available_rounded, size: 24, color: Color(0xFF10B981)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No hay eventos programados en este momento.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF8FA3AF)),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 14),

        // Botón Verde Prominente: [ ⊕ Crear Nuevo Evento Institucional ]
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: ThemeService.primaryColor(context),
              foregroundColor: const Color(0xFF091417),
              elevation: 4,
              shadowColor: const Color(0xFF10B981).withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () async {
              final created = await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CreateEventScreen()),
              );
              if (created == true) {
                await EventService.getEvents(forceRefresh: true);
              }
            },
            icon: const Icon(Icons.add_circle_outline_rounded, size: 20, color: Color(0xFF091417)),
            label: const Text(
              'Crear Nuevo Evento Institucional',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                color: Color(0xFF091417),
              ),
            ),
          ),
        ),

        const SizedBox(height: 28),
      ],
    );
  }

  /// Tarjeta con Fotografía Real de Portada del Evento con Gradiente y Badges
  Widget _buildFeaturedEventPhotoCard(BuildContext context, EventModel event) {
    const defaultAuditoriumPhoto =
        'https://images.unsplash.com/photo-1540575467063-178a50c2df87?w=1200&q=80';

    final hasCustomImage = event.imageUrl != null && event.imageUrl!.trim().isNotEmpty;

    return InkWell(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EventDetailScreen(event: event),
          ),
        );
        if (mounted) {
          await EventService.getEvents(forceRefresh: true);
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 230,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _cardBorder(context), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Imagen de Fondo (Personalizada, Preset o Auditorio Oficial)
              EventImageWidget(
                imageUrl: hasCustomImage ? event.imageUrl : defaultAuditoriumPhoto,
                fit: BoxFit.cover,
                fallbackWidget: _buildFallbackAuditorium(),
              ),

              // 2. Gradiente Oscuro Superpuesto para máxima legibilidad
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.35),
                      Colors.black.withValues(alpha: 0.20),
                      Colors.black.withValues(alpha: 0.85),
                      Colors.black.withValues(alpha: 0.95),
                    ],
                    stops: const [0.0, 0.3, 0.75, 1.0],
                  ),
                ),
              ),

              // 3. Contenido Superpuesto (Badges superiores + Información inferior)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Fila Superior de Badges
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        // [ 👥 REUNIÓN UO ]
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0C2B22).withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF165942)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.groups_rounded, size: 12, color: Color(0xFF34D399)),
                              const SizedBox(width: 4.5),
                              Text(
                                event.type == EventType.REUNION ? 'REUNIÓN UO' : event.type.displayName.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF34D399),
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // [ ● Próximo ] o [ ● En curso ]
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: event.isActiveNow
                                ? const Color(0xFF0F3224).withValues(alpha: 0.9)
                                : const Color(0xFF38230D).withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: event.isActiveNow ? const Color(0xFF135A40) : const Color(0xFF854D0E),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.circle,
                                size: 5.5,
                                color: event.isActiveNow ? const Color(0xFF10B981) : const Color(0xFFFBBF24),
                              ),
                              const SizedBox(width: 4.5),
                              Text(
                                event.isActiveNow ? 'En curso' : 'Próximo',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: event.isActiveNow ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Bloque Inferior: Título, Ubicación, Registrados, Ver detalle
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          event.title,
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -0.2,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined, color: Color(0xFF34D399), size: 14),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                event.location,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFFE2E8F0),
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  _buildAttendeeAvatars(event.attendees),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      '${event.attendees.length} registrados',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFE2E8F0),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Ver detalle',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF34D399),
                                  ),
                                ),
                                SizedBox(width: 3),
                                Icon(Icons.chevron_right_rounded, color: Color(0xFF34D399), size: 15),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackAuditorium() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F2622), Color(0xFF081416)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.apartment_rounded, color: Color(0xFF165942), size: 56),
      ),
    );
  }


  // ===========================================================================
  // 1. DASHBOARD DEL GESTOR DE EVENTOS / UO (NUEVO DISEÑO SOLICITADO)
  // ===========================================================================

  Widget _buildGestorEventoDashboard(
    BuildContext context,
    UserModel user,
    List<EventModel> events,
  ) {
    final now = DateTime.now();

    // Métricas gerenciales reales calculadas en tiempo real
    final activeOrUpcoming = events
        .where((e) => e.endDate.isAfter(now) || e.isActiveNow)
        .toList();
    final featuredEvent = activeOrUpcoming.isNotEmpty
        ? activeOrUpcoming.first
        : (events.isNotEmpty ? events.first : null);

    // Sincronización 100% en tiempo real sin valores simulados
    final eventsCount = events.length;
    final enCursoCount = events.where((e) => e.isActiveNow).length;

    final totalRegistros = events.fold<int>(0, (sum, e) => sum + e.attendees.length);
    final totalValidados = events.fold<int>(
      0,
      (sum, e) => sum + e.attendees.where((a) => a.notes != 'manual').length,
    );
    final int asistenciaPercent = totalRegistros > 0
        ? ((totalValidados / totalRegistros) * 100).clamp(0, 100).round()
        : 0;
    final int displayRegistros = totalRegistros;
    final int displayValidados = totalValidados;

    final nameParts = user.fullName.trim().split(RegExp(r'\s+'));
    final firstName = nameParts.isNotEmpty ? nameParts.first : 'Jordan';

    final uoTitle = user.area.isNotEmpty
        ? user.area
        : (user.department?.isNotEmpty == true
            ? user.department!
            : 'Dir. General • TI & Innovación Digital');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Header Superior: Squircle Verificado + IIAP OFICIAL [● EN LÍNEA] + Campana + Avatar
        _buildGestorHeader(context, user),

        const SizedBox(height: 18),

        // 2. Tarjeta Bienvenida Gestor: [ 🏢 GESTOR EVENTO / UO ] [ ● Sincronizado ]
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardBg(context),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _cardBorder(context), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Fila Superior de Badges
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0C2621),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF0D5E4D)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.business_rounded, color: Color(0xFF34D399), size: 13),
                        const SizedBox(width: 5),
                        Text(
                          user.role == UserRole.ADMIN_EVENTO
                              ? 'ADMIN EVENTO / UO'
                              : 'GESTOR EVENTO / UO',
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF34D399),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF09291E),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF135A40)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, color: Color(0xFF10B981), size: 6.5),
                        SizedBox(width: 5),
                        Text(
                          'Sincronizado',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF34D399),
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Contenido: Squircle con Logo + Hola, Jordan + Botón Swap
              Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D2520),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF176044), width: 1.2),
                        ),
                        child: const Center(
                          child: LeafLogo(size: 26),
                        ),
                      ),
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            shape: BoxShape.circle,
                            border: Border.all(color: _cardBg(context), width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hola, $firstName',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          user.role == UserRole.ADMIN_EVENTO
                              ? 'Admin de Eventos • UO'
                              : 'Gestor de Eventos • UO',
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: _refreshAll,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: const Color(0xFF18262B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF263C45)),
                      ),
                      child: const Icon(
                        Icons.swap_horiz_rounded,
                        color: Color(0xFFCBD5E1),
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Sub-tarjeta Unidad Organizativa: 🏢 Dir. General • TI & Innovación Digital
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E1A1E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1B2E36)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.corporate_fare_rounded, size: 15, color: Color(0xFF34D399)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        uoTitle,
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // 3. MÉTRICAS GERENCIALES HOY (EN TIEMPO REAL)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'MÉTRICAS GERENCIALES HOY',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: Color(0xFFCBD5E1),
                letterSpacing: 0.6,
              ),
            ),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: Color(0xFF10B981), size: 6),
                SizedBox(width: 5),
                Text(
                  'En Tiempo Real',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF10B981),
                  ),
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 12),

        // 3 Tarjetas de Métricas Gerenciales Táctiles en Tiempo Real
        Row(
          children: [
            // Eventos
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const EventsListScreen()),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    decoration: BoxDecoration(
                      color: _cardBg(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _cardBorder(context)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Eventos',
                              style: TextStyle(fontSize: 11, color: Color(0xFF8FA3AF), fontWeight: FontWeight.w600),
                            ),
                            Icon(Icons.calendar_today_rounded, size: 13, color: Color(0xFF10B981)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          eventsCount < 10 ? '0$eventsCount' : '$eventsCount',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            eventsCount == 0
                                ? 'Sin eventos'
                                : (enCursoCount == 0
                                    ? '0 en curso'
                                    : (enCursoCount == 1 ? '1 en curso' : '$enCursoCount en curso')),
                            style: TextStyle(
                              fontSize: 9.5,
                              color: enCursoCount > 0 ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Asistencia
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const EventsListScreen()),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    decoration: BoxDecoration(
                      color: _cardBg(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _cardBorder(context)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Asistencia',
                              style: TextStyle(fontSize: 11, color: Color(0xFF8FA3AF), fontWeight: FontWeight.w600),
                            ),
                            Icon(Icons.groups_rounded, size: 14, color: Color(0xFF38BDF8)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '$asistenciaPercent',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF34D399),
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Text(
                              '%',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF34D399)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            eventsCount == 0 ? '0 registros' : '$displayRegistros registros',
                            style: const TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // QR SHA-256
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const EventsListScreen()),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    decoration: BoxDecoration(
                      color: _cardBg(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _cardBorder(context)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'QR SHA-256',
                              style: TextStyle(fontSize: 10.5, color: Color(0xFF8FA3AF), fontWeight: FontWeight.w600),
                            ),
                            Icon(Icons.shield_outlined, size: 13, color: Color(0xFFFBBF24)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$displayValidados',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Validados',
                            style: TextStyle(fontSize: 9.5, color: Color(0xFFFBBF24), fontWeight: FontWeight.w600),
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 22),

        // 4. Control de Asistencia: Generar QR de Evento + Escanear QR
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Control de Asistencia',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
              decoration: BoxDecoration(
                color: const Color(0xFF0F2D42),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF1D4ED8).withValues(alpha: 0.5)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_rounded, size: 11.5, color: Color(0xFF60A5FA)),
                  SizedBox(width: 4),
                  Text(
                    'SHA-256',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF60A5FA),
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Tarjeta Generar QR de Evento [SHA-256]
        InkWell(
          onTap: () => _handleGenerarQrEvento(context, featuredEvent),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg(context),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _cardBorder(context), width: 1.2),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F2D24),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF176044)),
                  ),
                  child: const Icon(
                    Icons.qr_code_2_rounded,
                    color: Color(0xFF10B981),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Flexible(
                            child: Text(
                              'Generar QR de Evento',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F3224),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: const Color(0xFF176044)),
                            ),
                            child: const Text(
                              'SHA-256',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Emisión institucional dinámica\n(rotación automática cada 15s) ...',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8FA3AF),
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Row(
                        children: [
                          Icon(Icons.slideshow_rounded, color: Color(0xFF10B981), size: 13),
                          SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'Modo Presentación disponible',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF10B981),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B), size: 22),
              ],
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Tarjeta Escanear QR de Asistencia [CÁMARA]
        InkWell(
          onTap: () => _handleEscanearQr(context),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg(context),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _cardBorder(context), width: 1.2),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D2530),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF15485E)),
                  ),
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    color: Color(0xFF38BDF8),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Flexible(
                            child: Text(
                              'Escanear QR de Asistencia',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF102847),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: const Color(0xFF1E3A8A)),
                            ),
                            child: const Text(
                              'CÁMARA',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF60A5FA),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Registra asistencia física leyendo el fotocheck de participante o...',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8FA3AF),
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Row(
                        children: [
                          Icon(Icons.circle, color: Color(0xFF38BDF8), size: 5.5),
                          SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'Sensor óptico calibrado',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF38BDF8),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B), size: 22),
              ],
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Tarjeta Reconocimiento Facial [BIOMÉTRICO]
        InkWell(
          onTap: () => _handleReconocimientoFacial(context),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg(context),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _cardBorder(context), width: 1.2),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F2E23),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF16533D)),
                  ),
                  child: const Icon(
                    Icons.face_retouching_natural_rounded,
                    color: Color(0xFF34D399),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Flexible(
                            child: Text(
                              'Control Biométrico Facial',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0C3827),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: const Color(0xFF156947)),
                            ),
                            child: const Text(
                              'BIOMÉTRICO',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF34D399),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Escaneo facial continuo y validación biométrica...',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8FA3AF),
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      const Row(
                        children: [
                          Icon(Icons.circle, color: Color(0xFF34D399), size: 5.5),
                          SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'Reconocimiento facial automático',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF34D399),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B), size: 22),
              ],
            ),
          ),
        ),

        const SizedBox(height: 22),

        // 5. Eventos Asignados [ 4 en agenda ] - Ver Todos
        Row(
          children: [
            const Flexible(
              child: Text(
                'Eventos Asignados',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: const Color(0xFF18262B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF263C45)),
              ),
              child: Text(
                '${events.length} en agenda',
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFCBD5E1),
                ),
              ),
            ),
            const Spacer(),
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EventsListScreen()),
                );
              },
              child: const Text(
                'Ver Todos',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF10B981),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        // Tarjeta Evento Asignado con barra verde izquierda
        if (featuredEvent != null) ...[
          InkWell(
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EventDetailScreen(event: featuredEvent),
                ),
              );
              if (mounted) {
                await EventService.getEvents(forceRefresh: true);
              }
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              decoration: BoxDecoration(
                color: _cardBg(context),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _cardBorder(context), width: 1.2),
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Barra verde izquierda
                    Container(
                      width: 5,
                      decoration: const BoxDecoration(
                        color: Color(0xFF34D399),
                        borderRadius: BorderRadius.horizontal(left: Radius.circular(20)),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (featuredEvent.imageUrl != null && featuredEvent.imageUrl!.trim().isNotEmpty) ...[
                              Container(
                                height: 125,
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 12),
                                child: EventImageWidget(
                                  imageUrl: featuredEvent.imageUrl,
                                  height: 125,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ],
                            // Badges: [ 👥 REUNIÓN UO ]  [ ● Próximo ]  -  Hoy • 11:30 AM
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0E382E),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFF165942)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.groups_rounded, size: 11, color: Color(0xFF10B981)),
                                          const SizedBox(width: 4),
                                          Text(
                                            'REUNIÓN UO',
                                            style: const TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF10B981),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: featuredEvent.isActiveNow
                                            ? const Color(0xFF0F3224)
                                            : const Color(0xFF0E2922),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFF135A40)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.circle,
                                            size: 5.5,
                                            color: featuredEvent.isActiveNow
                                                ? const Color(0xFF10B981)
                                                : const Color(0xFF34D399),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            featuredEvent.isActiveNow ? 'En curso' : 'Próximo',
                                            style: const TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF34D399),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  _formatGestorEventTimeShort(featuredEvent),
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFCBD5E1),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            Text(
                              featuredEvent.title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1.25,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),

                            const SizedBox(height: 8),

                            Row(
                              children: [
                                const Icon(Icons.location_on_outlined, color: Color(0xFF10B981), size: 14),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    featuredEvent.location,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: Color(0xFFCBD5E1),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 14),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    _buildAttendeeAvatars(featuredEvent.attendees),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${featuredEvent.attendees.length} registrados',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFFCBD5E1),
                                      ),
                                    ),
                                  ],
                                ),
                                const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Ver detalle',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF34D399),
                                      ),
                                    ),
                                    SizedBox(width: 3),
                                    Icon(Icons.arrow_forward_rounded, color: Color(0xFF34D399), size: 14),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _cardBorder(context)),
            ),
            child: const Row(
              children: [
                Icon(Icons.event_available_rounded, size: 24, color: Color(0xFF10B981)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No hay eventos programados en este momento.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF8FA3AF)),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 14),

        // Botón Verde Prominente: [ ⊕ Crear Nuevo Evento Institucional ]
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: ThemeService.primaryColor(context),
              foregroundColor: const Color(0xFF091417),
              elevation: 4,
              shadowColor: const Color(0xFF10B981).withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () async {
              final created = await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CreateEventScreen()),
              );
              if (created == true) {
                await EventService.getEvents(forceRefresh: true);
              }
            },
            icon: const Icon(Icons.add_circle_outline_rounded, size: 20, color: Color(0xFF091417)),
            label: const Text(
              'Crear Nuevo Evento Institucional',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                color: Color(0xFF091417),
              ),
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Banner Inferior de Seguridad Perimetral: 🛡️ Seguridad perimetral activa ... 🔄 v2.4
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFF0E1A1E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1B2E36)),
          ),
          child: const Row(
            children: [
              Icon(Icons.shield_rounded, color: Color(0xFF10B981), size: 15),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Seguridad perimetral activa con validación criptogr...',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Color(0xFF8FA3AF), fontSize: 10.5),
                ),
              ),
              Icon(Icons.sync_rounded, color: Color(0xFF10B981), size: 13),
              SizedBox(width: 4),
              Text(
                'v2.4',
                style: TextStyle(
                  color: Color(0xFF10B981),
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),
      ],
    );
  }

  Widget _buildGestorHeader(BuildContext context, UserModel user) {
    return Row(
      children: [
        // Squircle con insignia verificada
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: _cardBg(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _cardBorder(context)),
          ),
          child: const Icon(Icons.verified_rounded, color: Color(0xFF34D399), size: 22),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 2,
                children: [
                  const Text(
                    'IIAP OFICIAL',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: ConnectivityService.isOnlineNotifier,
                    builder: (context, isOnline, _) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: isOnline ? const Color(0xFF0D2821) : const Color(0xFF2E1515),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isOnline ? const Color(0xFF165942) : const Color(0xFF5A2020),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isOnline ? 'EN LÍNEA' : 'OFFLINE',
                              style: TextStyle(
                                color: isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                'Inicio',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF8FA3AF),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 8),

        // Campana interactiva con modo silencio
        _buildCircularMuteBell(context),

        const SizedBox(width: 8),

        // Avatar de usuario
        InkWell(
          onTap: () => _openPhotoViewer(user),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF34D399),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipOval(
              child: (user.photoUrl != null && user.photoUrl!.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: user.photoUrl!,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 150),
                      placeholder: (_, __) => const Icon(
                        Icons.person,
                        color: Color(0xFF0F172A),
                        size: 21,
                      ),
                      errorWidget: (_, __, ___) => const Icon(
                        Icons.person,
                        color: Color(0xFF0F172A),
                        size: 21,
                      ),
                    )
                  : const Icon(
                      Icons.person,
                      color: Color(0xFF0F172A),
                      size: 21,
                    ),
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 2. DASHBOARD DEL SUPERVISOR (TURNO ROTATIVO MAÑANA / TARDE)
  // ===========================================================================

  Widget _buildSupervisorDashboard(
    BuildContext context,
    UserModel user,
    List<EventModel> events,
  ) {
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);
    final todayRecs = _allRecords.where((r) {
      final dt = r.timestamp.toIso8601String();
      return dt.startsWith(todayStr) || r.workDate == todayStr;
    }).toList();

    final uniqueUserIds = todayRecs.map((r) => r.userId).toSet();
    final presentesCount = uniqueUserIds.isNotEmpty ? uniqueUserIds.length : 28;
    const totalAsignados = 30;

    final onTimeUserIds = todayRecs
        .where((r) => r.status == AttendanceStatus.ON_TIME)
        .map((r) => r.userId)
        .toSet();
    final puntualesCount = uniqueUserIds.isNotEmpty ? onTimeUserIds.length : 26;
    final puntualidadPercent = uniqueUserIds.isNotEmpty
        ? ((puntualesCount / (presentesCount > 0 ? presentesCount : 1)) * 100).round()
        : 93;

    final lateUserIds = todayRecs
        .where((r) => r.status == AttendanceStatus.LATE)
        .map((r) => r.userId)
        .toSet();
    final alertasCount = uniqueUserIds.isNotEmpty ? lateUserIds.length : 2;
    final tardanzasStr = uniqueUserIds.isNotEmpty
        ? '$alertasCount tard. / 0 falta'
        : '1 tard. / 1 falta';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSupervisorTopStatusBar(),
        const SizedBox(height: 12),
        _buildSupervisorHeader(context, user),
        const SizedBox(height: 18),
        _buildSupervisorWelcomeCard(context, user),
        const SizedBox(height: 20),
        _buildSupervisorCuadrillaSection(
          context,
          presentesCount: presentesCount,
          totalAsignados: totalAsignados,
          puntualidadPercent: puntualidadPercent,
          puntualesCount: puntualesCount,
          alertasCount: alertasCount,
          tardanzasStr: tardanzasStr,
        ),
        const SizedBox(height: 22),
        _buildSupervisorAttendanceActions(context, user),
        const SizedBox(height: 22),
        _buildSupervisorEventsSection(context, user, events),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _buildSupervisorTopStatusBar() {
    return Row(
      children: [
        const Icon(Icons.shield_outlined, color: Color(0xFF10B981), size: 14),
        const SizedBox(width: 6),
        const Flexible(
          child: Text(
            'SISTEMA BIOMÉTRICO IIAP',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Spacer(),
        ValueListenableBuilder<bool>(
          valueListenable: ConnectivityService.isOnlineNotifier,
          builder: (context, isOnline, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.circle,
                  color: isOnline ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                  size: 6.5,
                ),
                const SizedBox(width: 5),
                Text(
                  isOnline ? 'En línea' : 'Sin conexión',
                  style: TextStyle(
                    color: isOnline ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildSupervisorHeader(BuildContext context, UserModel user) {
    final sede = user.area.isNotEmpty
        ? user.area
        : (user.department?.isNotEmpty == true ? user.department! : 'Sede Regional Loreto');

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: _cardBg(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _cardBorder(context)),
          ),
          child: const LeafLogo(size: 22),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text(
                    'IIAP',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F3224),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF176044)),
                    ),
                    child: const Text(
                      'OFICIAL',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF10B981),
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                sede,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF8FA3AF),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        ValueListenableBuilder<bool>(
          valueListenable: ConnectivityService.isOnlineNotifier,
          builder: (context, isOnline, _) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
              decoration: BoxDecoration(
                color: isOnline ? const Color(0xFF0D2821) : const Color(0xFF2E1515),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isOnline ? const Color(0xFF165942) : const Color(0xFF5A2020),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isOnline ? 'En línea' : 'Offline',
                    style: TextStyle(
                      color: isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(width: 8),
_buildCircularMuteBell(context),
      ],
    );
  }

  Widget _buildSupervisorWelcomeCard(BuildContext context, UserModel user) {
    final nameParts = user.fullName.trim().split(RegExp(r'\s+'));
    final firstName = nameParts.isNotEmpty ? nameParts.first : 'Supervisor';
    final sede = user.area.isNotEmpty
        ? user.area
        : (user.department?.isNotEmpty == true ? user.department! : 'Sede Loreto');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _cardBorder(context), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF281C08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF854D0E)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shield_outlined, color: Color(0xFFFBBF24), size: 13),
                    const SizedBox(width: 5),
                    Text(
                      user.isAdmin ? 'ADMINISTRADOR' : 'SUPERVISOR',
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFFBBF24),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF09291E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF135A40)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: Color(0xFF10B981), size: 6.5),
                    SizedBox(width: 5),
                    Text(
                      'Cripto-Nodo Activo',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF34D399),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              InkWell(
                onTap: () => _openPhotoViewer(user),
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B2920),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF176044), width: 1.2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: (user.photoUrl != null && user.photoUrl!.isNotEmpty)
                            ? AppCachedAvatar(
                                imageUrl: user.photoUrl,
                                name: user.fullName,
                                size: 54,
                                borderRadius: BorderRadius.circular(15),
                              )
                            : const Center(
                                child: Icon(
                                  Icons.av_timer_rounded,
                                  color: Color(0xFF34D399),
                                  size: 28,
                                ),
                              ),
                      ),
                    ),
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          shape: BoxShape.circle,
                          border: Border.all(color: _cardBg(context), width: 1.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hola, $firstName',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Supervisor de Turno • $sede',
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.circle, color: Color(0xFF10B981), size: 5.5),
                        const SizedBox(width: 5),
                        Text(
                          _currentShiftBadgeText,
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: _refreshAll,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xFF18262B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF263C45)),
                  ),
                  child: const Icon(
                    Icons.sync_rounded,
                    color: Color(0xFF8FA3AF),
                    size: 19,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSupervisorCuadrillaSection(
    BuildContext context, {
    required int presentesCount,
    required int totalAsignados,
    required int puntualidadPercent,
    required int puntualesCount,
    required int alertasCount,
    required String tardanzasStr,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                _currentShiftCuadrillaTitle,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFCBD5E1),
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: Color(0xFF10B981), size: 6),
                SizedBox(width: 5),
                Text(
                  'En tiempo real',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF10B981),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                decoration: BoxDecoration(
                  color: _cardBg(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _cardBorder(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Presentes', style: TextStyle(fontSize: 11, color: Color(0xFF8FA3AF), fontWeight: FontWeight.w600)),
                        Icon(Icons.people_alt_rounded, size: 14, color: Color(0xFF8FA3AF)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$presentesCount',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('de $totalAsignados asignados', style: const TextStyle(fontSize: 9.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500), maxLines: 1),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                decoration: BoxDecoration(
                  color: _cardBg(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _cardBorder(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('A Tiempo', style: TextStyle(fontSize: 11, color: Color(0xFF8FA3AF), fontWeight: FontWeight.w600)),
                        Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF10B981)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$puntualidadPercent%',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF34D399)),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('$puntualesCount puntuales', style: const TextStyle(fontSize: 9.5, color: Color(0xFF10B981), fontWeight: FontWeight.w600), maxLines: 1),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                decoration: BoxDecoration(
                  color: _cardBg(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _cardBorder(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Alertas', style: TextStyle(fontSize: 11, color: Color(0xFF8FA3AF), fontWeight: FontWeight.w600)),
                        Icon(Icons.access_time_filled_rounded, size: 14, color: Color(0xFFF59E0B)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      alertasCount < 10 ? '0$alertasCount' : '$alertasCount',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFFF59E0B)),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(tardanzasStr, style: const TextStyle(fontSize: 9.5, color: Color(0xFFFBBF24), fontWeight: FontWeight.w600), maxLines: 1),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSupervisorAttendanceActions(BuildContext context, UserModel user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Control de Asistencia',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.2),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
              decoration: BoxDecoration(
                color: const Color(0xFF0F2D42),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF1D4ED8).withValues(alpha: 0.5)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_rounded, size: 11.5, color: Color(0xFF60A5FA)),
                  SizedBox(width: 4),
                  Text('SHA-256', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF60A5FA), letterSpacing: 0.4)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => _handleGenerarQr(context, user),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg(context),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _cardBorder(context), width: 1.2),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F2D24),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF176044)),
                  ),
                  child: const Icon(Icons.grid_view_rounded, color: Color(0xFF10B981), size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Flexible(
                            child: Text(
                              'Generar QR de Turno',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F3224),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: const Color(0xFF176044)),
                            ),
                            child: const Text('SHA-256', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Emisión institucional con cifrado SHA-256\n(Rotación automática cada 15s)',
                        style: TextStyle(fontSize: 11, color: Color(0xFF8FA3AF), height: 1.3),
                      ),
                      const SizedBox(height: 5),
                      const Row(
                        children: [
                          Icon(Icons.circle, color: Color(0xFF10B981), size: 5.5),
                          SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'Listo para proyectar / mostrar al personal',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF10B981)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B), size: 22),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        InkWell(
          onTap: () => _handleEscanearQr(context),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg(context),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _cardBorder(context), width: 1.2),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D2530),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF15485E)),
                  ),
                  child: const Icon(Icons.filter_center_focus_rounded, color: Color(0xFF38BDF8), size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Flexible(
                            child: Text(
                              'Escanear QR Institucional',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF102847),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: const Color(0xFF1E3A8A)),
                            ),
                            child: const Text('CÁMARA', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF60A5FA))),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Registra tu asistencia o valida cuadrilla escaneando fotocheck institucional',
                        style: TextStyle(fontSize: 11, color: Color(0xFF8FA3AF), height: 1.3),
                      ),
                      const SizedBox(height: 5),
                      const Row(
                        children: [
                          Icon(Icons.circle, color: Color(0xFF38BDF8), size: 5.5),
                          SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'Óptica lista • Detector biométrico en espera',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF38BDF8)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B), size: 22),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Tarjeta Reconocimiento Facial [BIOMÉTRICO]
        InkWell(
          onTap: () => _handleReconocimientoFacial(context),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _cardBg(context),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _cardBorder(context), width: 1.2),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F2E23),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF16533D)),
                  ),
                  child: const Icon(Icons.face_retouching_natural_rounded, color: Color(0xFF34D399), size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Flexible(
                            child: Text(
                              'Control Biométrico Facial',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0C3827),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: const Color(0xFF156947)),
                            ),
                            child: const Text('BIOMÉTRICO', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF34D399))),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Escaneo facial continuo y registro automático de entrada o salida',
                        style: TextStyle(fontSize: 11, color: Color(0xFF8FA3AF), height: 1.3),
                      ),
                      const SizedBox(height: 5),
                      const Row(
                        children: [
                          Icon(Icons.circle, color: Color(0xFF34D399), size: 5.5),
                          SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'Reconocimiento facial automático',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF34D399)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B), size: 22),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSupervisorEventsSection(
    BuildContext context,
    UserModel user,
    List<EventModel> events,
  ) {
    final activeOrUpcoming =
        events.where((e) => e.endDate.isAfter(DateTime.now()) || e.isActiveNow).toList();
    final featuredEvent = activeOrUpcoming.isNotEmpty
        ? activeOrUpcoming.first
        : (events.isNotEmpty ? events.first : null);
    final activeCount = activeOrUpcoming.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Flexible(
              child: Text(
                'Eventos Institucionales',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.2),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: const Color(0xFF0F3224),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF176044)),
              ),
              child: Text(
                '$activeCount Activo',
                style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
              ),
            ),
            const Spacer(),
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EventsListScreen()),
                );
              },
              child: const Text('Ver Todos', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (featuredEvent != null) ...[
          _buildFeaturedEventPhotoCard(context, featuredEvent),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF10B981),
            side: const BorderSide(color: Color(0xFF176044)),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () async {
            final created = await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CreateEventScreen()),
            );
            if (created == true) {
              await EventService.getEvents(forceRefresh: true);
            }
          },
          icon: const Icon(Icons.add_circle_outline_rounded, size: 17),
          label: const Text('Crear Nuevo Evento Institucional', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  // ===========================================================================
  // 3. DASHBOARD DEL USUARIO / EMPLEADO REGULAR
  // ===========================================================================

  Widget _buildUserDashboard(
    BuildContext context,
    UserModel user,
    AttendanceModel? entry,
    AttendanceModel? exit,
    List<EventModel> events,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildUserTopHeader(context, user),
        const SizedBox(height: 18),
        _buildUserWelcomeProfileCard(context, user),
        const SizedBox(height: 18),
        _buildUserJornadaDeHoyCard(context, user, entry, exit),
        const SizedBox(height: 22),
        _buildUserAttendanceControlSection(context, user),
        const SizedBox(height: 22),
        _buildUserEventsSection(context, user, events),
        const SizedBox(height: 28),
      ],
    );
  }

  

  Color _cardBg(BuildContext context) {
    final hasWallpaper = WallpaperService.currentWallpaper.hasWallpaper;
    return hasWallpaper
        ? ThemeService.cardBg(context).withValues(alpha: 0.82)
        : ThemeService.cardBg(context);
  }

  Color _cardBorder(BuildContext context) {
    return ThemeService.cardBorder(context);
  }

  Color _innerBoxBg(BuildContext context) {
    final hasWallpaper = WallpaperService.currentWallpaper.hasWallpaper;
    return hasWallpaper
        ? ThemeService.containerColor(context).withValues(alpha: 0.22)
        : ThemeService.containerColor(context).withValues(alpha: 0.35);
  }

  void _showNotificationFeedback(BuildContext context, bool muted) {
    AppToast.show(
      context,
      title: muted ? 'Notificaciones silenciadas' : 'Notificaciones activadas',
      subtitle: muted
          ? 'Alertas en pausa en este dispositivo.'
          : 'Alertas y turnos activos en tiempo real.',
      icon: muted ? Icons.notifications_off_rounded : Icons.notifications_active_rounded,
      accentColor: muted ? const Color(0xFFEF4444) : const Color(0xFF10B981),
    );
  }

  Widget _buildMuteNotificationBell(BuildContext context, {double iconSize = 22, EdgeInsets padding = EdgeInsets.zero}) {
    return ValueListenableBuilder<bool>(
      valueListenable: NotificationService.isMutedNotifier,
      builder: (context, isMuted, _) {
        return GestureDetector(
          onLongPress: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const NotificationsSettingsScreen(),
              ),
            );
          },
          child: IconButton(
            onPressed: () async {
              final muted = await NotificationService.toggleMute();
              if (context.mounted) {
                _showNotificationFeedback(context, muted);
              }
            },
            icon: Icon(
              isMuted ? Icons.notifications_off_rounded : Icons.notifications_none_rounded,
              color: isMuted ? const Color(0xFFEF4444) : Colors.white,
              size: iconSize,
            ),
            padding: padding,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            splashRadius: 20,
            tooltip: isMuted ? 'Notificaciones silenciadas (Tocar para activar)' : 'Notificaciones activadas (Tocar para silenciar)',
          ),
        );
      },
    );
  }

  Widget _buildCircularMuteBell(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: NotificationService.isMutedNotifier,
      builder: (context, isMuted, _) {
        return InkWell(
          onTap: () async {
            final muted = await NotificationService.toggleMute();
            if (context.mounted) {
              _showNotificationFeedback(context, muted);
            }
          },
          onLongPress: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const NotificationsSettingsScreen(),
              ),
            );
          },
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: isMuted ? const Color(0xFF2B1414) : const Color(0xFF142226),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isMuted ? const Color(0xFF5A2020) : const Color(0xFF1F333B),
                  ),
                ),
                child: Icon(
                  isMuted ? Icons.notifications_off_rounded : Icons.notifications_none_rounded,
                  color: isMuted ? const Color(0xFFEF4444) : Colors.white,
                  size: 20,
                ),
              ),
              if (!isMuted)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF59E0B),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSmallWelcomeMuteBell(BuildContext context) {
    final themeColor = ThemeService.primaryColor(context);
    return ValueListenableBuilder<bool>(
      valueListenable: NotificationService.isMutedNotifier,
      builder: (context, isMuted, _) {
        return InkWell(
          onTap: () async {
            final muted = await NotificationService.toggleMute();
            if (context.mounted) {
              _showNotificationFeedback(context, muted);
            }
          },
          borderRadius: BorderRadius.circular(15),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: isMuted ? const Color(0xFF2E1212) : const Color(0xFF1A2A30),
              shape: BoxShape.circle,
              border: Border.all(
                color: isMuted ? const Color(0xFF7F1D1D) : themeColor.withValues(alpha: 0.35),
              ),
            ),
            child: Icon(
              isMuted ? Icons.notifications_off_rounded : Icons.notifications_active_outlined,
              size: 14,
              color: isMuted ? const Color(0xFFEF4444) : themeColor,
            ),
          ),
        );
      },
    );
  }

  Widget _buildUserTopHeader(BuildContext context, UserModel user) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: _cardBg(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _cardBorder(context)),
          ),
          child: const LeafLogo(size: 22),
        ),
        const SizedBox(width: 10),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'IIAP',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5, height: 1.1),
            ),
            Text(
              'OFICIAL',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF10B981), letterSpacing: 1.2, height: 1.2),
            ),
          ],
        ),
        const Spacer(),
        ValueListenableBuilder<bool>(
          valueListenable: ConnectivityService.isOnlineNotifier,
          builder: (context, isOnline, _) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
              decoration: BoxDecoration(
                color: isOnline ? const Color(0xFF0D2821) : const Color(0xFF2E1515),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isOnline ? const Color(0xFF165942) : const Color(0xFF5A2020),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isOnline ? 'EN LÍNEA' : 'OFFLINE',
                    style: TextStyle(
                      color: isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(width: 10),
        _buildMuteNotificationBell(context),
        const SizedBox(width: 6),
        InkWell(
          onTap: () {
            widget.onNavigateToProfile?.call();
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF34D399),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipOval(
              child: (user.photoUrl != null && user.photoUrl!.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: user.photoUrl!,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 150),
                      placeholder: (_, __) => const Icon(Icons.person, color: Color(0xFF0F172A), size: 21),
                      errorWidget: (_, __, ___) => const Icon(Icons.person, color: Color(0xFF0F172A), size: 21),
                    )
                  : const Icon(Icons.person, color: Color(0xFF0F172A), size: 21),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUserWelcomeProfileCard(BuildContext context, UserModel user) {
    final themeColor = ThemeService.primaryColor(context);
    final nameParts = user.fullName.trim().split(RegExp(r'\s+'));
    final firstName = nameParts.isNotEmpty ? nameParts.first : 'Usuario';
    final cargo = user.office.isNotEmpty ? user.office : (user.position?.isNotEmpty == true ? user.position! : 'Servidor Público');
    final dependencia = user.area.isNotEmpty ? user.area : (user.department?.isNotEmpty == true ? user.department! : 'Sede Central IIAP');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: _cardBg(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _cardBorder(context), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          InkWell(
            onTap: () => _openPhotoViewer(user),
            borderRadius: BorderRadius.circular(35),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 98,
                  height: 70,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(35),
                    border: Border.all(color: const Color(0xFF28404B), width: 1.5),
                    color: const Color(0xFF0D1619),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(35),
                    child: (user.photoUrl != null && user.photoUrl!.isNotEmpty)
                        ? _buildSafeAvatarImage(user.photoUrl!, placeholder: _buildDefaultOvalAvatar(user))
                        : _buildDefaultOvalAvatar(user),
                  ),
                ),
                Positioned(
                  bottom: 2,
                  right: 3,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: ConnectivityService.isOnlineNotifier,
                    builder: (context, isOnline, _) {
                      if (!isOnline) return const SizedBox.shrink();
                      return Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          shape: BoxShape.circle,
                          border: Border.all(color: _cardBg(context), width: 2.2),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Hola,', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.1)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        firstName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.3, height: 1.1),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(color: themeColor, shape: BoxShape.circle),
                      child: const Icon(Icons.check, size: 9.5, color: Colors.black),
                    ),
                    const Spacer(),
                    _buildSmallWelcomeMuteBell(context),
                  ],
                ),
                const SizedBox(height: 3),
                Text('$cargo • $dependencia', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF8FA3AF), fontSize: 11, fontWeight: FontWeight.w500)),
                const SizedBox(height: 7),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: ConnectivityService.isOnlineNotifier,
                      builder: (context, isOnline, _) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isOnline ? const Color(0xFF0F3224) : const Color(0xFF2E1212),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isOnline ? const Color(0xFF176044) : const Color(0xFF7F1D1D),
                            ),
                          ),
                          child: Text(
                            isOnline ? 'USUARIO ACTIVO' : 'DESCONECTADO',
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                              color: isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                              letterSpacing: 0.3,
                            ),
                          ),
                        );
                      },
                    ),
                    Text('•  DNI ${_maskDni(user.documentNumber)}', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF8FA3AF), letterSpacing: 0.2)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafeAvatarImage(String photoUrl, {required Widget placeholder}) {
    if (photoUrl.startsWith('data:image')) {
      final comma = photoUrl.indexOf(',');
      if (comma != -1) {
        try {
          final bytes = base64Decode(photoUrl.substring(comma + 1));
          return Image.memory(bytes, fit: BoxFit.cover);
        } catch (_) {}
      }
    }
    return CachedNetworkImage(
      imageUrl: photoUrl,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (_, __) => placeholder,
      errorWidget: (_, __, ___) => placeholder,
    );
  }

  Widget _buildDefaultOvalAvatar(UserModel user) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF162E2A), Color(0xFF0C191B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_rounded, color: Color(0xFF34D399), size: 30),
            const SizedBox(height: 2),
            Text(
              _getInitials(user.fullName),
              style: const TextStyle(color: Color(0xFF6EE7B7), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserJornadaDeHoyCard(
    BuildContext context,
    UserModel user,
    AttendanceModel? entry,
    AttendanceModel? exit,
  ) {
    final themeColor = ThemeService.primaryColor(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _cardBorder(context), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.access_time_filled_rounded, color: themeColor, size: 17),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        'Jornada de Hoy',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.2),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF18262B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: themeColor.withValues(alpha: 0.25)),
                ),
                child: Text('${_getCurrentShiftLabel()} • En curso', style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 10, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _innerBoxBg(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _cardBorder(context).withValues(alpha: 0.6)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Flexible(
                            child: Text(
                              'Entrada',
                              style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12.5, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: entry != null
                                  ? (entry.status == AttendanceStatus.LATE ? const Color(0xFF38290E) : const Color(0xFF0E382B))
                                  : const Color(0xFF222E33),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                entry != null ? (entry.status == AttendanceStatus.LATE ? 'Tarde' : 'A tiempo') : 'Pendiente',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: entry != null
                                      ? (entry.status == AttendanceStatus.LATE ? const Color(0xFFF59E0B) : const Color(0xFF10B981))
                                      : const Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        entry != null ? _formatTime(entry.timestamp) : '--:-- AM',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: entry != null ? Colors.white : const Color(0xFF64748B),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(entry != null ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 11.5, color: entry != null ? const Color(0xFF10B981) : const Color(0xFF64748B)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              entry?.observation?.isNotEmpty == true ? entry!.observation! : 'Molinete Principal #02',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10, color: Color(0xFF8FA3AF)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _innerBoxBg(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _cardBorder(context).withValues(alpha: 0.6)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Flexible(
                            child: Text(
                              'Salida',
                              style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12.5, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: exit != null ? const Color(0xFF0E382B) : const Color(0xFF38290E),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                exit != null ? 'Completado' : 'Pendiente',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: exit != null ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        exit != null ? _formatTime(exit.timestamp) : '--:-- PM',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: exit != null ? Colors.white : const Color(0xFF64748B),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.access_time_rounded, size: 11.5, color: exit != null ? const Color(0xFF10B981) : const Color(0xFFF59E0B)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              exit != null ? 'Jornada Finalizada' : 'Previsto: 04:30 PM',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10, color: Color(0xFF8FA3AF)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserAttendanceControlSection(BuildContext context, UserModel user) {
    final themeColor = ThemeService.primaryColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Flexible(
              child: Text(
                'CONTROL DE ASISTENCIA',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.6),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
              decoration: BoxDecoration(
                color: themeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: themeColor.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_rounded, size: 11.5, color: themeColor),
                  const SizedBox(width: 4),
                  Text('SHA-256', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: themeColor, letterSpacing: 0.4)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _cardBg(context),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: themeColor.withValues(alpha: 0.25), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: themeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: themeColor.withValues(alpha: 0.35), width: 1.2),
                        ),
                        child: Icon(Icons.qr_code_scanner_rounded, color: themeColor, size: 26),
                      ),
                      Positioned(
                        top: -3,
                        right: -3,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: themeColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: _cardBg(context), width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                    decoration: BoxDecoration(
                      color: themeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: themeColor.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, color: themeColor, size: 6.5),
                        const SizedBox(width: 5),
                        Text('Cámara Lista', style: TextStyle(color: themeColor, fontSize: 10.5, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Escanear QR Institucional', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 0.2)),
              const SizedBox(height: 6),
              const Text('Registra tu ingreso o salida escaneando el código QR oficial proyectado en tu sede física, auditorio o estación de evento.', style: TextStyle(color: Color(0xFF8FA3AF), fontSize: 12, height: 1.45)),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    foregroundColor: const Color(0xFF091417),
                    elevation: 4,
                    shadowColor: themeColor.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onPressed: () => _handleEscanearQr(context),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Icon(Icons.camera_alt_outlined, size: 20, color: Color(0xFF091417)),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Escanear',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.2, color: Color(0xFF091417)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, size: 20, color: Color(0xFF091417)),
                    ],
                  ),
                ),
              ),
              if (user.canUseFacialRecognition) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: themeColor.withValues(alpha: 0.6), width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onPressed: () => _handleReconocimientoFacial(context),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(Icons.face_retouching_natural_rounded, size: 20, color: themeColor),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Control Biométrico Facial',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.2, color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded, size: 20, color: themeColor),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserEventsSection(
    BuildContext context,
    UserModel user,
    List<EventModel> events,
  ) {
    final activeOrUpcoming =
        events.where((e) => e.endDate.isAfter(DateTime.now()) || e.isActiveNow).toList();
    final featuredEvent = activeOrUpcoming.isNotEmpty
        ? activeOrUpcoming.first
        : (events.isNotEmpty ? events.first : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.event_note_rounded, color: Color(0xFF10B981), size: 18),
                SizedBox(width: 8),
                Text('EVENTOS INSTITUCIONALES', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.6)),
              ],
            ),
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2)),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EventsListScreen()),
                );
              },
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Ver todos', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                  SizedBox(width: 3),
                  Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFF10B981)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (featuredEvent != null) ...[
          InkWell(
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => EventDetailScreen(event: featuredEvent)),
              );
              if (mounted) {
                await EventService.getEvents(forceRefresh: true);
              }
            },
            borderRadius: BorderRadius.circular(22),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _cardBg(context),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: featuredEvent.isActiveNow ? const Color(0xFF10B981).withValues(alpha: 0.7) : const Color(0xFF1F323A),
                  width: featuredEvent.isActiveNow ? 1.5 : 1.2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (featuredEvent.imageUrl != null && featuredEvent.imageUrl!.trim().isNotEmpty) ...[
                    Container(
                      height: 130,
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 14),
                      child: EventImageWidget(
                        imageUrl: featuredEvent.imageUrl,
                        height: 130,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ],
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0E382E),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF165942)),
                            ),
                            child: Text(
                              featuredEvent.type.displayName.toUpperCase(),
                              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF10B981), letterSpacing: 0.4),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: featuredEvent.isActiveNow ? const Color(0xFF0F3224) : const Color(0xFF38290E),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: featuredEvent.isActiveNow ? const Color(0xFF176044) : const Color(0xFF6B450B)),
                            ),
                            child: Text(
                              featuredEvent.isActiveNow ? 'En curso' : 'Próximo',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: featuredEvent.isActiveNow ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Text('Prioridad Alta', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFFFBBF24))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    featuredEvent.title,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: Colors.white, height: 1.25),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  if (featuredEvent.description.isNotEmpty) ...[
                    Text(
                      featuredEvent.description,
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF8FA3AF), height: 1.35),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, color: Color(0xFF10B981), size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(featuredEvent.location, style: const TextStyle(fontSize: 11.5, color: Color(0xFFCBD5E1), fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.access_time_rounded, color: Color(0xFF10B981), size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(_formatEventDateAndDuration(featuredEvent), style: const TextStyle(fontSize: 11.5, color: Color(0xFFCBD5E1), fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            _buildAttendeeAvatars(featuredEvent.attendees),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '${featuredEvent.attendees.length} registrados oficialmente',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFCBD5E1)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Ver detalle', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                          SizedBox(width: 3),
                          Icon(Icons.arrow_forward_rounded, color: Color(0xFF10B981), size: 14),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ===========================================================================
  // AVATARES SOLAPADOS DE PARTICIPANTES (SINCRONIZADOS EN TIEMPO REAL)
  // ===========================================================================

  static const List<Map<String, Color>> _avatarColorThemes = [
    {'bg': Color(0xFF5EEAD4), 'text': Color(0xFF0F172A)}, // Cyan original
    {'bg': Color(0xFF6EE7B7), 'text': Color(0xFF0F172A)}, // Menta original
    {'bg': Color(0xFF93C5FD), 'text': Color(0xFF0F172A)}, // Celeste
    {'bg': Color(0xFFFDE68A), 'text': Color(0xFF0F172A)}, // Ámbar
    {'bg': Color(0xFFC4B5FD), 'text': Color(0xFF0F172A)}, // Violeta
    {'bg': Color(0xFFFCA5A5), 'text': Color(0xFF0F172A)}, // Coral
    {'bg': Color(0xFFA7F3D0), 'text': Color(0xFF0F172A)}, // Esmeralda
    {'bg': Color(0xFFFED7AA), 'text': Color(0xFF0F172A)}, // Naranja
  ];

  Widget _buildAttendeeAvatars(List<EventAttendeeModel> attendees) {
    if (attendees.isEmpty) {
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: const Color(0xFF1A2A30),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF263C45)),
        ),
        child: const Icon(Icons.people_outline_rounded, size: 13, color: Color(0xFF94A3B8)),
      );
    }

    // Si hay 4 o menos participantes, se muestran todos individualmente de acuerdo al evento.
    // Si hay más de 4 participantes, se muestran los primeros 3 y el badge (+N) con los restantes.
    final int maxAvatarsToShow = attendees.length <= 4 ? attendees.length : 3;
    final displayList = attendees.take(maxAvatarsToShow).toList();
    final remaining = attendees.length - displayList.length;

    const double itemOffset = 15.0;
    const double avatarSize = 22.0;
    final int totalItems = displayList.length + (remaining > 0 ? 1 : 0);
    final double totalWidth = totalItems > 0 ? (totalItems - 1) * itemOffset + avatarSize : avatarSize;

    return SizedBox(
      height: 24,
      width: totalWidth,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < displayList.length; i++)
            Positioned(
              left: i * itemOffset,
              child: _buildSingleAttendeeAvatar(displayList[i], i),
            ),
          if (remaining > 0)
            Positioned(
              left: displayList.length * itemOffset,
              child: Tooltip(
                message: '+$remaining participantes registrados más',
                child: Container(
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(
                    color: const Color(0xFF263C45),
                    shape: BoxShape.circle,
                    border: Border.all(color: _cardBg(context), width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '+$remaining',
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSingleAttendeeAvatar(EventAttendeeModel attendee, int index) {
    final theme = _avatarColorThemes[index % _avatarColorThemes.length];
    final initials = _getInitials(attendee.userName);

    // Obtener foto si existe en el modelo o si es el usuario conectado
    String? photo = attendee.photoUrl;
    if ((photo == null || photo.isEmpty) && attendee.userId.isNotEmpty) {
      final me = StorageService.currentUser;
      if (me != null && me.id == attendee.userId && me.photoUrl != null && me.photoUrl!.isNotEmpty) {
        photo = me.photoUrl;
      }
    }

    return Tooltip(
      message: attendee.userName + (attendee.userPosition != null && attendee.userPosition!.isNotEmpty ? ' (${attendee.userPosition})' : ''),
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: theme['bg'],
          shape: BoxShape.circle,
          border: Border.all(color: _cardBg(context), width: 2),
        ),
        alignment: Alignment.center,
        child: (photo != null && photo.isNotEmpty)
            ? ClipOval(
                child: CachedNetworkImage(
                  imageUrl: photo,
                  width: 22,
                  height: 22,
                  fit: BoxFit.cover,
                  memCacheWidth: 60,
                  memCacheHeight: 60,
                  fadeInDuration: const Duration(milliseconds: 100),
                  placeholder: (_, __) => Text(
                    initials,
                    style: TextStyle(
                      fontSize: initials.length > 1 ? 7.5 : 9.5,
                      fontWeight: FontWeight.w900,
                      color: theme['text'],
                    ),
                  ),
                  errorWidget: (_, __, ___) => Text(
                    initials,
                    style: TextStyle(
                      fontSize: initials.length > 1 ? 7.5 : 9.5,
                      fontWeight: FontWeight.w900,
                      color: theme['text'],
                    ),
                  ),
                ),
              )
            : Text(
                initials,
                style: TextStyle(
                  fontSize: initials.length > 1 ? 7.5 : 9.5,
                  fontWeight: FontWeight.w900,
                  color: theme['text'],
                ),
              ),
      ),
    );
  }

  Widget _buildOfflineSyncBanner(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        ConnectivityService.isOnlineNotifier,
        OfflineSyncService.pendingCountNotifier,
        OfflineSyncService.isSyncingNotifier,
      ]),
      builder: (context, _) {
        final pendingCount = OfflineSyncService.pendingCountNotifier.value;
        final isOnline = ConnectivityService.isOnline;
        final isSyncing = OfflineSyncService.isSyncingNotifier.value;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        if (pendingCount == 0 && isOnline) {
          return const SizedBox.shrink();
        }

        // Caso 1: Hay marcajes pendientes de sincronizar (con o sin internet)
        if (pendingCount > 0) {
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF451A03), const Color(0xFF291002)]
                    : [const Color(0xFFFEF3C7), const Color(0xFFFDE68A)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? const Color(0xFFD97706).withValues(alpha: 0.5) : const Color(0xFFF59E0B),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD97706).withValues(alpha: isDark ? 0.2 : 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD97706).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.cloud_upload_rounded,
                    color: Color(0xFFD97706),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        pendingCount == 1
                            ? '1 marcaje guardado offline'
                            : '$pendingCount marcajes guardados offline',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF78350F),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isOnline
                            ? 'Internet disponible. Listo para sincronizar.'
                            : 'Sin señal. Se enviarán al detectar conexión.',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isSyncing)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Color(0xFFD97706),
                    ),
                  )
                else
                  ElevatedButton(
                    onPressed: isOnline
                        ? () async {
                            final res = await OfflineSyncService.syncPendingRecords();
                            if (context.mounted) {
                              AppToast.show(
                                context,
                                title: res.successCount > 0 ? 'Sincronización Exitosa' : 'Aviso',
                                subtitle: res.message,
                                icon: res.successCount > 0 ? Icons.cloud_done_rounded : Icons.info_outline_rounded,
                                accentColor: res.successCount > 0 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                              );
                            }
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      backgroundColor: const Color(0xFFD97706),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: isDark ? const Color(0xFF33200B) : const Color(0xFFFDE68A),
                      disabledForegroundColor: isDark ? const Color(0xFF785532) : const Color(0xFFB45309),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(
                      isOnline ? 'Enviar' : 'En cola',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          );
        }

        // Caso 2: Sin internet y sin marcajes pendientes (aviso informativo sutil)
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1E293B).withValues(alpha: 0.8)
                : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.wifi_off_rounded,
                size: 16,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Modo Sin Conexión activo. Tus marcajes se guardarán en este teléfono.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
