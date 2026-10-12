import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../utils/responsive.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/user_model.dart';
import '../../services/storage_service.dart';
import '../../services/auth_service.dart';
import '../../services/users_service.dart';
import '../../services/theme_service.dart';
import '../../services/wallpaper_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/api_client.dart';
import '../../widgets/photo_viewer_dialog.dart';
import '../../widgets/app_cached_avatar.dart';
import '../wallpaper_screen.dart';
import '../login_screen.dart';
import '../notifications_settings_screen.dart';
import '../../widgets/leaf_logo.dart';
import '../../widgets/profile_photo_cropper_dialog.dart';
import '../../widgets/app_toast.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _refreshProfile();
  }

  Future<void> _refreshProfile() async {
    try {
      await AuthService.getProfile();
      if (mounted) {
        setState(() {});
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    super.dispose();
  }

  String _detectDocumentType(String? doc) {
    if (doc == null || doc.trim().isEmpty) return 'DNI';
    final clean = doc.replaceAll(RegExp(r'''['"\s]'''), '').trim();
    if (RegExp(r'^\d{8}$').hasMatch(clean)) return 'DNI';
    if (RegExp(r'^[a-zA-Z0-9]{9}$').hasMatch(clean)) return 'CE';
    return 'Pasaporte';
  }

  String _getDocumentLabel(String? doc) {
    if (doc == null || doc.trim().isEmpty) return 'Documento';
    final type = _detectDocumentType(doc);
    if (type == 'CE') return 'CE';
    if (type == 'Pasaporte') return 'Pasaporte';
    return 'DNI';
  }

  Future<bool> _updateProfileField({
    required UserModel user,
    String? position,
    String? department,
    String? documentNumber,
    String? phoneNumber,
    required String fieldName,
  }) async {
    try {
      final updatedUser = user.copyWith(
        position: position ?? user.position,
        department: department ?? user.department,
        documentNumber: documentNumber ?? user.documentNumber,
        phoneNumber: phoneNumber ?? user.phoneNumber,
      );

      // 1. Guardar y refrescar de inmediato en el almacenamiento y sesión local
      await StorageService.updateCurrentUser(updatedUser);

      // 2. Sincronizar en backend y base de datos
      try {
        final profileData = <String, dynamic>{
          if (position != null) 'position': position,
          if (department != null) 'department': department,
          if (documentNumber != null) 'document_number': documentNumber,
          if (phoneNumber != null) 'phone_number': phoneNumber,
        };
        final updatedFromApi = await UsersService.updateProfile(profileData);
        await StorageService.updateCurrentUser(updatedFromApi);
      } catch (err) {
        debugPrint('Error sincronizando perfil con backend: $err');
        final errStr = err.toString();
        if (errStr.contains('ya está registrado') || errStr.contains('documento')) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('El número de documento ya está registrado por otro usuario.'),
                backgroundColor: const Color(0xFFEF4444),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
          return false;
        }
      }

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text('$fieldName actualizado exitosamente'),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar $fieldName: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _showEditOfficeDialog(UserModel user) async {
    final controller = TextEditingController(text: user.office);
    bool isSaving = false;
    final primary = ThemeService.primaryColor(context);

    final suggestions = [
      'Ingeniero de Sistemas',
      'Administrador de Sistemas',
      'Director / Jefatura',
      'Especialista / Investigador',
      'Asistente Administrativo',
    ];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
          final surfaceBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
          final borderCol = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
          final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

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
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.12 : 0.08),
                        border: Border(bottom: BorderSide(color: borderCol, width: 0.8)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.25 : 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                            ),
                            child: const Icon(Icons.business_rounded, color: Color(0xFF10B981), size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Oficina / Cargo',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Actualiza tu cargo o puesto institucional',
                                  style: TextStyle(fontSize: 11.5, color: textMuted),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close_rounded, size: 20, color: textMuted),
                            splashRadius: 18,
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Cargo o Puesto *',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: controller,
                              autofocus: true,
                              decoration: InputDecoration(
                                hintText: 'Ej. Ingeniero de Sistemas / Administrador',
                                hintStyle: TextStyle(fontSize: 12.5, color: isDark ? Colors.grey[500] : Colors.grey[400]),
                                prefixIcon: const Icon(Icons.business_rounded, size: 20),
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
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Sugerencias rápidas:',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textMuted),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: suggestions.map((sug) {
                                return InkWell(
                                  onTap: () {
                                    setDialogState(() => controller.text = sug);
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: controller.text.trim() == sug
                                          ? const Color(0xFF10B981).withValues(alpha: 0.18)
                                          : surfaceBg,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: controller.text.trim() == sug ? const Color(0xFF10B981) : borderCol,
                                      ),
                                    ),
                                    child: Text(
                                      sug,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: controller.text.trim() == sug ? FontWeight.bold : FontWeight.normal,
                                        color: controller.text.trim() == sug ? const Color(0xFF10B981) : textMuted,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                      decoration: BoxDecoration(
                        color: surfaceBg,
                        border: Border(top: BorderSide(color: borderCol, width: 0.8)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
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
                              icon: isSaving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : const Icon(Icons.check_rounded, size: 18),
                              label: const Text('Guardar Cargo', style: TextStyle(fontWeight: FontWeight.bold)),
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      setDialogState(() => isSaving = true);
                                      final success = await _updateProfileField(
                                        user: user,
                                        position: controller.text.trim(),
                                        fieldName: 'Oficina / Cargo',
                                      );
                                      if (success && ctx.mounted) {
                                        Navigator.of(ctx).pop();
                                      } else {
                                        setDialogState(() => isSaving = false);
                                      }
                                    },
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
        },
      ),
    );
  }

  Future<void> _showEditAreaDialog(UserModel user) async {
    final controller = TextEditingController(text: user.area);
    bool isSaving = false;
    final primary = ThemeService.primaryColor(context);

    final suggestions = [
      'Dirección General',
      'Tecnologías de la Información (OTI)',
      'Recursos Humanos',
      'Administración y Finanzas',
      'Investigación y Desarrollo',
    ];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
          final surfaceBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
          final borderCol = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
          final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

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
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: isDark ? 0.12 : 0.08),
                        border: Border(bottom: BorderSide(color: borderCol, width: 0.8)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6).withValues(alpha: isDark ? 0.25 : 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.35)),
                            ),
                            child: const Icon(Icons.hub_rounded, color: Color(0xFF3B82F6), size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Área Asignada',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Dirección o departamento institucional',
                                  style: TextStyle(fontSize: 11.5, color: textMuted),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close_rounded, size: 20, color: textMuted),
                            splashRadius: 18,
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Área o Departamento *',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: controller,
                              autofocus: true,
                              decoration: InputDecoration(
                                hintText: 'Ej. Dirección General / Tecnologías',
                                hintStyle: TextStyle(fontSize: 12.5, color: isDark ? Colors.grey[500] : Colors.grey[400]),
                                prefixIcon: const Icon(Icons.hub_rounded, size: 20),
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
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Áreas institucionales frecuentes:',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textMuted),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: suggestions.map((sug) {
                                return InkWell(
                                  onTap: () {
                                    setDialogState(() => controller.text = sug);
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: controller.text.trim() == sug
                                          ? const Color(0xFF3B82F6).withValues(alpha: 0.18)
                                          : surfaceBg,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: controller.text.trim() == sug ? const Color(0xFF3B82F6) : borderCol,
                                      ),
                                    ),
                                    child: Text(
                                      sug,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: controller.text.trim() == sug ? FontWeight.bold : FontWeight.normal,
                                        color: controller.text.trim() == sug ? const Color(0xFF3B82F6) : textMuted,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                      decoration: BoxDecoration(
                        color: surfaceBg,
                        border: Border(top: BorderSide(color: borderCol, width: 0.8)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
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
                              icon: isSaving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : const Icon(Icons.check_rounded, size: 18),
                              label: const Text('Guardar Área', style: TextStyle(fontWeight: FontWeight.bold)),
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      setDialogState(() => isSaving = true);
                                      final success = await _updateProfileField(
                                        user: user,
                                        department: controller.text.trim(),
                                        fieldName: 'Área Asignada',
                                      );
                                      if (success && ctx.mounted) {
                                        Navigator.of(ctx).pop();
                                      } else {
                                        setDialogState(() => isSaving = false);
                                      }
                                    },
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
        },
      ),
    );
  }

  Future<void> _showEditDocumentDialog(UserModel user) async {
    final controller = TextEditingController(text: user.documentNumber ?? '');
    String selectedDocType = _detectDocumentType(user.documentNumber);
    bool isSaving = false;
    final primary = ThemeService.primaryColor(context);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
          final surfaceBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
          final borderCol = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
          final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

          final docTypes = [
            {'type': 'DNI', 'label': 'DNI (8 dígitos)', 'len': 8, 'numeric': true},
            {'type': 'CE', 'label': 'Carné Extr. (9 caract.)', 'len': 9, 'numeric': false},
            {'type': 'Pasaporte', 'label': 'Pasaporte (6-12)', 'len': 12, 'numeric': false},
          ];

          final currentSpec = docTypes.firstWhere((e) => e['type'] == selectedDocType, orElse: () => docTypes.first);
          final int maxLen = currentSpec['len'] as int;
          final bool isNumeric = currentSpec['numeric'] as bool;
          final text = controller.text.trim();
          final isValidLen = selectedDocType == 'DNI'
              ? text.length == 8
              : (selectedDocType == 'CE' ? text.length == 9 : (text.length >= 6 && text.length <= 12));

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
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.12 : 0.08),
                        border: Border(bottom: BorderSide(color: borderCol, width: 0.8)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.25 : 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
                            ),
                            child: const Icon(Icons.fingerprint_rounded, color: Color(0xFFF59E0B), size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Documento de Identidad',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Identificación oficial requerida para asistencias',
                                  style: TextStyle(fontSize: 11.5, color: textMuted),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close_rounded, size: 20, color: textMuted),
                            splashRadius: 18,
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Tipo de Documento *',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: docTypes.map((dt) {
                                final isSelected = selectedDocType == dt['type'];
                                return Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 3),
                                    child: InkWell(
                                      onTap: () {
                                        setDialogState(() {
                                          selectedDocType = dt['type'] as String;
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(10),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 150),
                                        padding: const EdgeInsets.symmetric(vertical: 9),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.25 : 0.15)
                                              : surfaceBg,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: isSelected ? const Color(0xFFF59E0B) : borderCol,
                                            width: isSelected ? 1.5 : 1,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          dt['type'] as String,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                            color: isSelected ? const Color(0xFFF59E0B) : textMuted,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Número de $selectedDocType *',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: controller,
                              autofocus: true,
                              keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
                              maxLength: maxLen,
                              onChanged: (_) => setDialogState(() {}),
                              decoration: InputDecoration(
                                hintText: 'Ingrese número de $selectedDocType',
                                hintStyle: TextStyle(fontSize: 12.5, color: isDark ? Colors.grey[500] : Colors.grey[400]),
                                prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                                suffixIcon: isValidLen
                                    ? const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20)
                                    : null,
                                counterText: '',
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
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              selectedDocType == 'DNI'
                                  ? 'Debe contener 8 dígitos numéricos sin letras ni símbolos.'
                                  : (selectedDocType == 'CE'
                                      ? 'Debe contener exactamente 9 caracteres.'
                                      : 'Debe contener entre 6 y 12 caracteres oficiales.'),
                              style: TextStyle(fontSize: 11, color: textMuted),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                      decoration: BoxDecoration(
                        color: surfaceBg,
                        border: Border(top: BorderSide(color: borderCol, width: 0.8)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
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
                              icon: isSaving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : const Icon(Icons.check_rounded, size: 18),
                              label: const Text('Guardar Documento', style: TextStyle(fontWeight: FontWeight.bold)),
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      final rawDoc = controller.text.replaceAll(RegExp(r'''['"\s]'''), '').trim();
                                      if (selectedDocType == 'DNI' && !RegExp(r'^\d{8}$').hasMatch(rawDoc)) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: const Text('El DNI debe tener exactamente 8 dígitos numéricos.'),
                                            backgroundColor: const Color(0xFFEF4444),
                                            behavior: SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                        );
                                        return;
                                      } else if (selectedDocType == 'CE' && !RegExp(r'^[a-zA-Z0-9]{9}$').hasMatch(rawDoc)) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: const Text('El Carné de Extranjería (CE) debe tener exactamente 9 caracteres.'),
                                            backgroundColor: const Color(0xFFEF4444),
                                            behavior: SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                        );
                                        return;
                                      } else if (selectedDocType == 'Pasaporte' && (rawDoc.length < 6 || rawDoc.length > 12)) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: const Text('El Pasaporte debe tener entre 6 y 12 caracteres.'),
                                            backgroundColor: const Color(0xFFEF4444),
                                            behavior: SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                        );
                                        return;
                                      }

                                      setDialogState(() => isSaving = true);
                                      final success = await _updateProfileField(
                                        user: user,
                                        documentNumber: rawDoc,
                                        fieldName: 'Documento de Identidad',
                                      );
                                      if (success && ctx.mounted) {
                                        Navigator.of(ctx).pop();
                                      } else {
                                        setDialogState(() => isSaving = false);
                                      }
                                    },
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
        },
      ),
    );
  }

  Future<void> _showEditPhoneDialog(UserModel user) async {
    final controller = TextEditingController(text: user.phoneNumber ?? '');
    bool isSaving = false;
    final primary = ThemeService.primaryColor(context);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
          final surfaceBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
          final borderCol = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
          final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

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
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.12 : 0.08),
                        border: Border(bottom: BorderSide(color: borderCol, width: 0.8)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.25 : 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                            ),
                            child: const Icon(Icons.phone_android_rounded, color: Color(0xFF10B981), size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Teléfono de Contacto',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Número móvil para notificaciones y seguridad',
                                  style: TextStyle(fontSize: 11.5, color: textMuted),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close_rounded, size: 20, color: textMuted),
                            splashRadius: 18,
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Número de Celular *',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: controller,
                              autofocus: true,
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                hintText: 'Ej. 987 654 321',
                                hintStyle: TextStyle(fontSize: 12.5, color: isDark ? Colors.grey[500] : Colors.grey[400]),
                                prefixIcon: const Icon(Icons.phone_android_rounded, size: 20),
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
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Ingresa un número de celular válido para recibir alertas de marcación.',
                              style: TextStyle(fontSize: 11, color: textMuted),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                      decoration: BoxDecoration(
                        color: surfaceBg,
                        border: Border(top: BorderSide(color: borderCol, width: 0.8)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
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
                              icon: isSaving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : const Icon(Icons.check_rounded, size: 18),
                              label: const Text('Guardar Teléfono', style: TextStyle(fontWeight: FontWeight.bold)),
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      final rawPhone = controller.text.replaceAll(RegExp(r'''['"\s]'''), '').trim();
                                      setDialogState(() => isSaving = true);
                                      final success = await _updateProfileField(
                                        user: user,
                                        phoneNumber: rawPhone,
                                        fieldName: 'Teléfono de Contacto',
                                      );
                                      if (success && ctx.mounted) {
                                        Navigator.of(ctx).pop();
                                      } else {
                                        setDialogState(() => isSaving = false);
                                      }
                                    },
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
        },
      ),
    );
  }

  void _showFieldSelectorSheet(UserModel user) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgCol = isDark ? const Color(0xFF0F172A) : Colors.white;
    final borderCol = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          decoration: BoxDecoration(
            color: bgCol,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: borderCol, width: 1),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4.5,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const Text(
                    '¿Qué dato deseas actualizar?',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Selecciona el campo que necesitas modificar',
                    style: TextStyle(fontSize: 12, color: textMuted),
                  ),
                  const SizedBox(height: 14),
                  _buildSheetOptionTile(
                    icon: Icons.business_rounded,
                    color: const Color(0xFF10B981),
                    title: 'Oficina / Cargo',
                    subtitle: user.office.isNotEmpty ? user.office : 'Sin asignar',
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _showEditOfficeDialog(user);
                    },
                  ),
                  _buildSheetOptionTile(
                    icon: Icons.hub_rounded,
                    color: const Color(0xFF3B82F6),
                    title: 'Área Asignada',
                    subtitle: user.area.isNotEmpty ? user.area : 'Sin asignar',
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _showEditAreaDialog(user);
                    },
                  ),
                  _buildSheetOptionTile(
                    icon: Icons.fingerprint_rounded,
                    color: const Color(0xFFF59E0B),
                    title: 'Documento de Identidad',
                    subtitle: user.documentNumber?.isNotEmpty == true ? user.documentNumber! : 'No registrado',
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _showEditDocumentDialog(user);
                    },
                  ),
                  _buildSheetOptionTile(
                    icon: Icons.phone_android_rounded,
                    color: const Color(0xFF10B981),
                    title: 'Teléfono de Contacto',
                    subtitle: user.phoneNumber?.isNotEmpty == true ? user.phoneNumber! : 'No registrado',
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _showEditPhoneDialog(user);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSheetOptionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final itemBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final borderCol = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: itemBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderCol, width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: isDark ? 0.2 : 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withValues(alpha: 0.25)),
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
      _showPhotoOptions();
    }
  }

  Future<void> _pickAndUploadPhoto(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 92,
      );

      if (file == null) return;

      final rawBytes = await file.readAsBytes();
      if (!mounted) return;

      // Abrir el recortador de foto interactivo y responsivo
      final croppedBytes = await ProfilePhotoCropperDialog.show(
        context: context,
        imageBytes: rawBytes,
      );

      // Si el usuario canceló el recorte, no subir
      if (croppedBytes == null || !mounted) return;

      final base64Image = 'data:image/png;base64,${base64Encode(croppedBytes)}';

      // 1. CAMBIO INSTANTÁNEO (0 ms, estilo WhatsApp):
      // Aplicar el cambio al avatar de inmediato para que se refleje sin demoras
      final currentUser = StorageService.currentUser;
      if (currentUser != null) {
        await StorageService.updateCurrentUser(currentUser.copyWith(photoUrl: base64Image));
      }

      if (!mounted) return;
      AppToast.show(
        context,
        title: 'Foto de perfil actualizada',
        subtitle: 'Tu nueva foto ya está visible.',
        icon: Icons.check_circle_rounded,
        accentColor: const Color(0xFF10B981),
      );

      // 2. Sincronización transparente en segundo plano con el servidor:
      try {
        final newRemoteUrl = await UsersService.uploadPhotoBase64(base64Image, updateStorage: false);
        if (newRemoteUrl.isNotEmpty && mounted) {
          // Pre-calentar la imagen remota en memoria para que no haya parpadeo negro ni descarga pendiente
          try {
            final provider = appCachedImageProvider(newRemoteUrl);
            if (provider != null) {
              await precacheImage(provider, context);
            }
          } catch (_) {}
          final userNow = StorageService.currentUser;
          if (userNow != null) {
            await StorageService.updateCurrentUser(userNow.copyWith(photoUrl: newRemoteUrl));
          }
        }
      } on TimeoutException {
        debugPrint('Upload timed out, keeping local photo');
      } on ApiException catch (e) {
        debugPrint('Sync ApiException: ${e.message}');
      } catch (err) {
        debugPrint('Sync error: $err');
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.show(
        context,
        title: 'Error al cambiar foto',
        subtitle: '$e',
        icon: Icons.error_outline_rounded,
        accentColor: const Color(0xFFEF4444),
      );
    }
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF13111C) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: ThemeService.cardBorder(ctx),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'FOTO DE PERFIL',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.bold,
                    color: ThemeService.primaryColor(ctx),
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: ThemeService.containerColor(ctx),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.camera_alt_rounded,
                      color: ThemeService.primaryColor(ctx),
                      size: 22,
                    ),
                  ),
                  title: Text(
                    'Tomar Foto con la Cámara',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  subtitle: Text(
                    'Usa la cámara de tu teléfono móvil',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndUploadPhoto(ImageSource.camera);
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: ThemeService.containerColor(ctx),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.photo_library_rounded,
                      color: ThemeService.primaryColor(ctx),
                      size: 22,
                    ),
                  ),
                  title: Text(
                    'Elegir de la Galería',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  subtitle: Text(
                    'Selecciona una imagen de tu galería',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndUploadPhoto(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }



  // --- DIÁLOGO PARA CAMBIAR CONTRASEÑA CON CÓDIGO AL CORREO (MISMO FLUJO QUE OLVIDASTE CONTRASEÑA) ---
  Future<void> _showChangePasswordDialog(UserModel user) async {
    final codeController = TextEditingController();
    final newPwController = TextEditingController();
    final confirmPwController = TextEditingController();

    int step = 1; // 1: Solicitar código al correo, 2: Ingresar código y nueva contraseña
    bool obscureNew = true;
    bool obscureConfirm = true;
    bool isSubmitting = false;
    String? errorMessage;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final primaryColor = ThemeService.primaryColor(context);

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: ThemeService.cardBg(context),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (step == 1 ? primaryColor : Colors.green).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    step == 1 ? Icons.mark_email_read_outlined : Icons.lock_reset_rounded,
                    color: step == 1 ? primaryColor : Colors.green,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    step == 1 ? 'Cambiar Contraseña' : 'Verificar y Cambiar',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (step == 1) ...[
                    Text(
                      'Por seguridad de tu cuenta, te enviaremos un código de verificación de recuperación a tu correo institucional registrado:',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Tarjeta de Correo Destino (Solo lectura)
                    const Text('Correo de confirmación:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.email_outlined, size: 20, color: primaryColor),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              user.email,
                              style: TextStyle(
                                fontSize: 13.5,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Icon(Icons.verified_user_rounded, size: 18, color: Colors.green),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton.icon(
                        icon: const Icon(Icons.vpn_key_outlined, size: 16),
                        label: const Text('¿Ya recibiste un código? Ingresar aquí', style: TextStyle(fontSize: 12)),
                        onPressed: isSubmitting
                            ? null
                            : () {
                                setModalState(() {
                                  step = 2;
                                  errorMessage = null;
                                });
                              },
                      ),
                    ),
                  ] else ...[
                    Text(
                      'Ingresa el código de seguridad enviado a:\n${user.email}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Código de Seguridad
                    const Text('Código de Verificación *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: codeController,
                      keyboardType: TextInputType.text,
                      decoration: InputDecoration(
                        hintText: 'Ingresa el código recibido en tu correo',
                        prefixIcon: const Icon(Icons.pin_outlined, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(Icons.replay_rounded, size: 15),
                        label: const Text('Reenviar código al correo', style: TextStyle(fontSize: 11.5)),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                setModalState(() => isSubmitting = true);
                                try {
                                  final msg = await AuthService.forgotPassword(user.email);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(msg), backgroundColor: Colors.green),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                                    );
                                  }
                                } finally {
                                  setModalState(() => isSubmitting = false);
                                }
                              },
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Nueva Contraseña
                    const Text('Nueva Contraseña Fuerte *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: newPwController,
                      obscureText: obscureNew,
                      decoration: InputDecoration(
                        hintText: 'Mínimo 8 caract. con símbolos o guiones (- _)',
                        prefixIcon: const Icon(Icons.security_rounded, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                          onPressed: () => setModalState(() => obscureNew = !obscureNew),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Confirmar Nueva Contraseña
                    const Text('Confirmar Nueva Contraseña *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: confirmPwController,
                      obscureText: obscureConfirm,
                      decoration: InputDecoration(
                        hintText: 'Repite la nueva contraseña',
                        prefixIcon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                          onPressed: () => setModalState(() => obscureConfirm = !obscureConfirm),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ],

                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: const TextStyle(color: Colors.red, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting
                    ? null
                    : () {
                        if (step == 2) {
                          setModalState(() {
                            step = 1;
                            errorMessage = null;
                          });
                        } else {
                          Navigator.of(ctx).pop();
                        }
                      },
                child: Text(step == 2 ? 'Atrás' : 'Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: step == 1 ? primaryColor : Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (step == 1) {
                          // PASO 1: Enviar código al correo usando el endpoint que funciona al 100%
                          setModalState(() {
                            isSubmitting = true;
                            errorMessage = null;
                          });

                          try {
                            final msg = await AuthService.forgotPassword(user.email);
                            setModalState(() {
                              step = 2;
                              isSubmitting = false;
                            });

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(Icons.mark_email_read_rounded, color: Colors.white, size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(child: Text(msg)),
                                    ],
                                  ),
                                  backgroundColor: ThemeService.primaryColor(context),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            setModalState(() {
                              isSubmitting = false;
                              errorMessage = e.toString().replaceAll('Exception: ', '');
                            });
                          }
                        } else {
                          // PASO 2: Confirmar código y aplicar nueva contraseña usando resetPassword
                          final code = codeController.text.trim();
                          final newPw = newPwController.text.trim();
                          final confirmPw = confirmPwController.text.trim();

                          if (code.isEmpty) {
                            setModalState(() => errorMessage = 'Ingresa el código que te enviamos al correo.');
                            return;
                          }
                          if (newPw.length < 8) {
                            setModalState(() => errorMessage = 'La nueva contraseña debe tener al menos 8 caracteres.');
                            return;
                          }
                          if (!RegExp(r'[A-Z]').hasMatch(newPw)) {
                            setModalState(() => errorMessage = 'Debe incluir al menos una letra mayúscula (A-Z).');
                            return;
                          }
                          if (!RegExp(r'[a-z]').hasMatch(newPw)) {
                            setModalState(() => errorMessage = 'Debe incluir al menos una letra minúscula (a-z).');
                            return;
                          }
                          if (!RegExp(r'\d').hasMatch(newPw)) {
                            setModalState(() => errorMessage = 'Debe incluir al menos un número (0-9).');
                            return;
                          }
                          if (!RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\/;~`]').hasMatch(newPw)) {
                            setModalState(() => errorMessage = 'Debe incluir al menos un símbolo especial (!@#\$%- o _).');
                            return;
                          }
                          if (newPw != confirmPw) {
                            setModalState(() => errorMessage = 'Las nuevas contraseñas no coinciden.');
                            return;
                          }

                          setModalState(() {
                            isSubmitting = true;
                            errorMessage = null;
                          });

                          try {
                            final msg = await AuthService.resetPassword(
                              email: user.email.trim().toLowerCase(),
                              code: code,
                              newPassword: newPw,
                            );

                            if (context.mounted) {
                              Navigator.of(ctx).pop();
                              await StorageService.clearSession();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Row(
                                      children: [
                                        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                                        const SizedBox(width: 10),
                                        Expanded(child: Text('$msg Inicia sesión con tu nueva contraseña.')),
                                      ],
                                    ),
                                    backgroundColor: Colors.green,
                                    behavior: SnackBarBehavior.floating,
                                    duration: const Duration(seconds: 4),
                                  ),
                                );
                                Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                                  (route) => false,
                                );
                              }
                            }
                          } catch (e) {
                            setModalState(() {
                              isSubmitting = false;
                              errorMessage = e.toString().replaceAll('Exception: ', '');
                            });
                          }
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Text(step == 1 ? 'Enviar Código al Correo' : 'Actualizar Contraseña'),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- DIÁLOGO DE CAMBIO DE CORREO ELECTRÓNICO (PASO 1: ENVIAR OTP -> PASO 2: CONFIRMAR) ---
  Future<void> _showChangeEmailDialog(UserModel user) async {
    final newEmailController = TextEditingController();
    final otpController = TextEditingController();
    int step = 1;
    bool isSubmitting = false;
    String? currentError;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final primaryColor = ThemeService.primaryColor(context);

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: ThemeService.cardBg(context),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: step == 1
                        ? primaryColor.withValues(alpha: 0.15)
                        : Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    step == 1 ? Icons.mark_email_read_outlined : Icons.lock_clock_rounded,
                    color: step == 1 ? primaryColor : Colors.green,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    step == 1 ? 'Cambiar Correo' : 'Verificar Código',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (step == 1) ...[
                    Text(
                      'Se conservarán todas tus asistencias, fotos y permisos. Solo cambiará tu correo de acceso.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Correo Actual (Solo lectura)
                    const Text('Correo actual:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.email_outlined, size: 18, color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              user.email,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white70 : Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const Icon(Icons.lock_outline, size: 16, color: Colors.grey),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Nuevo Correo
                    const Text('Nuevo correo electrónico *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: newEmailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: 'Ingresa tu nuevo correo electrónico',
                        prefixIcon: const Icon(Icons.alternate_email_rounded, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Te enviaremos un código de seguridad de 6 dígitos a este nuevo correo.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ] else ...[
                    Text(
                      'Ingresa el código de 6 dígitos enviado a:\n${newEmailController.text.trim().toLowerCase()}',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Campo Código OTP
                    Center(
                      child: SizedBox(
                        width: 220,
                        child: TextField(
                          controller: otpController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 6,
                          ),
                          decoration: InputDecoration(
                            hintText: '000000',
                            counterText: '',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        icon: const Icon(Icons.replay_rounded, size: 16),
                        label: const Text('Reenviar código', style: TextStyle(fontSize: 12)),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                final email = newEmailController.text.trim().toLowerCase();
                                setModalState(() => isSubmitting = true);
                                try {
                                  await AuthService.requestEmailChange(email);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Código reenviado exitosamente.'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                                    );
                                  }
                                } finally {
                                  setModalState(() => isSubmitting = false);
                                }
                              },
                      ),
                    ),
                  ],

                  if (currentError != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              currentError!,
                              style: const TextStyle(color: Colors.red, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                  backgroundColor: step == 1 ? primaryColor : Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final newEmail = newEmailController.text.trim().toLowerCase();

                        if (step == 1) {
                          // Validaciones Paso 1
                          if (newEmail.isEmpty) {
                            setModalState(() => currentError = 'Ingresa el nuevo correo electrónico.');
                            return;
                          }
                          final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
                          if (!emailRegex.hasMatch(newEmail)) {
                            setModalState(() => currentError = 'Ingresa un correo electrónico válido.');
                            return;
                          }
                          if (newEmail == user.email.toLowerCase()) {
                            setModalState(() => currentError = 'El nuevo correo no puede ser igual al actual.');
                            return;
                          }

                          setModalState(() {
                            isSubmitting = true;
                            currentError = null;
                          });

                          try {
                            final res = await AuthService.requestEmailChange(newEmail);
                            setModalState(() {
                              step = 2;
                              isSubmitting = false;
                            });
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(res['message']?.toString() ?? 'Código de 6 dígitos enviado a $newEmail. Revisa tu correo.'),
                                  backgroundColor: ThemeService.primaryColor(context),
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 4),
                                ),
                              );
                            }
                          } catch (e) {
                            setModalState(() {
                              isSubmitting = false;
                              currentError = e.toString().replaceAll('Exception: ', '');
                            });
                          }
                        } else {
                          // Validaciones Paso 2
                          final code = otpController.text.trim();
                          if (code.length != 6) {
                            setModalState(() => currentError = 'El código debe tener exactamente 6 dígitos.');
                            return;
                          }

                          setModalState(() {
                            isSubmitting = true;
                            currentError = null;
                          });

                          try {
                            final updated = await AuthService.confirmEmailChange(
                              newEmail: newEmail,
                              code: code,
                            );

                            if (context.mounted) {
                              Navigator.of(ctx).pop();
                              setState(() {});
                              _refreshProfile();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('¡Correo actualizado con éxito a ${updated.email}!'),
                                  backgroundColor: Colors.green,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (e) {
                            setModalState(() {
                              isSubmitting = false;
                              currentError = e.toString().replaceAll('Exception: ', '');
                            });
                          }
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Text(step == 1 ? 'Enviar Código' : 'Confirmar Cambio'),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- DIÁLOGO PARA ELIMINAR / DESACTIVAR CUENTA PROPIA ---
  Future<void> _showDeleteAccountDialog(UserModel user) async {
    final passwordController = TextEditingController();
    bool obscurePassword = true;
    bool isSubmitting = false;
    String? errorMessage;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: ThemeService.cardBg(context),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 26),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Eliminar Cuenta',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFEF4444)),
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
                    '¿Estás seguro de que deseas eliminar tu cuenta de ${user.fullName}?\n\nEsta acción borrará tu acceso y liberará tu correo y DNI para que puedas registrarte nuevamente cuando lo desees.',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Ingresa tu contraseña para confirmar *',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      hintText: 'Tu contraseña actual',
                      prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          size: 20,
                        ),
                        onPressed: () => setModalState(() => obscurePassword = !obscurePassword),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorMessage!,
                      style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
                    ),
                  ],
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
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final pw = passwordController.text.trim();
                        if (pw.isEmpty) {
                          setModalState(() => errorMessage = 'Debes ingresar tu contraseña actual.');
                          return;
                        }

                        setModalState(() {
                          isSubmitting = true;
                          errorMessage = null;
                        });

                        try {
                          final msg = await AuthService.deleteMyAccount(pw);
                          if (context.mounted) {
                            Navigator.of(ctx).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text('$msg Puedes registrarte nuevamente cuando lo desees.')),
                                  ],
                                ),
                                backgroundColor: const Color(0xFFEF4444),
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 4),
                              ),
                            );
                            Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (_) => const LoginScreen()),
                              (route) => false,
                            );
                          }
                        } catch (e) {
                          setModalState(() {
                            isSubmitting = false;
                            errorMessage = e.toString().replaceAll('Exception: ', '');
                          });
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Eliminar Definitivamente'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar Sesión'),
        content: const Text('¿Estás seguro de que deseas salir de tu cuenta?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await AuthService.logout();
    if (!mounted) return;

    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
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
        final hasWallpaper = WallpaperService.currentWallpaper.hasWallpaper;
        final primaryColor = ThemeService.primaryColor(context);

        const mintGreen = Color(0xFF34D399);
        const darkSlate = Color(0xFF0F172A);

        return ValueListenableBuilder<UserModel?>(
          valueListenable: StorageService.currentUserNotifier,
          builder: (context, user, _) {
            if (user == null) {
              return const Center(child: CircularProgressIndicator());
            }

            final roleDisplayName = user.role == UserRole.ADMIN
                ? 'ADMIN IIAP'
                : (user.isSuperAdmin ? 'SUPERADMIN IIAP' : user.role.displayName.toUpperCase());

            return Scaffold(
              backgroundColor: hasWallpaper ? Colors.transparent : ThemeService.scaffoldBg(context),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Responsive.constrained(
              context,
              maxTabletWidth: 680,
              child: Column(
                children: [
                  const SizedBox(height: 12),

                  // ==========================================
                  // 1. SECCIÓN SUPERIOR: AVATAR, NOMBRE Y ROL
                  // ==========================================
                  Center(
                    child: Column(
                      children: [
                        // Avatar con indicador de estado verde y botón de cámara
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            GestureDetector(
                              onTap: () => _openPhotoViewer(user),
                              child: Hero(
                                tag: user.photoUrl != null && user.photoUrl!.isNotEmpty
                                    ? 'profile_photo_${user.photoUrl}'
                                    : 'profile_avatar_placeholder',
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: primaryColor.withValues(alpha: 0.5),
                                      width: 2.5,
                                    ),
                                  ),
                                  child: AppCachedAvatar(
                                    imageUrl: user.photoUrl,
                                    name: user.fullName,
                                    size: 92,
                                    backgroundColor: isDark ? const Color(0xFF16202A) : const Color(0xFFE2E8F0),
                                    textColor: isDark ? Colors.white : ThemeService.primaryColor(context),
                                  ),
                                ),
                              ),
                            ),

                            // Punto verde superior derecho (En línea reactivo a internet)
                            Positioned(
                              top: 2,
                              right: 2,
                              child: ValueListenableBuilder<bool>(
                                valueListenable: ConnectivityService.isOnlineNotifier,
                                builder: (context, isOnline, _) {
                                  if (!isOnline) return const SizedBox.shrink();
                                  return Container(
                                    width: 15,
                                    height: 15,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF22C55E),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: _cardBg(context),
                                        width: 2.5,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),

                            // Botón de cámara inferior derecho (Cámara / Galería)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: _showPhotoOptions,
                                child: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: ThemeService.primaryColor(context),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _cardBg(context),
                                      width: 2.5,
                                    ),
                                  ),
                                  child: const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Nombre de Usuario
                        Text(
                          user.fullName,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.2,
                            color: isDark ? Colors.white : darkSlate,
                          ),
                        ),
                        const SizedBox(height: 3),

                        // Correo Electrónico
                        Text(
                          user.email,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Badge de Rol Institucional
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF064E3B).withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFF10B981).withValues(alpha: 0.35),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.verified_rounded, size: 13, color: mintGreen),
                              const SizedBox(width: 5),
                              Text(
                                roleDisplayName,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: mintGreen,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  // ==========================================
                  // 2. TARJETA: INFORMACIÓN INSTITUCIONAL
                  // ==========================================
                  _buildInstitutionalInfoCard(context, user),

                  const SizedBox(height: 16),

                  // ==========================================
                  // 3. TARJETA: TEMA Y APARIENCIA (ESTILO MOCKUP)
                  // ==========================================
                  _buildThemeAndAppearanceCard(context, isDark),

                  const SizedBox(height: 16),

                  // ==========================================
                  // 4. TARJETA: SEGURIDAD Y CUENTA
                  // ==========================================
                  _buildSecurityAndAccountCard(context, user, isDark),

                  const SizedBox(height: 22),

                  // ==========================================
                  // 5. BOTÓN CERRAR SESIÓN
                  // ==========================================
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _cardBg(context),
                        foregroundColor: const Color(0xFFEF4444),
                        elevation: 0,
                        side: BorderSide(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                          width: 1,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _handleLogout,
                      icon: const Icon(Icons.logout_rounded, size: 18, color: Color(0xFFF87171)),
                      label: const Text(
                        'Cerrar Sesión',
                        style: TextStyle(
                          color: Color(0xFFF87171),
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  // Sello Institucional
                  Center(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const LeafLogo(size: 28),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Instituto de Investigaciones de la Amazonía Peruana',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: ThemeService.subtextColor(context),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
      },
    );
  }

  /// Tarjeta de Tema y Apariencia unificada según captura oficial
  Widget _buildThemeAndAppearanceCard(BuildContext context, bool isDark) {
    const mintGreen = Color(0xFF34D399);

    return AnimatedBuilder(
      animation: Listenable.merge([
        ThemeService.themeModeNotifier,
        ThemeService.accentColorNotifier,
      ]),
      builder: (context, _) {
        final currentAccent = ThemeService.currentAccent;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _cardBg(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _cardBorder(context),
              width: 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Icono + Título + Badge de Tema
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.public_rounded, color: mintGreen, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Tema y Apariencia',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF064E3B).withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      currentAccent.displayName.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: mintGreen,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Carrusel horizontal de temas estilo ventana/mockup
              SizedBox(
                height: 94,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: AppAccentColor.values.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final item = AppAccentColor.values[index];
                    final isSelected = item == currentAccent;
                    final itemColor = item.accentSample;

                    return GestureDetector(
                      onTap: () {
                        if (item != currentAccent) {
                          ThemeService.setAccentColor(item);
                        }
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 88,
                            height: 64,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _innerBoxBg(context),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? itemColor
                                    : (isDark ? const Color(0xFF1E2C38) : const Color(0xFFCBD5E1)),
                                width: isSelected ? 1.8 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      width: 9,
                                      height: 9,
                                      decoration: BoxDecoration(
                                        color: itemColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    if (isSelected)
                                      Icon(Icons.check_circle_rounded, size: 13, color: itemColor),
                                  ],
                                ),
                                Container(
                                  height: 3,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: itemColor,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            item.displayName,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected
                                  ? (isDark ? Colors.white : const Color(0xFF0F172A))
                                  : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              // Tile de Fondo de Pantalla
              ValueListenableBuilder<WallpaperItem>(
                valueListenable: WallpaperService.wallpaperNotifier,
                builder: (context, wallpaper, _) {
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const WallpaperScreen()),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: _innerBoxBg(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _cardBorder(context).withValues(alpha: 0.6),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: mintGreen.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.wallpaper_rounded, color: mintGreen, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Fondo de Pantalla',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  wallpaper.hasWallpaper ? 'Activo: ${wallpaper.title}' : 'Color sólido predeterminado',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Text(
                                'Cambiar',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: mintGreen,
                                ),
                              ),
                              SizedBox(width: 3),
                              Icon(Icons.chevron_right_rounded, size: 16, color: mintGreen),
                            ],
                          ),
                        ],
                      ),
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

  /// Tarjeta de Seguridad y Cuenta (Cambiar Contraseña, Correo, Notificaciones)
  Widget _buildSecurityAndAccountCard(BuildContext context, UserModel user, bool isDark) {
    const mintGreen = Color(0xFF34D399);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _cardBorder(context),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.shield_outlined, color: mintGreen, size: 18),
              SizedBox(width: 8),
              Text(
                'Seguridad y Cuenta',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 1. Cambiar Contraseña
          _buildSecurityTile(
            context: context,
            icon: Icons.history_rounded,
            title: 'Cambiar Contraseña',
            subtitle: 'Mínimo 8 caract., mayúscula, números ...',
            onTap: () => _showChangePasswordDialog(user),
          ),
          const SizedBox(height: 10),

          // 2. Cambiar Correo Electrónico
          _buildSecurityTile(
            context: context,
            icon: Icons.mail_outline_rounded,
            title: 'Cambiar Correo Electrónico',
            subtitle: 'Actualiza tu contacto sin perder histori...',
            onTap: () => _showChangeEmailDialog(user),
          ),
          const SizedBox(height: 10),

          // 3. Configuración de Notificaciones
          _buildSecurityTile(
            context: context,
            icon: Icons.notifications_active_outlined,
            title: 'Configuración de Notificaciones',
            subtitle: 'Alertas de asistencia, turno y alarmas o...',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationsSettingsScreen()),
              );
            },
          ),

          // Opción Eliminar Mi Cuenta (para cuentas regulares que no sean SuperAdmin)
          if (!user.isSuperAdmin) ...[
            const SizedBox(height: 10),
            _buildSecurityTile(
              context: context,
              icon: Icons.delete_outline_rounded,
              title: 'Eliminar Mi Cuenta',
              subtitle: 'Desactiva tu acceso permanentemente',
              isDanger: true,
              onTap: () => _showDeleteAccountDialog(user),
            ),
          ],
        ],
      ),
    );
  }

  /// Tile interactivo para la sección de Seguridad
  Widget _buildSecurityTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDanger = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const mintGreen = Color(0xFF34D399);
    final accentColor = isDanger ? const Color(0xFFEF4444) : mintGreen;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _innerBoxBg(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _cardBorder(context).withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accentColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isDanger
                          ? const Color(0xFFEF4444)
                          : (isDark ? Colors.white : const Color(0xFF0F172A)),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }

  /// Tarjeta de Información Institucional con estilo de tarjetas individuales
  Widget _buildInstitutionalInfoCard(BuildContext context, UserModel user) {
    const mintGreen = Color(0xFF34D399);

    final docLabel = _getDocumentLabel(user.documentNumber);
    final hasDoc = user.documentNumber?.isNotEmpty == true;
    final hasPhone = user.phoneNumber?.isNotEmpty == true;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _cardBorder(context),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Icono + Título + Botón Editar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.badge_rounded, color: mintGreen, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Información Institucional',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _showFieldSelectorSheet(user),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF064E3B).withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.edit_rounded, size: 12, color: mintGreen),
                      SizedBox(width: 4),
                      Text(
                        'Editar',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: mintGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 1. OFICINA / CARGO
          _buildInstitutionalTile(
            context: context,
            icon: Icons.business_rounded,
            label: 'OFICINA / CARGO',
            value: user.office.isNotEmpty ? user.office : 'Sin asignar',
            isPlaceholder: user.office.isEmpty,
            onTap: () => _showEditOfficeDialog(user),
          ),
          const SizedBox(height: 10),

          // 2. ÁREA ASIGNADA
          _buildInstitutionalTile(
            context: context,
            icon: Icons.hub_rounded,
            label: 'ÁREA ASIGNADA',
            value: user.area.isNotEmpty ? user.area : 'Sin asignar',
            isPlaceholder: user.area.isEmpty,
            onTap: () => _showEditAreaDialog(user),
          ),
          const SizedBox(height: 10),

          // 3. DOCUMENTO DE IDENTIDAD
          _buildInstitutionalTile(
            context: context,
            icon: Icons.fingerprint_rounded,
            label: 'DOCUMENTO DE IDENTIDAD ($docLabel)',
            value: hasDoc ? user.documentNumber! : 'No registrado',
            isPlaceholder: !hasDoc,
            trailingAction: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: hasDoc
                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                    : const Color(0xFFD97706).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasDoc ? const Color(0xFF10B981) : const Color(0xFFD97706),
                  width: 1,
                ),
              ),
              child: Text(
                hasDoc ? 'Registrado' : 'Completar',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: hasDoc ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                ),
              ),
            ),
            onTap: () => _showEditDocumentDialog(user),
          ),
          const SizedBox(height: 10),

          // 4. TELÉFONO DE CONTACTO
          _buildInstitutionalTile(
            context: context,
            icon: Icons.phone_android_rounded,
            label: 'TELÉFONO DE CONTACTO',
            value: hasPhone ? user.phoneNumber! : 'No registrado',
            isPlaceholder: !hasPhone,
            trailingAction: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: hasPhone
                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                    : const Color(0xFFD97706).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasPhone ? const Color(0xFF10B981) : const Color(0xFFD97706),
                  width: 1,
                ),
              ),
              child: Text(
                hasPhone ? 'Verificado' : 'Completar',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: hasPhone ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                ),
              ),
            ),
            onTap: () => _showEditPhoneDialog(user),
          ),
        ],
      ),
    );
  }

  /// Tile individual para información institucional
  Widget _buildInstitutionalTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    bool isPlaceholder = false,
    Widget? trailingAction,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const mintGreen = Color(0xFF34D399);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _innerBoxBg(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _cardBorder(context).withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: mintGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: mintGreen, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isPlaceholder ? FontWeight.w500 : FontWeight.bold,
                      fontStyle: isPlaceholder ? FontStyle.italic : FontStyle.normal,
                      color: isPlaceholder
                          ? const Color(0xFFF59E0B)
                          : (isDark ? Colors.white : const Color(0xFF0F172A)),
                    ),
                  ),
                ],
              ),
            ),
            if (trailingAction != null) ...[
              const SizedBox(width: 8),
              trailingAction,
            ],
          ],
        ),
      ),
    );
  }
}
