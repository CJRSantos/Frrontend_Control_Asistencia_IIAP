import 'package:flutter/material.dart';
import '../../utils/responsive.dart';
import '../../models/user_model.dart';
import '../../models/schedule_model.dart';
import '../../services/users_service.dart';
import '../../services/storage_service.dart';
import '../../services/schedule_service.dart';
import '../../services/attendance_service.dart';
import '../../services/api_client.dart';
import '../qr/qr_display_screen.dart';
import '../../services/theme_service.dart';

class SupervisorsTab extends StatefulWidget {
  const SupervisorsTab({super.key});

  @override
  State<SupervisorsTab> createState() => _SupervisorsTabState();
}

class _SupervisorsTabState extends State<SupervisorsTab> {
  bool _isLoading = true;
  int _maxSupervisors = 3;
  int _availableSlots = 3;
  List<UserModel> _allUsers = [];
  late final TextEditingController _searchController;
  String _searchQuery = '';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _loadData(resetSearch: false);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool resetSearch = true}) async {
    if (resetSearch) {
      _searchController.clear();
      _searchQuery = '';
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final currentUser = StorageService.currentUser;
    final isAdmin = currentUser?.isAdmin == true;

    try {
      final supFuture = isAdmin
          ? UsersService.getSupervisors().catchError((_) => <String, dynamic>{})
          : Future.value(<String, dynamic>{});
      final usersFuture = UsersService.findAll().catchError((_) async {
        try {
          final records = await AttendanceService.getAllRecords();
          final Map<String, UserModel> map = {};
          for (final r in records) {
            if (r.userId.isNotEmpty && !map.containsKey(r.userId)) {
              map[r.userId] = UserModel(
                id: r.userId,
                email: r.userEmail ?? '',
                fullName: r.userName ?? 'Colaborador',
                role: UserRole.USER,
              );
            }
          }
          return map.values.toList();
        } catch (_) {
          return <UserModel>[];
        }
      });

      final results = await Future.wait([supFuture, usersFuture]);
      final supData = results[0] as Map<String, dynamic>;
      final usersData = results[1] as List<UserModel>;

      if (isAdmin && supData.isNotEmpty) {
        final list = supData['supervisors'] is List ? (supData['supervisors'] as List) : [];
        final totalCount = (supData['total'] is int)
            ? supData['total'] as int
            : (supData['current_count'] is int ? supData['current_count'] as int : list.length);
        final maxSup = (supData['max_limit'] is int)
            ? supData['max_limit'] as int
            : (supData['max_supervisors'] is int ? supData['max_supervisors'] as int : 3);
        final avail = (supData['available_slots'] is int)
            ? supData['available_slots'] as int
            : (maxSup - totalCount).clamp(0, maxSup);

        _maxSupervisors = maxSup;
        _availableSlots = avail;
      }

      if (mounted) {
        setState(() {
          _allUsers = usersData;
          _isLoading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error al cargar personal: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _changeUserRole(UserModel targetUser, UserRole newRole) async {
    try {
      await UsersService.assignRole(targetUser.id, newRole);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rol de ${targetUser.fullName} actualizado a ${newRole.displayName}.'),
          backgroundColor: ThemeService.primaryColor(context),
        ),
      );
      _loadData();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: const Color(0xFFEF4444)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cambiar rol: $e'), backgroundColor: const Color(0xFFEF4444)),
      );
    }
  }

  Future<void> _confirmDeleteUser(UserModel targetUser) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final borderCol = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: borderCol),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444), size: 22),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Eliminar Cuenta',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          '¿Estás seguro de que deseas eliminar la cuenta de ${targetUser.fullName} (${targetUser.email})?\n\nEsta acción revocará sus accesos y permitirá que el colaborador pueda registrarse nuevamente desde cero.',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancelar',
              style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sí, Eliminar Cuenta', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await UsersService.deleteUser(targetUser.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cuenta de ${targetUser.fullName} eliminada exitosamente.'),
            backgroundColor: Colors.green,
          ),
        );
        _loadData();
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: const Color(0xFFEF4444)),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar cuenta: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  Future<void> _confirmUnbindDevice(UserModel targetUser) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final borderCol = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: borderCol),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFD97706).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.phonelink_erase_rounded, color: Color(0xFFD97706), size: 22),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Desvincular Dispositivo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          '¿Deseas desvincular el celular registrado para ${targetUser.fullName}?\n\n'
          'Esto liberará el bloqueo por hardware y permitirá que el colaborador pueda registrar su asistencia desde un nuevo teléfono.',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancelar',
              style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD97706),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sí, Desvincular', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await UsersService.unbindDevice(targetUser.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dispositivo de ${targetUser.fullName} desvinculado con éxito.'),
            backgroundColor: Colors.green,
          ),
        );
        _loadData();
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: const Color(0xFFEF4444)),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al desvincular dispositivo: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.SUPERADMIN:
      case UserRole.ADMIN:
        return const Color(0xFFD97706);
      case UserRole.ADMIN_EVENTO:
        return const Color(0xFF2563EB);
      case UserRole.GESTOR_EVENTO:
        return const Color(0xFF0D9488);
      case UserRole.SUPERVISOR:
        return const Color(0xFF7C3AED);
      case UserRole.USER:
        return const Color(0xFF10B981);
    }
  }

  Widget _buildSheetActionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDanger = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final itemBg = isDanger
        ? (isDark ? const Color(0xFF450A0A).withValues(alpha: 0.35) : const Color(0xFFFEF2F2))
        : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC));
    final borderCol = isDanger
        ? const Color(0xFFEF4444).withValues(alpha: 0.35)
        : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0));

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
                          color: isDanger ? const Color(0xFFEF4444) : (isDark ? Colors.white : const Color(0xFF0F172A)),
                        ),
                      ),
                      const SizedBox(height: 2),
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
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: isDanger
                      ? const Color(0xFFEF4444).withValues(alpha: 0.6)
                      : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showUserManagementSheet(UserModel u) {
    final current = StorageService.currentUser;
    final isSuperAdmin = current?.isSuperAdmin == true;
    final isAdmin = current?.isAdmin == true;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = ThemeService.primaryColor(context);

    final bgCol = isDark ? const Color(0xFF0F172A) : Colors.white;
    final cardBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final borderCol = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (ctx) {
        return Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            decoration: BoxDecoration(
              color: bgCol,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: borderCol, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 30,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Drag Handle
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

                      // User Profile Header Card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderCol),
                        ),
                        child: Row(
                          children: [
                            // Avatar con iniciales
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: primary.withValues(alpha: 0.15),
                              child: Text(
                                u.fullName.isNotEmpty
                                    ? u.fullName.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase()
                                    : 'U',
                                style: TextStyle(
                                  color: primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    u.fullName,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.2,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      if (u.documentNumber != null && u.documentNumber!.isNotEmpty) ...[
                                        Text(
                                          'DNI: ${u.documentNumber}',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w500,
                                            color: textMuted,
                                          ),
                                        ),
                                        Text(' • ', style: TextStyle(color: textMuted, fontSize: 11)),
                                      ],
                                      Expanded(
                                        child: Text(
                                          u.office.isNotEmpty ? u.office : (u.area.isNotEmpty ? u.area : 'Sin área asignada'),
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: textMuted,
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
                            const SizedBox(width: 8),
                            // Badge de Rol Actual
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getRoleColor(u.role).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: _getRoleColor(u.role).withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                u.role.displayName,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _getRoleColor(u.role),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // SECCIÓN 1: GESTIÓN DE PERFIL Y EQUIPO
                      Text(
                        'DATOS Y EQUIPO',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),

                      _buildSheetActionTile(
                        icon: Icons.edit_note_rounded,
                        color: const Color(0xFF10B981),
                        title: 'Editar Oficina y Área',
                        subtitle: 'Actualizar la sede, oficina y área asignada',
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showEditUserOfficeAreaDialog(u);
                        },
                      ),

                      if (isAdmin)
                        _buildSheetActionTile(
                          icon: Icons.phonelink_erase_rounded,
                          color: const Color(0xFFD97706),
                          title: 'Desvincular Celular / Equipo',
                          subtitle: 'Permitir que el usuario vincule un nuevo dispositivo',
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _confirmUnbindDevice(u);
                          },
                        ),

                      const SizedBox(height: 14),

                      // SECCIÓN 2: ROLES Y PERMISOS
                      Text(
                        'ASIGNACIÓN DE ROLES Y PERMISOS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),

                      if (isSuperAdmin && u.role != UserRole.ADMIN)
                        _buildSheetActionTile(
                          icon: Icons.military_tech_rounded,
                          color: const Color(0xFFD97706),
                          title: 'Designar Admin / Presidente',
                          subtitle: 'Otorga permisos de máxima autoridad institucional',
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _changeUserRole(u, UserRole.ADMIN);
                          },
                        ),

                      if (isAdmin && u.role != UserRole.ADMIN_EVENTO)
                        _buildSheetActionTile(
                          icon: Icons.event_available_rounded,
                          color: const Color(0xFF2563EB),
                          title: 'Designar Admin de Eventos / UO',
                          subtitle: 'Gestión y control de eventos institucionales y UO',
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _changeUserRole(u, UserRole.ADMIN_EVENTO);
                          },
                        ),

                      if (isAdmin && u.role != UserRole.GESTOR_EVENTO)
                        _buildSheetActionTile(
                          icon: Icons.campaign_rounded,
                          color: const Color(0xFF0D9488),
                          title: 'Designar Gestor de Eventos / UO',
                          subtitle: 'Toma de asistencias y soporte en eventos',
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _changeUserRole(u, UserRole.GESTOR_EVENTO);
                          },
                        ),

                      if (isAdmin && u.role != UserRole.SUPERVISOR)
                        _buildSheetActionTile(
                          icon: Icons.verified_user_rounded,
                          color: const Color(0xFF7C3AED),
                          title: 'Designar Supervisor',
                          subtitle: 'Supervisar y corregir marcas del personal asignado',
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _changeUserRole(u, UserRole.SUPERVISOR);
                          },
                        ),

                      if (u.role != UserRole.USER)
                        _buildSheetActionTile(
                          icon: Icons.person_outline_rounded,
                          color: const Color(0xFF64748B),
                          title: 'Cambiar a Rol Colaborador',
                          subtitle: 'Rol básico (solo marca y consulta su propia asistencia)',
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _changeUserRole(u, UserRole.USER);
                          },
                        ),

                      const SizedBox(height: 14),

                      // SECCIÓN 3: ZONA DE PELIGRO
                      Text(
                        'ZONA DE RIESGO',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: const Color(0xFFEF4444).withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: 8),

                      _buildSheetActionTile(
                        icon: Icons.delete_outline_rounded,
                        color: const Color(0xFFEF4444),
                        title: 'Eliminar Cuenta',
                        subtitle: 'Borra al colaborador; podrá registrarse nuevamente',
                        isDanger: true,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _confirmDeleteUser(u);
                        },
                      ),
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

  Widget _buildAdminUserActions(UserModel u) {
    final current = StorageService.currentUser;
    final isSuperAdmin = current?.isSuperAdmin == true;

    // Si es SuperAdmin, no puede ser modificado por otros
    if (u.isSuperAdmin && !isSuperAdmin) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showUserManagementSheet(u),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
              width: 0.8,
            ),
          ),
          child: const Icon(
            Icons.more_vert_rounded,
            size: 18,
            color: Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  void _showEditUserOfficeAreaDialog(UserModel targetUser) {
    final officeCtrl = TextEditingController(text: targetUser.office);
    final areaCtrl = TextEditingController(text: targetUser.area);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final surfaceBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final borderCol = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final primary = ThemeService.primaryColor(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: borderCol),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.apartment_rounded, color: primary, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Oficina y Área', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(
                    targetUser.fullName,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                'Actualiza la oficina y área asignada a este colaborador:',
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: officeCtrl,
                decoration: InputDecoration(
                  labelText: 'Oficina / Sede',
                  hintText: 'Ej. Presidencia, Sede Central...',
                  prefixIcon: const Icon(Icons.apartment_rounded, size: 20),
                  filled: true,
                  fillColor: surfaceBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderCol),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: primary, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: areaCtrl,
                decoration: InputDecoration(
                  labelText: 'Área / Departamento',
                  hintText: 'Ej. Tecnologías, Recursos Humanos...',
                  prefixIcon: const Icon(Icons.grid_view_rounded, size: 20),
                  filled: true,
                  fillColor: surfaceBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderCol),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: primary, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancelar',
              style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: () async {
              final newOffice = officeCtrl.text.trim();
              final newArea = areaCtrl.text.trim();
              Navigator.of(ctx).pop();

              try {
                await UsersService.updateUser(targetUser.id, {
                  'position': newOffice,
                  'department': newArea,
                });
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Oficina y Área actualizadas para ${targetUser.fullName}.'),
                    backgroundColor: primary,
                  ),
                );
                _loadData();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error al actualizar: $e'),
                    backgroundColor: const Color(0xFFEF4444),
                  ),
                );
              }
            },
            child: const Text('Guardar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDirectDeleteDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.person_remove_rounded, color: Color(0xFFEF4444)),
            SizedBox(width: 8),
            Text('Eliminar por Correo o ID', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ingresa el nombre, correo o ID de la cuenta que deseas eliminar (ej: Jhon):',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'ej. Jhon o jhon@iiap.gob.pe',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final query = controller.text.trim();
              if (query.isEmpty) return;
              Navigator.of(ctx).pop();

              final match = _allUsers.cast<UserModel?>().firstWhere(
                (u) =>
                    u != null &&
                    (u.email.toLowerCase() == query.toLowerCase() ||
                        u.id == query ||
                        u.fullName.toLowerCase().contains(query.toLowerCase())),
                orElse: () => null,
              );

              if (match != null) {
                _confirmDeleteUser(match);
              } else {
                try {
                  await UsersService.deleteUser(query);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Cuenta $query eliminada exitosamente.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  _loadData();
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('No se encontró cuenta para "$query".'),
                      backgroundColor: const Color(0xFFEF4444),
                    ),
                  );
                }
              }
            },
            child: const Text('Buscar y Eliminar'),
          ),
        ],
      ),
    );
  }

  void _showDesignateQrModal() {
    final current = StorageService.currentUser;
    final isSuper = current?.isSuperAdmin == true;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF9333EA).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.qr_code_2_rounded, color: Color(0xFF9333EA), size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Designar Rol mediante Código QR',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text('El colaborador escaneará este código para ascender de inmediato',
                              style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (isSuper)
                  _buildRoleQrTile(
                    title: 'Admin / Presidente Institucional',
                    subtitle: 'Control administrativo, designa Admin y Gestores de eventos',
                    icon: Icons.military_tech_rounded,
                    color: const Color(0xFFD97706),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const QrDisplayScreen(
                            mode: QrMode.roleAssignment,
                            targetRole: 'ADMIN',
                            customTitle: 'Designar Admin / Presidente',
                            customSubtitle: 'El nuevo Presidente escaneará este código con su app',
                          ),
                        ),
                      );
                    },
                  ),
                _buildRoleQrTile(
                  title: 'Admin de Eventos / Unidad Organizativa',
                  subtitle: 'CRUD total de eventos de su UO y gestión de participantes',
                  icon: Icons.event_available_rounded,
                  color: const Color(0xFF2563EB),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const QrDisplayScreen(
                          mode: QrMode.roleAssignment,
                          targetRole: 'ADMIN_EVENTO',
                          customTitle: 'Designar Admin de Eventos / UO',
                          customSubtitle: 'Escanear para otorgar administración de eventos de su UO',
                        ),
                      ),
                    );
                  },
                ),
                _buildRoleQrTile(
                  title: 'Gestor de Eventos / UO',
                  subtitle: 'Control operativo de eventos asignados, proyecta QR y asistencia',
                  icon: Icons.campaign_rounded,
                  color: const Color(0xFF0D9488),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const QrDisplayScreen(
                          mode: QrMode.roleAssignment,
                          targetRole: 'GESTOR_EVENTO',
                          customTitle: 'Designar Gestor de Eventos / UO',
                          customSubtitle: 'Escanear para otorgar rol de Gestor de eventos',
                        ),
                      ),
                    );
                  },
                ),
                _buildRoleQrTile(
                  title: 'Supervisor de Asistencia',
                  subtitle: 'Control y supervisión de marcas de entrada y salida',
                  icon: Icons.verified_user_rounded,
                  color: const Color(0xFF7C3AED),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => QrDisplayScreen(
                          mode: QrMode.supervisorAssignment,
                          customTitle: 'Designar Supervisor de Asistencia',
                          customSubtitle: 'Escanear para otorgar rol de Supervisor de Asistencia',
                          availableSlots: _availableSlots,
                          maxSupervisors: _maxSupervisors,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoleQrTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.3)),
              color: color.withValues(alpha: 0.05),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openScheduleDialog(UserModel user) {
    final currentSchedule = ScheduleService.getSchedule(user.id, user: user);
    ScheduleType selectedType = currentSchedule.type;
    int checkInH = currentSchedule.type == ScheduleType.personalizado
        ? ScheduleModel.normalizeHour(currentSchedule.checkInHour, isCheckOut: false)
        : currentSchedule.checkInHour;
    int checkInM = currentSchedule.checkInMinute;
    int checkOutH = currentSchedule.type == ScheduleType.personalizado
        ? ScheduleModel.normalizeHour(currentSchedule.checkOutHour, isCheckOut: true)
        : currentSchedule.checkOutHour;
    int checkOutM = currentSchedule.checkOutMinute;
    int tolerance = currentSchedule.toleranceMinutes;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;

          void updatePreset(ScheduleType type) {
            final def = ScheduleModel.defaultForType(userId: user.id, type: type);
            setSheetState(() {
              selectedType = type;
              checkInH = def.checkInHour;
              checkInM = def.checkInMinute;
              checkOutH = def.checkOutHour;
              checkOutM = def.checkOutMinute;
              tolerance = def.toleranceMinutes;
            });
          }

          Future<void> pickCheckInTime() async {
            final picked = await showTimePicker(
              context: ctx,
              initialTime: TimeOfDay(hour: checkInH, minute: checkInM),
              helpText: 'HORA DE ENTRADA',
            );
            if (picked != null) {
              setSheetState(() {
                int newH = picked.hour;
                if (newH >= 1 && newH <= 6 && (checkInH >= 12 || checkOutH >= 13)) {
                  newH += 12;
                }
                checkInH = newH;
                checkInM = picked.minute;
                selectedType = ScheduleType.personalizado;
              });
            }
          }

          Future<void> pickCheckOutTime() async {
            final picked = await showTimePicker(
              context: ctx,
              initialTime: TimeOfDay(hour: checkOutH, minute: checkOutM),
              helpText: 'HORA DE SALIDA',
            );
            if (picked != null) {
              setSheetState(() {
                int newH = picked.hour;
                if (newH >= 1 && newH <= 11) {
                  newH += 12;
                }
                checkOutH = newH;
                checkOutM = picked.minute;
                selectedType = ScheduleType.personalizado;
              });
            }
          }

          // Cálculos para formatos 12h y 24h
          final inH12 = checkInH % 12 == 0 ? 12 : checkInH % 12;
          final in24Str = '${checkInH.toString().padLeft(2, '0')}:${checkInM.toString().padLeft(2, '0')}';

          final outH12 = checkOutH % 12 == 0 ? 12 : checkOutH % 12;
          final out24Str = '${checkOutH.toString().padLeft(2, '0')}:${checkOutM.toString().padLeft(2, '0')}';

          // Cálculo del límite de puntualidad en tiempo real
          final effectiveInH = (checkInH >= 1 && checkInH <= 6) ? checkInH + 12 : checkInH;
          final totalTolMins = effectiveInH * 60 + checkInM + tolerance;
          final tolH12 = ((totalTolMins ~/ 60) % 12 == 0) ? 12 : ((totalTolMins ~/ 60) % 12);
          final tolPeriod = ((totalTolMins ~/ 60) % 24) >= 12 ? 'PM' : 'AM';
          final tolMStr = (totalTolMins % 60).toString().padLeft(2, '0');
          final tolLimitFormatted = '${tolH12.toString().padLeft(2, '0')}:$tolMStr $tolPeriod';

          return Container(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
            decoration: BoxDecoration(
              color: ThemeService.cardBg(context),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Barra de agarre
                  Center(
                    child: Container(
                      width: 40,
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
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2D5E2A).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.access_time_filled_rounded, color: Color(0xFF2D5E2A), size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Asignar Horario y Turno',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              user.fullName,
                              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Sección Modalidad y Turno
                  Text(
                    'MODALIDAD Y TURNO LABORAL',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Lista de opciones preestablecidas
                  _buildPresetTile(
                    title: 'Horario Institucional Regular',
                    subtitle: 'Entrada 08:00 AM (Tolerancia hasta 08:30 AM) • Salida 05:00 PM',
                    type: ScheduleType.institucional,
                    isSelected: selectedType == ScheduleType.institucional,
                    isDark: isDark,
                    onTap: () => updatePreset(ScheduleType.institucional),
                  ),
                  const SizedBox(height: 8),
                  _buildPresetTile(
                    title: 'Horario Personalizado',
                    subtitle: 'Ajustar horas de entrada y salida libremente con AM/PM exacto',
                    type: ScheduleType.personalizado,
                    isSelected: selectedType == ScheduleType.personalizado,
                    isDark: isDark,
                    onTap: () => updatePreset(ScheduleType.personalizado),
                  ),

                  const SizedBox(height: 18),

                  // Visualización y selección manual de horas con controles AM/PM
                  Row(
                    children: [
                      // Tarjeta Hora Entrada
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selectedType == ScheduleType.personalizado
                                  ? const Color(0xFF16A34A).withValues(alpha: 0.5)
                                  : ThemeService.cardBorder(context),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Hora Entrada', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                                  Text(
                                    in24Str,
                                    style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: pickCheckInTime,
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.login_rounded, size: 18, color: Color(0xFF16A34A)),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${inH12.toString().padLeft(2, '0')}:${checkInM.toString().padLeft(2, '0')}',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Selector AM / PM explícito
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildAmPmChip(
                                      label: 'AM',
                                      isSelected: checkInH < 12,
                                      isDark: isDark,
                                      onTap: () {
                                        if (checkInH >= 12) {
                                          setSheetState(() {
                                            checkInH -= 12;
                                            selectedType = ScheduleType.personalizado;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: _buildAmPmChip(
                                      label: 'PM',
                                      isSelected: checkInH >= 12,
                                      isDark: isDark,
                                      onTap: () {
                                        if (checkInH < 12) {
                                          setSheetState(() {
                                            checkInH += 12;
                                            selectedType = ScheduleType.personalizado;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Tarjeta Hora Salida
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selectedType == ScheduleType.personalizado
                                  ? const Color(0xFFD97706).withValues(alpha: 0.5)
                                  : ThemeService.cardBorder(context),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Hora Salida', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                                  Text(
                                    out24Str,
                                    style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: pickCheckOutTime,
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.logout_rounded, size: 18, color: Color(0xFFD97706)),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${outH12.toString().padLeft(2, '0')}:${checkOutM.toString().padLeft(2, '0')}',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Selector AM / PM explícito
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildAmPmChip(
                                      label: 'AM',
                                      isSelected: checkOutH < 12,
                                      isDark: isDark,
                                      onTap: () {
                                        if (checkOutH >= 12) {
                                          setSheetState(() {
                                            checkOutH -= 12;
                                            selectedType = ScheduleType.personalizado;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: _buildAmPmChip(
                                      label: 'PM',
                                      isSelected: checkOutH >= 12,
                                      isDark: isDark,
                                      onTap: () {
                                        if (checkOutH < 12) {
                                          setSheetState(() {
                                            checkOutH += 12;
                                            selectedType = ScheduleType.personalizado;
                                          });
                                        }
                                      },
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

                  const SizedBox(height: 16),

                  // Tolerancia de Ingreso con indicador en tiempo real
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Tolerancia de ingreso:',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Límite puntual: $tolLimitFormatted',
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFF16A34A), fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2D5E2A).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '+$tolerance min',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2D5E2A), fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: tolerance.toDouble().clamp(0.0, 60.0),
                    min: 0,
                    max: 60,
                    divisions: 12,
                    activeColor: ThemeService.primaryColor(context),
                    onChanged: (val) {
                      setSheetState(() => tolerance = val.toInt());
                    },
                  ),

                  const SizedBox(height: 14),

                  // Botón de Confirmación
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ThemeService.primaryColor(context),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        final normIn = (checkInH >= 1 && checkInH <= 6) ? checkInH + 12 : checkInH;
                        final normOut = (checkOutH >= 1 && checkOutH <= 11) ? checkOutH + 12 : checkOutH;

                        final updatedSchedule = ScheduleModel(
                          userId: user.id,
                          type: selectedType,
                          checkInHour: normIn,
                          checkInMinute: checkInM,
                          checkOutHour: normOut,
                          checkOutMinute: checkOutM,
                          toleranceMinutes: tolerance,
                          updatedAt: DateTime.now(),
                          updatedByName: StorageService.currentUser?.fullName,
                        );

                        final messenger = ScaffoldMessenger.of(context);
                        await ScheduleService.saveSchedule(updatedSchedule);

                        if (ctx.mounted) {
                          Navigator.of(ctx).pop();
                        }
                        if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Horario actualizado para :  (Límite: )',
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                              backgroundColor: const Color(0xFF15803D),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          );
                        }
                      },
                      child: const Text(
                        'Guardar Horario',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPresetTile({
    required String title,
    required String subtitle,
    required ScheduleType type,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF14532D).withValues(alpha: 0.4) : const Color(0xFFDCFCE7))
              : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF2D5E2A)
                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: isSelected ? const Color(0xFF2D5E2A) : const Color(0xFF94A3B8),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
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
          ],
        ),
      ),
    );
  }


  Widget _buildAmPmChip({
    required String label,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF2D5E2A)
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected
                ? Colors.white
                : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
          ),
        ),
      ),
    );
  }

  Color _getScheduleBadgeBg(ScheduleType type, bool isDark) {
    switch (type) {
      case ScheduleType.institucional:
        return isDark ? const Color(0xFF1E3A8A).withValues(alpha: 0.3) : const Color(0xFFDBEAFE);
      case ScheduleType.personalizado:
        return isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);
    }
  }

  Color _getScheduleBadgeTextColor(ScheduleType type, bool isDark) {
    switch (type) {
      case ScheduleType.institucional:
        return isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8);
      case ScheduleType.personalizado:
        return isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final currentUser = StorageService.currentUser;
    final isAdmin = currentUser?.isAdmin == true;

    final filteredUsers = _allUsers.where((u) {
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      return u.fullName.toLowerCase().contains(query) || u.email.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isAdmin ? 'Gestión de Personal y Horarios' : 'Control de Horarios de Personal',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Recargar lista completa',
            onPressed: () => _loadData(resetSearch: true),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 48),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: () => _loadData(resetSearch: true), child: const Text('Reintentar')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _loadData(resetSearch: true),
                  child: Responsive.constrained(
                    context,
                    maxTabletWidth: 860,
                    child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    children: [
                      // Botón Designar con QR (Admin, Gestores, Supervisores) (SOLO ADMIN)
                      if (isAdmin) ...[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF9333EA),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 2,
                            ),
                            icon: const Icon(Icons.qr_code_rounded, size: 22),
                            label: const Text(
                              'Designar con QR (Admin, Gestores, Supervisores)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            onPressed: _showDesignateQrModal,
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],

                      // Barra de Búsqueda de Personal
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: ThemeService.cardBg(context),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: ThemeService.cardBorder(context)),
                              ),
                              child: TextField(
                                controller: _searchController,
                                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                                style: TextStyle(fontSize: 14, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                                decoration: InputDecoration(
                                  hintText: 'Buscar personal por nombre o correo...',
                                  hintStyle: TextStyle(fontSize: 13, color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                                  prefixIcon: Icon(Icons.search_rounded, size: 20, color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: Icon(Icons.close_rounded, size: 18, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                          tooltip: 'Limpiar búsqueda',
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() => _searchQuery = '');
                                          },
                                        )
                                      : null,
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                ),
                              ),
                            ),
                          ),
                          if (isAdmin) ...[
                            const SizedBox(width: 8),
                            InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: _showDirectDeleteDialog,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.25)),
                                ),
                                child: const Icon(Icons.person_remove_rounded, color: Color(0xFFEF4444), size: 22),
                              ),
                            ),
                          ],
                        ],
                      ),

                      const SizedBox(height: 18),

                      // Encabezado de la lista
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Nómina y Horarios Asignados (${filteredUsers.length})',
                              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Toca para editar',
                            style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Lista reactiva de colaboradores con horarios
                      ValueListenableBuilder<Map<String, ScheduleModel>>(
                        valueListenable: ScheduleService.schedulesNotifier,
                        builder: (context, schedulesMap, _) {
                          if (filteredUsers.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 30),
                              child: Center(
                                child: Text(
                                  _searchQuery.isEmpty
                                      ? 'No se encontraron colaboradores registrados.'
                                      : 'No hay resultados para "$_searchQuery"',
                                  style: TextStyle(color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                ),
                              ),
                            );
                          }

                          return Column(
                            children: filteredUsers.map((u) {
                              final schedule = ScheduleService.getSchedule(u.id, user: u);
                              final badgeBg = _getScheduleBadgeBg(schedule.type, isDark);
                              final badgeTextColor = _getScheduleBadgeTextColor(schedule.type, isDark);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: ThemeService.cardBg(context),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: ThemeService.cardBorder(context),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () => _openScheduleDialog(u),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 19,
                                                backgroundColor: ThemeService.cardBorder(context),
                                                child: Text(
                                                  u.fullName.isNotEmpty ? u.fullName[0].toUpperCase() : 'U',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: isDark ? Colors.white : const Color(0xFF2D5E2A),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      u.fullName,
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    Text(
                                                      u.email,
                                                      style: TextStyle(
                                                        fontSize: 11.5,
                                                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    if (u.office.isNotEmpty || u.area.isNotEmpty) ...[
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        [if (u.office.isNotEmpty) u.office, if (u.area.isNotEmpty) u.area].join(' • '),
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          color: Color(0xFF2D5E2A),
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              // Badge de Rol
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: u.isAdmin
                                                      ? const Color(0xFFFEE2E2)
                                                      : (u.isSupervisor ? const Color(0xFFF3E8FF) : const Color(0xFFDCFCE7)),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  u.role.displayName,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: u.isAdmin
                                                        ? const Color(0xFFDC2626)
                                                        : (u.isSupervisor ? const Color(0xFF9333EA) : const Color(0xFF16A34A)),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          const Divider(height: 1),
                                          const SizedBox(height: 10),

                                          // Fila del Horario Asignado
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.schedule_rounded, size: 16, color: badgeTextColor),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: badgeBg,
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Text(
                                                          '${schedule.fullLabel} • Tol: 08:30 AM',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w600,
                                                            color: badgeTextColor,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              TextButton.icon(
                                                style: TextButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  visualDensity: VisualDensity.compact,
                                                ),
                                                icon: const Icon(Icons.edit_calendar_rounded, size: 15, color: Color(0xFF2D5E2A)),
                                                label: const Text(
                                                  'Horario',
                                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2D5E2A)),
                                                ),
                                                onPressed: () => _openScheduleDialog(u),
                                              ),
                                              if (isAdmin && u.id != currentUser?.id) ...[
                                                const SizedBox(width: 4),
                                                _buildAdminUserActions(u),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
    );
  }
}
