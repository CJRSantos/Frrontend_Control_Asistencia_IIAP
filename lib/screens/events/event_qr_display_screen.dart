import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../config/api_config.dart';
import '../../models/event_model.dart';
import '../../services/api_client.dart';
import '../../services/event_service.dart';
import '../../services/theme_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_button.dart';

enum EventQrMode {
  registered,
  external,
}

class EventQrDisplayScreen extends StatefulWidget {
  final EventModel event;
  final EventQrMode initialMode;

  const EventQrDisplayScreen({
    super.key,
    required this.event,
    this.initialMode = EventQrMode.registered,
  });

  @override
  State<EventQrDisplayScreen> createState() => _EventQrDisplayScreenState();
}

class _EventQrDisplayScreenState extends State<EventQrDisplayScreen> {
  static const int _rotationSeconds = 30;

  late EventQrMode _selectedMode;
  late String _currentQrData;
  late int _attendeesCount;
  String? _selectedShift;

  int _secondsRemaining = _rotationSeconds;
  bool _justRotated = false;
  String _rotationReason = '';

  Timer? _countdownTimer;
  Timer? _pollingTimer;
  Timer? _badgeTimer;

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.initialMode;
    _attendeesCount = widget.event.attendeesCount;

    final shifts = widget.event.shifts.where((s) => s.enabled).toList();
    if (shifts.isNotEmpty) {
      final hour = DateTime.now().hour;
      if (hour < 13 && shifts.any((s) => s.name == 'manana')) {
        _selectedShift = 'manana';
      } else if (hour < 18 && shifts.any((s) => s.name == 'tarde')) {
        _selectedShift = 'tarde';
      } else if (shifts.any((s) => s.name == 'noche')) {
        _selectedShift = 'noche';
      } else {
        _selectedShift = shifts.first.name;
      }
    }

    _currentQrData = _generateDynamicQr();
    _startTimers();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pollingTimer?.cancel();
    _badgeTimer?.cancel();
    super.dispose();
  }

  /// Genera el contenido dinámico del QR según el modo seleccionado
  String _generateDynamicQr() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final nonce = Random().nextInt(999999).toString().padLeft(6, '0');
    final shiftParam = _selectedShift != null ? '&shift=$_selectedShift' : '';

    final titleParam = '&title=${Uri.encodeComponent(widget.event.title)}';
    final locParam = '&loc=${Uri.encodeComponent(widget.event.location)}';
    final uoParam = widget.event.organizationalUnit != null && widget.event.organizationalUnit!.isNotEmpty
        ? '&uo=${Uri.encodeComponent(widget.event.organizationalUnit!)}'
        : '';
    final typeParam = '&type=${widget.event.type.name}';
    final startParam = '&start=${widget.event.startDate.millisecondsSinceEpoch}';
    final endParam = '&end=${widget.event.endDate.millisecondsSinceEpoch}';

    if (_selectedMode == EventQrMode.registered) {
      // Formato para usuarios de la App IIAP con cuenta activa (Autocontenido para funcionar 100% Offline)
      return 'IIAP-EVT-${widget.event.id}?t=$timestamp&nonce=$nonce$shiftParam$titleParam$locParam$uoParam$typeParam$startParam$endParam';
    } else {
      // URL web pública para abrir el formulario en el navegador del celular
      final baseUrl = ApiConfig.eventPublicRegistrationUrl(widget.event.id);
      final separator = baseUrl.contains('?') ? '&' : '?';
      return '$baseUrl${separator}t=$timestamp&nonce=$nonce$shiftParam$titleParam$locParam';
    }
  }

  void _startTimers() {
    // 1. Temporizador de cuenta regresiva de 30 segundos
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining > 1) {
        setState(() => _secondsRemaining--);
      } else {
        _rotateQr(reason: 'Renovado automáticamente por tiempo (30s)');
      }
    });

    // 2. Sondeo en tiempo real cada 1.5 segundos para detectar nuevos registros
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      _checkNewAttendees();
    });
  }

  bool _isCheckingAttendees = false;

  /// Consulta al backend si hay un nuevo asistente registrado al evento
  Future<void> _checkNewAttendees() async {
    if (!mounted || _isCheckingAttendees) return;
    _isCheckingAttendees = true;
    try {
      final res = await ApiClient.get(ApiConfig.eventById(widget.event.id), requiresAuth: false);
      if (res is Map<String, dynamic> && mounted) {
        int latestCount = 0;
        if (res['attendees_count'] is int) {
          latestCount = res['attendees_count'] as int;
        } else if (res['attendees'] is List) {
          latestCount = (res['attendees'] as List).length;
        }

        // Si se detecta un nuevo registro de participante:
        if (latestCount > _attendeesCount) {
          _attendeesCount = latestCount;
          // Actualizar evento en memoria para reflejar el nuevo asistente al instante
          EventService.getEventById(widget.event.id);
          EventService.getEvents();
          HapticFeedback.heavyImpact();
          _rotateQr(
            reason: '¡NUEVO REGISTRO CONFIRMADO! Código QR renovado',
            highlight: true,
          );
        }
      }
    } catch (_) {
      // Ignorar errores silenciosos en sondeo de fondo
    } finally {
      _isCheckingAttendees = false;
    }
  }

  /// Rota visualmente el código QR y reinicia el contador de 30s
  void _rotateQr({required String reason, bool highlight = false}) {
    if (!mounted) return;

    _badgeTimer?.cancel();
    setState(() {
      _currentQrData = _generateDynamicQr();
      _secondsRemaining = _rotationSeconds;
      _justRotated = true;
      _rotationReason = reason;
    });

    _badgeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _justRotated = false);
      }
    });

    if (highlight) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '¡Asistencia registrada! Total participantes: $_attendeesCount',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _manualRegenerateQr() {
    HapticFeedback.lightImpact();
    _rotateQr(reason: 'Código QR renovado manualmente por el Administrador');
  }

  void _switchMode(EventQrMode mode) {
    if (_selectedMode == mode) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedMode = mode;
      _currentQrData = _generateDynamicQr();
      _secondsRemaining = _rotationSeconds;
      _justRotated = true;
      _rotationReason = mode == EventQrMode.registered
          ? 'Modo cambiado: Usuario Registrado (App IIAP)'
          : 'Modo cambiado: Usuario no Registrado (Formulario Web)';
    });

    _badgeTimer?.cancel();
    _badgeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _justRotated = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isTablet = Responsive.isTablet(context);
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= 900;

    // Tamaño adaptativo del QR para iPad, Tablet, Monitor o Teléfono
    final double qrBoxSize = isWide
        ? 340.0
        : (isTablet ? 300.0 : (size.width < 360 ? 210.0 : 250.0));

    final progressRatio = (_secondsRemaining / _rotationSeconds).clamp(0.0, 1.0);
    final progressColor = _secondsRemaining > 10
        ? const Color(0xFF16A34A)
        : (_secondsRemaining > 5 ? const Color(0xFFEAB308) : const Color(0xFFEF4444));

    final activeModeColor = _selectedMode == EventQrMode.registered
        ? const Color(0xFF16A34A)
        : const Color(0xFF0284C7);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Proyección QR de Evento',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        elevation: 0,
        backgroundColor: ThemeService.cardBg(context),
        actions: [
          IconButton(
            icon: const Icon(Icons.autorenew_rounded),
            tooltip: 'Cambiar Código QR ahora',
            onPressed: _manualRegenerateQr,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isTablet ? 32 : 18,
              vertical: isTablet ? 24 : 16,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isWide ? 760 : (isTablet ? 600 : 480),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 1. Selector de Modo: Usuario Registrado vs Usuario Externo
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                      ),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildModeTab(
                            title: 'Usuario Registrado',
                            subtitle: 'Con App IIAP',
                            icon: Icons.phone_android_rounded,
                            mode: EventQrMode.registered,
                            isSelected: _selectedMode == EventQrMode.registered,
                            activeColor: const Color(0xFF16A34A),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _buildModeTab(
                            title: 'Usuario no Registrado',
                            subtitle: 'Formulario Web',
                            icon: Icons.language_rounded,
                            mode: EventQrMode.external,
                            isSelected: _selectedMode == EventQrMode.external,
                            activeColor: const Color(0xFF0284C7),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 2. Encabezado del Evento
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(isTablet ? 20 : 16),
                    decoration: BoxDecoration(
                      color: ThemeService.cardBg(context),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: ThemeService.cardBorder(context)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: ThemeService.primaryColor(context).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                widget.event.displayTypeName.toUpperCase(),
                                style: TextStyle(
                                  color: ThemeService.primaryColor(context),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            // Contador en vivo de Asistentes Confirmados
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: Container(
                                key: ValueKey(_attendeesCount),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFF16A34A).withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.people_alt_rounded, size: 14, color: Color(0xFF16A34A)),
                                    const SizedBox(width: 5),
                                    Text(
                                      '$_attendeesCount Participantes',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF16A34A),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          widget.event.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: isTablet ? 19 : 16.5,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.location_on_outlined, size: 15, color: ThemeService.subtextColor(context)),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                widget.event.location,
                                style: TextStyle(fontSize: 12.5, color: ThemeService.subtextColor(context)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Selector dinámico de Turnos si el evento tiene turnos activos
                  if (widget.event.shifts.where((s) => s.enabled).length > 1) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: widget.event.shifts.where((s) => s.enabled).map((shift) {
                          final isSelected = _selectedShift == shift.name;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () {
                                if (_selectedShift != shift.name) {
                                  setState(() => _selectedShift = shift.name);
                                  _rotateQr(reason: 'Turno cambiado a ${shift.label}');
                                }
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? ThemeService.primaryColor(context)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: ThemeService.primaryColor(context).withValues(alpha: 0.3),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          )
                                        ]
                                      : null,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      shift.name == 'manana'
                                          ? Icons.wb_sunny_rounded
                                          : shift.name == 'tarde'
                                              ? Icons.wb_twilight_rounded
                                              : Icons.nights_stay_rounded,
                                      size: 15,
                                      color: isSelected ? Colors.white : (isDark ? Colors.white60 : const Color(0xFF64748B)),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      shift.label,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                        color: isSelected ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF475569)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),

                  // 3. Banner animado al renovar código por escaneo
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _justRotated
                        ? Container(
                            key: const ValueKey('rotated_banner'),
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: activeModeColor,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: activeModeColor.withValues(alpha: 0.4),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.autorenew_rounded, color: Colors.white, size: 16),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    _rotationReason.isNotEmpty ? _rotationReason : '¡CÓDIGO QR RENOVADO!',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11.5,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('empty_banner')),
                  ),

                  // 4. Tarjeta del Código QR Dinámico
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    padding: EdgeInsets.all(isTablet ? 24 : 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _justRotated ? activeModeColor : const Color(0xFFE2E8F0),
                        width: _justRotated ? 3.5 : 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _justRotated
                              ? activeModeColor.withValues(alpha: 0.35)
                              : Colors.black.withValues(alpha: 0.08),
                          blurRadius: _justRotated ? 24 : 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Badge descriptivo del tipo de QR
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: activeModeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: activeModeColor.withValues(alpha: 0.3)),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _selectedMode == EventQrMode.registered
                                      ? Icons.phone_android_rounded
                                      : Icons.language_rounded,
                                  size: 14,
                                  color: activeModeColor,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  (_selectedMode == EventQrMode.registered
                                      ? 'QR PARA USUARIO REGISTRADO'
                                      : 'QR PARA USUARIO NO REGISTRADO') +
                                  (_selectedShift != null
                                      ? ' • ${_selectedShift == "manana" ? "MAÑANA" : _selectedShift == "tarde" ? "TARDE" : "NOCHE"}'
                                      : ''),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: activeModeColor,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Código QR renderizado
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 350),
                          transitionBuilder: (child, anim) => ScaleTransition(
                            scale: anim,
                            child: FadeTransition(opacity: anim, child: child),
                          ),
                          child: QrImageView(
                            key: ValueKey(_currentQrData),
                            data: _currentQrData,
                            version: QrVersions.auto,
                            size: qrBoxSize,
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Color(0xFF0F172A),
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Barra y Contador Regresivo de 30 Segundos
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.timer_outlined, size: 16, color: progressColor),
                                      const SizedBox(width: 6),
                                      const Text(
                                        'Renovación en:',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    '${_secondsRemaining}s',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: progressColor,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: progressRatio,
                                  minHeight: 6,
                                  backgroundColor: const Color(0xFFE2E8F0),
                                  valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Botón directo para Cambiar/Regenerar QR manualmente
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              side: BorderSide(color: activeModeColor),
                              foregroundColor: activeModeColor,
                            ),
                            onPressed: _manualRegenerateQr,
                            icon: const Icon(Icons.autorenew_rounded, size: 18),
                            label: const Text(
                              'Cambiar Código QR Ahora',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 5. Caja explicativa e instructiva según el modo
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: ThemeService.cardBg(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: ThemeService.cardBorder(context)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _selectedMode == EventQrMode.registered
                              ? Icons.info_outline_rounded
                              : Icons.open_in_browser_rounded,
                          size: 20,
                          color: activeModeColor,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _selectedMode == EventQrMode.registered
                                ? 'Para personas con la App IIAP y cuenta activa: abren la app, presionan "Escanear QR de Asistencia" y su presencia en el evento queda confirmada al instante.'
                                : 'Para personas sin la app: apuntan con la cámara de su celular (o Google Lens) y se les abrirá el formulario web oficial en su navegador para completar sus datos y figurar en la lista.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: ThemeService.subtextColor(context),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 6. Botones de Acción: Copiar Enlace y Cerrar
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: isTablet ? 15 : 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            side: BorderSide(color: ThemeService.primaryColor(context)),
                          ),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _currentQrData));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  _selectedMode == EventQrMode.registered
                                      ? 'Código de evento copiado al portapapeles'
                                      : 'Enlace web oficial de registro copiado al portapapeles',
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          icon: Icon(Icons.copy_rounded, color: ThemeService.primaryColor(context), size: 18),
                          label: Text(
                            _selectedMode == EventQrMode.registered ? 'Copiar Código' : 'Copiar Enlace Web',
                            style: TextStyle(
                              color: ThemeService.primaryColor(context),
                              fontWeight: FontWeight.bold,
                              fontSize: isTablet ? 14 : 12.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppButton(
                          text: 'Cerrar',
                          height: isTablet ? 50 : 45,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeTab({
    required String title,
    required String subtitle,
    required IconData icon,
    required EventQrMode mode,
    required bool isSelected,
    required Color activeColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => _switchMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF0F172A) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: activeColor.withValues(alpha: 0.5), width: 1.5)
              : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? activeColor
                  : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected
                          ? (isDark ? Colors.white : const Color(0xFF0F172A))
                          : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? activeColor
                          : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
