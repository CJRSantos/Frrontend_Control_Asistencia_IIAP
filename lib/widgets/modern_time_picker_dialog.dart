import 'package:flutter/material.dart';
import '../services/theme_service.dart';

/// Diálogo moderno, estético y táctil para selección de hora sin la tosquedad del reloj analógico predeterminado.
class ModernTimePickerDialog extends StatefulWidget {
  final TimeOfDay initialTime;
  final String title;
  final String? subtitle;
  final Color? primaryColor;

  const ModernTimePickerDialog({
    super.key,
    required this.initialTime,
    this.title = 'Seleccionar Hora',
    this.subtitle,
    this.primaryColor,
  });

  static Future<TimeOfDay?> show({
    required BuildContext context,
    required TimeOfDay initialTime,
    String title = 'Seleccionar Hora',
    String? subtitle,
    Color? primaryColor,
  }) {
    return showDialog<TimeOfDay>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ModernTimePickerDialog(
        initialTime: initialTime,
        title: title,
        subtitle: subtitle,
        primaryColor: primaryColor,
      ),
    );
  }

  @override
  State<ModernTimePickerDialog> createState() => _ModernTimePickerDialogState();
}

class _ModernTimePickerDialogState extends State<ModernTimePickerDialog> {
  late int _hour; // 1 to 12
  late int _minute; // 0 to 59
  late DayPeriod _period; // AM or PM
  bool _editingMinutes = false;

  @override
  void initState() {
    super.initState();
    _hour = widget.initialTime.hourOfPeriod == 0 ? 12 : widget.initialTime.hourOfPeriod;
    _minute = widget.initialTime.minute;
    _period = widget.initialTime.period;
  }

  TimeOfDay get _selectedTime {
    int h24 = _hour % 12;
    if (_period == DayPeriod.pm) {
      h24 += 12;
    }
    return TimeOfDay(hour: h24, minute: _minute);
  }

  void _applyPreset(int hour24, int minute) {
    setState(() {
      _period = hour24 >= 12 ? DayPeriod.pm : DayPeriod.am;
      final h12 = hour24 % 12;
      _hour = h12 == 0 ? 12 : h12;
      _minute = minute;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = widget.primaryColor ?? ThemeService.primaryColor(context);

    final bgCard = isDark ? const Color(0xFF0F172A) : Colors.white;
    final surfaceColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: bgCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderColor, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.15),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: isDark ? 0.12 : 0.08),
                  border: Border(bottom: BorderSide(color: borderColor, width: 0.8)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.access_time_filled_rounded, color: primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                          if (widget.subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.subtitle!,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),

              // Cuerpo
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Visualizador Digital Principal (Hora : Minutos | AM/PM)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: surfaceColor,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Botón Horas
                          InkWell(
                            onTap: () => setState(() => _editingMinutes = false),
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: !_editingMinutes
                                    ? primary.withValues(alpha: 0.22)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: !_editingMinutes ? primary : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                _hour.toString().padLeft(2, '0'),
                                style: TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w800,
                                  color: !_editingMinutes ? primary : (isDark ? Colors.white : Colors.black87),
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ),

                          // Dos puntos parpadeantes / fijos
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              ':',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                              ),
                            ),
                          ),

                          // Botón Minutos
                          InkWell(
                            onTap: () => setState(() => _editingMinutes = true),
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: _editingMinutes
                                    ? primary.withValues(alpha: 0.22)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _editingMinutes ? primary : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                _minute.toString().padLeft(2, '0'),
                                style: TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w800,
                                  color: _editingMinutes ? primary : (isDark ? Colors.white : Colors.black87),
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 16),

                          // Selector AM / PM Segmentado
                          Container(
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F172A) : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: borderColor),
                            ),
                            child: Column(
                              children: [
                                _buildPeriodButton('AM', DayPeriod.am, primary, isDark),
                                Container(height: 1, width: 44, color: borderColor),
                                _buildPeriodButton('PM', DayPeriod.pm, primary, isDark),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Selector de Modo (Horas vs Minutos)
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _editingMinutes = false),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: !_editingMinutes ? primary : surfaceColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'HORAS (1 - 12)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                  color: !_editingMinutes ? Colors.white : (isDark ? Colors.grey[400] : Colors.grey[600]),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _editingMinutes = true),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _editingMinutes ? primary : surfaceColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'MINUTOS (00 - 55)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                  color: _editingMinutes ? Colors.white : (isDark ? Colors.grey[400] : Colors.grey[600]),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Grilla / Fichas Táctiles de Horas o Minutos
                    if (!_editingMinutes) ...[
                      // Selector de Horas (1 a 12)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: List.generate(12, (index) {
                          final h = index + 1;
                          final isSel = _hour == h;
                          return InkWell(
                            onTap: () => setState(() {
                              _hour = h;
                              _editingMinutes = true; // Auto avanza a minutos para agilidad
                            }),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: 48,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isSel ? primary : surfaceColor,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSel ? primary : borderColor,
                                  width: 1.2,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                h.toString().padLeft(2, '0'),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isSel ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ] else ...[
                      // Selector de Minutos (Múltiplos de 5)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55].map((m) {
                          final isSel = _minute == m;
                          return InkWell(
                            onTap: () => setState(() => _minute = m),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: 48,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isSel ? primary : surfaceColor,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSel ? primary : borderColor,
                                  width: 1.2,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                m.toString().padLeft(2, '0'),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isSel ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 10),

                      // Ajuste Fino (+ / - 1 minuto)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton.filledTonal(
                            icon: const Icon(Icons.remove, size: 18),
                            onPressed: () {
                              setState(() {
                                _minute = (_minute - 1 + 60) % 60;
                              });
                            },
                            style: IconButton.styleFrom(
                              backgroundColor: surfaceColor,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'Ajuste fino: ${_minute.toString().padLeft(2, '0')} m',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.grey[400] : Colors.grey[700],
                              ),
                            ),
                          ),
                          IconButton.filledTonal(
                            icon: const Icon(Icons.add, size: 18),
                            onPressed: () {
                              setState(() {
                                _minute = (_minute + 1) % 60;
                              });
                            },
                            style: IconButton.styleFrom(
                              backgroundColor: surfaceColor,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 14),

                    // Atajos Frecuentes de Asistencia Institucional
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'HORARIOS FRECUENTES:',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildPresetChip('07:45 AM', 7, 45, surfaceColor, borderColor, isDark),
                          const SizedBox(width: 6),
                          _buildPresetChip('08:00 AM', 8, 0, surfaceColor, borderColor, isDark),
                          const SizedBox(width: 6),
                          _buildPresetChip('01:00 PM', 13, 0, surfaceColor, borderColor, isDark),
                          const SizedBox(width: 6),
                          _buildPresetChip('02:00 PM', 14, 0, surfaceColor, borderColor, isDark),
                          const SizedBox(width: 6),
                          _buildPresetChip('06:00 PM', 18, 0, surfaceColor, borderColor, isDark),
                          const SizedBox(width: 6),
                          _buildPresetChip('06:30 PM', 18, 30, surfaceColor, borderColor, isDark),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Botones de Acción
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  border: Border(top: BorderSide(color: borderColor, width: 0.8)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: borderColor),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          'Cancelar',
                          style: TextStyle(
                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).pop(_selectedTime),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text(
                          'Aceptar',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
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

  Widget _buildPeriodButton(String label, DayPeriod period, Color primary, bool isDark) {
    final isSelected = _period == period;
    return InkWell(
      onTap: () => setState(() => _period = period),
      borderRadius: BorderRadius.circular(11),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 44,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: isSelected ? Colors.white : (isDark ? Colors.grey[400] : Colors.grey[700]),
          ),
        ),
      ),
    );
  }

  Widget _buildPresetChip(String label, int h24, int m, Color bg, Color border, bool isDark) {
    return InkWell(
      onTap: () => _applyPreset(h24, m),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }
}
