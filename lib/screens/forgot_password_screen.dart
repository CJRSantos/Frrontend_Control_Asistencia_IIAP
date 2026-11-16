import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/theme_service.dart';
import '../services/api_client.dart';
import '../widgets/app_button.dart';
import '../widgets/app_text_field.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKeyEmail = GlobalKey<FormState>();
  final _formKeyReset = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  int _currentStep = 1; // 1: Pedir Correo, 2: Ingresar Código y Nueva Clave

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSendCode() async {
    if (!_formKeyEmail.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final msg = await AuthService.forgotPassword(_emailController.text.trim());
      if (!mounted) return;

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

      setState(() {
        _currentStep = 2;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al enviar código: $e'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleResetPassword() async {
    if (!_formKeyReset.currentState!.validate()) return;

    if (_newPasswordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Las contraseñas no coinciden.'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final msg = await AuthService.resetPassword(
        email: _emailController.text.trim(),
        code: _codeController.text.trim(),
        newPassword: _newPasswordController.text,
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(msg)),
            ],
          ),
          backgroundColor: ThemeService.primaryColor(context),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );

      // Regresar al Login para que inicie sesión con su nueva clave
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al restablecer contraseña: $e'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          _currentStep == 1 ? 'Recuperar Cuenta' : 'Nueva Contraseña',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Tarjeta Encabezado
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: ThemeService.cardBg(context),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: ThemeService.cardBorder(context), width: 1.2),
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
                                _currentStep == 1 ? Icons.lock_reset_rounded : Icons.vpn_key_rounded,
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
                                    _currentStep == 1 ? '¿Olvidaste tu contraseña?' : 'Código de Seguridad',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Paso $_currentStep de 2',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: ThemeService.primaryColor(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _currentStep == 1
                              ? 'Ingresa tu correo electrónico registrado. Te enviaremos un código de seguridad de 6 dígitos para que puedas definir una nueva contraseña.'
                              : 'Ingresa el código de 6 dígitos que enviamos a ${_emailController.text} y escribe tu nueva contraseña.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Contenido según el Paso
                  if (_currentStep == 1) _buildStep1Email(context) else _buildStep2Reset(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep1Email(BuildContext context) {
    return Form(
      key: _formKeyEmail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _emailController,
            label: 'Correo Electrónico',
            hint: 'ejemplo@iiap.gob.pe',
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Ingresa tu correo electrónico';
              }
              if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(value.trim())) {
                return 'Ingresa un correo electrónico válido';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          AppButton(
            text: 'Enviar Código de 6 Dígitos',
            icon: Icons.send_rounded,
            isLoading: _isLoading,
            onPressed: _handleSendCode,
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Volver al Inicio de Sesión'),
              style: TextButton.styleFrom(
                foregroundColor: ThemeService.primaryColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2Reset(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Form(
      key: _formKeyReset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Chip con el correo
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: ThemeService.containerColor(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ThemeService.primaryColor(context).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.email_rounded, size: 18, color: ThemeService.primaryColor(context)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _emailController.text,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ThemeService.primaryColor(context),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _currentStep = 1),
                  child: Icon(Icons.edit_outlined, size: 18, color: ThemeService.primaryColor(context)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Código de 6 dígitos
          AppTextField(
            controller: _codeController,
            label: 'Código de Verificación (6 Dígitos)',
            hint: 'Ej. 123456',
            prefixIcon: Icons.pin_outlined,
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Ingresa el código de 6 dígitos';
              }
              if (value.trim().length != 6) {
                return 'El código debe tener exactamente 6 dígitos';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Nueva Contraseña
          AppTextField(
            controller: _newPasswordController,
            label: 'Nueva Contraseña',
            hint: 'Mínimo 8 caracteres',
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
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Ingresa tu nueva contraseña';
              }
              if (value.length < 8) {
                return 'La contraseña debe tener al menos 8 caracteres';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Confirmar Contraseña
          AppTextField(
            controller: _confirmPasswordController,
            label: 'Confirmar Nueva Contraseña',
            hint: 'Repite tu nueva contraseña',
            prefixIcon: Icons.lock_clock_outlined,
            obscureText: _obscureConfirm,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                size: 20,
              ),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Confirma tu nueva contraseña';
              }
              if (value != _newPasswordController.text) {
                return 'Las contraseñas no coinciden';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),

          AppButton(
            text: 'Guardar Nueva Contraseña',
            icon: Icons.check_circle_rounded,
            isLoading: _isLoading,
            onPressed: _handleResetPassword,
          ),
          const SizedBox(height: 14),

          // Reenviar código
          Center(
            child: TextButton(
              onPressed: _isLoading ? null : _handleSendCode,
              child: Text(
                '¿No recibiste el código? Reenviar',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ThemeService.primaryColor(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
