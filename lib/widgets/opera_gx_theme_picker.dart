import 'package:flutter/material.dart';
import '../services/theme_service.dart';

class OperaGxThemePicker extends StatelessWidget {
  const OperaGxThemePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: Listenable.merge([
        ThemeService.themeModeNotifier,
        ThemeService.accentColorNotifier,
      ]),
      builder: (context, _) {
        final currentAccent = ThemeService.currentAccent;
        final activeColor = currentAccent.accentSample;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Título TEMA estilo Opera GX
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'TEMA',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: activeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: activeColor.withValues(alpha: 0.4), width: 1),
                  ),
                  child: Text(
                    currentAccent.displayName,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: activeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Carrusel de tarjetas cyberpunk estilo Opera GX
            SizedBox(
              height: 156,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: AppAccentColor.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
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
                        // Tarjeta: oscura/opaca si no está seleccionada, luminosa y con glow si está seleccionada
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 104,
                          height: 114,
                          decoration: BoxDecoration(
                            // Inactiva: fondo oscurito opaco con leve tinte; Activa: degradado vivo lleno de color
                            color: isSelected
                                ? null
                                : (isDark
                                    ? Color.alphaBlend(itemColor.withValues(alpha: 0.08), const Color(0xFF0F131C))
                                    : Color.alphaBlend(itemColor.withValues(alpha: 0.08), const Color(0xFFF1F5F9))),
                            gradient: isSelected
                                ? LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: isDark
                                        ? [
                                            itemColor.withValues(alpha: 0.40),
                                            item.darkContainer.withValues(alpha: 0.90),
                                            item.darkCardBg,
                                          ]
                                        : [
                                            item.lightContainer,
                                            itemColor.withValues(alpha: 0.35),
                                            Colors.white,
                                          ],
                                  )
                                : null,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isSelected
                                  ? itemColor
                                  : itemColor.withValues(alpha: isDark ? 0.32 : 0.28),
                              width: isSelected ? 2.5 : 1.2,
                            ),
                            // Solo la tarjeta seleccionada lleva sombra/glow para rendimiento ultra fluido
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: itemColor.withValues(alpha: isDark ? 0.65 : 0.45),
                                      blurRadius: 16,
                                      spreadRadius: 1.5,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Marco decorativo interno
                              Positioned.fill(
                                child: Padding(
                                  padding: const EdgeInsets.all(7),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: itemColor.withValues(alpha: isSelected ? 0.50 : 0.18),
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // Contenido del mockup interior
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Logo anillo Opera GX
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: itemColor.withValues(alpha: isSelected ? 0.25 : 0.08),
                                      border: Border.all(
                                        color: isSelected ? itemColor : itemColor.withValues(alpha: 0.45),
                                        width: isSelected ? 2.5 : 2.0,
                                      ),
                                    ),
                                    child: Center(
                                      child: Container(
                                        width: 18,
                                        height: 18,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: itemColor.withValues(alpha: isSelected ? 0.50 : 0.15),
                                          border: Border.all(
                                            color: isSelected ? itemColor : itemColor.withValues(alpha: 0.45),
                                            width: isSelected ? 2 : 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),

                                  // Barra simulada de búsqueda/nav
                                  Container(
                                    width: 58,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: itemColor.withValues(alpha: isSelected ? 0.75 : 0.28),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                  const SizedBox(height: 6),

                                  // Cuadrículas simuladas
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: List.generate(
                                      4,
                                      (i) => Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 2.5),
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: itemColor.withValues(alpha: isSelected ? 0.80 : 0.32),
                                          borderRadius: BorderRadius.circular(2.5),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              // Badge circular de check en la esquina para destacar la seleccionada
                              if (isSelected)
                                Positioned(
                                  top: 7,
                                  right: 7,
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: itemColor,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: itemColor.withValues(alpha: 0.8),
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Nombre tech en mayúsculas
                        Text(
                          item.displayName,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                            letterSpacing: 0.6,
                            color: isSelected
                                ? itemColor
                                : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                            shadows: isSelected
                                ? [
                                    Shadow(
                                      color: itemColor.withValues(alpha: 0.7),
                                      blurRadius: 6,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(height: 3),

                        // Pequeña línea indicadora de tema activo
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: isSelected ? 22 : 0,
                          height: 2.5,
                          decoration: BoxDecoration(
                            color: itemColor,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: itemColor.withValues(alpha: 0.8),
                                      blurRadius: 4,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

          ],
        );
      },
    );
  }
}
