import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'config/api_config.dart';
import 'services/theme_service.dart';
import 'services/wallpaper_service.dart';
import 'services/storage_service.dart';
import 'services/attendance_service.dart';
import 'services/schedule_service.dart';
import 'services/connectivity_service.dart';
import 'services/notification_service.dart';
import 'screens/splash_gate_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Asegurar que la barra superior del celular (batería, hora, internet) NUNCA se oculte en toda la app
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  // Inicialización paralela inmediata de almacenamiento y configuración (0 ms de espera)
  await Future.wait([
    ThemeService.init(),
    WallpaperService.init(),
    ApiConfig.init(),
    StorageService.init(),
    AttendanceService.init(),
  ]);

  // Iniciar conectividad y notificaciones en segundo plano sin frenar el primer renderizado de la app
  ConnectivityService.init();

  runApp(const MyApp());

  // Servicios secundarios en segundo plano (diferidos al primer frame para renderizado inmediato a 60/120 FPS)
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ScheduleService.init();
    NotificationService.init();
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        ThemeService.themeModeNotifier,
        ThemeService.accentColorNotifier,
        WallpaperService.hasWallpaperNotifier,
      ]),
      builder: (context, _) {
        final accent = ThemeService.currentAccent;
        final hasWallpaper = WallpaperService.currentWallpaper.hasWallpaper;
        return MaterialApp(
          navigatorKey: StorageService.navigatorKey,
          title: 'IIAP Asistencia',
          debugShowCheckedModeBanner: false,
          themeAnimationDuration: Duration.zero,
          locale: const Locale('es', 'ES'),
          supportedLocales: const [
            Locale('es', 'ES'),
            Locale('es'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          themeMode: ThemeMode.dark,
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: accent.lightPrimary,
            scaffoldBackgroundColor: hasWallpaper
                ? Colors.transparent
                : accent.lightScaffoldBg,
            cardColor: accent.lightCardBg,
            dividerColor: accent.lightCardBorder,
            colorScheme: ColorScheme.fromSeed(
              seedColor: accent.lightPrimary,
              primary: accent.lightPrimary,
              secondary: accent.accentSample,
              surface: accent.lightCardBg,
              onSurface: const Color(0xFF0F172A),
              primaryContainer: accent.lightContainer,
              brightness: Brightness.light,
            ),
            navigationBarTheme: NavigationBarThemeData(
              backgroundColor: hasWallpaper
                  ? Colors.white.withValues(alpha: 0.9)
                  : accent.lightCardBg,
              indicatorColor: accent.lightPrimary.withValues(alpha: 0.18),
              iconTheme: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return IconThemeData(color: accent.lightPrimary);
                }
                return const IconThemeData(color: Color(0xFF64748B));
              }),
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: accent.lightPrimary,
                  );
                }
                return const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                );
              }),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: accent.lightPrimary,
                foregroundColor: Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            cardTheme: CardThemeData(
              color: hasWallpaper
                  ? Colors.white.withValues(alpha: 0.85)
                  : accent.lightCardBg,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: accent.lightPrimary.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: hasWallpaper
                  ? Colors.transparent
                  : accent.lightCardBg,
              foregroundColor: accent.lightPrimary,
              elevation: hasWallpaper ? 0 : 0.5,
              systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: hasWallpaper ? Brightness.light : Brightness.dark,
                statusBarBrightness: hasWallpaper ? Brightness.dark : Brightness.light,
              ),
            ),
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: CupertinoPageTransitionsBuilder(),
                TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
                TargetPlatform.windows: ZoomPageTransitionsBuilder(),
                TargetPlatform.linux: ZoomPageTransitionsBuilder(),
              },
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: accent.darkPrimary,
            scaffoldBackgroundColor: hasWallpaper
                ? Colors.transparent
                : accent.darkScaffoldBg,
            cardColor: accent.darkCardBg,
            dividerColor: accent.darkCardBorder,
            colorScheme: ColorScheme.dark(
              primary: accent.darkPrimary,
              secondary: accent.accentSample,
              surface: accent.darkCardBg,
              onSurface: Colors.white,
              primaryContainer: accent.darkContainer,
              onPrimary: Colors.black,
              brightness: Brightness.dark,
            ),
            navigationBarTheme: NavigationBarThemeData(
              backgroundColor: hasWallpaper
                  ? const Color(0xFF0C1316).withValues(alpha: 0.88)
                  : accent.darkCardBg,
              indicatorColor: accent.darkPrimary.withValues(alpha: 0.22),
              iconTheme: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return IconThemeData(color: accent.darkPrimary);
                }
                return const IconThemeData(color: Color(0xFF94A3B8));
              }),
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: accent.darkPrimary,
                  );
                }
                return const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF94A3B8),
                );
              }),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: accent.darkPrimary,
                foregroundColor: const Color(0xFF091417),
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            cardTheme: CardThemeData(
              color: hasWallpaper
                  ? const Color(0xFF0F171A).withValues(alpha: 0.8)
                  : accent.darkCardBg,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: accent.darkPrimary.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: hasWallpaper
                  ? Colors.transparent
                  : accent.darkCardBg,
              foregroundColor: Colors.white,
              elevation: hasWallpaper ? 0 : 0.5,
              systemOverlayStyle: const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
              ),
            ),
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: CupertinoPageTransitionsBuilder(),
                TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
                TargetPlatform.windows: ZoomPageTransitionsBuilder(),
                TargetPlatform.linux: ZoomPageTransitionsBuilder(),
              },
            ),
            useMaterial3: true,
          ),
          builder: (context, child) {
            return WallpaperService.buildBackgroundContainer(
              context: context,
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const SplashGateScreen(),
        );
      },
    );
  }
}
