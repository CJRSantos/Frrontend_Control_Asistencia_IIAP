import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/theme_service.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../widgets/leaf_logo.dart';
import '../widgets/app_button.dart';
import '../widgets/app_text_field.dart';
import 'home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _documentController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String _documentType = 'DNI';
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _documentController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final cleanDoc = _documentController.text.replaceAll(RegExp(r'''['"\s]'''), '').trim();
      final cleanPhone = _phoneController.text.replaceAll(RegExp(r'''['"\s]'''), '').trim();

      final user = await AuthService.register(
        fullName: _nameController.text.trim(),
        email: _emailController.text.trim().toLowerCase(),
        password: _passwordController.text,
        documentNumber: cleanDoc.isEmpty ? null : cleanDoc,
        phoneNumber: cleanPhone.isEmpty ? null : cleanPhone,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '¡Cuenta creada con éxito! Rol asignado: ${user.role.displayName}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: ThemeService.primaryColor(context),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
        ),
      );

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  e.message,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error inesperado: $e'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showDocumentTypeSelector() {
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Tipo de Documento de Identidad',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildDocTypeOption(
                  ctx: ctx,
                  type: 'DNI',
                  title: 'DNI (Documento Nacional de Identidad)',
                  subtitle: 'Exactamente 8 dígitos numéricos (Perú)',
                  icon: Icons.badge_outlined,
                ),
                const SizedBox(height: 10),
                _buildDocTypeOption(
                  ctx: ctx,
                  type: 'CE',
                  title: 'CE (Carné de Extranjería)',
                  subtitle: 'Exactamente 9 caracteres alfanuméricos',
                  icon: Icons.credit_card_outlined,
                ),
                const SizedBox(height: 10),
                _buildDocTypeOption(
                  ctx: ctx,
                  type: 'Pasaporte',
                  title: 'Pasaporte',
                  subtitle: 'De 6 a 12 caracteres alfanuméricos',
                  icon: Icons.menu_book_outlined,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDocTypeOption({
    required BuildContext ctx,
    required String type,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    final isSelected = _documentType == type;
    final primary = ThemeService.primaryColor(ctx);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        Navigator.pop(ctx);
        if (_documentType != type) {
          setState(() {
            _documentType = type;
            _documentController.clear();
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? primary.withValues(alpha: 0.15)
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? primary : ThemeService.cardBorder(ctx),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? primary : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? primary : (isDark ? Colors.white : const Color(0xFF0F172A)),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: primary, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0.5,
        titleSpacing: 16,
        title: Row(
          children: [
            LeafLogo(size: 26, color: ThemeService.primaryColor(context)),
            const SizedBox(width: 10),
            Text(
              'IIAP Asistencia',
              style: TextStyle(
                color: ThemeService.primaryColor(context),
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Card
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: ThemeService.cardBg(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: ThemeService.cardBorder(context),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: ThemeService.containerColor(context),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.person_add_alt_1_rounded,
                                  color: ThemeService.primaryColor(context),
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Registro de Personal',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Sistema de Control de Asistencias IIAP',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
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

                    const SizedBox(height: 24),

                    // Nombre Completo
                    AppTextField(
                      controller: _nameController,
                      label: 'Nombre Completo',
                      hint: 'Escribe tu nombre completo',
                      prefixIcon: Icons.person_outline_rounded,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'El nombre es obligatorio';
                        if (v.trim().length < 3) return 'Ingresa un nombre válido';
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // Correo Electrónico
                    AppTextField(
                      controller: _emailController,
                      label: 'Correo Electrónico',
                      hint: 'ejemplo@iiap.gob.pe o correo personal',
                      prefixIcon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'El correo es obligatorio';
                        final clean = v.trim();
                        final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
                        if (!emailRegex.hasMatch(clean)) {
                          return 'Ingresa un correo electrónico válido';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // Selector de Tipo de Documento de Identidad
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _showDocumentTypeSelector,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: ThemeService.cardBg(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: ThemeService.cardBorder(context)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.badge_outlined, color: ThemeService.primaryColor(context), size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Row(
                                children: [
                                  Text(
                                    'Tipo de Doc: ',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: ThemeService.primaryColor(context).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _documentType,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: ThemeService.primaryColor(context),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: ThemeService.primaryColor(context).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Cambiar',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: ThemeService.primaryColor(context),
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: ThemeService.primaryColor(context)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Fila: Nº de Documento de Identidad + Teléfono (9 dígitos)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Campo Documento Dinámico
                        Expanded(
                          child: AppTextField(
                            controller: _documentController,
                            label: 'Nº $_documentType',
                            hint: _documentType == 'DNI'
                                ? '8 dígitos'
                                : (_documentType == 'CE' ? '9 caracteres' : '6 a 12 caract.'),
                            prefixIcon: Icons.fingerprint_rounded,
                            keyboardType: _documentType == 'DNI' ? TextInputType.number : TextInputType.text,
                            maxLength: _documentType == 'DNI' ? 8 : (_documentType == 'CE' ? 9 : 12),
                            inputFormatters: [
                              if (_documentType == 'DNI') FilteringTextInputFormatter.digitsOnly,
                              if (_documentType != 'DNI') FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                              LengthLimitingTextInputFormatter(
                                _documentType == 'DNI' ? 8 : (_documentType == 'CE' ? 9 : 12),
                              ),
                            ],
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'El $_documentType es obligatorio';
                              }
                              final clean = v.trim();
                              if (_documentType == 'DNI') {
                                if (clean.length != 8 || !RegExp(r'^\d{8}$').hasMatch(clean)) {
                                  return 'Debe tener 8 dígitos';
                                }
                              } else if (_documentType == 'CE') {
                                if (clean.length != 9 || !RegExp(r'^[a-zA-Z0-9]{9}$').hasMatch(clean)) {
                                  return 'Debe tener 9 caracteres';
                                }
                              } else if (_documentType == 'Pasaporte') {
                                if (clean.length < 6 || clean.length > 12 || !RegExp(r'^[a-zA-Z0-9]{6,12}$').hasMatch(clean)) {
                                  return 'Entre 6 y 12 caracteres';
                                }
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 14),
                        // Campo Teléfono (9 dígitos)
                        Expanded(
                          child: AppTextField(
                            controller: _phoneController,
                            label: 'Teléfono',
                            hint: '9 dígitos',
                            prefixIcon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                            maxLength: 9,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(9),
                            ],
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'El teléfono es obligatorio';
                              final clean = v.trim();
                              if (clean.length != 9 || !RegExp(r'^\d{9}$').hasMatch(clean)) {
                                return 'Debe tener 9 dígitos';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Contraseña (Fuerte)
                    AppTextField(
                      controller: _passwordController,
                      label: 'Contraseña',
                      hint: 'Mínimo 8 caract. (Mayús, Minús, Núm, Símbolo)',
                      prefixIcon: Icons.lock_outline_rounded,
                      obscureText: _obscurePassword,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'La contraseña es obligatoria';
                        if (v.length < 8) return 'Debe tener al menos 8 caracteres';
                        if (!RegExp(r'[A-Z]').hasMatch(v)) {
                          return 'Debe incluir al menos una letra mayúscula (A-Z)';
                        }
                        if (!RegExp(r'[a-z]').hasMatch(v)) {
                          return 'Debe incluir al menos una letra minúscula (a-z)';
                        }
                        if (!RegExp(r'\d').hasMatch(v)) {
                          return 'Debe incluir al menos un número (0-9)';
                        }
                          if (!RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\/;~`]').hasMatch(v)) {
                            return 'Debe incluir al menos un símbolo especial (!@#\$%)';
                          }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // Confirmar Contraseña
                    AppTextField(
                      controller: _confirmPasswordController,
                      label: 'Confirmar Contraseña',
                      hint: 'Repite tu contraseña',
                      prefixIcon: Icons.lock_clock_outlined,
                      obscureText: _obscureConfirmPassword,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Confirma tu contraseña';
                        if (v != _passwordController.text) {
                          return 'Las contraseñas no coinciden';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 24),

                    // Botón Registrarse
                    AppButton(
                      text: 'Registrarse',
                      icon: Icons.check_circle_outline,
                      isLoading: _isLoading,
                      onPressed: _handleRegister,
                    ),

                    const SizedBox(height: 12),

                    // Enlace a Login
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '¿Ya tienes una cuenta registrada? ',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Text(
                            'Inicia Sesión',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: ThemeService.primaryColor(context),
                            ),
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
      ),
    );
  }
}
