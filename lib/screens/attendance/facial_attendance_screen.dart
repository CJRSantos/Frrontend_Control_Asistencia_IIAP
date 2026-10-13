import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import '../../services/storage_service.dart';

class FacialAttendanceScreen extends StatefulWidget {
  final String jwtToken; // Token JWT del usuario autenticado
  final String backendBaseUrl; // Ej: 'http://192.168.1.50:3000/api' o 'http://10.0.2.2:3000/api'

  const FacialAttendanceScreen({
    super.key,
    required this.jwtToken,
    required this.backendBaseUrl,
  });

  @override
  State<FacialAttendanceScreen> createState() => _FacialAttendanceScreenState();
}

class _FacialAttendanceScreenState extends State<FacialAttendanceScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  Timer? _throttlingTimer;

  bool _isProcessingFrame = false;
  bool _attendanceSuccess = false;
  String _statusMessage = "Posiciona tu rostro dentro del óvalo...";
  Color _statusColor = Colors.white;
  IconData _statusIcon = Icons.face;

  @override
  void initState() {
    super.initState();
    final user = StorageService.currentUser;
    if (user != null && !user.canUseFacialRecognition) {
      _statusMessage = "Acceso restringido: Tu rol no está autorizado para usar el Control Biométrico Facial.";
      _statusColor = Colors.redAccent;
      _statusIcon = Icons.shield_outlined;
      return;
    }
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        if (mounted) {
          setState(() {
            _statusMessage = "No se encontraron cámaras disponibles.";
            _statusColor = Colors.redAccent;
          });
        }
        return;
      }
      // Detección de factor de forma:
      // En iPad / Tablet (kiosco o tótem de asistencia), la cámara frontal es la adecuada para que el personal se encuadre.
      // En teléfonos móviles (iPhone / Android), se inicia por defecto con la trasera para supervisores.
      // En ambos casos, el usuario puede alternar la cámara libremente con el botón superior.
      final isTablet = MediaQueryData.fromView(WidgetsBinding.instance.platformDispatcher.views.first).size.shortestSide >= 600;
      final defaultCamera = _cameras!.firstWhere(
        (cam) => cam.lensDirection == (isTablet ? CameraLensDirection.front : CameraLensDirection.back),
        orElse: () => _cameras!.first,
      );
      await _startCamera(defaultCamera);
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = "Error al inicializar cámara: $e";
          _statusColor = Colors.redAccent;
        });
      }
    }
  }

  Future<void> _startCamera(CameraDescription camera) async {
    _throttlingTimer?.cancel();
    if (_cameraController != null) {
      await _cameraController!.dispose();
    }
    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium, // Resolución ideal: rápida y ligera
      enableAudio: false,
    );
    await _cameraController!.initialize();
    if (!mounted) return;
    setState(() {});
    // Iniciar el ciclo de captura automática con throttling (cada 1.8 segundos)
    _startContinuousFaceScanning();
  }

  Future<void> _switchCamera() async {
    if (_cameras == null || _cameras!.length < 2 || _cameraController == null) return;
    final currentLens = _cameraController!.description.lensDirection;
    final nextCamera = _cameras!.firstWhere(
      (cam) => cam.lensDirection != currentLens,
      orElse: () => _cameras!.first,
    );
    await _startCamera(nextCamera);
  }

  /// Throttling obligatorio: 1 frame cada 1.8s para no saturar la red ni el backend
  void _startContinuousFaceScanning() {
    _throttlingTimer?.cancel();
    _throttlingTimer = Timer.periodic(const Duration(milliseconds: 1800), (timer) async {
      if (_isProcessingFrame || _attendanceSuccess || _cameraController == null || !_cameraController!.value.isInitialized) {
        return;
      }
      await _captureAndProcessFrame();
    });
  }

  Future<void> _captureAndProcessFrame() async {
    if (_isProcessingFrame || _attendanceSuccess) return;
    setState(() {
      _isProcessingFrame = true;
      _statusMessage = "Escaneando rostro...";
      _statusColor = Colors.amberAccent;
      _statusIcon = Icons.sync;
    });
    try {
      // Capturar frame en formato JPG
      final XFile imageFile = await _cameraController!.takePicture();
      final bytes = await File(imageFile.path).readAsBytes();
      final base64Image = base64Encode(bytes);
      // Eliminar temporalmente el archivo capturado para no llenar la memoria del teléfono
      File(imageFile.path).delete().ignore();

      // Enviar al backend de NestJS
      final url = Uri.parse('${widget.backendBaseUrl}/attendance/facial-recognition');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.jwtToken}',
        },
        body: jsonEncode({
          'image_base64': base64Image,
          'device_id': 'flutter-facial-app',
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          // ¡ÉXITO! Detener el timer y la cámara inmediatamente
          _throttlingTimer?.cancel();
          final userName = data['user']?['full_name'] ?? 'Usuario';
          final type = data['type'] == 'CHECK_IN' ? 'ENTRADA' : 'SALIDA';
          if (mounted) {
            setState(() {
              _attendanceSuccess = true;
              _statusMessage = "✅ ¡Asistencia de $type registrada con éxito para $userName!";
              _statusColor = Colors.greenAccent;
              _statusIcon = Icons.check_circle;
            });
          }
          // Opcional: Cerrar la pantalla después de 2.5 segundos
          Future.delayed(const Duration(milliseconds: 2500), () {
            if (mounted) Navigator.pop(context, true);
          });
          return;
        } else {
          if (mounted) {
            setState(() {
              _statusMessage = data['message'] ?? "Rostro no detectado o no coincide.";
              _statusColor = Colors.orangeAccent;
              _statusIcon = Icons.warning_amber_rounded;
            });
          }
        }
      } else if (response.statusCode == 403) {
        _throttlingTimer?.cancel();
        if (mounted) {
          setState(() {
            _statusMessage = "Acceso denegado: Tu rol no tiene permisos para operar el Control Biométrico Facial.";
            _statusColor = Colors.redAccent;
            _statusIcon = Icons.shield_outlined;
          });
        }
        return;
      } else {
        if (mounted) {
          setState(() {
            _statusMessage = "Esperando alineación de rostro...";
            _statusColor = Colors.white70;
            _statusIcon = Icons.face;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = "Buscando rostro...";
          _statusColor = Colors.white70;
        });
      }
    } finally {
      if (mounted && !_attendanceSuccess) {
        setState(() {
          _isProcessingFrame = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _throttlingTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = StorageService.currentUser;
    if (user != null && !user.canUseFacialRecognition) {
      return Scaffold(
        backgroundColor: const Color(0xFF091417),
        appBar: AppBar(
          title: const Text("Control Biométrico Facial", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          backgroundColor: const Color(0xFF0F1E24),
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7F1D1D).withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
                  ),
                  child: const Icon(Icons.shield_outlined, color: Color(0xFFEF4444), size: 48),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Acceso Restringido',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Tu rol no tiene autorización para operar el Control Biométrico Facial.\nEsta función es de uso exclusivo para Administradores, Supervisores y Gestores.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.45),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: const Color(0xFF091417),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Volver al Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.greenAccent),
        ),
      );
    }

    final isFrontCamera = _cameraController?.description.lensDirection == CameraLensDirection.front;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Control Biométrico Facial", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.black87,
        elevation: 0,
        actions: [
          if (_cameras != null && _cameras!.length > 1)
            IconButton(
              icon: Icon(
                isFrontCamera ? Icons.camera_front_rounded : Icons.camera_rear_rounded,
                color: const Color(0xFF34D399),
              ),
              tooltip: isFrontCamera ? 'Cambiar a cámara trasera' : 'Cambiar a cámara frontal',
              onPressed: _switchCamera,
            ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Vista previa de la cámara (Llena la pantalla sin distorsión en iPad/iPhone)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final previewSize = _cameraController!.value.previewSize;
                if (previewSize == null) {
                  return CameraPreview(_cameraController!);
                }
                final isLandscape = constraints.maxWidth > constraints.maxHeight;
                final previewW = isLandscape ? previewSize.width : previewSize.height;
                final previewH = isLandscape ? previewSize.height : previewSize.width;

                return ClipRect(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: previewW,
                      height: previewH,
                      child: CameraPreview(_cameraController!),
                    ),
                  ),
                );
              },
            ),
          ),
          // 2. HUD - Guía visual ovalada con animación
          CustomPaint(
            size: Size.infinite,
            painter: FaceOvalOverlayPainter(
              borderColor: _attendanceSuccess
                  ? Colors.greenAccent
                  : (_isProcessingFrame ? Colors.amberAccent : Colors.white),
            ),
          ),
          // 3. Indicador de cámara activa en la parte superior
          Positioned(
            top: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isFrontCamera ? Icons.camera_front_rounded : Icons.camera_rear_rounded,
                    color: const Color(0xFF34D399),
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isFrontCamera ? 'Cámara Frontal' : 'Cámara Trasera (Oficial)',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          // 4. Panel inferior de feedback visual (Totalmente responsivo y anti-overflow)
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: SafeArea(
              top: false,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _statusColor, width: 1.8),
                  boxShadow: [
                    BoxShadow(
                      color: _statusColor.withValues(alpha: 0.25),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(_statusIcon, color: _statusColor, size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _statusMessage,
                        style: TextStyle(
                          color: _statusColor,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_isProcessingFrame && !_attendanceSuccess) ...[
                      const SizedBox(width: 10),
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dibuja el marco de la cámara oscureciendo el exterior y dejando un óvalo transparente en el centro
class FaceOvalOverlayPainter extends CustomPainter {
  final Color borderColor;
  FaceOvalOverlayPainter({required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()..color = Colors.black.withValues(alpha: 0.45);
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;

    // Proporción áurea anatómica del rostro humano adaptada a iPhone y pantalla grande de iPad
    final isLandscape = size.width > size.height;
    final double ovalHeight = isLandscape
        ? (size.height * 0.65).clamp(220.0, 480.0)
        : (size.height * 0.45).clamp(240.0, 400.0);
    final double ovalWidth = (ovalHeight * 0.74).clamp(160.0, size.width * 0.85);

    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * (isLandscape ? 0.46 : 0.42)),
      width: ovalWidth,
      height: ovalHeight,
    );

    // Máscara oscura exterior
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, backgroundPaint);

    // Borde ovalado iluminado
    canvas.drawOval(ovalRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant FaceOvalOverlayPainter oldDelegate) {
    return oldDelegate.borderColor != borderColor;
  }
}
