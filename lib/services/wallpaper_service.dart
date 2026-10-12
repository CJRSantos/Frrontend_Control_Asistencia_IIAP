import 'dart:io';
import 'package:flutter/material.dart';
import 'theme_service.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum WallpaperType { none, preset, custom }

class WallpaperItem {
  final String id;
  final String title;
  final String category; // 'General', 'Chicas', 'Chicos', etc.
  final WallpaperType type;
  final String? assetPath;
  final String? customFilePath;

  const WallpaperItem({
    required this.id,
    required this.title,
    this.category = 'General',
    required this.type,
    this.assetPath,
    this.customFilePath,
  });

  bool get hasWallpaper => type != WallpaperType.none;

  ImageProvider? get imageProvider {
    if (type == WallpaperType.preset && assetPath != null) {
      return AssetImage(assetPath!);
    } else if (type == WallpaperType.custom && customFilePath != null) {
      final file = File(customFilePath!);
      if (file.existsSync()) {
        return FileImage(file);
      }
    }
    return null;
  }
}

class WallpaperService {
  static const String _keyWallpaperId = 'active_wallpaper_id_v2';
  static const String _keyWallpaperType = 'active_wallpaper_type_v2';
  static const String _keyCustomPath = 'active_wallpaper_custom_path_v2';

  static const WallpaperItem defaultNone = WallpaperItem(
    id: 'none',
    title: 'Color Sólido',
    category: 'General',
    type: WallpaperType.none,
  );

  static const List<WallpaperItem> presets = [
    // === CATEGORÍA: CYBER & HACKERS ===
    WallpaperItem(
      id: 'backiee_72450',
      title: 'SECURITY MATRIX LOCK',
      category: 'Cyber & Hackers',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-72450.jpg',
    ),
    WallpaperItem(
      id: 'backiee_218350',
      title: 'DATA BREACH GLITCH',
      category: 'Cyber & Hackers',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-218350.jpg',
    ),
    WallpaperItem(
      id: 'backiee_106859',
      title: 'ANONYMOUS MÁSCARA',
      category: 'Cyber & Hackers',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-106859.jpg',
    ),
    WallpaperItem(
      id: 'backiee_116398',
      title: 'ANONYMOUS TYPO',
      category: 'Cyber & Hackers',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-116398.jpg',
    ),
    WallpaperItem(
      id: 'backiee_226979',
      title: 'SOMBRAS ANONYMOUS',
      category: 'Cyber & Hackers',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-226979.jpg',
    ),
    WallpaperItem(
      id: 'backiee_251643',
      title: 'SILENCE HOODED',
      category: 'Cyber & Hackers',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-251643.jpg',
    ),
    WallpaperItem(
      id: 'backiee_272113',
      title: 'CYBER THEFT SCREEN',
      category: 'Cyber & Hackers',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-272113.jpg',
    ),
    WallpaperItem(
      id: 'backiee_76116',
      title: 'V FOR VENDETTA AMOLED',
      category: 'Cyber & Hackers',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-76116.jpg',
    ),
    WallpaperItem(
      id: 'backiee_376386',
      title: 'CRYSTAL BLIND HALO',
      category: 'Cyber & Hackers',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-376386.jpg',
    ),
    WallpaperItem(
      id: 'backiee_377102',
      title: 'OJOS DORADOS GLOW',
      category: 'Cyber & Hackers',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-377102.jpg',
    ),

    // === CATEGORÍA: SUPERDEPORTIVOS & MOTOR ===
    WallpaperItem(
      id: 'backiee_271014',
      title: 'LAMBORGHINI CYBER NEO',
      category: 'Superdeportivos & Motor',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-271014.jpg',
    ),
    WallpaperItem(
      id: 'backiee_336692',
      title: 'PORSCHE 911 NOIR',
      category: 'Superdeportivos & Motor',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-336692.jpg',
    ),
    WallpaperItem(
      id: 'backiee_318259',
      title: 'DARK BMW LIGHTS AMOLED',
      category: 'Superdeportivos & Motor',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-318259.jpg',
    ),
    WallpaperItem(
      id: 'backiee_268681',
      title: 'DODGE CHALLENGER NEÓN',
      category: 'Superdeportivos & Motor',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-268681.jpg',
    ),
    WallpaperItem(
      id: 'backiee_48041',
      title: 'CARBON FIBER HOT ROD',
      category: 'Superdeportivos & Motor',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-48041.jpg',
    ),
    WallpaperItem(
      id: 'backiee_371513',
      title: 'SUNSET LUXURY MANSION',
      category: 'Superdeportivos & Motor',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-371513.jpg',
    ),

    // === CATEGORÍA: FUTURISTA & MECHA ===
    WallpaperItem(
      id: 'backiee_314124',
      title: 'MECHA PILOT HUD',
      category: 'Futurista & Mecha',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-314124.jpg',
    ),
    WallpaperItem(
      id: 'backiee_58135',
      title: 'TERMINATOR CYBER SKULLS',
      category: 'Futurista & Mecha',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-58135.jpg',
    ),
    WallpaperItem(
      id: 'backiee_58919',
      title: 'T-800 ENDOSKELETON',
      category: 'Futurista & Mecha',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-58919.jpg',
    ),

    // === CATEGORÍA: AVENTURA & ÉPICO ===
    WallpaperItem(
      id: 'backiee_329746',
      title: 'NAVÍO PIRATA TORMENTA',
      category: 'Aventura & Épico',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-329746.jpg',
    ),
    WallpaperItem(
      id: 'backiee_70030',
      title: 'GALIÓN REAL OCÉANO',
      category: 'Aventura & Épico',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-70030.jpg',
    ),
    WallpaperItem(
      id: 'backiee_76222',
      title: 'EXPRESO VAPOR C6120',
      category: 'Aventura & Épico',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-76222.jpg',
    ),
    WallpaperItem(
      id: 'backiee_67041',
      title: 'NIGHT RUNWAY LANDING',
      category: 'Aventura & Épico',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-67041.jpg',
    ),
    WallpaperItem(
      id: 'backiee_341668',
      title: 'MAFIA MONEY TABLE NOIR',
      category: 'Aventura & Épico',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-341668.jpg',
    ),
    WallpaperItem(
      id: 'backiee_376037',
      title: 'GUERRERA DORADA PALADÍN',
      category: 'Aventura & Épico',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-376037.jpg',
    ),
    WallpaperItem(
      id: 'backiee_376827',
      title: 'BRISA MARINA & GAVIOTAS',
      category: 'Aventura & Épico',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-376827.jpg',
    ),
    WallpaperItem(
      id: 'backiee_376833',
      title: 'SILUETA ATARDECER SKYLINE',
      category: 'Aventura & Épico',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-376833.jpg',
    ),

    // === CATEGORÍA: GAMING & ESTILO ===
    WallpaperItem(
      id: 'backiee_47564',
      title: 'XBOX GAMING ELITE',
      category: 'Gaming & Estilo',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-47564.jpg',
    ),
    WallpaperItem(
      id: 'backiee_371043',
      title: 'MAFIA QUEEN ARSENAL',
      category: 'Gaming & Estilo',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-371043.jpg',
    ),
    WallpaperItem(
      id: 'backiee_33718',
      title: 'WALL-E EXPLORER',
      category: 'Gaming & Estilo',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-33718.jpg',
    ),
    WallpaperItem(
      id: 'backiee_376766',
      title: 'MANGA NOIR AVIATOR',
      category: 'Gaming & Estilo',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-376766.jpg',
    ),
    WallpaperItem(
      id: 'backiee_376786',
      title: 'GAMER YELLOW HOODIE',
      category: 'Gaming & Estilo',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-376786.jpg',
    ),
    WallpaperItem(
      id: 'backiee_376350',
      title: 'ANIME SUNSET SMILE',
      category: 'Gaming & Estilo',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-376350.jpg',
    ),
    WallpaperItem(
      id: 'backiee_376681',
      title: 'CYBER CITY GLAMOUR',
      category: 'Gaming & Estilo',
      type: WallpaperType.preset,
      assetPath: 'assets/images/wallpapers/backiee-376681.jpg',
    ),
  ];

  static final ValueNotifier<WallpaperItem> wallpaperNotifier =
      ValueNotifier<WallpaperItem>(defaultNone);

  static SharedPreferences? _prefs;

  static WallpaperItem get currentWallpaper => wallpaperNotifier.value;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final savedId = _prefs?.getString(_keyWallpaperId) ?? 'none';
    final savedType = _prefs?.getString(_keyWallpaperType) ?? 'none';
    final savedCustomPath = _prefs?.getString(_keyCustomPath);

    if (savedType == 'preset') {
      final found = presets.firstWhere(
        (p) => p.id == savedId,
        orElse: () => defaultNone,
      );
      wallpaperNotifier.value = found;
    } else if (savedType == 'custom' && savedCustomPath != null) {
      final file = File(savedCustomPath);
      if (file.existsSync()) {
        wallpaperNotifier.value = WallpaperItem(
          id: 'custom',
          title: 'Personalizado',
          type: WallpaperType.custom,
          customFilePath: savedCustomPath,
        );
      } else {
        wallpaperNotifier.value = defaultNone;
      }
    } else {
      wallpaperNotifier.value = defaultNone;
    }
  }

  static Future<void> setPreset(WallpaperItem preset) async {
    wallpaperNotifier.value = preset;
    await _prefs?.setString(_keyWallpaperId, preset.id);
    await _prefs?.setString(_keyWallpaperType, 'preset');
    await _prefs?.remove(_keyCustomPath);
  }

  static Future<void> setCustom(String filePath) async {
    final item = WallpaperItem(
      id: 'custom',
      title: 'Personalizado',
      type: WallpaperType.custom,
      customFilePath: filePath,
    );
    wallpaperNotifier.value = item;
    await _prefs?.setString(_keyWallpaperId, 'custom');
    await _prefs?.setString(_keyWallpaperType, 'custom');
    await _prefs?.setString(_keyCustomPath, filePath);
  }

  static Future<void> clearWallpaper() async {
    wallpaperNotifier.value = defaultNone;
    await _prefs?.setString(_keyWallpaperId, 'none');
    await _prefs?.setString(_keyWallpaperType, 'none');
    await _prefs?.remove(_keyCustomPath);
    ThemeService.setAccentColor(AppAccentColor.verdeSelva);
  }

  /// Construye un contenedor con el fondo activo protegido por overlay oscuro
  /// para garantizar que ningún texto, tarjeta o botón pierda legibilidad,
  /// asegurando que la barra de estado superior (batería, hora, red) nunca se oculte.
  static Widget buildBackgroundContainer({
    required BuildContext context,
    required Widget child,
  }) {
    final wallpaper = wallpaperNotifier.value;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Asegurar que la barra superior (Status Bar) del teléfono siempre se muestre con máxima nitidez
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark || wallpaper.hasWallpaper
          ? Brightness.light // Iconos blancos brillantes
          : Brightness.dark, // Iconos oscuros sobre fondo claro
      statusBarBrightness: isDark || wallpaper.hasWallpaper
          ? Brightness.dark
          : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark || wallpaper.hasWallpaper
          ? Brightness.light
          : Brightness.dark,
    );

    final defaultBgColor = isDark
        ? ThemeService.currentAccent.darkScaffoldBg
        : ThemeService.currentAccent.lightScaffoldBg;

    if (!wallpaper.hasWallpaper) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: ColoredBox(
          color: defaultBgColor,
          child: child,
        ),
      );
    }

    final provider = wallpaper.imageProvider;
    if (provider == null) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: ColoredBox(
          color: defaultBgColor,
          child: child,
        ),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Capa 1: Imagen de Fondo
          Positioned.fill(
            child: Image(
              image: provider,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            ),
          ),
          // Capa 2: Velo Protector de Legibilidad (Overlay con tinte ambiental)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(
                alpha: isDark ? 0.72 : 0.55,
              ),
            ),
          ),
          // Capa 3: Contenido de la pantalla
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}
