import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/attendance_service.dart';
import '../../services/facial_service.dart';

class FacialAttendanceScreen extends StatefulWidget {
  final bool isAdmin; // Diferencia entre registro (user) y asistencia (admin)
  final String? jwtToken;
  final String? backendBaseUrl;

  const FacialAttendanceScreen({
    super.key,
    this.isAdmin = true,
    this.jwtToken,
    this.backendBaseUrl,
  });

  @override
  State<FacialAttendanceScreen> createState() => _FacialAttendanceScreenState();
}

class _FacialAttendanceScreenState extends State<FacialAttendanceScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isProcessing = false;
  String _statusMessage = 'Apunta tu rostro a la cámara';

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final status = await Permission.camera.request();
    if (status != PermissionStatus.granted) {
      _showError('Permiso de cámara denegado');
      return;
    }

    _cameras = await availableCameras();
    if (_cameras == null || _cameras!.isEmpty) {
      _showError('No hay cámara disponible');
      return;
    }

    final frontCamera = _cameras!.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras!.first,
    );

    _cameraController = CameraController(
      frontCamera, // Cámara frontal preferente
      ResolutionPreset.high,
      enableAudio: false,
    );

    await _cameraController!.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _captureAndProcess() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Procesando imagen...';
    });

    try {
      // 1. Capturar foto
      final XFile photo = await _cameraController!.takePicture();
      final File imageFile = File(photo.path);

      setState(() => _statusMessage = 'Analizando rostro...');

      // 2. Procesar según el rol
      if (widget.isAdmin) {
        await _processAdminScan(imageFile);
      } else {
        await _processUserRegistration(imageFile);
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = 'Apunta tu rostro a la cámara';
        });
      }
    }
  }

  /// Admin escanea rostro para registrar asistencia
  Future<void> _processAdminScan(File imageFile) async {
    final attendanceService = AttendanceService(); // Inyectar según tu patrón
    final result = await attendanceService.registerFacialAttendance(imageFile);

    if (result['success'] == true) {
      final userName = result['user']?['name'] ?? result['user']?['full_name'] ?? 'Usuario';
      _showSuccess(
        '✅ $userName',
        'Asistencia registrada correctamente',
      );
    } else {
      _showError('❌ ${result['message']}');
    }
  }

  /// Usuario registra su rostro (una sola vez)
  Future<void> _processUserRegistration(File imageFile) async {
    final facialService = FacialService(); // Inyectar según tu patrón
    await facialService.registerFace(imageFile);

    _showSuccess(
      '✅ Rostro registrado',
      'Ya no verás esta opción nuevamente',
    );

    // Regresar a la pantalla anterior (la opción desaparecerá del menú)
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) Navigator.pop(context, true);
  }

  void _showSuccess(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAdmin 
          ? 'Escanear Asistencia' 
          : 'Registrar mi Rostro'),
      ),
      body: Column(
        children: [
          // Vista de cámara con overlay guía
          Expanded(
            child: _cameraController == null
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    children: [
                      CameraPreview(_cameraController!),
                      // Overlay con guía de rostro
                      CustomPaint(
                        size: Size.infinite,
                        painter: FaceGuidePainter(),
                      ),
                      // Indicador de procesamiento
                      if (_isProcessing)
                        Container(
                          color: Colors.black54,
                          child: const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                        ),
                    ],
                  ),
          ),
          
          // Mensaje de estado
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _statusMessage,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
          
          // Botón de captura
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _captureAndProcess,
              icon: const Icon(Icons.camera_alt),
              label: Text(widget.isAdmin 
                ? 'Escanear Rostro' 
                : 'Capturar mi Rostro'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32, 
                  vertical: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Painter para dibujar la guía oval del rostro
class FaceGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.7,
      height: size.height * 0.5,
    );

    canvas.drawOval(ovalRect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
