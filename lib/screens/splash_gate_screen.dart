import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/storage_service.dart';
import '../widgets/leaf_logo.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class SplashGateScreen extends StatefulWidget {
  const SplashGateScreen({super.key});

  @override
  State<SplashGateScreen> createState() => _SplashGateScreenState();
}

class _SplashGateScreenState extends State<SplashGateScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _scaleAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeIn),
    );

    _animController.forward();
    _initAppAndNavigate();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _initAppAndNavigate() async {
    // Permitir al usuario ver el splash institucional de IIAP con fluidez (~700ms)
    // mientras en paralelo se verifica la sesión en disco
    final startTime = DateTime.now();

    if (StorageService.tokenSync == null) {
      await StorageService.init();
    }

    final user = StorageService.currentUser;
    final token = StorageService.tokenSync ?? await StorageService.getToken();

    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    const minSplashDuration = 700;
    if (elapsed < minSplashDuration) {
      await Future.delayed(Duration(milliseconds: minSplashDuration - elapsed));
    }

    if (!mounted || _hasNavigated) return;
    _hasNavigated = true;

    // Si hay usuario o token guardado localmente, se va al HomeScreen de forma instantánea.
    // Nunca pide login de nuevo si ya tiene cuenta iniciada.
    if (user != null || (token != null && token.isNotEmpty)) {
      _navigateTo(const HomeScreen());
    } else {
      _navigateTo(const LoginScreen());
    }
  }

  void _navigateTo(Widget targetScreen) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (context, animation, secondaryAnimation) => targetScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF0F2911),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF133215),
        body: RepaintBoundary(
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF3F6C42), // Verde medio superior
                  Color(0xFF2B542E), // Verde institucional
                  Color(0xFF1B431E), // Transición
                  Color(0xFF0F2B12), // Verde base
                ],
              ),
            ),
            child: SafeArea(
              child: Stack(
                children: [
                  // Logo central IIAP
                  Center(
                    child: FadeTransition(
                      opacity: _opacityAnimation,
                      child: ScaleTransition(
                        scale: _scaleAnimation,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: const LeafLogo(size: 84),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'IIAP',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 3.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Pie de página institucional
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 32, left: 24, right: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'CONTROL DE ASISTENCIA',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.0,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: 44,
                          height: 1.2,
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Instituto de Investigaciones de la\nAmazonía Peruana',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 12,
                            height: 1.45,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
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
}
