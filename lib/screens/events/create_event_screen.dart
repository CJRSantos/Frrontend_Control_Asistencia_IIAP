import '../../widgets/event_image_widget.dart';
import '../home_screen.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import '../../models/event_model.dart';
import '../../models/user_model.dart';
import '../../services/event_service.dart';
import '../../services/storage_service.dart';
import '../../services/theme_service.dart';
import '../../services/wallpaper_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_cached_avatar.dart';

class CreateEventScreen extends StatefulWidget {
  final EventModel? eventToEdit;

  const CreateEventScreen({
    super.key,
    this.eventToEdit,
  });

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  int _currentStep = 0;

  final _formKey = GlobalKey<FormState>();

  late TextEditingController _titleController;
  late TextEditingController _uoController;
  late TextEditingController _descriptionController;
  late TextEditingController _locationController;

  late EventType _selectedType;
  late DateTime _startDate;
  late DateTime _endDate;
  late bool _requiresAttendance;
  String? _eventImageUrl;

  // Turnos Independientes del Evento
  bool _hasManana = true;
  TimeOfDay _mananaStart = const TimeOfDay(hour: 8, minute: 30);
  TimeOfDay _mananaEnd = const TimeOfDay(hour: 12, minute: 30);

  bool _hasTarde = false;
  TimeOfDay _tardeStart = const TimeOfDay(hour: 14, minute: 0);
  TimeOfDay _tardeEnd = const TimeOfDay(hour: 18, minute: 0);

  bool _hasNoche = false;
  TimeOfDay _nocheStart = const TimeOfDay(hour: 18, minute: 30);
  TimeOfDay _nocheEnd = const TimeOfDay(hour: 21, minute: 30);

  bool _isSubmitting = false;
  bool _isCustomUo = false;
  int? _maxCapacity;
  bool _generateCertificate = false;
  bool _allowWebRegistration = true;

  static const List<String> _uoOficiales = [
    'Presidencia Ejecutiva',
    'Dirección de Investigación en Recursos Naturales (DIRN)',
    'Dirección de Investigación e Información Ambiental (DIIA)',
    'Dirección de Investigación en Manejo Integral del Bosque (DIMIB)',
    'Laboratorio de Inteligencia Artificial (IA)',
    'Oficina de Tecnologías de Información (OTI)',
    'Oficina de Recursos Humanos (ORH)',
    'Oficina de Administración y Finanzas (OAF)',
    'Estación Experimental Allpahuayo',
    'Estación Experimental Jenaro Herrera',
    'Estación Experimental Quistococha',
    'Sede Regional San Martín (Tarapoto)',
    'Sede Regional Ucayali (Pucallpa)',
    'Sede Regional Madre de Dios',
  ];

  @override
  void initState() {
    super.initState();
    final edit = widget.eventToEdit;
    final now = DateTime.now();

    _titleController = TextEditingController(text: edit?.title ?? '');
    _uoController = TextEditingController(text: edit?.organizationalUnit ?? '');
    _descriptionController = TextEditingController(text: edit?.description ?? '');
    _locationController = TextEditingController(text: edit?.location ?? 'IIAP - Sede Central');

    _selectedType = edit?.type ?? EventType.CAPACITACION;
    _eventImageUrl = edit?.imageUrl;

    final currentUser = StorageService.currentUser;
    if (_uoController.text.trim().isEmpty) {
      if (currentUser?.department != null && currentUser!.department!.trim().isNotEmpty) {
        _uoController.text = currentUser.department!.trim();
      } else {
        _uoController.text = _uoOficiales.first;
      }
    }

    final initialStart = edit?.startDate ?? now.add(const Duration(hours: 1));
    _startDate = DateTime(initialStart.year, initialStart.month, initialStart.day);

    final initialEnd = edit?.endDate ?? initialStart.add(const Duration(hours: 4));
    _endDate = DateTime(initialEnd.year, initialEnd.month, initialEnd.day);

    _requiresAttendance = edit?.requiresAttendance ?? true;

    // Restaurar turnos si viene de edición
    final editShifts = edit?.shifts;
    if (editShifts != null && editShifts.isNotEmpty) {
      _hasManana = false;
      _hasTarde = false;
      _hasNoche = false;
      for (final s in editShifts) {
        final sName = s.name.toLowerCase();
        if (sName == 'manana') {
          _hasManana = s.enabled;
          _mananaStart = _parseTimeOfDay(s.startTime, defaultHour: 8, defaultMinute: 30);
          _mananaEnd = _parseTimeOfDay(s.endTime, defaultHour: 12, defaultMinute: 30);
        } else if (sName == 'tarde') {
          _hasTarde = s.enabled;
          _tardeStart = _parseTimeOfDay(s.startTime, defaultHour: 14, defaultMinute: 0);
          _tardeEnd = _parseTimeOfDay(s.endTime, defaultHour: 18, defaultMinute: 0);
        } else if (sName == 'noche') {
          _hasNoche = s.enabled;
          _nocheStart = _parseTimeOfDay(s.startTime, defaultHour: 18, defaultMinute: 30);
          _nocheEnd = _parseTimeOfDay(s.endTime, defaultHour: 21, defaultMinute: 30);
        }
      }
      if (!_hasManana && !_hasTarde && !_hasNoche) {
        _hasManana = true;
      }
    } else if (edit != null) {
      final sHour = edit.startDate.hour;
      final startTod = TimeOfDay(hour: edit.startDate.hour, minute: edit.startDate.minute);
      final endTod = TimeOfDay(hour: edit.endDate.hour, minute: edit.endDate.minute);
      if (sHour < 13) {
        _hasManana = true;
        _mananaStart = startTod;
        _mananaEnd = endTod;
      } else if (sHour < 18) {
        _hasTarde = true;
        _tardeStart = startTod;
        _tardeEnd = endTod;
      } else {
        _hasNoche = true;
        _nocheStart = startTod;
        _nocheEnd = endTod;
      }
    }

    if (edit?.isEventosMirror == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Este evento es gestionado por el Sistema de Eventos y no puede modificarse.'),
            backgroundColor: Color(0xFF6366F1),
            duration: Duration(seconds: 4),
          ),
        );
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 800,
        imageQuality: 82,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        final base64String = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        setState(() {
          _eventImageUrl = base64String;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar imagen: $e'), backgroundColor: const Color(0xFFDC2626)),
        );
      }
    }
  }

  void _showImageOptions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF131D21) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF64748B),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Foto de Portada del Evento',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Selecciona una fotografía desde tu dispositivo o toma una foto en vivo.',
                style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: Color(0xFF10B981)),
                ),
                title: const Text('Galería de Fotos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('Subir fotografía desde tu dispositivo', style: TextStyle(fontSize: 11.5)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: Color(0xFF38BDF8)),
                ),
                title: const Text('Tomar Fotografía con Cámara', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('Fotografiar el auditorio o sala en vivo', style: TextStyle(fontSize: 11.5)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              
              if (_eventImageUrl != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() => _eventImageUrl = null);
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                    label: const Text('Quitar Foto de Portada', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  TimeOfDay _parseTimeOfDay(String timeStr, {required int defaultHour, required int defaultMinute}) {
    try {
      final parts = timeStr.split(':');
      if (parts.length >= 2) {
        return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }
    } catch (_) {}
    return TimeOfDay(hour: defaultHour, minute: defaultMinute);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _uoController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    const months = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Set', 'Oct', 'Nov', 'Dic'];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Fecha de inicio del evento',
      confirmText: 'Aceptar',
      cancelText: 'Cancelar',
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate;
        }
      });
    }
  }

  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate.isBefore(_startDate) ? _startDate : _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Fecha de culminación del evento',
      confirmText: 'Aceptar',
      cancelText: 'Cancelar',
    );
    if (picked != null) {
      setState(() => _endDate = picked);
    }
  }

  Future<void> _selectShiftTime({
    required TimeOfDay initialTime,
    required String title,
    required ValueChanged<TimeOfDay> onSelected,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: title,
      confirmText: 'Aceptar',
      cancelText: 'Cancelar',
    );
    if (picked != null) {
      setState(() => onSelected(picked));
    }
  }

  Future<void> _showCapacityPicker() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController(text: _maxCapacity != null ? '$_maxCapacity' : '50');
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
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
              const Text(
                'Capacidad de Sala / Cupo Máximo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Define el límite de asistentes para el aforo permitido:',
                style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [30, 50, 100, 200, 500].map((count) {
                  return ActionChip(
                    label: Text('$count personas'),
                    backgroundColor: controller.text == '$count'
                        ? const Color(0xFF10B981).withValues(alpha: 0.2)
                        : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                    onPressed: () {
                      Navigator.pop(ctx, count);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Cantidad personalizada',
                  suffixText: 'asistentes',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: () {
                    final parsed = int.tryParse(controller.text.trim());
                    if (parsed != null && parsed > 0) {
                      Navigator.pop(ctx, parsed);
                    } else {
                      Navigator.pop(ctx, null);
                    }
                  },
                  child: const Text('Confirmar Cupo', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selected != null) {
      setState(() {
        _maxCapacity = selected;
      });
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    // Validación obligatoria: al menos 1 turno activo
    if (!_hasManana && !_hasTarde && !_hasNoche) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes activar al menos un turno para el evento (Mañana, Tarde o Noche).'),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final activeShifts = <EventShift>[];
    if (_hasManana) {
      activeShifts.add(EventShift(
        name: 'manana',
        label: 'Turno Mañana',
        startTime: _formatTimeOfDay(_mananaStart),
        endTime: _formatTimeOfDay(_mananaEnd),
        enabled: true,
      ));
    }
    if (_hasTarde) {
      activeShifts.add(EventShift(
        name: 'tarde',
        label: 'Turno Tarde',
        startTime: _formatTimeOfDay(_tardeStart),
        endTime: _formatTimeOfDay(_tardeEnd),
        enabled: true,
      ));
    }
    if (_hasNoche) {
      activeShifts.add(EventShift(
        name: 'noche',
        label: 'Turno Noche',
        startTime: _formatTimeOfDay(_nocheStart),
        endTime: _formatTimeOfDay(_nocheEnd),
        enabled: true,
      ));
    }

    final firstShift = activeShifts.first;
    final lastShift = activeShifts.last;
    final startParts = firstShift.startTime.split(':');
    final endParts = lastShift.endTime.split(':');

    final start = DateTime(
      _startDate.year,
      _startDate.month,
      _startDate.day,
      int.parse(startParts[0]),
      int.parse(startParts[1]),
    );
    final end = DateTime(
      _endDate.year,
      _endDate.month,
      _endDate.day,
      int.parse(endParts[0]),
      int.parse(endParts[1]),
    );

    if (end.isBefore(start) || end.isAtSameMomentAs(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La fecha y hora de culminación debe ser posterior al inicio.'),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (widget.eventToEdit?.isEventosMirror == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este evento se administra desde el Sistema de Eventos.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final uoText = _uoController.text.trim();
      final uoVal = uoText.isNotEmpty ? uoText : null;

      if (widget.eventToEdit != null) {
        final updated = widget.eventToEdit!.copyWith(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          location: _locationController.text.trim(),
          startDate: start,
          endDate: end,
          type: _selectedType,
          requiresAttendance: _requiresAttendance,
          organizationalUnit: uoVal,
          shifts: activeShifts,
          imageUrl: _eventImageUrl,
          clearImageUrl: _eventImageUrl == null || _eventImageUrl!.isEmpty,
        );
        final saved = await EventService.updateEvent(updated);
        if (!mounted) return;
        Navigator.of(context).pop(saved);
      } else {
        final created = await EventService.createEvent(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          location: _locationController.text.trim(),
          startDate: start,
          endDate: end,
          type: _selectedType,
          requiresAttendance: _requiresAttendance,
          organizationalUnit: uoVal,
          shifts: activeShifts,
          imageUrl: _eventImageUrl,
        );
        if (!mounted) return;
        await _showSuccessModal(created);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar evento: $e'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Modal de Éxito Limpio y Minimalista según solicitud oficial
  Future<void> _showSuccessModal(EventModel event) async {
    const mintGreen = Color(0xFF34D399);
    const darkGreen = Color(0xFF064E3B);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Checkmark en verde esmeralda
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: mintGreen.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(color: mintGreen, width: 2),
                  ),
                  child: const Center(
                    child: Icon(Icons.check_rounded, color: mintGreen, size: 44),
                  ),
                ),
                const SizedBox(height: 20),

                // 2. Título principal
                const Text(
                  '¡Evento Publicado Con Éxito!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (event.title.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: mintGreen,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 26),

                // 3. Botón único: Volver al Inicio
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: mintGreen,
                      foregroundColor: darkGreen,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).pop(event);
                      await EventService.getEvents(forceRefresh: true);
                    },
                    child: const Text(
                      'Listo / Volver a Eventos',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                        color: darkGreen,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _getTypeIcon(EventType type) {
    switch (type) {
      case EventType.CAPACITACION:
        return Icons.school_rounded;
      case EventType.REUNION:
        return Icons.groups_rounded;
      case EventType.INSTITUCIONAL:
        return Icons.account_balance_rounded;
      case EventType.TALLER:
        return Icons.handshake_rounded;
      case EventType.CONFERENCIA:
        return Icons.mic_external_on_rounded;
      case EventType.OTRO:
        return Icons.event_rounded;
    }
  }

  Color _getTypeColor(EventType type) {
    switch (type) {
      case EventType.CAPACITACION:
        return const Color(0xFF2563EB); // Azul
      case EventType.REUNION:
        return const Color(0xFF0D9488); // Teal
      case EventType.INSTITUCIONAL:
        return const Color(0xFF7C3AED); // Púrpura
      case EventType.TALLER:
        return const Color(0xFFEA580C); // Naranja
      case EventType.CONFERENCIA:
        return const Color(0xFFDB2777); // Rosa
      case EventType.OTRO:
        return const Color(0xFF4B5563); // Gris
    }
  }

  void _openEventTypeSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: ThemeService.cardBg(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
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
                  Icon(Icons.category_rounded, size: 22, color: Color(0xFF2563EB)),
                  SizedBox(width: 10),
                  Text(
                    'Seleccionar Tipo de Evento',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Elige la categoría oficial del evento institucional',
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 16),
              ...EventType.values.map((type) {
                final isSelected = _selectedType == type;
                final color = _getTypeColor(type);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () {
                      setState(() => _selectedType = type);
                      Navigator.pop(ctx);
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? color.withValues(alpha: isDark ? 0.2 : 0.1)
                            : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? color
                              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(_getTypeIcon(type), color: color, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              type.displayName,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected
                                    ? (isDark ? Colors.white : color)
                                    : (isDark ? Colors.white : const Color(0xFF1E293B)),
                              ),
                            ),
                          ),
                          if (isSelected)
                            Icon(Icons.check_circle_rounded, color: color, size: 22)
                          else
                            Icon(Icons.circle_outlined,
                                color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1), size: 20),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _openUoSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = ThemeService.primaryColor(context);
    String searchQuery = '';
    final searchController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredUos = _uoOficiales.where((uo) {
              if (searchQuery.trim().isEmpty) return true;
              return uo.toLowerCase().contains(searchQuery.toLowerCase());
            }).toList();

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              decoration: BoxDecoration(
                color: ThemeService.cardBg(context),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.apartment_rounded, size: 22, color: primary),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Seleccionar Unidad Organizativa (UO)',
                              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Direcciones, Oficinas y Estaciones Oficiales del IIAP',
                              style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Buscador en vivo
                  TextField(
                    controller: searchController,
                    onChanged: (val) => setModalState(() => searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Buscar unidad organizativa...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        ...filteredUos.map((uo) {
                          final isSelected = _uoController.text.trim().toLowerCase() == uo.toLowerCase();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _uoController.text = uo;
                                  _isCustomUo = false;
                                });
                                Navigator.pop(ctx);
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? primary.withValues(alpha: isDark ? 0.2 : 0.1)
                                      : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? primary
                                        : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                                    width: isSelected ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.business_rounded,
                                      size: 18,
                                      color: isSelected ? primary : const Color(0xFF94A3B8),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        uo,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                          color: isSelected
                                              ? (isDark ? Colors.white : primary)
                                              : (isDark ? Colors.white : const Color(0xFF1E293B)),
                                        ),
                                      ),
                                    ),
                                    if (isSelected)
                                      Icon(Icons.check_circle_rounded, color: primary, size: 20),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                        const Divider(height: 20),
                        // Opción personalizada
                        InkWell(
                          onTap: () {
                            setState(() {
                              _isCustomUo = true;
                              _uoController.clear();
                            });
                            Navigator.pop(ctx);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                style: BorderStyle.solid,
                              ),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.edit_note_rounded, size: 20, color: Color(0xFFF59E0B)),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Escribir otra Unidad / Oficina personalizada...',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatTime12h(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '${hour.toString().padLeft(2, '0')}:$minute $period';
  }

  int _activeShiftsCount() {
    int c = 0;
    if (_hasManana) c++;
    if (_hasTarde) c++;
    if (_hasNoche) c++;
    return c;
  }

  String _activeShiftsSummary() {
    final list = <String>[];
    if (_hasManana) list.add('Mañana');
    if (_hasTarde) list.add('Tarde');
    if (_hasNoche) list.add('Noche');
    if (list.isEmpty) return 'Sin turnos';
    return list.join(' & ');
  }

  Widget _buildStepperHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mintGreen = ThemeService.primaryColor(context);
    final darkGreen = isDark ? const Color(0xFF062319) : const Color(0xFF064E3B);
    final inactiveBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final inactiveLine = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final inactiveText = isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);

    Widget buildCircle(int stepIndex, String number) {
      final isDone = _currentStep > stepIndex;
      final isActive = _currentStep == stepIndex;
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: (isDone || isActive) ? mintGreen : inactiveBg,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: isDone
              ? Icon(Icons.check, size: 16, color: darkGreen)
              : Text(
                  number,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isActive ? darkGreen : inactiveText,
                  ),
                ),
        ),
      );
    }

    Widget buildLabel(int stepIndex, String label) {
      final isDone = _currentStep > stepIndex;
      final isActive = _currentStep == stepIndex;
      return Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
          color: (isDone || isActive)
              ? (isDark ? Colors.white : const Color(0xFF0F172A))
              : inactiveText,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Column(
        children: [
          Row(
            children: [
              InkWell(
                onTap: () => setState(() => _currentStep = 0),
                borderRadius: BorderRadius.circular(20),
                child: buildCircle(0, '1'),
              ),
              Expanded(
                child: Container(
                  height: 2.5,
                  color: _currentStep >= 1 ? mintGreen : inactiveLine,
                ),
              ),
              InkWell(
                onTap: () {
                  if (widget.eventToEdit != null || _titleController.text.trim().isNotEmpty) {
                    setState(() => _currentStep = 1);
                  }
                },
                borderRadius: BorderRadius.circular(20),
                child: buildCircle(1, '2'),
              ),
              Expanded(
                child: Container(
                  height: 2.5,
                  color: _currentStep >= 2 ? mintGreen : inactiveLine,
                ),
              ),
              InkWell(
                onTap: () {
                  if (widget.eventToEdit != null || (_titleController.text.trim().isNotEmpty && (_hasManana || _hasTarde || _hasNoche))) {
                    setState(() => _currentStep = 2);
                  }
                },
                borderRadius: BorderRadius.circular(20),
                child: buildCircle(2, '3'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              InkWell(
                onTap: () => setState(() => _currentStep = 0),
                child: buildLabel(0, '1. INFO'),
              ),
              InkWell(
                onTap: () {
                  if (widget.eventToEdit != null || _titleController.text.trim().isNotEmpty) {
                    setState(() => _currentStep = 1);
                  }
                },
                child: buildLabel(1, '2. TURNOS'),
              ),
              InkWell(
                onTap: () {
                  if (widget.eventToEdit != null || (_titleController.text.trim().isNotEmpty && (_hasManana || _hasTarde || _hasNoche))) {
                    setState(() => _currentStep = 2);
                  }
                },
                child: buildLabel(2, '3. CIERRE'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypeQuickButton({
    required EventType type,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _selectedType == type;
    const mintGreen = Color(0xFF10B981);
    const darkGreen = Color(0xFF064E3B);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedType = type),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? mintGreen
                : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? mintGreen
                  : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: isSelected ? darkGreen : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? darkGreen : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShiftCardNew({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconBgColor,
    required bool isEnabled,
    required TimeOfDay startTime,
    required TimeOfDay endTime,
    required ValueChanged<bool> onToggle,
    required VoidCallback onPickStart,
    required VoidCallback onPickEnd,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const mintGreen = Color(0xFF34D399);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEnabled
              ? mintGreen.withValues(alpha: 0.5)
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
          width: isEnabled ? 1.3 : 1.0,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconBgColor.withValues(alpha: isEnabled ? 0.25 : 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: isEnabled ? iconBgColor : Colors.grey),
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
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: isEnabled,
                activeTrackColor: mintGreen,
                onChanged: onToggle,
              ),
            ],
          ),
          if (isEnabled) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onPickStart,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0B131E) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.schedule_rounded, size: 12, color: Color(0xFF94A3B8)),
                              SizedBox(width: 4),
                              Text('Hora Inicio', style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8))),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _formatTime12h(startTime),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: onPickEnd,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0B131E) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.schedule_send_rounded, size: 12, color: Color(0xFF94A3B8)),
                              SizedBox(width: 4),
                              Text('Hora Fin', style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8))),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _formatTime12h(endTime),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
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
    );
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
        final isEdit = widget.eventToEdit != null;
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

        return PopScope(
          canPop: _currentStep == 0,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (_currentStep > 0) {
              setState(() => _currentStep--);
            }
          },
          child: Scaffold(
          backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white : const Color(0xFF0F172A)),
          onPressed: () {
            if (_currentStep > 0) {
              setState(() => _currentStep--);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Text(
          isEdit ? 'Editar Evento' : 'Crear Nuevo Evento',
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          if (isEdit)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isSubmitting ? null : _handleSubmit,
                icon: _isSubmitting
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_rounded, size: 18),
                label: const Text(
                  'Guardar',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Responsive.constrained(
            context,
            maxTabletWidth: 700,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. STEPPER CONECTOR SUPERIOR (1. INFO ── 2. TURNOS ── 3. CIERRE)
                  _buildStepperHeader(),
                  const SizedBox(height: 10),

                  // 2. CONTENIDO SEGÚN EL PASO ACTIVO
                  if (_currentStep == 0) ...[
                    // ==========================================
                    // --- PASO 1: INFO ---
                    // ==========================================
                    // Header Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: cardBorder),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF064E3B).withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.calendar_today_rounded, color: mintGreen, size: 22),
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
                                        'Programación de Evento IIAP',
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF064E3B).withValues(alpha: 0.6),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                                      ),
                                      child: const Text(
                                        'Oficial',
                                        style: TextStyle(
                                          color: mintGreen,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Código QR institucional con validación biométrica...',
                                  style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // FOTO DE PORTADA DEL EVENTO (CON PERSISTENCIA)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Foto de Portada del Evento',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        if (_eventImageUrl != null)
                          InkWell(
                            onTap: _showImageOptions,
                            child: const Text(
                              'Cambiar Foto',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF34D399)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _showImageOptions,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        height: 160,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _eventImageUrl != null ? mintGreen : cardBorder,
                            width: _eventImageUrl != null ? 1.5 : 1,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: _eventImageUrl != null
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    GestureDetector(
                                      onTap: () => EventImageWidget.showFullScreen(
                                        context,
                                        _eventImageUrl,
                                        title: _titleController.text.trim().isNotEmpty
                                            ? _titleController.text.trim()
                                            : 'Vista previa de la imagen',
                                      ),
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        child: EventImageWidget(
                                          imageUrl: _eventImageUrl,
                                          fit: BoxFit.cover,
                                          fallbackWidget: const Center(
                                            child: Icon(Icons.broken_image_rounded, color: Color(0xFF64748B), size: 36),
                                          ),
                                        ),
                                      ),
                                    ),
                                    IgnorePointer(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.transparent,
                                              Colors.black.withValues(alpha: 0.65),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 10,
                                      left: 12,
                                      right: 12,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Row(
                                            children: [
                                              Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                                              SizedBox(width: 5),
                                              Text('Foto vinculada al evento', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                          IconButton(
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFF87171), size: 20),
                                            onPressed: () => setState(() => _eventImageUrl = null),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF064E3B).withValues(alpha: 0.3),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.add_a_photo_outlined, color: mintGreen, size: 26),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Subir Foto de Portada (Opcional)',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'Cámara o galería de fotos',
                                      style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // TÍTULO DEL EVENTO
                    Row(
                      children: [
                        Text(
                          'Título del Evento',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text('*', style: TextStyle(color: mintGreen, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cardBorder),
                      ),
                      child: TextFormField(
                        controller: _titleController,
                        style: TextStyle(fontSize: 14, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.text_fields_rounded, color: Color(0xFF64748B), size: 20),
                          hintText: 'Taller Institucional de Asistencia y Gestión',
                          hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 13.5),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'El título del evento es obligatorio';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 18),

                    // TIPO DE EVENTO
                    Row(
                      children: [
                        Text(
                          'Tipo de Evento',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text('*', style: TextStyle(color: mintGreen, fontWeight: FontWeight.bold, fontSize: 16)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF064E3B).withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                          ),
                          child: const Text(
                            'Selector Dinámico',
                            style: TextStyle(color: mintGreen, fontSize: 10.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _openEventTypeSelector,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cardBorder),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(_getTypeIcon(_selectedType), color: mintGreen, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedType.displayName,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Toca para cambiar la categoría del evento',
                                    style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF94A3B8), size: 24),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _buildTypeQuickButton(
                          type: EventType.CAPACITACION,
                          label: 'Capacitación',
                          icon: Icons.school_outlined,
                        ),
                        const SizedBox(width: 8),
                        _buildTypeQuickButton(
                          type: EventType.REUNION,
                          label: 'Reunión de Coord.',
                          icon: Icons.handshake_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildTypeQuickButton(
                          type: EventType.INSTITUCIONAL,
                          label: 'Seminario IIAP',
                          icon: Icons.account_balance_outlined,
                        ),
                        const SizedBox(width: 8),
                        _buildTypeQuickButton(
                          type: EventType.TALLER,
                          label: 'Taller de Campo',
                          icon: Icons.science_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // UNIDAD ORGANIZATIVA (UO)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  'Unidad Organizativa (UO)',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Text('*', style: TextStyle(color: mintGreen, fontWeight: FontWeight.bold, fontSize: 16)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF064E3B).withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.security_rounded, size: 11, color: mintGreen),
                                SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    'Admin IIAP: Acceso Total',
                                    style: TextStyle(color: mintGreen, fontSize: 10, fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _openUoSelector,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cardBorder),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF064E3B).withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.domain_rounded, color: mintGreen, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _uoController.text.isNotEmpty ? _uoController.text : 'Seleccionar Unidad...',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Sede Central Iquitos • 14 sedes y direcciones',
                                    style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B), size: 22),
                          ],
                        ),
                      ),
                    ),
                    if (_isCustomUo) ...[
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: cardBorder),
                        ),
                        child: TextFormField(
                          controller: _uoController,
                          style: TextStyle(fontSize: 13.5, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.edit_note_rounded, color: Color(0xFFF59E0B), size: 20),
                            hintText: 'Escribe el nombre de la Unidad personalizada...',
                            hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 26),

                    if (isEdit) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: _isSubmitting ? null : _handleSubmit,
                          icon: _isSubmitting
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.save_rounded, size: 19),
                          label: const Text(
                            'Guardar Cambios del Evento',
                            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // BOTÓN CONTINUAR A SEDES & HORARIOS
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themePrimary,
                          foregroundColor: isDark ? Colors.white : Colors.black,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () {
                          if (_titleController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Por favor, ingresa el título del evento.'),
                                backgroundColor: Color(0xFFDC2626),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }
                          setState(() => _currentStep = 1);
                        },
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Continuar',
                              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: darkGreen),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward_rounded, color: darkGreen, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ] else if (_currentStep == 1) ...[
                    // ==========================================
                    // --- PASO 2: TURNOS --- (Idéntico a Imagen 1)
                    // ==========================================
                    // Header Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: cardBorder),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF064E3B).withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.domain_rounded, color: mintGreen, size: 22),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Configuración Espacial y Temporal',
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Define la sede física, enlaces virtuales y los horarios...',
                                  style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // UBICACIÓN / PLATAFORMA * (OBLIGATORIO)
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 17, color: mintGreen),
                        const SizedBox(width: 6),
                        Text(
                          'Ubicación / Plataforma',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text('*', style: TextStyle(color: mintGreen, fontWeight: FontWeight.bold, fontSize: 16)),
                        const Spacer(),
                        const Text(
                          'OBLIGATORIO',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 0.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cardBorder),
                      ),
                      child: TextFormField(
                        controller: _locationController,
                        style: TextStyle(fontSize: 14, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.location_on_rounded, color: mintGreen, size: 20),
                          suffixIcon: Icon(Icons.map_outlined, color: Color(0xFF64748B), size: 20),
                          hintText: 'IIAP - Sede Central, Auditorio Principal...',
                          hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 13.5),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Sugerencias rápidas con chips
                    const Text('Sugerencias rápidas:', style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildQuickLocChip('IIAP - Sede Central', Icons.business_rounded),
                        _buildQuickLocChip('Auditorio Principal', Icons.meeting_room_rounded),
                        _buildQuickLocChip('Sala de Capacitaciones', Icons.groups_rounded),
                        _buildQuickLocChip('Virtual (Meet)', Icons.videocam_rounded),
                        _buildQuickLocChip('Virtual (Zoom)', Icons.headset_mic_rounded),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // VIGENCIA DEL EVENTO
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined, size: 16, color: mintGreen),
                        const SizedBox(width: 6),
                        Text(
                          'Vigencia del Evento',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF064E3B).withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 5, height: 5, decoration: const BoxDecoration(color: mintGreen, shape: BoxShape.circle)),
                              const SizedBox(width: 5),
                              Text(
                                _startDate.day == _endDate.day && _startDate.month == _endDate.month && _startDate.year == _endDate.year
                                    ? 'Jornada Única'
                                    : 'Varios Días',
                                style: const TextStyle(color: mintGreen, fontSize: 10.5, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cardBorder),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _selectStartDate,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF0B131E) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Fecha Inicio', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.calendar_today_rounded, size: 14, color: mintGreen),
                                        const SizedBox(width: 6),
                                        Text(
                                          _formatDate(_startDate),
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InkWell(
                              onTap: _selectEndDate,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF0B131E) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Fecha Fin', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.event_available_rounded, size: 15, color: mintGreen),
                                        const SizedBox(width: 6),
                                        Text(
                                          _formatDate(_endDate),
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // TURNOS Y HORARIOS INDEPENDIENTES
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded, size: 18, color: mintGreen),
                        const SizedBox(width: 6),
                        Text(
                          'Turnos y Horarios Independientes',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Puedes activar 1 solo turno, 2 turnos o los 3 turnos en el mismo evento:',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                    ),
                    const SizedBox(height: 12),

                    // Turno Mañana
                    _buildShiftCardNew(
                      title: 'Turno Mañana',
                      subtitle: 'Jornada matutina protocolar',
                      icon: Icons.wb_sunny_rounded,
                      iconBgColor: const Color(0xFF10B981),
                      isEnabled: _hasManana,
                      startTime: _mananaStart,
                      endTime: _mananaEnd,
                      onToggle: (val) => setState(() => _hasManana = val),
                      onPickStart: () => _selectShiftTime(
                        initialTime: _mananaStart,
                        title: 'Hora Inicio - Turno Mañana',
                        onSelected: (t) => _mananaStart = t,
                      ),
                      onPickEnd: () => _selectShiftTime(
                        initialTime: _mananaEnd,
                        title: 'Hora Fin - Turno Mañana',
                        onSelected: (t) => _mananaEnd = t,
                      ),
                    ),

                    // Turno Tarde
                    _buildShiftCardNew(
                      title: 'Turno Tarde',
                      subtitle: 'Jornada vespertina técnica',
                      icon: Icons.wb_twilight_rounded,
                      iconBgColor: const Color(0xFFF59E0B),
                      isEnabled: _hasTarde,
                      startTime: _tardeStart,
                      endTime: _tardeEnd,
                      onToggle: (val) => setState(() => _hasTarde = val),
                      onPickStart: () => _selectShiftTime(
                        initialTime: _tardeStart,
                        title: 'Hora Inicio - Turno Tarde',
                        onSelected: (t) => _tardeStart = t,
                      ),
                      onPickEnd: () => _selectShiftTime(
                        initialTime: _tardeEnd,
                        title: 'Hora Fin - Turno Tarde',
                        onSelected: (t) => _tardeEnd = t,
                      ),
                    ),

                    // Turno Noche
                    _buildShiftCardNew(
                      title: 'Turno Noche',
                      subtitle: 'Jornada nocturna / Clausura',
                      icon: Icons.nights_stay_rounded,
                      iconBgColor: const Color(0xFF6366F1),
                      isEnabled: _hasNoche,
                      startTime: _nocheStart,
                      endTime: _nocheEnd,
                      onToggle: (val) => setState(() => _hasNoche = val),
                      onPickStart: () => _selectShiftTime(
                        initialTime: _nocheStart,
                        title: 'Hora Inicio - Turno Noche',
                        onSelected: (t) => _nocheStart = t,
                      ),
                      onPickEnd: () => _selectShiftTime(
                        initialTime: _nocheEnd,
                        title: 'Hora Fin - Turno Noche',
                        onSelected: (t) => _nocheEnd = t,
                      ),
                    ),

                    // Resumen de Turnos Activos
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cardBorder),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.fact_check_outlined, color: mintGreen, size: 18),
                          const SizedBox(width: 8),
                          const Text(
                            'Turnos activos seleccionados:',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF064E3B).withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${_activeShiftsCount()} Turnos',
                              style: const TextStyle(color: mintGreen, fontWeight: FontWeight.bold, fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (isEdit) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: _isSubmitting ? null : _handleSubmit,
                          icon: _isSubmitting
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.save_rounded, size: 19),
                          label: const Text(
                            'Guardar Cambios del Evento',
                            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // BOTONES INFERIORES DEL PASO 2
                    Row(
                      children: [
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark ? Colors.white : const Color(0xFF0F172A),
                            side: BorderSide(color: cardBorder),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: () => setState(() => _currentStep = 0),
                          child: const Row(
                            children: [
                              Icon(Icons.arrow_back_rounded, size: 16),
                              SizedBox(width: 6),
                              Text('Atrás', style: TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: mintGreen,
                              foregroundColor: darkGreen,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: () {
                              if (!_hasManana && !_hasTarde && !_hasNoche) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Debes activar al menos un turno para el evento.'),
                                    backgroundColor: Color(0xFFDC2626),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                                return;
                              }
                              setState(() => _currentStep = 2);
                            },
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Ir al Cierre',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: darkGreen),
                                ),
                                SizedBox(width: 6),
                                Icon(Icons.arrow_forward_rounded, color: darkGreen, size: 16),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    // ==========================================
                    // --- PASO 3: CIERRE --- (Idéntico a Imagen 2)
                    // ==========================================
                    // Card Resumen Ejecutivo Superior
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
                              Container(width: 6, height: 6, decoration: const BoxDecoration(color: mintGreen, shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              const Text(
                                'RESUMEN EJECUTIVO',
                                style: TextStyle(color: mintGreen, fontSize: 10.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                              ),
                              const Spacer(),
                              const Row(
                                children: [
                                  Icon(Icons.lock_outline_rounded, size: 12, color: Color(0xFF94A3B8)),
                                  SizedBox(width: 4),
                                  Text('Listo para sellar', style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8))),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF064E3B).withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.event_note_rounded, color: mintGreen, size: 20),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _titleController.text.isNotEmpty ? _titleController.text : 'Taller Institucional',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '📍 ${_locationController.text}  •  ${_formatDate(_startDate)} (${_activeShiftsSummary()})',
                                      style: const TextStyle(fontSize: 11.5, color: mintGreen),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // DESCRIPCIÓN Y AGENDA OFICIAL
                    Row(
                      children: [
                        const Icon(Icons.format_list_bulleted_rounded, size: 17, color: mintGreen),
                        const SizedBox(width: 6),
                        Text(
                          'Descripción y Agenda Oficial',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const Spacer(),
                        const Text('Opcional', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Chips rápidos de plantilla
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildTemplateChip(
                          label: 'Plantilla Temario',
                          icon: Icons.view_headline_rounded,
                          template: '• Presentación y bienvenida institucional\n• Objetivos de la jornada de capacitación\n• Mesa redonda y preguntas',
                        ),
                        _buildTemplateChip(
                          label: 'Horarios clave',
                          icon: Icons.schedule_rounded,
                          template: '• ${_activeShiftsSummary()}: Acreditación e ingreso con QR\n• Sesión práctica y entrega de constancias',
                        ),
                        _buildTemplateChip(
                          label: 'Requisitos',
                          icon: Icons.checklist_rounded,
                          template: '• Portar DNI para validación en puerta\n• Asistencia puntual en los turnos seleccionados',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0B131E) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cardBorder),
                      ),
                      child: TextFormField(
                        controller: _descriptionController,
                        maxLines: 4,
                        style: TextStyle(fontSize: 13, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                        decoration: const InputDecoration(
                          hintText: 'Detalla los objetivos, ponentes, requisitos o temas a tratar en la sesión institucional...',
                          hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 12.5),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // CONTROL QR INSTITUCIONAL DINÁMICO
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: cardBorder),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: mintGreen.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.qr_code_scanner_rounded, color: mintGreen, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Control QR Institucional Dinámico',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13.5,
                                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'Permite a los asistentes escanear el QR proyectado y quedar registrados al instante con validación biométrica o DNI.',
                                      style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), height: 1.3),
                                    ),
                                  ],
                                ),
                              ),
                              Switch.adaptive(
                                value: _requiresAttendance,
                                activeTrackColor: mintGreen,
                                onChanged: (val) => setState(() => _requiresAttendance = val),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          InkWell(
                            onTap: () => setState(() => _allowWebRegistration = !_allowWebRegistration),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF0B131E) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _allowWebRegistration ? mintGreen.withValues(alpha: 0.4) : Colors.transparent,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.devices_rounded, size: 18, color: _allowWebRegistration ? mintGreen : const Color(0xFF64748B)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Registro externo vía Web móvil',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: _allowWebRegistration ? (isDark ? Colors.white : const Color(0xFF0F172A)) : const Color(0xFF94A3B8),
                                          ),
                                        ),
                                        const Text(
                                          'Sin descarga de App requerida (Público general)',
                                          style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: _allowWebRegistration ? mintGreen : Colors.transparent,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: _allowWebRegistration ? mintGreen : const Color(0xFF64748B),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: _allowWebRegistration
                                        ? const Icon(Icons.check, size: 15, color: darkGreen)
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // AJUSTES OPERATIVOS Y PROTOCOLO
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
                            children: const [
                              Icon(Icons.tune_rounded, size: 18, color: mintGreen),
                              SizedBox(width: 8),
                              Text('Ajustes Operativos y Protocolo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Text('Capacidad de Sala / Aforo', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                              const Spacer(),
                              Text(
                                _maxCapacity == null ? 'Ilimitado' : '$_maxCapacity personas',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _maxCapacity == null ? mintGreen : const Color(0xFF38BDF8),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => setState(() => _maxCapacity = null),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 9),
                                    decoration: BoxDecoration(
                                      color: _maxCapacity == null
                                          ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))
                                          : (isDark ? const Color(0xFF0B131E) : const Color(0xFFF8FAFC)),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: _maxCapacity == null ? mintGreen.withValues(alpha: 0.6) : cardBorder,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.all_inclusive_rounded, size: 15, color: _maxCapacity == null ? mintGreen : const Color(0xFF94A3B8)),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Sin Límite',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: _maxCapacity == null ? (isDark ? Colors.white : const Color(0xFF0F172A)) : const Color(0xFF94A3B8),
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
                                  onTap: _showCapacityPicker,
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 9),
                                    decoration: BoxDecoration(
                                      color: _maxCapacity != null
                                          ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))
                                          : (isDark ? const Color(0xFF0B131E) : const Color(0xFFF8FAFC)),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: _maxCapacity != null ? const Color(0xFF38BDF8) : cardBorder,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.group_outlined, size: 15, color: _maxCapacity != null ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8)),
                                        const SizedBox(width: 6),
                                        Text(
                                          _maxCapacity != null ? 'Cupo: $_maxCapacity' : 'Establecer Cupo',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: _maxCapacity != null ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
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
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.workspace_premium_outlined, color: Color(0xFFF59E0B), size: 20),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Certificado de Asistencia Digital', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                    Text('Generar constancia PDF al marcar salida', style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8))),
                                  ],
                                ),
                              ),
                              Switch.adaptive(
                                value: _generateCertificate,
                                activeTrackColor: mintGreen,
                                onChanged: (val) => setState(() => _generateCertificate = val),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // BOTÓN PRINCIPAL: PUBLICAR / ACTUALIZAR EVENTO OFICIAL
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themePrimary,
                          foregroundColor: isDark ? Colors.white : Colors.black,
                          elevation: 3,
                          shadowColor: mintGreen.withValues(alpha: 0.4),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: _isSubmitting ? null : _handleSave,
                        child: _isSubmitting
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: darkGreen))
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    widget.eventToEdit != null ? Icons.save_rounded : Icons.rocket_launch_rounded,
                                    color: isDark ? Colors.white : Colors.black,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    widget.eventToEdit != null ? 'Guardar Cambios del Evento' : 'Publicar Evento Oficial',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.white : Colors.black),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => setState(() => _currentStep = 1),
                        icon: const Icon(Icons.arrow_back_rounded, size: 16, color: Color(0xFF94A3B8)),
                        label: const Text(
                          'Volver a Turnos',
                          style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
      },
    );
  }

  Widget _buildQuickLocChip(String label, IconData icon) {
    final isSelected = _locationController.text.trim().toLowerCase() == label.toLowerCase();
    const mintGreen = Color(0xFF34D399);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () => setState(() => _locationController.text = label),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF064E3B).withValues(alpha: 0.5)
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? mintGreen : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? mintGreen : const Color(0xFF94A3B8)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? mintGreen : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateChip({required String label, required IconData icon, required String template}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () {
        final current = _descriptionController.text.trim();
        setState(() {
          _descriptionController.text = current.isEmpty ? template : '$current\n\n$template';
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: const Color(0xFF34D399)),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
