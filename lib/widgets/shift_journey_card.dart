import 'package:flutter/material.dart';
import '../models/attendance_model.dart';
import '../services/theme_service.dart';
import '../services/wallpaper_service.dart';

class ShiftJourneyCard extends StatelessWidget {
  final ShiftJourneyRecord journey;
  final bool showUserName;
  final VoidCallback? onEdit;

  const ShiftJourneyCard({
    super.key,
    required this.journey,
    this.showUserName = false,
    this.onEdit,
  });

  String _formatTime(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:$minute $ampm';
  }

  String _formatDateWithDay(String dateStr) {
    try {
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        final y = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        final d = int.parse(parts[2]);
        final dt = DateTime(y, m, d);
        const days = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
        const months = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Set', 'Oct', 'Nov', 'Dic'];
        final dayName = days[dt.weekday - 1];
        final monthName = months[m - 1];
        return '$dayName, $d $monthName';
      }
    } catch (_) {}
    return dateStr;
  }

  String? _calculateDuration(DateTime? start, DateTime? end) {
    if (start == null || end == null) return null;
    final diff = end.difference(start);
    if (diff.isNegative) return null;
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    if (hours == 0) return '${minutes}m';
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }

  Color _cardBg(BuildContext context) {
    final hasWallpaper = WallpaperService.currentWallpaper.hasWallpaper;
    return hasWallpaper
        ? ThemeService.cardBg(context).withValues(alpha: 0.85)
        : ThemeService.cardBg(context);
  }

  Color _innerBoxBg(BuildContext context) {
    final hasWallpaper = WallpaperService.currentWallpaper.hasWallpaper;
    return hasWallpaper
        ? ThemeService.containerColor(context).withValues(alpha: 0.22)
        : ThemeService.containerColor(context).withValues(alpha: 0.35);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isMorning = journey.shift == AttendanceShift.MORNING;
    final shiftColor = isMorning
        ? (isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7))
        : (isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706));
    final shiftBg = isMorning
        ? (isDark ? const Color(0xFF082F49) : const Color(0xFFE0F2FE))
        : (isDark ? const Color(0xFF331D08) : const Color(0xFFFEF3C7));

    final checkIn = journey.checkIn;
    final checkOut = journey.checkOut;

    // Estado de la salida
    final hasExit = checkOut != null;
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final isPastDay = journey.workDate.compareTo(todayStr) < 0;

    // Horas de salida de referencia: Mañana 13:00 (780m), Tarde 18:30 (1110m)
    final nowMinutes = now.hour * 60 + now.minute;
    final scheduledExitMins = isMorning ? 13 * 60 : 18 * 60 + 30;
    final isPastExitTime = journey.workDate == todayStr ? nowMinutes >= scheduledExitMins : true;

    final isMissingCheckout = !hasExit && (isPastDay || isPastExitTime);
    final durationStr = (checkIn != null && checkOut != null)
        ? _calculateDuration(checkIn.timestamp, checkOut.timestamp)
        : null;

    final String? observation = checkIn?.observation ?? checkOut?.observation;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isMissingCheckout
              ? const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.45 : 0.6)
              : ThemeService.cardBorder(context),
          width: isMissingCheckout ? 1.3 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isMissingCheckout
                ? const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.08 : 0.04)
                : Colors.black.withValues(alpha: isDark ? 0.28 : 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ==========================================
                // CABECERA 100% RESPONSIVA: TURNO + FECHA + BADGE ESTADO
                // ==========================================
                Row(
                  children: [
                    // Pill de Turno compacto (Mañana o Tarde)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: shiftBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: shiftColor.withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isMorning ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded,
                            size: 11.5,
                            color: shiftColor,
                          ),
                          const SizedBox(width: 3.5),
                          Text(
                            isMorning ? 'Mañana' : 'Tarde',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: shiftColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Fecha con icono calendario con ajuste elástico
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 11.5,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 3.5),
                          Expanded(
                            child: Text(
                              _formatDateWithDay(journey.workDate),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Badge de Estado Global de la Jornada (adaptable con Flexible y FittedBox)
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: hasExit
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF052E16) : const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isDark ? const Color(0xFF166534) : const Color(0xFF86EFAC),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.check_circle_rounded,
                                      size: 11,
                                      color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A),
                                    ),
                                    const SizedBox(width: 3.5),
                                    Text(
                                      'Completado',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : (isMissingCheckout
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF451A03) : const Color(0xFFFEF3C7),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isDark ? const Color(0xFF92400E) : const Color(0xFFFDE68A),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.warning_amber_rounded,
                                          size: 11.5,
                                          color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
                                        ),
                                        const SizedBox(width: 3.5),
                                        Text(
                                          'Sin salida',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF082F49) : const Color(0xFFE0F2FE),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isDark ? const Color(0xFF0369A1) : const Color(0xFFBAE6FD),
                                        width: 1,
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.timelapse_rounded, size: 11, color: Color(0xFF38BDF8)),
                                        SizedBox(width: 3.5),
                                        Text(
                                          'En curso',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF38BDF8),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )),
                      ),
                    ),


                  ],
                ),

                // ==========================================
                // VISTA SUPERVISOR: NOMBRE Y DNI DEL USUARIO
                // ==========================================
                if (showUserName && journey.userName != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5.5),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0B141E) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 11,
                          backgroundColor: ThemeService.primaryColor(context).withValues(alpha: 0.15),
                          child: Text(
                            journey.userName!.isNotEmpty ? journey.userName![0].toUpperCase() : 'U',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: ThemeService.primaryColor(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            journey.userName!,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (journey.userDocument != null && journey.userDocument!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'DNI ${journey.userDocument}',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 11),

                // ==========================================
                // FILA DE ENTRADA Y SALIDA 100% RESPONSIVA Y SIN DESBORDAMIENTO
                // ==========================================
                Row(
                  children: [
                    // --------------------------------------
                    // TARJETA DE ENTRADA
                    // --------------------------------------
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8.5, vertical: 8),
                        decoration: BoxDecoration(
                          color: _innerBoxBg(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.login_rounded,
                                      size: 11.5,
                                      color: const Color(0xFF10B981),
                                    ),
                                    const SizedBox(width: 3),
                                    const Text(
                                      'ENTRADA',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF10B981),
                                        letterSpacing: 0.25,
                                      ),
                                    ),
                                  ],
                                ),
                                if (checkIn != null)
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: checkIn.status == AttendanceStatus.ON_TIME
                                            ? (isDark ? const Color(0xFF06331E) : const Color(0xFFDCFCE7))
                                            : (isDark ? const Color(0xFF381F08) : const Color(0xFFFEF3C7)),
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(
                                          color: checkIn.status == AttendanceStatus.ON_TIME
                                              ? (isDark ? const Color(0xFF135A40) : const Color(0xFF86EFAC))
                                              : (isDark ? const Color(0xFF78350F) : const Color(0xFFFDE68A)),
                                        ),
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          checkIn.status == AttendanceStatus.ON_TIME ? 'A tiempo' : 'Tardanza',
                                          style: TextStyle(
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.w800,
                                            color: checkIn.status == AttendanceStatus.ON_TIME
                                                ? (isDark ? const Color(0xFF34D399) : const Color(0xFF16A34A))
                                                : (isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706)),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _formatTime(checkIn?.timestamp),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(
                                  checkIn != null
                                      ? (checkIn.isManual ? Icons.edit_note_rounded : Icons.qr_code_2_rounded)
                                      : Icons.radio_button_unchecked_rounded,
                                  size: 10.5,
                                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                                ),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    checkIn != null
                                        ? (checkIn.isManual ? 'Manual' : 'QR')
                                        : 'Sin registro',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),

                    // --------------------------------------
                    // TARJETA DE SALIDA
                    // --------------------------------------
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8.5, vertical: 8),
                        decoration: BoxDecoration(
                          color: _innerBoxBg(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.logout_rounded,
                                      size: 11.5,
                                      color: hasExit
                                          ? const Color(0xFFF59E0B)
                                          : (isMissingCheckout ? const Color(0xFFEF4444) : Colors.grey),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      'SALIDA',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: hasExit
                                            ? const Color(0xFFF59E0B)
                                            : (isMissingCheckout ? const Color(0xFFEF4444) : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
                                        letterSpacing: 0.25,
                                      ),
                                    ),
                                  ],
                                ),
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: hasExit
                                          ? (isDark ? const Color(0xFF06331E) : const Color(0xFFDCFCE7))
                                          : (isMissingCheckout
                                              ? (isDark ? const Color(0xFF381414) : const Color(0xFFFEE2E2))
                                              : (isDark ? const Color(0xFF132338) : const Color(0xFFE0F2FE))),
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(
                                        color: hasExit
                                            ? (isDark ? const Color(0xFF135A40) : const Color(0xFF86EFAC))
                                            : (isMissingCheckout
                                                ? (isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFCA5A5))
                                                : (isDark ? const Color(0xFF1E3A8A) : const Color(0xFFBAE6FD))),
                                      ),
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        hasExit ? 'Registrada' : (isMissingCheckout ? 'Pendiente' : 'En curso'),
                                        style: TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w800,
                                          color: hasExit
                                              ? (isDark ? const Color(0xFF34D399) : const Color(0xFF16A34A))
                                              : (isMissingCheckout
                                                  ? (isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626))
                                                  : (isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB))),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 7),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                hasExit ? _formatTime(checkOut.timestamp) : '—',
                                style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w900,
                                  color: hasExit
                                      ? (isDark ? Colors.white : const Color(0xFF0F172A))
                                      : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3.5),
                            Row(
                              children: [
                                Icon(
                                  hasExit
                                      ? (checkOut.isManual ? Icons.edit_note_rounded : Icons.qr_code_2_rounded)
                                      : (isMissingCheckout ? Icons.warning_amber_rounded : Icons.hourglass_top_rounded),
                                  size: 11,
                                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                                ),
                                const SizedBox(width: 3.5),
                                Expanded(
                                  child: Text(
                                    hasExit
                                        ? (checkOut.isManual ? 'Manual' : 'QR')
                                        : (isMissingCheckout ? 'Sin marcar' : 'Por marcar'),
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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

                // ==========================================
                // BANNER INFORMATIVO INFERIOR: DURACIÓN O ALERTA
                // ==========================================
                if (durationStr != null) ...[
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5.5),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF062316) : const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: isDark ? const Color(0xFF135A3E) : const Color(0xFFA7F3D0),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.timer_outlined, size: 12.5, color: Color(0xFF10B981)),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'Tiempo trabajado: $durationStr',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF10B981),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.verified_rounded, size: 12.5, color: Color(0xFF10B981)),
                      ],
                    ),
                  ),
                ] else if (isMissingCheckout) ...[
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5.5),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2E1708) : const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: isDark ? const Color(0xFF78350F) : const Color(0xFFFDE68A),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 12.5,
                          color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'Salida no registrada al cierre del turno programado.',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // ==========================================
                // OBSERVACIÓN O JUSTIFICACIÓN SI EXISTE
                // ==========================================
                if (observation != null && observation.trim().isNotEmpty) ...[
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.5) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.notes_rounded,
                          size: 11.5,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            observation,
                            style: TextStyle(
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
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
}