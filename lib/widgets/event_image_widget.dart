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
