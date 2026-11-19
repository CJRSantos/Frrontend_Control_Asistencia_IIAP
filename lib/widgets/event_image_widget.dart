import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/api_config.dart';

/// Widget de renderizado de imagen de evento de alto rendimiento.
/// - Cachea los bytes Base64 decodificados en memoria para evitar re-decodificaciones innecesarias.
/// - Implementa gaplessPlayback y ValueKey estables para eliminar por completo el parpadeo
///   durante reconstrucciones periódicas o de sondeo en tiempo real.
/// - Soporta URLs Base64 (data:image/..., /9j/..., iVBOR...) y URLs HTTP/HTTPS con caché de red y memoria.
class EventImageWidget extends StatefulWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? fallbackWidget;

  const EventImageWidget({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fallbackWidget,
  });

  /// Determina si una cadena representa datos de imagen en base64
  static bool isBase64Image(String? url) {
    if (url == null) return false;
    final trimmed = url.trim();
    return trimmed.startsWith('data:image') ||
        trimmed.startsWith('data:application/octet-stream;base64') ||
        trimmed.startsWith('/9j/') ||
        trimmed.startsWith('iVBORw0KGgo');
  }

  /// Caché estático en memoria de cadenas base64 a Uint8List decodificados.
  static final Map<String, Uint8List> _base64Cache = {};

  static Uint8List? getOrDecodeBase64(String? dataUrl) {
    if (dataUrl == null || !isBase64Image(dataUrl)) return null;
    final trimmed = dataUrl.trim();
    if (_base64Cache.containsKey(trimmed)) {
      return _base64Cache[trimmed];
    }
    try {
      final clean = trimmed.contains(',') ? trimmed.split(',').last.trim() : trimmed;
      final sanitized = clean.replaceAll(RegExp(r'[\r\n\s]'), '');
      final bytes = base64Decode(sanitized);
      if (_base64Cache.length > 60) {
        _base64Cache.remove(_base64Cache.keys.first);
      }
      _base64Cache[trimmed] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Abre el visor interactivo de pantalla completa para cualquier imagen de evento
  static void showFullScreen(BuildContext context, String? imageUrl, {String? title}) {
    if (imageUrl == null || imageUrl.trim().isEmpty) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.94),
        barrierDismissible: true,
        pageBuilder: (ctx, anim1, anim2) => FullScreenImageViewer(
          imageUrl: imageUrl,
          title: title,
        ),
        transitionsBuilder: (ctx, anim, secondaryAnim, child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }

  @override
  State<EventImageWidget> createState() => _EventImageWidgetState();
}

class _EventImageWidgetState extends State<EventImageWidget> {
  Uint8List? _cachedBytes;

  @override
  void initState() {
    super.initState();
    _loadBytes();
  }

  @override
  void didUpdateWidget(covariant EventImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _loadBytes();
    }
  }

  void _loadBytes() {
    final url = widget.imageUrl;
    if (url != null && EventImageWidget.isBase64Image(url)) {
      _cachedBytes = EventImageWidget.getOrDecodeBase64(url);
    } else {
      _cachedBytes = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.imageUrl?.trim();
    final hasImage = url != null && url.isNotEmpty;

    Widget content;
    if (!hasImage) {
      content = widget.fallbackWidget ?? _defaultFallback();
    } else if (EventImageWidget.isBase64Image(url)) {
      final bytes = _cachedBytes ?? EventImageWidget.getOrDecodeBase64(url);
      if (bytes != null) {
        content = Image.memory(
          bytes,
          key: ValueKey('event_img_mem_${url.hashCode}'),
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => widget.fallbackWidget ?? _defaultFallback(),
        );
      } else {
        content = widget.fallbackWidget ?? _defaultFallback();
      }
    } else {
      final effectiveUrl = (url.startsWith('http://') || url.startsWith('https://'))
          ? url
          : (url.startsWith('/') ? '${ApiConfig.serverRoot}$url' : '${ApiConfig.serverRoot}/$url');
      content = CachedNetworkImage(
        key: ValueKey('event_img_net_${effectiveUrl.hashCode}'),
        imageUrl: effectiveUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        fadeInDuration: const Duration(milliseconds: 80),
        placeholder: (_, __) => widget.fallbackWidget ?? _defaultFallback(),
        errorWidget: (_, __, ___) => widget.fallbackWidget ?? _defaultFallback(),
      );
    }

    if (widget.borderRadius != null) {
      return ClipRRect(
        borderRadius: widget.borderRadius!,
        child: content,
      );
    }
    return content;
  }

  Widget _defaultFallback() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: const Color(0xFF1E293B),
      child: const Center(
        child: Icon(Icons.event_note_rounded, color: Color(0xFF10B981), size: 36),
      ),
    );
  }
}

/// Visor interactivo en pantalla completa con soporte para zoom,
/// botón de retroceso y cierre por toque o deslizamiento hacia abajo.
class FullScreenImageViewer extends StatefulWidget {
  final String imageUrl;
  final String? title;

  const FullScreenImageViewer({
    super.key,
    required this.imageUrl,
    this.title,
  });

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  double _verticalDragOffset = 0.0;
  final TransformationController _transformationController = TransformationController();

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_transformationController.value.getMaxScaleOnAxis() <= 1.05) {
      if (details.delta.dy > 0 || _verticalDragOffset > 0) {
        setState(() {
          _verticalDragOffset = (_verticalDragOffset + details.delta.dy).clamp(0.0, 450.0);
        });
      }
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_verticalDragOffset > 90 || (details.primaryVelocity ?? 0) > 300) {
      Navigator.of(context).pop();
    } else if (_verticalDragOffset > 0) {
      setState(() {
        _verticalDragOffset = 0.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double dragProgress = (_verticalDragOffset / 300.0).clamp(0.0, 1.0);
    final double bgOpacity = (0.94 * (1.0 - dragProgress * 0.7)).clamp(0.1, 0.94);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Fondo táctil que detecta toque en cualquier lugar para cerrar
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                color: Colors.black.withValues(alpha: bgOpacity),
              ),
            ),

            // 2. Imagen con soporte de zoom táctil y arrastre para cerrar
            Center(
              child: Transform.translate(
                offset: Offset(0, _verticalDragOffset),
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: 0.5,
                  maxScale: 5.0,
                  clipBehavior: Clip.none,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Hero(
                      tag: 'event_image_hero_${widget.imageUrl.hashCode}',
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: size.width * 0.96,
                          maxHeight: size.height * 0.85,
                        ),
                        child: EventImageWidget(
                          imageUrl: widget.imageUrl,
                          fit: BoxFit.contain,
                          fallbackWidget: const Center(
                            child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 3. Barra superior con solo botón de retroceso (sin la 'X')
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.85 * (1.0 - dragProgress)),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 28),
                        tooltip: 'Volver',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          widget.title ?? 'Imagen del Evento',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
