import 'package:flutter/material.dart';
import '../../utils/responsive.dart';
import '../../models/attendance_model.dart';
import '../../models/user_model.dart';
import '../../services/storage_service.dart';
import '../../services/attendance_service.dart';
import '../../services/pdf_report_service.dart';
import '../../widgets/shift_journey_card.dart';
import '../../widgets/pending_checkout_card.dart';
import '../../services/theme_service.dart';
import '../../services/wallpaper_service.dart';
import '../../widgets/leaf_logo.dart';
import '../../widgets/modern_time_picker_dialog.dart';

class AttendanceTab extends StatefulWidget {
  const AttendanceTab({super.key});

  @override
  State<AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<AttendanceTab> {
  List<AttendanceModel> _myRecords = [];
  List<AttendanceModel> _allRecords = [];
  List<Map<String, dynamic>> _pendingCheckouts = [];
  bool _isLoadingMy = true;
  bool _isLoadingAll = false;
  bool _isLoadingPending = false;
  bool _hasFetchedMy = false;
  bool _isGeneratingPdf = false;

  // Filtros activos para Mis Asistencias y Registro General
  String _myFilter = 'all';
  String _allFilter = 'all';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  Color _cardBg(BuildContext context) {
    final hasWallpaper = WallpaperService.currentWallpaper.hasWallpaper;
    return hasWallpaper
        ? ThemeService.cardBg(context).withValues(alpha: 0.85)
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

  @override
  void initState() {
    super.initState();
    // 1. Carga inmediata de registros guardados localmente (0 ms)
    _myRecords = AttendanceService.getCachedMyRecords();
    _allRecords = AttendanceService.getCachedAllRecords();
    _isLoadingMy = _myRecords.isEmpty;
    _isLoadingAll = _allRecords.isEmpty;

    final user = StorageService.currentUserNotifier.value ?? StorageService.currentUser;
    if (user != null && (user.isAdmin || user.isSupervisor)) {
      _loadAllRecords();
      _loadMyRecords();
      _loadPendingCheckouts();
    } else {
      _loadMyRecords();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMyRecords() async {
    if (_myRecords.isEmpty) {
      setState(() => _isLoadingMy = true);
    }
    try {
      final records = await AttendanceService.getMyRecords();
      if (mounted) {
        setState(() {
          _myRecords = records;
          _isLoadingMy = false;
          _hasFetchedMy = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingMy = false;
          _hasFetchedMy = true;
        });
      }
    }
  }

  Future<void> _loadAllRecords() async {
    if (_allRecords.isEmpty) {
      setState(() => _isLoadingAll = true);
    }
    try {
      final records = await AttendanceService.getAllRecords();
      if (mounted) {
        setState(() {
          _allRecords = records;
          _isLoadingAll = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingAll = false;
        });
      }
    }
  }

  Future<void> _loadPendingCheckouts() async {
    setState(() => _isLoadingPending = true);
    try {
      final list = await AttendanceService.getPendingCheckouts();
      if (mounted) {
        setState(() {
          _pendingCheckouts = list;
          _isLoadingPending = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingPending = false);
      }
    }
  }

  Future<void> _exportPdfReport() async {
    final user = StorageService.currentUserNotifier.value;
    if (user == null) return;

    if (_allRecords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay registros de asistencias para exportar.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isGeneratingPdf = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Generando Reporte Oficial PDF del IIAP...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      await PdfReportService.generateAndPreviewReport(
        records: _allRecords,
        currentUser: user,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingPdf = false);
      }
    }
  }

  Future<void> _showManualAttendanceDialog() async {
    final dniController = TextEditingController();
    final obsController = TextEditingController();
    AttendanceType selectedType = AttendanceType.CHECK_IN;
    AttendanceShift selectedShift =
        DateTime.now().hour < 13 ? AttendanceShift.MORNING : AttendanceShift.AFTERNOON;
    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: ThemeService.cardBg(context),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.emergency_outlined, color: Colors.amber, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Marcación Manual',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        'Contingencia por Celular Avariado/Robado',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Registrar asistencia manual para un colaborador que no puede escanear el QR.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Campo DNI
                  const Text('Documento / DNI del Colaborador *',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: dniController,
                    keyboardType: TextInputType.number,
                    maxLength: 8,
                    decoration: InputDecoration(
                      hintText: 'Ingrese los 8 dígitos del DNI',
                      prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Selector de Turno: MAÑANA / TARDE
                  const Text('Turno de la Jornada *',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => setDialogState(() => selectedShift = AttendanceShift.MORNING),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: selectedShift == AttendanceShift.MORNING
                                  ? Colors.blue.withValues(alpha: 0.2)
                                  : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04)),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selectedShift == AttendanceShift.MORNING
                                    ? Colors.blue
                                    : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.wb_sunny_rounded,
                                  size: 16,
                                  color: selectedShift == AttendanceShift.MORNING ? Colors.blue : Colors.grey,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'MAÑANA',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: selectedShift == AttendanceShift.MORNING ? Colors.blue : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () => setDialogState(() => selectedShift = AttendanceShift.AFTERNOON),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: selectedShift == AttendanceShift.AFTERNOON
                                  ? Colors.amber.withValues(alpha: 0.2)
                                  : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04)),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selectedShift == AttendanceShift.AFTERNOON
                                    ? Colors.amber
                                    : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.nights_stay_rounded,
                                  size: 16,
                                  color: selectedShift == AttendanceShift.AFTERNOON ? Colors.amber : Colors.grey,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'TARDE',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: selectedShift == AttendanceShift.AFTERNOON ? Colors.amber : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Selector de Tipo: ENTRADA / SALIDA
                  const Text('Tipo de Marcación *',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => setDialogState(() => selectedType = AttendanceType.CHECK_IN),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: selectedType == AttendanceType.CHECK_IN
                                  ? Colors.green.withValues(alpha: 0.2)
                                  : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04)),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selectedType == AttendanceType.CHECK_IN ? Colors.green : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.login_rounded,
                                  size: 18,
                                  color: selectedType == AttendanceType.CHECK_IN ? Colors.green : Colors.grey,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'ENTRADA',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: selectedType == AttendanceType.CHECK_IN ? Colors.green : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () => setDialogState(() => selectedType = AttendanceType.CHECK_OUT),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: selectedType == AttendanceType.CHECK_OUT
                                  ? Colors.orange.withValues(alpha: 0.2)
                                  : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04)),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selectedType == AttendanceType.CHECK_OUT ? Colors.orange : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.logout_rounded,
                                  size: 18,
                                  color: selectedType == AttendanceType.CHECK_OUT ? Colors.orange : Colors.grey,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'SALIDA',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: selectedType == AttendanceType.CHECK_OUT ? Colors.orange : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Observación / Justificación
                  const Text('Motivo / Observación *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: obsController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Ej. Celular averiado / Olvido involuntario',
                      prefixIcon: const Icon(Icons.edit_note_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ThemeService.primaryColor(context),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final dni = dniController.text.trim();
                        final obs = obsController.text.trim();
                        if (dni.length != 8) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('El DNI debe tener 8 dígitos numéricos.')),
                          );
                          return;
                        }
                        if (obs.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Por favor ingresa la observación del motivo.')),
                          );
                          return;
                        }

                        setDialogState(() => isSubmitting = true);
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        final nav = Navigator.of(ctx);

                        try {
                          final res = await AttendanceService.registerManualAttendance(
                            dni: dni,
                            type: selectedType.name,
                            shift: selectedShift.name,
                            observation: obs,
                          );
                          nav.pop();
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text(res['message']?.toString() ?? 'Asistencia registrada con éxito.'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          if (mounted) {
                            _loadAllRecords();
                            _loadPendingCheckouts();
                            _loadMyRecords();
                          }
                        } catch (e) {
                          setDialogState(() => isSubmitting = false);
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Registrar Asistencia'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Diálogo para que el Administrador o Supervisor edite los horarios de Entrada y Salida
  /// de cualquier colaborador (soluciona cuando llegan temprano, olvidan marcar entrada y marcan a la 1 PM)
  Future<void> _showEditJourneyDialog(ShiftJourneyRecord journey) async {
    final primary = ThemeService.primaryColor(context);

    final isMorning = journey.shift == AttendanceShift.MORNING;

    // Horas iniciales
    TimeOfDay inTime = journey.checkIn != null
        ? TimeOfDay.fromDateTime(journey.checkIn!.timestamp)
        : TimeOfDay(hour: isMorning ? 8 : 14, minute: 0);

    TimeOfDay outTime = journey.checkOut != null
        ? TimeOfDay.fromDateTime(journey.checkOut!.timestamp)
        : TimeOfDay(hour: isMorning ? 13 : 18, minute: isMorning ? 0 : 30);

    bool enableCheckIn = true;
    bool enableCheckOut = journey.checkOut != null || (journey.checkIn != null && journey.isPendingCheckOut);

    AttendanceStatus inStatus = journey.checkIn?.status ?? AttendanceStatus.ON_TIME;
    final obsController = TextEditingController(
      text: journey.checkIn?.observation ?? journey.checkOut?.observation ?? 'Ajuste de horarios por Administrador',
    );

    bool isSubmitting = false;

    String formatTimeOfDay(TimeOfDay t) {
      final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
      final minute = t.minute.toString().padLeft(2, '0');
      final period = t.period == DayPeriod.am ? 'a. m.' : 'p. m.';
      return '${hour.toString().padLeft(2, '0')}:$minute $period';
    }

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
          final surfaceBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
          final borderCol = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              decoration: BoxDecoration(
                color: dialogBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: borderCol, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.15),
                    blurRadius: 32,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header con degradado sutil
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: isDark ? 0.12 : 0.08),
                        border: Border(bottom: BorderSide(color: borderCol, width: 0.8)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.edit_calendar_rounded, color: primary, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Editar Horarios de Asistencia',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  journey.userName ?? 'Colaborador',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: primary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: () => Navigator.of(ctx).pop(),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),

                    // Contenido Scrolleable
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Badges (Fecha, DNI, Turno)
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: surfaceBg,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: borderCol),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.calendar_today_rounded, size: 12, color: Colors.grey),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Fecha: ${journey.workDate}',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                                if (journey.userDocument != null && journey.userDocument!.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: surfaceBg,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: borderCol),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.badge_rounded, size: 12, color: Colors.grey),
                                        const SizedBox(width: 5),
                                        Text(
                                          'DNI: ${journey.userDocument}',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isMorning
                                        ? const Color(0xFF2563EB).withValues(alpha: 0.15)
                                        : const Color(0xFFD97706).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isMorning
                                          ? const Color(0xFF2563EB).withValues(alpha: 0.4)
                                          : const Color(0xFFD97706).withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Text(
                                    journey.shift == AttendanceShift.MORNING ? 'Turno Mañana' : 'Turno Tarde',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isMorning ? const Color(0xFF3B82F6) : const Color(0xFFF59E0B),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Nota explicativa
                            Container(
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD97706).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.info_outline_rounded, color: Color(0xFFF59E0B), size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Si el colaborador llegó a tiempo pero olvidó marcar en la mañana y marcó a la 1:00 PM, establece aquí su Entrada (ej: 08:00 AM) y su Salida (01:00 PM).',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 14),

                            // 1. SECCIÓN ENTRADA (Tarjeta Verde Esmeralda)
                            Container(
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                color: enableCheckIn
                                    ? const Color(0xFF10B981).withValues(alpha: isDark ? 0.08 : 0.05)
                                    : surfaceBg,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: enableCheckIn
                                      ? const Color(0xFF10B981).withValues(alpha: 0.4)
                                      : borderCol,
                                  width: 1.2,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  InkWell(
                                    onTap: () => setDialogState(() => enableCheckIn = !enableCheckIn),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: Checkbox(
                                            value: enableCheckIn,
                                            activeColor: const Color(0xFF10B981),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                                            onChanged: (v) => setDialogState(() => enableCheckIn = v ?? true),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(Icons.login_rounded, size: 17, color: Color(0xFF10B981)),
                                        const SizedBox(width: 6),
                                        const Expanded(
                                          child: Text(
                                            'Entrada (Ingreso)',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (enableCheckIn) ...[
                                    const SizedBox(height: 10),
                                    // Botón de Selección de Hora Táctil
                                    InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () async {
                                        final picked = await ModernTimePickerDialog.show(
                                          context: context,
                                          initialTime: inTime,
                                          title: 'Hora de Entrada',
                                          subtitle: 'Ingreso de ${journey.userName ?? "colaborador"}',
                                          primaryColor: const Color(0xFF10B981),
                                        );
                                        if (picked != null) {
                                          setDialogState(() => inTime = picked);
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF0F172A) : Colors.white,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              children: [
                                                const Icon(Icons.access_time_rounded, size: 18, color: Color(0xFF10B981)),
                                                const SizedBox(width: 8),
                                                Text(
                                                  formatTimeOfDay(inTime),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                    letterSpacing: 0.3,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                'Cambiar',
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF10B981),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    // Selector de Estado de Entrada con Pastillas (Puntual vs Tardanza)
                                    Row(
                                      children: [
                                        Expanded(
                                          child: InkWell(
                                            onTap: () => setDialogState(() => inStatus = AttendanceStatus.ON_TIME),
                                            borderRadius: BorderRadius.circular(8),
                                            child: AnimatedContainer(
                                              duration: const Duration(milliseconds: 150),
                                              padding: const EdgeInsets.symmetric(vertical: 8),
                                              decoration: BoxDecoration(
                                                color: inStatus == AttendanceStatus.ON_TIME
                                                    ? const Color(0xFF10B981)
                                                    : surfaceBg,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: inStatus == AttendanceStatus.ON_TIME
                                                      ? const Color(0xFF10B981)
                                                      : borderCol,
                                                ),
                                              ),
                                              alignment: Alignment.center,
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.check_circle_rounded,
                                                    size: 14,
                                                    color: inStatus == AttendanceStatus.ON_TIME ? Colors.white : const Color(0xFF10B981),
                                                  ),
                                                  const SizedBox(width: 5),
                                                  Text(
                                                    'Puntual',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                      color: inStatus == AttendanceStatus.ON_TIME ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: InkWell(
                                            onTap: () => setDialogState(() => inStatus = AttendanceStatus.LATE),
                                            borderRadius: BorderRadius.circular(8),
                                            child: AnimatedContainer(
                                              duration: const Duration(milliseconds: 150),
                                              padding: const EdgeInsets.symmetric(vertical: 8),
                                              decoration: BoxDecoration(
                                                color: inStatus == AttendanceStatus.LATE
                                                    ? const Color(0xFFF59E0B)
                                                    : surfaceBg,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: inStatus == AttendanceStatus.LATE
                                                      ? const Color(0xFFF59E0B)
                                                      : borderCol,
                                                ),
                                              ),
                                              alignment: Alignment.center,
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.warning_amber_rounded,
                                                    size: 14,
                                                    color: inStatus == AttendanceStatus.LATE ? Colors.white : const Color(0xFFF59E0B),
                                                  ),
                                                  const SizedBox(width: 5),
                                                  Text(
                                                    'Tardanza',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                      color: inStatus == AttendanceStatus.LATE ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            const SizedBox(height: 12),

                            // 2. SECCIÓN SALIDA (Tarjeta Ámbar / Sunset)
                            Container(
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                color: enableCheckOut
                                    ? const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.08 : 0.05)
                                    : surfaceBg,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: enableCheckOut
                                      ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
                                      : borderCol,
                                  width: 1.2,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  InkWell(
                                    onTap: () => setDialogState(() => enableCheckOut = !enableCheckOut),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: Checkbox(
                                            value: enableCheckOut,
                                            activeColor: const Color(0xFFF59E0B),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                                            onChanged: (v) => setDialogState(() => enableCheckOut = v ?? false),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(Icons.logout_rounded, size: 17, color: Color(0xFFF59E0B)),
                                        const SizedBox(width: 6),
                                        const Expanded(
                                          child: Text(
                                            'Salida (Refrigerio / Fin)',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (enableCheckOut) ...[
                                    const SizedBox(height: 10),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () async {
                                        final picked = await ModernTimePickerDialog.show(
                                          context: context,
                                          initialTime: outTime,
                                          title: 'Hora de Salida',
                                          subtitle: 'Salida de ${journey.userName ?? "colaborador"}',
                                          primaryColor: const Color(0xFFF59E0B),
                                        );
                                        if (picked != null) {
                                          setDialogState(() => outTime = picked);
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF0F172A) : Colors.white,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              children: [
                                                const Icon(Icons.access_time_rounded, size: 18, color: Color(0xFFF59E0B)),
                                                const SizedBox(width: 8),
                                                Text(
                                                  formatTimeOfDay(outTime),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                    letterSpacing: 0.3,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                'Cambiar',
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFFF59E0B),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            const SizedBox(height: 14),

                            // Observación / Motivo
                            const Text(
                              'Motivo / Observación de la corrección *',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: obsController,
                              maxLines: 2,
                              decoration: InputDecoration(
                                hintText: 'Ej. Olvido de marca matutina / Salida regularizada',
                                hintStyle: TextStyle(fontSize: 12, color: isDark ? Colors.grey[500] : Colors.grey[400]),
                                prefixIcon: const Icon(Icons.edit_note_rounded, size: 20),
                                filled: true,
                                fillColor: surfaceBg,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: borderCol),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: borderCol),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: primary, width: 1.5),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Barra Inferior de Acciones
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                      decoration: BoxDecoration(
                        color: surfaceBg,
                        border: Border(top: BorderSide(color: borderCol, width: 0.8)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: borderCol),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                  child: Text(
                                    'Cancelar',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    elevation: 0,
                                  ),
                                  icon: isSubmitting
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                        )
                                      : const Icon(Icons.save_rounded, size: 18),
                                  label: const Text(
                                    'Guardar Corrección',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  onPressed: isSubmitting
                                      ? null
                                      : () async {
                                          if (!enableCheckIn && !enableCheckOut) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Debes habilitar al menos la Entrada o la Salida.')),
                                            );
                                            return;
                                          }

                                          setDialogState(() => isSubmitting = true);
                                          final scaffoldMessenger = ScaffoldMessenger.of(context);
                                          final nav = Navigator.of(ctx);

                                          final inStr = enableCheckIn
                                              ? '${inTime.hour.toString().padLeft(2, '0')}:${inTime.minute.toString().padLeft(2, '0')}'
                                              : null;
                                          final outStr = enableCheckOut
                                              ? '${outTime.hour.toString().padLeft(2, '0')}:${outTime.minute.toString().padLeft(2, '0')}'
                                              : null;

                                          try {
                                            final res = await AttendanceService.correctJourney(
                                              userId: journey.userId,
                                              workDate: journey.workDate,
                                              shift: journey.shift,
                                              checkInTime: inStr,
                                              checkInStatus: inStatus,
                                              checkOutTime: outStr,
                                              observation: obsController.text.trim(),
                                            );
                                            nav.pop();
                                            scaffoldMessenger.showSnackBar(
                                              SnackBar(
                                                backgroundColor: Colors.green,
                                                content: Text(res['message']?.toString() ?? 'Horarios corregidos exitosamente.'),
                                              ),
                                            );
                                            if (mounted) {
                                              _loadAllRecords();
                                              _loadPendingCheckouts();
                                              _loadMyRecords();
                                            }
                                          } catch (e) {
                                            setDialogState(() => isSubmitting = false);
                                            scaffoldMessenger.showSnackBar(
                                              SnackBar(
                                                backgroundColor: Colors.red,
                                                content: Text('Error al corregir horarios: $e'),
                                              ),
                                            );
                                          }
                                        },
                                ),
                              ),
                            ],
                          ),
                          if (journey.checkIn != null || journey.checkOut != null) ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFFEF4444),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                                label: const Text(
                                  'Eliminar Marca de Asistencia',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                                onPressed: isSubmitting
                                    ? null
                                    : () async {
                                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                                        final nav = Navigator.of(ctx);

                                        final confirmDelete = await showDialog<bool>(
                                          context: context,
                                          builder: (deleteCtx) => AlertDialog(
                                            title: const Text('¿Eliminar Asistencia?'),
                                            content: Text(
                                              '¿Deseas eliminar este registro de asistencia de ${journey.userName} correspondiente al turno ${journey.shift == AttendanceShift.MORNING ? "Mañana" : "Tarde"} del ${journey.workDate}?',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.of(deleteCtx).pop(false),
                                                child: const Text('Cancelar'),
                                              ),
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                                                onPressed: () => Navigator.of(deleteCtx).pop(true),
                                                child: const Text('Sí, Eliminar', style: TextStyle(color: Colors.white)),
                                              ),
                                            ],
                                          ),
                                        );

                                        if (confirmDelete == true) {
                                          setDialogState(() => isSubmitting = true);

                                          try {
                                            if (journey.checkIn != null) {
                                              await AttendanceService.deleteAttendanceRecord(journey.checkIn!.id);
                                            }
                                            if (journey.checkOut != null && journey.checkOut?.id != journey.checkIn?.id) {
                                              await AttendanceService.deleteAttendanceRecord(journey.checkOut!.id);
                                            }
                                            nav.pop();
                                            scaffoldMessenger.showSnackBar(
                                              const SnackBar(
                                                backgroundColor: Colors.green,
                                                content: Text('Registro de asistencia eliminado exitosamente.'),
                                              ),
                                            );
                                            if (mounted) {
                                              _loadAllRecords();
                                              _loadPendingCheckouts();
                                              _loadMyRecords();
                                            }
                                          } catch (e) {
                                            setDialogState(() => isSubmitting = false);
                                            scaffoldMessenger.showSnackBar(
                                              SnackBar(
                                                backgroundColor: Colors.red,
                                                content: Text('Error al eliminar registro: $e'),
                                              ),
                                            );
                                          }
                                        }
                                      },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmWeeklyReset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.cleaning_services_rounded, color: Colors.orange),
            SizedBox(width: 10),
            Expanded(child: Text('Reinicio Semanal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ],
        ),
        content: const Text(
          'El sistema reinicia automáticamente todo el historial de asistencias los viernes a las 10:00 PM para evitar saturar la base de datos y la aplicación para todos (admin, supervisores y personal).\n\n¿Deseas ejecutar un reinicio manual en este momento?',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reiniciar Ahora'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reiniciando historial semanal...')),
      );
      try {
        final res = await AttendanceService.clearWeeklyHistory();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.green,
              content: Text(res['message']?.toString() ?? 'Historial semanal reiniciado exitosamente.'),
            ),
          );
          _loadAllRecords();
          _loadPendingCheckouts();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red,
              content: Text('Error al reiniciar historial: $e'),
            ),
          );
        }
      }
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
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final hasWallpaper = WallpaperService.currentWallpaper.hasWallpaper;
        final primaryColor = ThemeService.primaryColor(context);

        return ValueListenableBuilder<UserModel?>(
          valueListenable: StorageService.currentUserNotifier,
          builder: (context, user, _) {
            final isAdmin = user != null && user.isAdmin;
            final isSupervisor = user != null && user.isSupervisor;

            if (isAdmin || isSupervisor) {
              if (_allRecords.isEmpty && !_isLoadingAll) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    _loadAllRecords();
                    _loadPendingCheckouts();
                  }
                });
              }
            }

            // 1. Administrador General: TabBar con "Registro General", "Mis Asistencias", "Pendientes de Salida"
            if (isAdmin) {
              return DefaultTabController(
                length: 3,
                child: Scaffold(
                  backgroundColor: hasWallpaper ? Colors.transparent : ThemeService.scaffoldBg(context),
                  appBar: AppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    title: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _cardBg(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _cardBorder(context)),
                          ),
                          child: const LeafLogo(size: 20),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Control Institucional',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5, letterSpacing: -0.2),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Administración Central • IIAP',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF10B981)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        tooltip: 'Marcación Manual de Emergencia',
                        onPressed: _showManualAttendanceDialog,
                      ),
                      IconButton(
                        icon: _isGeneratingPdf
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.picture_as_pdf_rounded),
                        tooltip: 'Exportar Reporte PDF (Entradas y Salidas)',
                        onPressed: _isGeneratingPdf ? null : _exportPdfReport,
                      ),
                      IconButton(
                        icon: const Icon(Icons.cleaning_services_rounded),
                        tooltip: 'Reinicio Semanal (Viernes 10:00 PM)',
                        onPressed: _confirmWeeklyReset,
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded),
                        tooltip: 'Actualizar',
                        onPressed: () {
                          _loadAllRecords();
                          _loadPendingCheckouts();
                        },
                      ),
                    ],
                    bottom: TabBar(
                      labelColor: primaryColor,
                      indicatorColor: primaryColor,
                      unselectedLabelColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      indicatorWeight: 3,
                      tabs: [
                        const Tab(
                          icon: Icon(Icons.corporate_fare_rounded, size: 20),
                          text: 'Registro General',
                        ),
                        const Tab(
                          icon: Icon(Icons.person_outline_rounded, size: 20),
                          text: 'Mis Asistencias',
                        ),
                        Tab(
                          icon: Badge(
                            isLabelVisible: _pendingCheckouts.isNotEmpty,
                            label: Text('${_pendingCheckouts.length}'),
                            backgroundColor: Colors.amber[800],
                            child: const Icon(Icons.pending_actions_rounded, size: 20),
                          ),
                          text: 'Pendientes de Salida',
                        ),
                      ],
                    ),
                  ),
                  body: TabBarView(
                    children: [
                      _buildJourneyList(
                        ShiftJourneyRecord.groupFromRecords(_allRecords),
                        _isLoadingAll,
                        () async {
                          await _loadAllRecords();
                          await _loadPendingCheckouts();
                        },
                        showUserName: true,
                        canEdit: true,
                      ),
                      _buildJourneyList(
                        ShiftJourneyRecord.groupFromRecords(_myRecords),
                        _isLoadingMy,
                        _loadMyRecords,
                        showUserName: false,
                      ),
                      _buildPendingList(
                        _pendingCheckouts,
                        _isLoadingPending,
                        _loadPendingCheckouts,
                      ),
                    ],
                  ),
                ),
              );
            }

            // 2. Colaborador Regular: Solo su propio historial de jornadas (La vista principal que ven los usuarios)
            if (!isSupervisor) {
              if (!_hasFetchedMy && !_isLoadingMy) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _loadMyRecords();
                });
              }
              return Scaffold(
                backgroundColor: hasWallpaper ? Colors.transparent : ThemeService.scaffoldBg(context),
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _cardBg(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _cardBorder(context)),
                        ),
                        child: const LeafLogo(size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Historial de Asistencias',
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16.5, letterSpacing: -0.2),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Registro Oficial de Marcaciones • IIAP',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: primaryColor,
                                letterSpacing: 0.2,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: 'Actualizar',
                      onPressed: _loadMyRecords,
                    ),
                  ],
                ),
                body: _buildJourneyList(
                  ShiftJourneyRecord.groupFromRecords(_myRecords),
                  _isLoadingMy,
                  _loadMyRecords,
                  showUserName: false,
                ),
              );
            }

            // 3. Supervisor: 3 pestañas: "Mis Asistencias", "Registro Institucional", "Pendientes de Salida"
            return DefaultTabController(
              length: 3,
              child: Scaffold(
                backgroundColor: hasWallpaper ? Colors.transparent : ThemeService.scaffoldBg(context),
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _cardBg(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _cardBorder(context)),
                        ),
                        child: const LeafLogo(size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Control de Asistencias',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5, letterSpacing: -0.2),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Supervisión de Cuadrilla • IIAP',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF10B981)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      tooltip: 'Marcación Manual de Emergencia',
                      onPressed: _showManualAttendanceDialog,
                    ),
                    IconButton(
                      icon: _isGeneratingPdf
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.picture_as_pdf_rounded),
                      tooltip: 'Exportar Reporte PDF (Entradas y Salidas)',
                      onPressed: _isGeneratingPdf ? null : _exportPdfReport,
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: 'Actualizar',
                      onPressed: () {
                        _loadMyRecords();
                        _loadAllRecords();
                        _loadPendingCheckouts();
                      },
                    ),
                  ],
                  bottom: TabBar(
                    labelColor: primaryColor,
                    indicatorColor: primaryColor,
                    unselectedLabelColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    indicatorWeight: 3,
                    tabs: [
                      const Tab(
                        icon: Icon(Icons.person_outline_rounded, size: 20),
                        text: 'Mis Asistencias',
                      ),
                      const Tab(
                        icon: Icon(Icons.corporate_fare_rounded, size: 20),
                        text: 'Registro General',
                      ),
                      Tab(
                        icon: Badge(
                          isLabelVisible: _pendingCheckouts.isNotEmpty,
                          label: Text('${_pendingCheckouts.length}'),
                          backgroundColor: Colors.amber[800],
                          child: const Icon(Icons.pending_actions_rounded, size: 20),
                        ),
                        text: 'Pendientes',
                      ),
                    ],
                  ),
                ),
                body: TabBarView(
                  children: [
                    _buildJourneyList(
                      ShiftJourneyRecord.groupFromRecords(_myRecords),
                      _isLoadingMy,
                      _loadMyRecords,
                      showUserName: false,
                    ),
                    _buildJourneyList(
                      ShiftJourneyRecord.groupFromRecords(_allRecords),
                      _isLoadingAll,
                      () async {
                        await _loadAllRecords();
                        await _loadPendingCheckouts();
                      },
                      showUserName: true,
                      canEdit: true,
                    ),
                    _buildPendingList(
                      _pendingCheckouts,
                      _isLoadingPending,
                      _loadPendingCheckouts,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<ShiftJourneyRecord> _filterJourneys(
    List<ShiftJourneyRecord> journeys,
    String filter,
    String search,
  ) {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final nowMinutes = now.hour * 60 + now.minute;

    bool isMissingCheckout(ShiftJourneyRecord j) {
      if (j.checkOut != null) return false;
      final isMorning = j.shift == AttendanceShift.MORNING;
      final isPastDay = j.workDate.compareTo(todayStr) < 0;
      final scheduledExitMins = isMorning ? 13 * 60 : 18 * 60 + 30;
      final isPastExitTime = j.workDate == todayStr ? nowMinutes >= scheduledExitMins : true;
      return isPastDay || isPastExitTime;
    }

    var list = journeys;

    if (search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      list = list.where((j) {
        final name = (j.userName ?? '').toLowerCase();
        final doc = (j.userDocument ?? '').toLowerCase();
        final email = (j.userEmail ?? '').toLowerCase();
        final date = j.workDate.toLowerCase();
        return name.contains(q) || doc.contains(q) || email.contains(q) || date.contains(q);
      }).toList();
    }

    if (filter == 'completed') {
      return list.where((j) => j.isCompleted).toList();
    } else if (filter == 'ontime') {
      return list.where((j) => j.checkIn?.status == AttendanceStatus.ON_TIME).toList();
    } else if (filter == 'late') {
      return list.where((j) => j.checkIn?.status == AttendanceStatus.LATE).toList();
    } else if (filter == 'missing') {
      return list.where(isMissingCheckout).toList();
    }

    return list;
  }

  Widget _buildSummaryHeroCard({
    required BuildContext context,
    required List<ShiftJourneyRecord> allJourneys,
    required String currentFilter,
    required ValueChanged<String> onFilterChanged,
    required bool showSearch,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = ThemeService.primaryColor(context);

    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final nowMinutes = now.hour * 60 + now.minute;

    bool isMissingCheckout(ShiftJourneyRecord j) {
      if (j.checkOut != null) return false;
      final isMorning = j.shift == AttendanceShift.MORNING;
      final isPastDay = j.workDate.compareTo(todayStr) < 0;
      final scheduledExitMins = isMorning ? 13 * 60 : 18 * 60 + 30;
      final isPastExitTime = j.workDate == todayStr ? nowMinutes >= scheduledExitMins : true;
      return isPastDay || isPastExitTime;
    }

    final total = allJourneys.length;
    final completed = allJourneys.where((j) => j.isCompleted).length;
    final onTime = allJourneys.where((j) => j.checkIn?.status == AttendanceStatus.ON_TIME).length;
    final lateCount = allJourneys.where((j) => j.checkIn?.status == AttendanceStatus.LATE).length;
    final missing = allJourneys.where(isMissingCheckout).length;

    final totalWithCheckIn = onTime + lateCount;
    final punctuality = totalWithCheckIn > 0
        ? ((onTime / totalWithCheckIn) * 100).round()
        : (total > 0 ? 100 : 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _cardBorder(context), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Fila superior: Icono + Titulo + Badge Oficial (100% elástica y sin desbordamiento)
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5.5),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  Icons.insights_rounded,
                  size: 15,
                  color: primaryColor,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'RESUMEN DE ASISTENCIAS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5.5,
                      height: 5.5,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'OFICIAL',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF10B981),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Fila de 4 KPIs
          Row(
            children: [
              _buildStatTile(
                label: 'Jornadas',
                value: '$total',
                icon: Icons.calendar_month_rounded,
                color: primaryColor,
                isDark: isDark,
              ),
              const SizedBox(width: 6),
              _buildStatTile(
                label: 'Puntualidad',
                value: '$punctuality%',
                icon: Icons.check_circle_rounded,
                color: const Color(0xFF10B981),
                isDark: isDark,
              ),
              const SizedBox(width: 6),
              _buildStatTile(
                label: 'Tardanzas',
                value: '$lateCount',
                icon: Icons.access_time_filled_rounded,
                color: const Color(0xFFF59E0B),
                isDark: isDark,
              ),
              const SizedBox(width: 6),
              _buildStatTile(
                label: 'Sin salida',
                value: '$missing',
                icon: Icons.warning_rounded,
                color: const Color(0xFFEF4444),
                isDark: isDark,
              ),
            ],
          ),

          // Buscador si es Vista de Administrador/Supervisor (showSearch)
          if (showSearch) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() => _searchQuery = val);
              },
              decoration: InputDecoration(
                hintText: 'Buscar por colaborador, DNI o fecha...',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: _innerBoxBg(context),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _cardBorder(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _cardBorder(context).withValues(alpha: 0.5)),
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Chips de filtro interactivo
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(
                  label: 'Todas',
                  count: total,
                  filterKey: 'all',
                  currentFilter: currentFilter,
                  onTap: () => onFilterChanged('all'),
                  accentColor: primaryColor,
                  isDark: isDark,
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  label: 'Completadas',
                  count: completed,
                  filterKey: 'completed',
                  currentFilter: currentFilter,
                  onTap: () => onFilterChanged('completed'),
                  accentColor: const Color(0xFF10B981),
                  isDark: isDark,
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  label: 'A tiempo',
                  count: onTime,
                  filterKey: 'ontime',
                  currentFilter: currentFilter,
                  onTap: () => onFilterChanged('ontime'),
                  accentColor: const Color(0xFF10B981),
                  isDark: isDark,
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  label: 'Tardanzas',
                  count: lateCount,
                  filterKey: 'late',
                  currentFilter: currentFilter,
                  onTap: () => onFilterChanged('late'),
                  accentColor: const Color(0xFFF59E0B),
                  isDark: isDark,
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  label: 'Sin salida',
                  count: missing,
                  filterKey: 'missing',
                  currentFilter: currentFilter,
                  onTap: () => onFilterChanged('missing'),
                  accentColor: const Color(0xFFEF4444),
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7.5),
        decoration: BoxDecoration(
          color: _innerBoxBg(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 14.5, color: color),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required int count,
    required String filterKey,
    required String currentFilter,
    required VoidCallback onTap,
    required Color accentColor,
    required bool isDark,
  }) {
    final isSelected = currentFilter == filterKey;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor.withValues(alpha: 0.2)
                : (isDark ? const Color(0xFF0F1A22) : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? accentColor
                  : (isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06)),
              width: isSelected ? 1.4 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected
                      ? (isDark ? Colors.white : accentColor)
                      : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? accentColor
                      : (isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: isSelected
                        ? Colors.white
                        : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJourneyList(
    List<ShiftJourneyRecord> journeys,
    bool isLoading,
    Future<void> Function() onRefresh, {
    required bool showUserName,
    bool canEdit = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = ThemeService.primaryColor(context);

    if (isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.8,
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Cargando historial de asistencias...',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ThemeService.subtextColor(context),
              ),
            ),
          ],
        ),
      );
    }

    if (journeys.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        color: primaryColor,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          children: [
            const SizedBox(height: 50),
            Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: primaryColor.withValues(alpha: 0.25)),
                ),
                child: Icon(
                  Icons.assignment_late_outlined,
                  size: 38,
                  color: primaryColor,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No se encontraron jornadas registradas',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5),
            ),
            const SizedBox(height: 8),
            Text(
              'Tus asistencias aparecerán aquí automáticamente cada vez que marques entrada y salida en la institución.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Actualizar ahora'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryColor,
                  side: BorderSide(color: primaryColor.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final activeFilter = showUserName ? _allFilter : _myFilter;
    final activeSearch = showUserName ? _searchQuery : '';
    final filtered = _filterJourneys(journeys, activeFilter, activeSearch);

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: primaryColor,
      child: Responsive.constrained(
        context,
        maxTabletWidth: 860,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          itemCount: filtered.isEmpty ? 2 : filtered.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildSummaryHeroCard(
                context: context,
                allJourneys: journeys,
                currentFilter: activeFilter,
                onFilterChanged: (newFilter) {
                  setState(() {
                    if (showUserName) {
                      _allFilter = newFilter;
                    } else {
                      _myFilter = newFilter;
                    }
                  });
                },
                showSearch: showUserName,
              );
            }

            if (filtered.isEmpty) {
              return Container(
                margin: const EdgeInsets.only(top: 14),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _cardBg(context),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _cardBorder(context)),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.filter_list_off_rounded,
                      size: 40,
                      color: ThemeService.subtextColor(context),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Sin registros para este filtro',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'No se encontraron jornadas que coincidan con la categoría seleccionada.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: ThemeService.subtextColor(context),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          if (showUserName) {
                            _allFilter = 'all';
                            _searchController.clear();
                            _searchQuery = '';
                          } else {
                            _myFilter = 'all';
                          }
                        });
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Mostrar todas las jornadas'),
                    ),
                  ],
                ),
              );
            }

            final journey = filtered[index - 1];
            return ShiftJourneyCard(
              journey: journey,
              showUserName: showUserName,
              onEdit: canEdit ? () => _showEditJourneyDialog(journey) : null,
            );
          },
        ),
      ),
    );
  }

  Widget _buildPendingList(
    List<Map<String, dynamic>> items,
    bool isLoading,
    Future<void> Function() onRefresh,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = ThemeService.primaryColor(context);

    if (isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.8,
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Cargando pendientes de salida...',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ThemeService.subtextColor(context),
              ),
            ),
          ],
        ),
      );
    }

    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        color: primaryColor,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(32),
          children: [
            const SizedBox(height: 60),
            Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.25)),
                ),
                child: const Icon(
                  Icons.check_circle_outline_rounded,
                  size: 38,
                  color: Color(0xFF10B981),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Sin salidas pendientes',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5),
            ),
            const SizedBox(height: 8),
            Text(
              'Todos los colaboradores han completado su registro de salida para sus jornadas correspondientes.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Actualizar lista'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryColor,
                  side: BorderSide(color: primaryColor.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: primaryColor,
      child: Responsive.constrained(
        context,
        maxTabletWidth: 860,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return PendingCheckoutCard(
              item: item,
              onManualRecord: () {
                final shift = AttendanceShift.fromString(item['shift']?.toString());
                final dummyJourney = ShiftJourneyRecord(
                  id: item['id']?.toString() ?? '',
                  userId: item['user_id']?.toString() ?? '',
                  userName: item['user_name']?.toString(),
                  userEmail: item['user_email']?.toString(),
                  userDocument: item['user_document']?.toString(),
                  workDate: item['work_date']?.toString() ?? '',
                  shift: shift,
                  checkIn: AttendanceModel(
                    id: item['id']?.toString() ?? '',
                    userId: item['user_id']?.toString() ?? '',
                    timestamp: DateTime.tryParse(item['check_in_timestamp']?.toString() ?? '') ?? DateTime.now(),
                    type: AttendanceType.CHECK_IN,
                    status: AttendanceStatus.ON_TIME,
                    shift: shift,
                    workDate: item['work_date']?.toString(),
                  ),
                );
                _showEditJourneyDialog(dummyJourney);
              },
            );
          },
        ),
      ),
    );
  }
}

