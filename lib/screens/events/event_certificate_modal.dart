import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/api_config.dart';
import '../../models/event_model.dart';
import '../../services/theme_service.dart';

class EventCertificateModal extends StatelessWidget {
  final EventModel event;
  final EventAttendeeModel attendee;
  final bool isDialog;

  const EventCertificateModal({
    super.key,
    required this.event,
    required this.attendee,
    this.isDialog = false,
  });

  static Future<void> show(
    BuildContext context, {
    required EventModel event,
    required EventAttendeeModel attendee,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final isTablet = width >= 640;

    if (isTablet) {
      return showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 780),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Material(
                color: ThemeService.cardBg(context),
                child: EventCertificateModal(event: event, attendee: attendee, isDialog: true),
              ),
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EventCertificateModal(event: event, attendee: attendee, isDialog: false),
    );
  }

  String _formatDateTime(DateTime date) {
    const months = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Set', 'Oct', 'Nov', 'Dic'];
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final ampm = date.hour >= 12 ? 'p. m.' : 'a. m.';
    return '${date.day} ${months[date.month - 1]} ${date.year} • ${hour.toString().padLeft(2, '0')}:$minute $ampm';
  }

  String _formatTime(DateTime date) {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final ampm = date.hour >= 12 ? 'p. m.' : 'a. m.';
    return '${hour.toString().padLeft(2, '0')}:$minute $ampm';
  }

  String _getVerificationHash() {
    final identifier = attendee.userId.isNotEmpty
        ? attendee.userId
        : (attendee.documentNumber != null && attendee.documentNumber!.isNotEmpty
            ? attendee.documentNumber!
            : attendee.userName);
    final raw = '${event.id}_${identifier}_${attendee.registeredAt.millisecondsSinceEpoch}';
    final bytes = utf8.encode(raw);
    int hash = 0xcbf29ce484222325;
    for (var b in bytes) {
      hash = (hash ^ b) & 0xFFFFFFFFFFFFFFFF;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    final hex = hash.toUnsigned(64).toRadixString(16).toUpperCase().padLeft(16, '0');
    return 'IIAP-CERT-${hex.substring(0, 4)}-${hex.substring(4, 8)}-${hex.substring(8, 12)}';
  }

  String _buildQrUrl(String certCode) {
    const defaultHost = 'https://dev-api-control.iiap.gob.pe';
    String baseUrl = ApiConfig.defaultPublicRegistrationUrl;
    if (baseUrl.isEmpty || baseUrl.contains('dev-registro-eventos.iiap.gob.pe')) {
      baseUrl = defaultHost;
    }
    baseUrl = baseUrl.replaceAll(RegExp(r'/$'), '');
    final nameEncoded = Uri.encodeComponent(attendee.userName);
    final eventEncoded = Uri.encodeComponent(event.title);
    final doc = attendee.documentNumber ?? '';
    final timeEncoded = Uri.encodeComponent(_formatDateTime(attendee.registeredAt));

    return '$baseUrl/registro.html?cert=$certCode&id=${event.id}&name=$nameEncoded&dni=$doc&event=$eventEncoded&time=$timeEncoded';
  }

  Future<void> _handlePrintPdf(BuildContext context) async {
    final certCode = _getVerificationHash();
    final doc = pw.Document();

    const primaryColor = PdfColor.fromInt(0xFF004D40); // Verde IIAP
    const accentGreen = PdfColor.fromInt(0xFF16A34A);
    const darkText = PdfColor.fromInt(0xFF0F172A);
    const mutedText = PdfColor.fromInt(0xFF475569);
    const lightBg = PdfColor.fromInt(0xFFF8FAFC);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context ctx) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(28),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              border: pw.Border.all(color: primaryColor, width: 2.5),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(16)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // Encabezado Oficial
                pw.Text(
                  'REPÚBLICA DEL PERÚ',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: mutedText, letterSpacing: 1.5),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'INSTITUTO DE INVESTIGACIONES DE LA AMAZONÍA PERUANA',
                  style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: primaryColor),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'SISTEMA INTEGRADO DE CONTROL DE ASISTENCIA Y EVENTOS',
                  style: pw.TextStyle(fontSize: 8.5, color: mutedText),
                ),
                pw.SizedBox(height: 12),
                pw.Divider(color: primaryColor, thickness: 1),
                pw.SizedBox(height: 14),

                // Título Constancia
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: const pw.BoxDecoration(
                    color: accentGreen,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
                  ),
                  child: pw.Text(
                    'CONSTANCIA OFICIAL DE ASISTENCIA',
                    style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.white, letterSpacing: 1),
                  ),
                ),
                pw.SizedBox(height: 16),

                pw.Text(
                  'El Instituto de Investigaciones de la Amazonía Peruana deja constancia que:',
                  style: const pw.TextStyle(fontSize: 11, color: mutedText),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 12),

                // Nombre del Participante
                pw.Text(
                  attendee.userName.toUpperCase(),
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: primaryColor),
                  textAlign: pw.TextAlign.center,
                ),
                if (attendee.documentNumber != null && attendee.documentNumber!.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'DOCUMENTO DE IDENTIDAD: ${attendee.documentNumber}',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: darkText),
                  ),
                ],
                pw.SizedBox(height: 14),

                pw.Text(
                  'Ha participado y registrado satisfactoriamente su asistencia en el evento institucional:',
                  style: const pw.TextStyle(fontSize: 11, color: mutedText),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 10),

                // Título del Evento
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: const pw.BoxDecoration(
                    color: lightBg,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        event.title,
                        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: darkText),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Tipo: ${event.type.displayName.toUpperCase()}  |  Ubicación: ${event.location}',
                        style: const pw.TextStyle(fontSize: 9.5, color: mutedText),
                        textAlign: pw.TextAlign.center,
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),

                // Datos de Registro
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Fecha del Evento:', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: darkText)),
                        pw.Text('${event.startDate.day}/${event.startDate.month}/${event.startDate.year}', style: const pw.TextStyle(fontSize: 9.5, color: mutedText)),
                        pw.SizedBox(height: 6),
                        pw.Text('Horario:', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: darkText)),
                        pw.Text('${event.startDate.hour}:${event.startDate.minute.toString().padLeft(2, '0')} - ${event.endDate.hour}:${event.endDate.minute.toString().padLeft(2, '0')}', style: const pw.TextStyle(fontSize: 9.5, color: mutedText)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Fecha de Registro:', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: darkText)),
                        pw.Text('${attendee.registeredAt.day}/${attendee.registeredAt.month}/${attendee.registeredAt.year}', style: const pw.TextStyle(fontSize: 9.5, color: mutedText)),
                        pw.SizedBox(height: 6),
                        pw.Text('Hora de Acreditación:', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: darkText)),
                        pw.Text('${attendee.registeredAt.hour.toString().padLeft(2, '0')}:${attendee.registeredAt.minute.toString().padLeft(2, '0')}:${attendee.registeredAt.second.toString().padLeft(2, '0')}', style: const pw.TextStyle(fontSize: 9.5, color: mutedText)),
                      ],
                    ),
                  ],
                ),
                pw.Spacer(),

                // Pie de Página con Código de Verificación
                pw.Divider(color: PdfColors.grey300, thickness: 0.8),
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'CÓDIGO DE VERIFICACIÓN CRIPTOGRÁFICA:',
                          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: darkText),
                        ),
                        pw.Text(certCode, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Documento oficial generado electrónicamente por el IIAP. Válido sin firma manuscrita.',
                          style: const pw.TextStyle(fontSize: 7, color: mutedText),
                        ),
                      ],
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: accentGreen, width: 1),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      child: pw.Text(
                        'SELLO VERIFICADO',
                        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: accentGreen),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Constancia_${attendee.userName.replaceAll(' ', '_')}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = ThemeService.primaryColor(context);
    final certCode = _getVerificationHash();

    return Container(
      decoration: BoxDecoration(
        color: ThemeService.cardBg(context),
        borderRadius: isDialog
            ? BorderRadius.circular(24)
            : const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: isDialog ? 24 : 16,
        left: isDialog ? 24 : 18,
        right: isDialog ? 24 : 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + (isDialog ? 24 : 20),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * (isDialog ? 0.88 : 0.90),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tirador superior para móviles
          if (!isDialog) ...[
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
                  color: const Color(0xFF16A34A).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.verified_rounded, color: Color(0xFF16A34A), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Constancia de Asistencia',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Certificado digital emitido oficialmente por el IIAP',
                      style: TextStyle(fontSize: 12, color: ThemeService.subtextColor(context)),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Cerrar',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),

          // Tarjeta de la Constancia (Scrollable)
          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF16A34A).withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Badge Institucional
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'INSTITUTO DE INVESTIGACIONES DE LA AMAZONÍA PERUANA',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: primary,
                          letterSpacing: 0.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Icono de Verificado
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Color(0xFF16A34A),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(height: 10),

                    const Text(
                      'ASISTENCIA OFICIAL CONFIRMADA',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF16A34A),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Nombre del participante
                    Text(
                      attendee.userName,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                      textAlign: TextAlign.center,
                    ),

                    if (attendee.documentNumber != null && attendee.documentNumber!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Documento: ${attendee.documentNumber}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: ThemeService.subtextColor(context),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),

                    // Detalles del Evento
                    _buildRow(context, 'Evento:', event.title, isBold: true),
                    const SizedBox(height: 8),
                    _buildRow(context, 'Tipo de Evento:', event.type.displayName),
                    const SizedBox(height: 8),
                    _buildRow(context, 'Fecha:', _formatDateTime(event.startDate)),
                    const SizedBox(height: 8),
                    _buildRow(context, 'Horario:', '${_formatTime(event.startDate)} - ${_formatTime(event.endDate)}'),
                    const SizedBox(height: 8),
                    _buildRow(context, 'Ubicación:', event.location),
                    const SizedBox(height: 8),
                    _buildRow(context, 'Registro en Sistema:', _formatDateTime(attendee.registeredAt)),

                    const SizedBox(height: 18),
                    const Divider(height: 1),
                    const SizedBox(height: 16),

                    // Código QR de Validación + Hash
                    Row(
                      children: [
                        Tooltip(
                          message: 'Toca para abrir la constancia oficial en el navegador',
                          child: InkWell(
                            onTap: () async {
                              final uri = Uri.parse(_buildQrUrl(certCode));
                              try {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              } catch (_) {}
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300, width: 1.5),
                              ),
                              child: QrImageView(
                                data: _buildQrUrl(certCode),
                                version: QrVersions.auto,
                                size: 84,
                                gapless: true,
                                errorCorrectionLevel: QrErrorCorrectLevel.M,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Código de Validación:',
                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 3),
                              SelectableText(
                                certCode,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  color: primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Autenticado digitalmente por el IIAP. Válido para trámite institucional.',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: ThemeService.subtextColor(context),
                                ),
                              ),
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: () async {
                                  final uri = Uri.parse(_buildQrUrl(certCode));
                                  try {
                                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                                  } catch (_) {}
                                },
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: primary.withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.open_in_browser_rounded, size: 14, color: primary),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Verificar en línea',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Botón de Descarga / Impresión PDF
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
              onPressed: () => _handlePrintPdf(context),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
              label: const Text(
                'Guardar / Imprimir Constancia (PDF)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, String label, String value, {bool isBold = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ThemeService.subtextColor(context),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
        ),
      ],
    );
  }
}
