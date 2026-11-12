import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/event_model.dart';
import '../../services/api_client.dart';
import '../../services/event_service.dart';
import '../../services/theme_service.dart';

class ManualAttendeeModal extends StatefulWidget {
  final EventModel event;
  final bool isDialog;

  const ManualAttendeeModal({
    super.key,
    required this.event,
    this.isDialog = false,
  });

  static Future<EventModel?> show(BuildContext context, {required EventModel event}) {
    final width = MediaQuery.sizeOf(context).width;
    final isTabletOrDesktop = width >= 640;

    if (isTabletOrDesktop) {
      return showDialog<EventModel>(
        context: context,
        barrierDismissible: true,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580, maxHeight: 760),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Material(
                color: ThemeService.cardBg(context),
                child: ManualAttendeeModal(event: event, isDialog: true),
              ),
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet<EventModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ManualAttendeeModal(event: event, isDialog: false),
    );
  }

  @override
  State<ManualAttendeeModal> createState() => _ManualAttendeeModalState();
}

class _ManualAttendeeModalState extends State<ManualAttendeeModal> {
  final _formKey = GlobalKey<FormState>();

  // 4 Campos obligatorios base
  final _nameController = TextEditingController();
  final _dniController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  // Campos adicionales opcionales
  final _ageController = TextEditingController();
  final _careerController = TextEditingController();
  final _institutionController = TextEditingController();
  final _positionController = TextEditingController();
  final _notesController = TextEditingController();

  String _docType = 'DNI';
  String? _selectedGender;
  String? _selectedShift;
  bool _showMoreFields = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  late EventModel _lastUpdatedEvent;

  @override
  void initState() {
    super.initState();
    _lastUpdatedEvent = widget.event;
    final shifts = widget.event.shifts.where((s) => s.enabled).toList();
    if (shifts.isNotEmpty) {
      final hour = DateTime.now().hour;
      if (hour < 13 && shifts.any((s) => s.name.toLowerCase() == 'manana')) {
        _selectedShift = shifts.firstWhere((s) => s.name.toLowerCase() == 'manana').name;
      } else if (hour < 18 && shifts.any((s) => s.name.toLowerCase() == 'tarde')) {
        _selectedShift = shifts.firstWhere((s) => s.name.toLowerCase() == 'tarde').name;
      } else if (shifts.any((s) => s.name.toLowerCase() == 'noche')) {
        _selectedShift = shifts.firstWhere((s) => s.name.toLowerCase() == 'noche').name;
      } else {
        _selectedShift = shifts.first.name;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dniController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _ageController.dispose();
    _careerController.dispose();
    _institutionController.dispose();
    _positionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _clearForm() {
    _nameController.clear();
    _dniController.clear();
    _phoneController.clear();
    _emailController.clear();
    _ageController.clear();
    _careerController.clear();
    _institutionController.clear();
    _positionController.clear();
    _notesController.clear();
    setState(() {
      _selectedGender = null;
      _errorMessage = null;
      _isSubmitting = false;
    });
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final updatedEvent = await EventService.registerManualAttendee(
        eventId: widget.event.id,
        fullName: _nameController.text.trim(),
        documentNumber: _dniController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        gender: _selectedGender,
        age: _ageController.text.trim().isNotEmpty ? int.tryParse(_ageController.text.trim()) : null,
        career: _careerController.text.trim().isNotEmpty ? _careerController.text.trim() : null,
        institution: _institutionController.text.trim().isNotEmpty ? _institutionController.text.trim() : null,
        position: _positionController.text.trim().isNotEmpty ? _positionController.text.trim() : null,
        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
        shift: _selectedShift,
      );

      if (!mounted) return;

      // Diálogo de confirmación para registrar a otro participante (100% responsivo sin desbordamientos)
      final registerAnother = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actionsOverflowButtonSpacing: 8,
          title: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '¡Registro Exitoso!',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Text(
            'Se registró correctamente a "${_nameController.text.trim()}".\n\n¿Deseas registrar a otra persona para este evento?',
            style: const TextStyle(fontSize: 13.5, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('No, finalizar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Registrar a otro'),
            ),
          ],
        ),
      );

      _lastUpdatedEvent = updatedEvent;
      if (registerAnother == true) {
        _clearForm();
      } else {
        if (mounted) {
          Navigator.of(context).pop(_lastUpdatedEvent);
        }
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _isSubmitting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error al registrar: $e';
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = ThemeService.primaryColor(context);

    return Container(
      decoration: BoxDecoration(
        color: ThemeService.cardBg(context),
        borderRadius: widget.isDialog
            ? BorderRadius.circular(24)
            : const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: widget.isDialog ? 24 : 16,
        left: widget.isDialog ? 24 : 20,
        right: widget.isDialog ? 24 : 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + (widget.isDialog ? 24 : 20),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * (widget.isDialog ? 0.88 : 0.90),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Barra superior (solo en BottomSheet móvil)
            if (!widget.isDialog) ...[
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
              const SizedBox(height: 14),
            ],

            // Encabezado
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.person_add_alt_1_rounded, color: primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Registrar Participante',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Registro manual oficial de asistencia al evento',
                        style: TextStyle(
                          fontSize: 12,
                          color: ThemeService.subtextColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.of(context).pop(_lastUpdatedEvent),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),

            // Banner de error si ocurre duplicidad u otro fallo
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Contenido con Scroll responsivo
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 480;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- Selector de Turno (si el evento tiene turnos) ---
                        if (widget.event.shifts.where((s) => s.enabled).length > 1)
                          _buildShiftSelector(),

                        // --- 1. Nombre Completo ---
                        _buildNameField(),
                        const SizedBox(height: 14),

                        // --- 2 y 3. Documento & Celular ---
                        if (isWide) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildDocumentField()),
                              const SizedBox(width: 12),
                              Expanded(child: _buildPhoneField()),
                            ],
                          ),
                        ] else ...[
                          _buildDocumentField(),
                          const SizedBox(height: 14),
                          _buildPhoneField(),
                        ],
                        const SizedBox(height: 14),

                        // --- 4. Correo Electrónico ---
                        _buildEmailField(),
                        const SizedBox(height: 18),

                        // --- Toggle Más Campos ---
                        _buildMoreFieldsToggle(primary, isDark),

                        // --- Campos Adicionales (Expandible) ---
                        AnimatedCrossFade(
                          firstChild: const SizedBox.shrink(),
                          secondChild: Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildGenderField(),
                                const SizedBox(height: 14),

                                if (isWide) ...[
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(width: 120, child: _buildAgeField()),
                                      const SizedBox(width: 12),
                                      Expanded(child: _buildPositionField()),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: _buildCareerField()),
                                      const SizedBox(width: 12),
                                      Expanded(child: _buildInstitutionField()),
                                    ],
                                  ),
                                ] else ...[
                                  _buildAgeField(),
                                  const SizedBox(height: 14),
                                  _buildPositionField(),
                                  const SizedBox(height: 14),
                                  _buildCareerField(),
                                  const SizedBox(height: 14),
                                  _buildInstitutionField(),
                                ],
                                const SizedBox(height: 14),
                                _buildNotesField(),
                              ],
                            ),
                          ),
                          crossFadeState: _showMoreFields ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                          duration: const Duration(milliseconds: 250),
                        ),

                        const SizedBox(height: 24),
                      ],
                    );
                  },
                ),
              ),
            ),

            // Botón de Enviar
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                onPressed: _isSubmitting ? null : _handleSubmit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.how_to_reg_rounded, size: 20),
                label: Text(
                  _isSubmitting ? 'Registrando participante...' : 'Confirmar y Registrar Participante',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Sub-widgets de Campos ---
  Widget _buildShiftSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shifts = widget.event.shifts.where((s) => s.enabled).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('Turno del Evento *', hint: 'Selecciona la jornada de asistencia'),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _selectedShift,
              dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              items: shifts.map((s) {
                final icon = s.name == 'manana'
                    ? Icons.wb_sunny_rounded
                    : s.name == 'tarde'
                        ? Icons.wb_twilight_rounded
                        : Icons.nights_stay_rounded;
                final color = s.name == 'manana'
                    ? const Color(0xFFF59E0B)
                    : s.name == 'tarde'
                        ? const Color(0xFFF97316)
                        : const Color(0xFF6366F1);
                return DropdownMenuItem<String>(
                  value: s.name,
                  child: Row(
                    children: [
                      Icon(icon, size: 16, color: color),
                      const SizedBox(width: 8),
                      Text(
                        '${s.label} (${s.startTime} - ${s.endTime})',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedShift = val);
              },
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _buildNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('Nombre Completo *', hint: 'Nombres y Apellidos'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          decoration: _inputDecoration(
            context,
            hintText: 'Ej. Juan Carlos Pérez Mendoza',
            icon: Icons.person_outline_rounded,
          ),
          validator: (value) {
            final val = value?.trim() ?? '';
            if (val.length < 3) return 'Ingresa el nombre completo';
            final words = val.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
            if (words.length < 2) return 'Ingresa nombres y apellidos (mínimo 2 palabras)';
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildDocumentField() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('Documento *', hint: 'DNI (8 dígitos) / CE'),
        const SizedBox(height: 6),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                border: Border.all(color: ThemeService.cardBorder(context)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _docType,
                  borderRadius: BorderRadius.circular(12),
                  items: const [
                    DropdownMenuItem(value: 'DNI', child: Text('DNI', style: TextStyle(fontWeight: FontWeight.bold))),
                    DropdownMenuItem(value: 'CE', child: Text('C.E.')),
                    DropdownMenuItem(value: 'PASSPORT', child: Text('Pas.')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _docType = val;
                        _dniController.clear();
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: _dniController,
                keyboardType: _docType == 'DNI' ? TextInputType.number : TextInputType.text,
                inputFormatters: [
                  if (_docType == 'DNI') ...[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ] else ...[
                    LengthLimitingTextInputFormatter(12),
                  ],
                ],
                decoration: _inputDecoration(
                  context,
                  hintText: _docType == 'DNI' ? 'Ej. 70123456' : 'N° documento',
                  icon: Icons.badge_outlined,
                ),
                validator: (value) {
                  final val = value?.trim() ?? '';
                  if (val.isEmpty) return 'Ingresa documento';
                  if (_docType == 'DNI' && val.length != 8) {
                    return 'DNI: 8 dígitos';
                  }
                  if (_docType != 'DNI' && val.length < 6) {
                    return 'Mínimo 6 caracteres';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('Teléfono / Celular *', hint: '9 dígitos (Perú)'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(9),
          ],
          decoration: _inputDecoration(
            context,
            hintText: 'Ej. 965123456',
            icon: Icons.phone_android_rounded,
          ),
          validator: (value) {
            final val = value?.trim() ?? '';
            if (val.isEmpty) return 'Ingresa el número de celular';
            if (val.length != 9 || !val.startsWith('9')) {
              return 'Celular de 9 dígitos que inicie con 9';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('Correo Electrónico *', hint: 'Para constancia digital'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: _inputDecoration(
            context,
            hintText: 'Ej. participante@iiap.gob.pe',
            icon: Icons.alternate_email_rounded,
          ),
          validator: (value) {
            final val = value?.trim().toLowerCase() ?? '';
            if (val.isEmpty) return 'Ingresa el correo electrónico';
            final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
            if (!emailRegex.hasMatch(val)) return 'Formato de correo no válido';
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildMoreFieldsToggle(Color primary, bool isDark) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        setState(() => _showMoreFields = !_showMoreFields);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: _showMoreFields
              ? primary.withValues(alpha: 0.12)
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _showMoreFields ? primary.withValues(alpha: 0.4) : ThemeService.cardBorder(context),
          ),
        ),
        child: Row(
          children: [
            Icon(
              _showMoreFields ? Icons.remove_circle_outline_rounded : Icons.add_circle_outline_rounded,
              size: 20,
              color: _showMoreFields ? primary : ThemeService.subtextColor(context),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _showMoreFields
                    ? 'Ocultar campos adicionales'
                    : 'Añadir más campos (Sexo, Edad, Carrera...)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _showMoreFields ? primary : (isDark ? Colors.white : const Color(0xFF0F172A)),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '+ Opcionales',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenderField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('Sexo / Género', hint: 'Opcional'),
        const SizedBox(height: 6),
        Row(
          children: [
            _buildGenderChip('MASCULINO', 'Masculino', Icons.male_rounded),
            const SizedBox(width: 8),
            _buildGenderChip('FEMENINO', 'Femenino', Icons.female_rounded),
            const SizedBox(width: 8),
            _buildGenderChip('OTRO', 'Otro', Icons.transgender_rounded),
          ],
        ),
      ],
    );
  }

  Widget _buildAgeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('Edad', hint: 'Años (máx. 2 dígitos)'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _ageController,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(2),
          ],
          decoration: _inputDecoration(
            context,
            hintText: 'Ej. 25',
            icon: Icons.cake_outlined,
          ),
          validator: (val) {
            if (val != null && val.trim().isNotEmpty) {
              final age = int.tryParse(val.trim());
              if (age == null || age < 1 || age > 99) {
                return 'Ingresa una edad válida (1 a 99 años)';
              }
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildCareerField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('Carrera / Profesión', hint: 'Área académica'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _careerController,
          textCapitalization: TextCapitalization.words,
          decoration: _inputDecoration(
            context,
            hintText: 'Ej. Biología, Ing. Forestal, Agronomía',
            icon: Icons.school_outlined,
          ),
        ),
      ],
    );
  }

  Widget _buildInstitutionField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('Institución / Entidad', hint: 'Procedencia'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _institutionController,
          textCapitalization: TextCapitalization.words,
          decoration: _inputDecoration(
            context,
            hintText: 'Ej. UNAP, IIAP, GORE Loreto, Particular',
            icon: Icons.account_balance_outlined,
          ),
        ),
      ],
    );
  }

  Widget _buildPositionField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('Cargo u Ocupación', hint: 'Rol'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _positionController,
          textCapitalization: TextCapitalization.sentences,
          decoration: _inputDecoration(
            context,
            hintText: 'Ej. Investigador, Docente, Estudiante',
            icon: Icons.work_outline_rounded,
          ),
        ),
      ],
    );
  }

  Widget _buildNotesField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('Observaciones / Notas', hint: 'Comentarios del registro'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _notesController,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: _inputDecoration(
            context,
            hintText: 'Ej. Asistió en delegación / acreditado por Administrador',
            icon: Icons.edit_note_rounded,
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(String label, {String? hint}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        if (hint != null)
          Text(
            hint,
            style: TextStyle(
              fontSize: 11,
              color: ThemeService.subtextColor(context),
            ),
          ),
      ],
    );
  }

  Widget _buildGenderChip(String value, String label, IconData icon) {
    final isSelected = _selectedGender == value;
    final primary = ThemeService.primaryColor(context);

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          setState(() {
            _selectedGender = isSelected ? null : value;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? primary.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? primary : ThemeService.cardBorder(context),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isSelected ? primary : ThemeService.subtextColor(context)),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? primary : ThemeService.subtextColor(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(BuildContext context, {required String hintText, required IconData icon}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = ThemeService.primaryColor(context);

    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        fontSize: 13,
        color: ThemeService.subtextColor(context).withValues(alpha: 0.7),
      ),
      prefixIcon: Icon(icon, size: 18, color: ThemeService.subtextColor(context)),
      filled: true,
      fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: ThemeService.cardBorder(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: ThemeService.cardBorder(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
      ),
    );
  }
}
