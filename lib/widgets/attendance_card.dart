import 'package:flutter/material.dart';
import '../models/attendance_model.dart';
import '../models/schedule_model.dart';
import '../services/schedule_service.dart';
import '../services/theme_service.dart';

class AttendanceCard extends StatelessWidget {
  final AttendanceModel record;
  final bool showUserName;

  const AttendanceCard({
    super.key,
    required this.record,
    this.showUserName = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isCheckIn = record.type == AttendanceType.CHECK_IN;
    final typeColor = isCheckIn
        ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A))
        : (isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706));
    final typeBg = isCheckIn
        ? (isDark ? const Color(0xFF14532D).withValues(alpha: 0.35) : const Color(0xFFDCFCE7))
        : (isDark ? const Color(0xFF78350F).withValues(alpha: 0.35) : const Color(0xFFFEF3C7));

    // Formateo de fecha y hora
    final timeStr = _formatTime(record.timestamp);
    final dateStr = _formatDate(record.timestamp);

    // Horario y evaluaciÃ³n dinÃ¡mica asignada al usuario
    final schedule = ScheduleService.getSchedule(record.userId);
    final evaluation = schedule.evaluateAttendance(record.timestamp, isCheckIn);
    final isPunctual = isCheckIn ? (record.status == AttendanceStatus.ON_TIME) : true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: ThemeService.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ThemeService.cardBorder(context),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showDetailModal(context, schedule, evaluation, isDark),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icono representativo
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: typeBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isCheckIn ? Icons.login_rounded : Icons.logout_rounded,
                    color: typeColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),

                // Detalles de la marca
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Fila Superior: Nombre del Usuario (si aplica) o Tipo + Hora, junto con el Badge de puntualidad
                      if (showUserName && record.userName != null) ...[
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                record.userName!,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            _buildPunctualityBadge(isCheckIn, isPunctual, isDark),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: typeBg,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                record.type.label,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: typeColor,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                timeStr,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: typeBg,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                record.type.label,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: typeColor,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                timeStr,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            _buildPunctualityBadge(isCheckIn, isPunctual, isDark),
                          ],
                        ),
                      ],

                      const SizedBox(height: 6),

                      // Badge con el Horario Asignado al Personal
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: ThemeService.cardBorder(context),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.alarm_rounded,
                              size: 11.5,
                              color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'Horario: ${record.shift.label}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 6),

                      // Fecha y Supervisor emisor
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 11.5,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            ),
                          ),
                          if (record.markedByName != null) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.verified_user_outlined,
                              size: 11.5,
                              color: isDark ? const Color(0xFF81C784) : const Color(0xFF2D5E2A),
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                record.markedByName!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? const Color(0xFF81C784) : const Color(0xFF2D5E2A),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPunctualityBadge(bool isCheckIn, bool isPunctual, bool isDark) {
    if (!isCheckIn) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E3A8A).withValues(alpha: 0.25) : const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 11, color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB)),
            const SizedBox(width: 3),
            Text(
              'Salida',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
              ),
            ),
          ],
        ),
      );
    }

    if (isPunctual) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF14532D).withValues(alpha: 0.3) : const Color(0xFFDCFCE7),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 11, color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A)),
            const SizedBox(width: 3),
            Text(
              'A tiempo',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF7F1D1D).withValues(alpha: 0.3) : const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 11, color: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626)),
            const SizedBox(width: 3),
            Text(
              'Tarde',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C),
              ),
            ),
          ],
        ),
      );
    }
  }

  void _showDetailModal(BuildContext context, ScheduleModel schedule, ScheduleEvaluation evaluation, bool isDark) {
    final isPunctual = record.type == AttendanceType.CHECK_IN ? (record.status == AttendanceStatus.ON_TIME) : true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: ThemeService.cardBg(context),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(
                        record.type == AttendanceType.CHECK_IN
                            ? (isPunctual ? Icons.check_circle_rounded : Icons.cancel_rounded)
                            : Icons.verified_rounded,
                        color: record.type == AttendanceType.CHECK_IN
                            ? (isPunctual ? const Color(0xFF16A34A) : const Color(0xFFDC2626))
                            : const Color(0xFF2563EB),
                        size: 26,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Detalle de Asistencia',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildDetailRow('Colaborador:', record.userName ?? 'Usuario Registrado', isDark),
                  _buildDetailRow('Tipo de Marca:', record.type.label, isDark),
                  _buildDetailRow('Hora Registrada:', _formatTime(record.timestamp), isDark),
                  _buildDetailRow('Fecha:', _formatDate(record.timestamp), isDark),
                  _buildDetailRow('Horario:', schedule.timeRangeFormatted12h, isDark),
                  _buildDetailRow('Tolerancia de Entrada:', 'Hasta las ${schedule.toleranceLimitFormatted}', isDark),
                  if (record.isManual)
                    _buildDetailRow('Modalidad:', 'Marcación Manual de Emergencia', isDark, highlightColor: Colors.amber),
                  if (record.observation != null && record.observation!.isNotEmpty)
                    _buildDetailRow('Justificación / Motivo:', record.observation!, isDark),
                  _buildDetailRow(
                    'Puntualidad:',
                    record.type == AttendanceType.CHECK_IN
                        ? (isPunctual ? 'A tiempo' : 'Tarde')
                        : 'Salida Registrada',
                    isDark,
                    highlightColor: record.type == AttendanceType.CHECK_IN
                        ? (isPunctual ? const Color(0xFF16A34A) : const Color(0xFFDC2626))
                        : null,
                  ),
                  if (record.markedByName != null)
                    _buildDetailRow('Supervisor Autorizador:', record.markedByName!, isDark),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2D5E2A),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Entendido'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, bool isDark, {Color? highlightColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12.5, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: highlightColor ?? (isDark ? Colors.white : const Color(0xFF0F172A)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute:$second $ampm';
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year;
    return '$day/$month/$year';
  }
}

