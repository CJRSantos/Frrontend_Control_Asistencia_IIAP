import '../../widgets/event_image_widget.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/event_model.dart';
import '../../services/event_service.dart';
import '../../services/storage_service.dart';
import '../../services/theme_service.dart';
import '../../services/wallpaper_service.dart';
import '../../utils/responsive.dart';
import '../qr/qr_scanner_screen.dart';
import '../qr/qr_display_screen.dart';
import '../../services/users_service.dart';
import '../../models/user_model.dart';
import 'create_event_screen.dart';
import 'event_certificate_modal.dart';
import 'event_qr_display_screen.dart';
import 'manual_attendee_modal.dart';
import '../../widgets/app_cached_avatar.dart';
import '../../widgets/app_toast.dart';

class EventDetailScreen extends StatefulWidget {
  final EventModel event;

  const EventDetailScreen({
    super.key,
    required this.event,
  });

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  late EventModel _currentEvent;
  bool _isLoading = false;
  Timer? _liveRefreshTimer;
  bool _isLiveRefreshing = false;
  List<Map<String, dynamic>> _assignedManagers = [];
  Uint8List? _memoizedImageBytes;
  String? _lastDecodedUrl;

  Uint8List? _getOrDecodeImageBytes(String? url) {
    if (url == null || !url.startsWith('data:image')) return null;
    if (_lastDecodedUrl == url && _memoizedImageBytes != null) {
      return _memoizedImageBytes;
    }
    try {
      _lastDecodedUrl = url;
      _memoizedImageBytes = base64Decode(url.split(',').last);
      return _memoizedImageBytes;
    } catch (_) {
      return null;
    }
  }
  int _selectedTab = 0;
  String _attendeeSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _currentEvent = widget.event;
    EventService.eventsNotifier.addListener(_onEventsUpdated);
    _startLiveRefresh();
    _loadManagers();
  }

  void _startLiveRefresh() {
    _liveRefreshTimer?.cancel();
    // Sondeo periódico para reflejar en tiempo real participantes que escanean el QR o se registran vía web/manual
    _liveRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted || _isLiveRefreshing) return;
      _isLiveRefreshing = true;
      try {
        final fresh = await EventService.getEventById(_currentEvent.id);
        if (fresh != null && mounted) {
          final attendeesChanged = fresh.attendees.length != _currentEvent.attendees.length;
          final titleChanged = fresh.title != _currentEvent.title;
          final imageChanged = fresh.imageUrl != _currentEvent.imageUrl;
          final statusChanged = fresh.status != _currentEvent.status;
          final managersChanged = fresh.managerIds.length != _currentEvent.managerIds.length;

          if (attendeesChanged || titleChanged || imageChanged || statusChanged || managersChanged) {
            final hadFewer = fresh.attendees.length > _currentEvent.attendees.length;
            setState(() {
              _currentEvent = fresh;
              if (imageChanged) {
                _memoizedImageBytes = _getOrDecodeImageBytes(fresh.imageUrl);
              }
            });
            if (managersChanged || _assignedManagers.isEmpty) {
              _loadManagers();
            }
            if (hadFewer) {
              HapticFeedback.lightImpact();
            }
          }
        }
      } catch (_) {} finally {
        _isLiveRefreshing = false;
      }
    });
  }

  @override
  void dispose() {
    _liveRefreshTimer?.cancel();
    EventService.eventsNotifier.removeListener(_onEventsUpdated);
    super.dispose();
  }

  void _onEventsUpdated() {
    final updated = EventService.eventsNotifier.value.firstWhere(
      (e) => e.id == _currentEvent.id,
      orElse: () => _currentEvent,
    );
    if (mounted && updated != _currentEvent) {
      final hadFewer = updated.attendees.length > _currentEvent.attendees.length;
      setState(() => _currentEvent = updated);
      _loadManagers();
      if (hadFewer) {
        HapticFeedback.lightImpact();
      }
    }
  }

  Future<void> _loadManagers() async {
    try {
      final managers = await EventService.getEventManagers(_currentEvent.id);
      if (mounted) {
        setState(() => _assignedManagers = managers);
      }
    } catch (_) {}
  }

  Future<void> _handleOpenAssignManagerModal() async {
    List<UserModel> users = [];
    try {
      users = await UsersService.findAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando colaboradores: $e'), backgroundColor: const Color(0xFFDC2626)),
      );
      return;
    }

    if (!mounted) return;
    String searchFilter = '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final filtered = users.where((u) {
            final matchesSearch = u.fullName.toLowerCase().contains(searchFilter.toLowerCase()) ||
                u.email.toLowerCase().contains(searchFilter.toLowerCase());
            final notCreator = u.id != _currentEvent.createdById;
            final notAlreadyManager = !_currentEvent.managerIds.contains(u.id);
            return matchesSearch && notCreator && notAlreadyManager;
          }).toList();

          return Container(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            decoration: BoxDecoration(
              color: ThemeService.cardBg(ctx),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(Icons.manage_accounts_rounded, color: Color(0xFF0D9488), size: 24),
                    SizedBox(width: 10),
                    Text(
                      'Asignar Gestor de Evento',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'El usuario seleccionado obtendrá permisos completos para editar, proyectar asistencia y registrar participantes.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 14),
                TextField(
                  onChanged: (val) => setModalState(() => searchFilter = val.trim()),
                  decoration: InputDecoration(
                    hintText: 'Buscar colaborador por nombre o correo...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: filtered.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No se encontraron colaboradores disponibles para asignar.',
                              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final u = filtered[i];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFF0D9488).withValues(alpha: 0.15),
                                child: Text(
                                  u.fullName.isNotEmpty ? u.fullName[0].toUpperCase() : 'U',
                                  style: const TextStyle(color: Color(0xFF0D9488), fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(u.fullName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                              subtitle: Text('${u.email} • ${u.role.displayName}', style: const TextStyle(fontSize: 11.5)),
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0D9488),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () async {
                                  Navigator.of(ctx).pop();
                                  try {
                                    await EventService.addEventManager(_currentEvent.id, u.id);
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('¡${u.fullName} ahora es Gestor de este evento!'),
                                        backgroundColor: const Color(0xFF0D9488),
                                      ),
                                    );
                                    _loadManagers();
                                    await EventService.getEvents(forceRefresh: true);
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error al asignar gestor: $e'), backgroundColor: const Color(0xFFDC2626)),
                                    );
                                  }
                                },
                                child: const Text('Asignar', style: TextStyle(fontSize: 12)),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _handleDesignateManagerQr() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QrDisplayScreen(
          mode: QrMode.roleAssignment,
          targetRole: 'GESTOR_EVENTO',
          targetEventId: _currentEvent.id,
          customTitle: 'Designar Gestor del Evento',
          customSubtitle: 'El usuario escaneará para asumir el control operativo de este evento',
        ),
      ),
    );
  }

  Future<void> _handleRemoveManager(String userId, String userName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Revocar Gestor de Evento'),
        content: Text('¿Deseas retirar a $userName como gestor de este evento?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sí, Retirar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await EventService.removeEventManager(_currentEvent.id, userId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$userName ya no es gestor de este evento.')),
        );
        _loadManagers();
        await EventService.getEvents(forceRefresh: true);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al retirar gestor: $e'), backgroundColor: const Color(0xFFDC2626)),
        );
      }
    }
  }

  String _formatDateTime(DateTime date) {
    const months = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Set', 'Oct', 'Nov', 'Dic'];
    final day = date.day.toString().padLeft(2, '0');
    final month = months[date.month - 1];
    final year = date.year;
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final ampm = date.hour >= 12 ? 'p. m.' : 'a. m.';
    return '$day $month $year, ${hour.toString().padLeft(2, '0')}:$minute $ampm';
  }

  String _formatAttendeeTime(DateTime date) {
    final local = date.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'p. m.' : 'a. m.';
    return '${hour.toString().padLeft(2, '0')}:$minute $ampm';
  }

  Future<void> _handleScanAttendance() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QrScannerScreen(
          target: ScanTarget.eventAttendance,
          eventId: _currentEvent.id,
        ),
      ),
    );
    if (result == true) {
      await _fetchEventDetails();
      if (mounted) {
        AppToast.show(
          context,
          title: '¡Asistencia al evento registrada con éxito!',
          icon: Icons.check_circle_rounded,
          accentColor: const Color(0xFF10B981),
        );
      }
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('¿Eliminar Evento?'),
        content: Text('¿Estás seguro de cancelar y eliminar el evento "${_currentEvent.title}"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await EventService.deleteEvent(_currentEvent.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Evento eliminado')),
          );
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: const Color(0xFFDC2626)),
          );
        }
      }
    }
  }

  Future<void> _handleRemoveAttendee(EventAttendeeModel attendee) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.person_remove_rounded, color: Color(0xFFDC2626), size: 24),
            SizedBox(width: 8),
            Text('¿Estas Seguro?'),
          ],
        ),
        content: Text(
          '¿Estás seguro de eliminar a "${attendee.userName}" de la lista oficial de asistencia de este evento? Si fue un error, la persona podrá volver a registrarse.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              elevation: 0,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        final idToRemove = attendee.id.isNotEmpty ? attendee.id : attendee.userId;
        final updated = await EventService.removeAttendee(
          eventId: _currentEvent.id,
          attendeeId: idToRemove,
        );
        if (mounted) {
          setState(() => _currentEvent = updated);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Se eliminó a ${attendee.userName} del evento.'),
              backgroundColor: const Color(0xFF16A34A),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al eliminar participante: $e'),
              backgroundColor: const Color(0xFFDC2626),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleManualRegisterAttendee() async {
    final updated = await ManualAttendeeModal.show(context, event: _currentEvent);
    if (mounted) {
      if (updated != null) {
        setState(() => _currentEvent = updated);
      }
      await _fetchEventDetails();
    }
  }

  void _handleViewCertificate() {
    final currentUser = StorageService.currentUser;
    if (currentUser == null) return;

    EventAttendeeModel myAttendee;
    try {
      myAttendee = _currentEvent.attendees.firstWhere(
        (a) => a.userId == currentUser.id,
      );
    } catch (_) {
      myAttendee = EventAttendeeModel(
        id: '',
        userId: currentUser.id,
        userName: currentUser.fullName,
        userEmail: currentUser.email,
        userDepartment: currentUser.department,
        userPosition: currentUser.position,
        documentNumber: currentUser.documentNumber,
        registeredAt: DateTime.now(),
        isExternal: false,
      );
    }

    EventCertificateModal.show(context, event: _currentEvent, attendee: myAttendee);
  }

  String _toCalendarFormat(DateTime dt) {
    final utc = dt.toUtc();
    return '${utc.year}${utc.month.toString().padLeft(2, '0')}${utc.day.toString().padLeft(2, '0')}T${utc.hour.toString().padLeft(2, '0')}${utc.minute.toString().padLeft(2, '0')}${utc.second.toString().padLeft(2, '0')}Z';
  }

  Future<void> _handleAddToCalendar() async {
    final startStr = _toCalendarFormat(_currentEvent.startDate);
    final endStr = _toCalendarFormat(_currentEvent.endDate);
    final title = Uri.encodeComponent(_currentEvent.title);
    final desc = Uri.encodeComponent(_currentEvent.description.isNotEmpty ? _currentEvent.description : 'Evento Institucional IIAP');
    final loc = Uri.encodeComponent(_currentEvent.location);

    final googleUrl = 'https://calendar.google.com/calendar/render?action=TEMPLATE&text=$title&dates=$startStr/$endStr&details=$desc&location=$loc';
    final outlookUrl = 'https://outlook.live.com/calendar/0/deeplink/compose?subject=$title&startdt=${_currentEvent.startDate.toIso8601String()}&enddt=${_currentEvent.endDate.toIso8601String()}&body=$desc&location=$loc';

    final width = MediaQuery.sizeOf(context).width;
    final isTabletOrDesktop = width >= 640;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(maxWidth: isTabletOrDesktop ? 520 : double.infinity),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: ThemeService.cardBg(ctx),
            borderRadius: isTabletOrDesktop
                ? BorderRadius.circular(24)
                : const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(20, isTabletOrDesktop ? 22 : 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isTabletOrDesktop) ...[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Row(
                children: [
                  Icon(Icons.calendar_month_rounded, color: Color(0xFF2563EB), size: 24),
                  SizedBox(width: 10),
                  Text(
                    'Añadir a mi Calendario',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Selecciona el calendario de tu preferencia para sincronizar este evento:',
                style: TextStyle(fontSize: 12.5, color: ThemeService.subtextColor(ctx)),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: ThemeService.cardBorder(ctx)),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4285F4).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.event_available_rounded, color: Color(0xFF4285F4), size: 20),
                ),
                title: const Text('Google Calendar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('Sincronizar en Android, iPhone o Web', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final uri = Uri.parse(googleUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: ThemeService.cardBorder(ctx)),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0078D4).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.email_outlined, color: Color(0xFF0078D4), size: 20),
                ),
                title: const Text('Outlook / Microsoft 365', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('Calendario corporativo', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final uri = Uri.parse(outlookUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: ThemeService.cardBorder(ctx)),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: ThemeService.primaryColor(ctx).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.copy_rounded, color: ThemeService.primaryColor(ctx), size: 20),
                ),
                title: const Text('Copiar Datos del Evento', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('Título, fecha, hora y ubicación en portapapeles', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.check_rounded, size: 18),
                onTap: () {
                  Navigator.of(ctx).pop();
                  final text = '${_currentEvent.title}\nFecha: ${_formatDateTime(_currentEvent.startDate)}\nLugar: ${_currentEvent.location}\n${_currentEvent.description}';
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('¡Datos del evento copiados al portapapeles!'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _handleOpenQrDisplay() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventQrDisplayScreen(
          event: _currentEvent,
          initialMode: EventQrMode.registered,
        ),
      ),
    );
  }

  Widget _buildTabItem({
    required int index,
    required IconData icon,
    required String label,
    int? badgeCount,
    Color? customActiveColor,
  }) {
    final isSelected = _selectedTab == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = customActiveColor ?? ThemeService.primaryColor(context);
    final inactiveColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTab = index),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? activeColor : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: isSelected ? activeColor : inactiveColor),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? (isDark ? Colors.white : const Color(0xFF0F172A)) : inactiveColor,
                  ),
                ),
                if (badgeCount != null) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? activeColor.withValues(alpha: 0.22)
                          : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$badgeCount',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? activeColor : inactiveColor,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required Color iconBgColor,
    required String label,
    required String value,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconBgColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: iconBgColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDescriptionContent(bool isDark) {
    if (_currentEvent.description.trim().isEmpty) {
      return Text(
        'Sin descripción o temario especificado para este evento.',
        style: TextStyle(
          fontSize: 13,
          fontStyle: FontStyle.italic,
          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
        ),
      );
    }

    final lines = _currentEvent.description
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.length > 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines.map((line) {
          final cleanText = line.startsWith('-') || line.startsWith('•') || line.startsWith('*')
              ? line.substring(1).trim()
              : line;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF34D399),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    cleanText,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      );
    }

    return Text(
      _currentEvent.description,
      style: TextStyle(
        fontSize: 13.5,
        color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
        height: 1.5,
      ),
    );
  }

  Widget _buildManagersCard(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF0D9488).withValues(alpha: isDark ? 0.4 : 0.25),
          width: 1.3,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D9488).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.manage_accounts_rounded, color: Color(0xFF0D9488), size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Gestores del Evento',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isDark ? Colors.white : const Color(0xFF134E4A),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D9488).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_currentEvent.managerIds.length} Asignados',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0D9488),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Colaboradores facultados para administrar el evento y proyectar códigos QR.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: isDark ? const Color(0xFF99F6E4) : const Color(0xFF115E59),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_assignedManagers.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _assignedManagers.map((m) {
                final name = m['full_name'] ?? m['name'] ?? 'Gestor';
                final userId = m['id'] ?? '';
                return Chip(
                  avatar: CircleAvatar(
                    backgroundColor: const Color(0xFF0D9488),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'G',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  label: Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  deleteIcon: const Icon(Icons.close_rounded, size: 16),
                  onDeleted: () => _handleRemoveManager(userId, name),
                  backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  side: BorderSide(color: const Color(0xFF0D9488).withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D9488),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _handleOpenAssignManagerModal,
                  icon: const Icon(Icons.person_add_rounded, size: 17),
                  label: const Text('+ Asignar Gestor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0D9488),
                    side: const BorderSide(color: Color(0xFF0D9488)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _handleDesignateManagerQr,
                  icon: const Icon(Icons.qr_code_2_rounded, size: 17),
                  label: const Text('Designar con QR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilteredAttendeesList(bool isDark, bool canManage) {
    final q = _attendeeSearchQuery.trim().toLowerCase();
    final attendees = _currentEvent.attendees.where((a) {
      if (q.isEmpty) return true;
      return a.userName.toLowerCase().contains(q) ||
          (a.documentNumber != null && a.documentNumber!.toLowerCase().contains(q)) ||
          (a.shift != null && a.shift!.toLowerCase().contains(q)) ||
          a.userEmail.toLowerCase().contains(q);
    }).toList();

    if (attendees.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111827) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.people_outline_rounded, size: 36, color: ThemeService.subtextColor(context)),
              const SizedBox(height: 10),
              Text(
                q.isEmpty
                    ? 'Aún no hay participantes registrados en este evento.'
                    : 'No se encontraron participantes que coincidan con "$q".',
                style: TextStyle(fontSize: 13, color: ThemeService.subtextColor(context)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: attendees.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final attendee = attendees[index];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111827) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Builder(
                builder: (context) {
                  String? photo = attendee.photoUrl;
                  if ((photo == null || photo.isEmpty) && attendee.userId.isNotEmpty) {
                    final me = StorageService.currentUser;
                    if (me != null && me.id == attendee.userId && me.photoUrl != null && me.photoUrl!.isNotEmpty) {
                      photo = me.photoUrl;
                    }
                  }
                  if (photo != null && photo.isNotEmpty) {
                    return CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFF34D399).withValues(alpha: 0.15),
                      backgroundImage: appCachedImageProvider(photo),
                      onBackgroundImageError: (_, __) {},
                      child: null,
                    );
                  }
                  return CircleAvatar(
                    backgroundColor: const Color(0xFF34D399).withValues(alpha: 0.15),
                    radius: 18,
                    child: Text(
                      attendee.userName.isNotEmpty ? attendee.userName[0].toUpperCase() : 'P',
                      style: const TextStyle(
                        color: Color(0xFF34D399),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          attendee.userName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (attendee.isExternal) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'EXTERNO',
                              style: TextStyle(
                                color: Color(0xFF0284C7),
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                        if (attendee.shift != null && attendee.shift!.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: (attendee.shift == 'manana'
                                      ? const Color(0xFFF59E0B)
                                      : attendee.shift == 'tarde'
                                          ? const Color(0xFFF97316)
                                          : const Color(0xFF6366F1))
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              attendee.shift == 'manana'
                                  ? 'MAÑANA'
                                  : attendee.shift == 'tarde'
                                      ? 'TARDE'
                                      : attendee.shift == 'noche'
                                          ? 'NOCHE'
                                          : attendee.shift!.toUpperCase(),
                              style: TextStyle(
                                color: attendee.shift == 'manana'
                                    ? const Color(0xFFF59E0B)
                                    : attendee.shift == 'tarde'
                                        ? const Color(0xFFF97316)
                                        : const Color(0xFF6366F1),
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      attendee.isExternal || (attendee.documentNumber != null && attendee.documentNumber!.isNotEmpty)
                          ? [
                              if (attendee.documentNumber != null && attendee.documentNumber!.isNotEmpty)
                                'DNI: ${attendee.documentNumber}',
                              if (attendee.phoneNumber != null && attendee.phoneNumber!.isNotEmpty)
                                'Cel: ${attendee.phoneNumber}',
                              if (attendee.career != null && attendee.career!.isNotEmpty)
                                attendee.career!,
                              if (attendee.institution != null && attendee.institution!.isNotEmpty)
                                attendee.institution!,
                            ].join(' • ')
                          : '${attendee.userDepartment ?? attendee.userPosition ?? attendee.userEmail} • ${_formatAttendeeTime(attendee.registeredAt)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: ThemeService.subtextColor(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (canManage) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 19,
                    color: Color(0xFFEF4444),
                  ),
                  tooltip: 'Eliminar participante del evento',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: _isLoading ? null : () => _handleRemoveAttendee(attendee),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _fetchEventDetails() async {
    try {
      final fresh = await EventService.getEventById(_currentEvent.id);
      if (fresh != null && mounted) {
        setState(() => _currentEvent = fresh);
        await _loadManagers();
        return;
      }
      final events = await EventService.getEvents(forceRefresh: true);
      final found = events.firstWhere((e) => e.id == _currentEvent.id, orElse: () => _currentEvent);
      if (mounted) {
        setState(() => _currentEvent = found);
        await _loadManagers();
      }
    } catch (_) {}
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
        final currentUser = StorageService.currentUser;
        final isSuperAdmin = currentUser?.isSuperAdmin == true;
        final isAdmin = currentUser?.isAdmin == true || isSuperAdmin;
        final isAssignedManager = currentUser != null && _currentEvent.managerIds.contains(currentUser.id);
        final canManage = currentUser?.canManageEvents == true || isSuperAdmin || isAdmin || isAssignedManager;
        final canProjectQr = currentUser?.canManageEvents == true || isSuperAdmin || isAdmin || isAssignedManager;
        final canScanAttendance = !isAdmin && !isSuperAdmin && !isAssignedManager;
        final isAlreadyRegistered = currentUser != null && _currentEvent.isUserRegistered(currentUser.id);

        final hasWallpaper = WallpaperService.currentWallpaper.hasWallpaper;
        const mintGreen = Color(0xFF34D399);
        const darkGreen = Color(0xFF064E3B);
        final themePrimary = ThemeService.primaryColor(context);

        final bgColor = hasWallpaper
            ? Colors.transparent
            : ThemeService.scaffoldBg(context);
        final cardBg = hasWallpaper
            ? ThemeService.cardBg(context).withValues(alpha: 0.85)
            : ThemeService.cardBg(context);
        final cardBorder = ThemeService.cardBorder(context);

        return Scaffold(
          backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white : const Color(0xFF0F172A)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            'Detalle del Evento',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
        actions: [
          if (canManage && !_currentEvent.isEventosMirror) ...[
            IconButton(
              tooltip: 'Editar evento',
              icon: Icon(Icons.edit_outlined, color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569), size: 20),
              onPressed: () async {
                final updated = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CreateEventScreen(eventToEdit: _currentEvent),
                  ),
                );
                if (updated != null) {
                  if (updated is EventModel) {
                    setState(() {
                      _currentEvent = updated;
                    });
                  }
                  await _fetchEventDetails();
                }
              },
            ),
            IconButton(
              tooltip: 'Eliminar evento',
              icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFF87171), size: 22),
              onPressed: _confirmDelete,
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(right: 16, left: 4),
            child: AppCachedAvatar(
              imageUrl: StorageService.currentUser?.photoUrl,
              name: StorageService.currentUser?.fullName ?? 'U',
              size: 34,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: mintGreen,
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          onRefresh: _fetchEventDetails,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Responsive.constrained(
              context,
              maxTabletWidth: 760,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 0. PORTADA OFICIAL DEL EVENTO (SI POSEE)
                  if (_currentEvent.imageUrl != null && _currentEvent.imageUrl!.trim().isNotEmpty) ...[
                    Container(
                      height: 190,
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark ? const Color(0xFF1F323A) : const Color(0xFFCBD5E1),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(19),
                        child: EventImageWidget(
                          imageUrl: _currentEvent.imageUrl,
                          fit: BoxFit.cover,
                          height: 190,
                          width: double.infinity,
                          fallbackWidget: const Center(
                            child: Icon(Icons.apartment_rounded, color: Color(0xFF10B981), size: 48),
                          ),
                        ),
                      ),
                    ),
                  ],

                  // 1. FILA DE BADGES SUPERIORES
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (_currentEvent.isEventosMirror) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.5)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.sync_rounded, size: 12, color: Color(0xFF818CF8)),
                              SizedBox(width: 5),
                              Text(
                                'Sistema de Eventos',
                                style: TextStyle(
                                  color: Color(0xFF818CF8),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      // Badge de Tipo de Evento
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF064E3B).withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: mintGreen,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _currentEvent.type.displayName,
                              style: const TextStyle(
                                color: mintGreen,
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Badge de Estado del Evento
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          _currentEvent.status.displayName,
                          style: TextStyle(
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                      // Badge Oficial IIAP
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF064E3B).withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.45)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified_outlined, color: mintGreen, size: 14),
                            SizedBox(width: 5),
                            Text(
                              'Oficial IIAP',
                              style: TextStyle(
                                color: mintGreen,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 2. TÍTULO DEL EVENTO
                  Text(
                    _currentEvent.title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                      height: 1.25,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 3. SUBTÍTULO (Fecha de Inicio • Asistentes)
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today_outlined, size: 14, color: mintGreen),
                          const SizedBox(width: 6),
                          Text(
                            _formatDateTime(_currentEvent.startDate),
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: mintGreen,
                            ),
                          ),
                        ],
                      ),
                      const Text(
                        '•',
                        style: TextStyle(fontSize: 14, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.people_outline_rounded, size: 16, color: mintGreen),
                          const SizedBox(width: 5),
                          Text(
                            '${_currentEvent.attendees.length} Asistentes',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: mintGreen,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 4. DOS BOTONES DE ACCIÓN PRINCIPALES (Solo si tiene permisos: Supervisor, Gestor, Admin o Encargado)
                  if (canProjectQr || canManage) ...[
                    Row(
                      children: [
                        // Botón 1: Proyectar QR
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: themePrimary,
                              foregroundColor: isDark ? Colors.white : const Color(0xFF064E3B),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: _handleOpenQrDisplay,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.qr_code_scanner_rounded, size: 19, color: darkGreen),
                                  const SizedBox(width: 6),
                                  Text(
                                    'QR',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.bold,
                                      color: darkGreen,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Botón 2: Registro Manual
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                              foregroundColor: const Color(0xFFF59E0B),
                              elevation: 0,
                              side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: _handleManualRegisterAttendee,
                            child: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.person_add_alt_1_rounded, size: 18, color: Color(0xFFF59E0B)),
                                  SizedBox(width: 6),
                                  Text(
                                    'Registro Manual',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFF59E0B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                  ],

                  // 5. BARRA DE NAVEGACIÓN DE PESTAÑAS (TABS - Adaptativas según rol)
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                          width: 1.5,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        _buildTabItem(
                          index: 0,
                          icon: Icons.info_outline_rounded,
                          label: 'Info & Temario',
                        ),
                        if (canProjectQr)
                          _buildTabItem(
                            index: 1,
                            icon: Icons.qr_code_scanner_rounded,
                            label: 'Control & QR',
                          ),
                        _buildTabItem(
                          index: canProjectQr ? 2 : 1,
                          icon: Icons.people_outline_rounded,
                          label: 'Participantes',
                          badgeCount: _currentEvent.attendees.length,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 6. CONTENIDO SEGÚN LA PESTAÑA ACTIVA
                  if (_selectedTab == 0) ...[
                    // PESTAÑA 0: Info & Temario
                    // Tarjeta 1: Fechas, Ubicación y Organizador
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
                          _buildInfoItem(
                            icon: Icons.calendar_today_rounded,
                            iconBgColor: const Color(0xFF0D9488),
                            label: 'FECHA DE INICIO',
                            value: _formatDateTime(_currentEvent.startDate),
                          ),
                          const SizedBox(height: 16),
                          _buildInfoItem(
                            icon: Icons.event_repeat_rounded,
                            iconBgColor: const Color(0xFF0284C7),
                            label: 'CULMINACIÓN',
                            value: _formatDateTime(_currentEvent.endDate),
                          ),
                          const SizedBox(height: 16),
                          _buildInfoItem(
                            icon: Icons.location_on_outlined,
                            iconBgColor: const Color(0xFF10B981),
                            label: 'UBICACIÓN',
                            value: _currentEvent.location,
                          ),
                          const SizedBox(height: 16),
                          _buildInfoItem(
                            icon: Icons.shield_outlined,
                            iconBgColor: const Color(0xFFF59E0B),
                            label: 'ORGANIZADOR',
                            value: '${_currentEvent.createdByName} (${_currentEvent.createdByRole.toUpperCase()})',
                          ),
                          if (_currentEvent.shifts.where((s) => s.enabled).isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _buildShiftsInfoRow(context, _currentEvent.shifts.where((s) => s.enabled).toList()),
                          ],
                          const SizedBox(height: 20),

                          // Botón Añadir a mi Calendario
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                foregroundColor: mintGreen,
                                elevation: 0,
                                side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: _handleAddToCalendar,
                              icon: const Icon(Icons.calendar_month_outlined, color: mintGreen, size: 19),
                              label: const Text(
                                'Añadir a mi Calendario',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                  color: mintGreen,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Tarjeta 2: Descripción y Temario
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
                          const Row(
                            children: [
                              Icon(Icons.description_outlined, color: mintGreen, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Descripción y Temario',
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0B131E) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                            ),
                            child: _buildDescriptionContent(isDark),
                          ),
                        ],
                      ),
                    ),

                    // Banner de Constancia de Asistencia si ya está acreditado
                    if (isAlreadyRegistered) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF064E3B).withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: mintGreen.withValues(alpha: 0.5)),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isCompact = constraints.maxWidth < 340;
                            if (isCompact) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: mintGreen.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Icon(Icons.verified_rounded, color: mintGreen, size: 24),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              '¡Tu Asistencia está Confirmada!',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: mintGreen,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              'Descarga tu constancia oficial en PDF.',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: mintGreen,
                                      foregroundColor: darkGreen,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    ),
                                    onPressed: _handleViewCertificate,
                                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 16, color: darkGreen),
                                    label: const Text('Descargar Constancia Oficial', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: darkGreen)),
                                  ),
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: mintGreen.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.verified_rounded, color: mintGreen, size: 24),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '¡Tu Asistencia está Confirmada!',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: mintGreen,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        'Descarga tu constancia oficial en formato PDF.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: mintGreen,
                                    foregroundColor: darkGreen,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                  onPressed: _handleViewCertificate,
                                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 16, color: darkGreen),
                                  label: const Text('Constancia', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: darkGreen)),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],

                    // Botón para que usuario regular/supervisor escanee asistencia si está habilitado
                    if (canScanAttendance && !isAlreadyRegistered && _currentEvent.requiresAttendance && _currentEvent.status != EventStatus.CANCELLED) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _handleScanAttendance,
                          icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                          label: const Text(
                            'Escanear QR de Asistencia',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                      ),
                    ],
                  ] else if (canProjectQr && _selectedTab == 1) ...[
                    // PESTAÑA 1: Control & QR (solo visible para roles autorizados)
                    _buildQrOptionCard(
                      context: context,
                      title: 'QR para Personal IIAP y Registrados',
                      badge: 'SISTEMA IIAP',
                      badgeColor: const Color(0xFF10B981),
                      icon: Icons.domain_rounded,
                      description: 'Proyecta el código para que los colaboradores con la app móvil confirmen su asistencia al instante.',
                      buttonText: 'QR Registrados',
                      buttonColor: const Color(0xFF10B981),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EventQrDisplayScreen(
                              event: _currentEvent,
                              initialMode: EventQrMode.registered,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    _buildQrOptionCard(
                      context: context,
                      title: 'QR para Invitados y Público Externo',
                      badge: 'INVITADOS Y EXTERNOS',
                      badgeColor: const Color(0xFF0284C7),
                      icon: Icons.public_rounded,
                      description: 'Abre el formulario web de registro público sin necesidad de tener instalada la app en el teléfono.',
                      buttonText: 'QR Externos',
                      buttonColor: const Color(0xFF0284C7),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EventQrDisplayScreen(
                              event: _currentEvent,
                              initialMode: EventQrMode.external,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    _buildManagersCard(context, isDark),
                  ] else ...[
                    // PESTAÑA 2: Participantes
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '${_currentEvent.attendees.length} Registrados',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const Spacer(),
                              if (canManage)
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: mintGreen,
                                    foregroundColor: darkGreen,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: _handleManualRegisterAttendee,
                                  icon: const Icon(Icons.person_add_rounded, size: 16, color: darkGreen),
                                  label: const Text('+ Registrar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: darkGreen)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            onChanged: (val) => setState(() => _attendeeSearchQuery = val),
                            decoration: InputDecoration(
                              hintText: 'Buscar por nombre, correo, DNI...',
                              hintStyle: TextStyle(fontSize: 12.5, color: ThemeService.subtextColor(context)),
                              prefixIcon: Icon(Icons.search_rounded, size: 20, color: ThemeService.subtextColor(context)),
                              filled: true,
                              fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildFilteredAttendeesList(isDark, canManage),
                  ],

                  const SizedBox(height: 36),
                ],
              ),
            ),
          ),
        ),
      ),
    );
      },
    );
  }

    Widget _buildShiftsInfoRow(BuildContext context, List<EventShift> shifts) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.schedule_rounded, size: 18, color: ThemeService.primaryColor(context)),
            const SizedBox(width: 8),
            Text(
              'Turnos Programados',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: shifts.map((s) {
            final color = s.name == 'manana'
                ? const Color(0xFFF59E0B)
                : s.name == 'tarde'
                    ? const Color(0xFFF97316)
                    : const Color(0xFF6366F1);
            final icon = s.name == 'manana'
                ? Icons.wb_sunny_rounded
                : s.name == 'tarde'
                    ? Icons.wb_twilight_rounded
                    : Icons.nights_stay_rounded;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 13, color: color),
                  const SizedBox(width: 6),
                  Text(
                    '${s.label} (${s.startTime} - ${s.endTime})',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }


  Widget _buildQrOptionCard({
    required BuildContext context,
    required String title,
    required String badge,
    required Color badgeColor,
    required IconData icon,
    required String description,
    required String buttonText,
    required Color buttonColor,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.6) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: badgeColor.withValues(alpha: isDark ? 0.4 : 0.3),
          width: 1.3,
        ),
        boxShadow: [
          BoxShadow(
            color: badgeColor.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: badgeColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          color: badgeColor,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.38,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: buttonColor,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: onTap,
              icon: const Icon(Icons.qr_code_2_rounded, size: 17),
              label: Text(
                buttonText,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
