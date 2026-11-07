import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';

class FacialService {
  final Dio _dio;
  final String _facialServiceUrl;

  FacialService([Dio? dio])
      : _dio = dio ?? Dio(),
        _facialServiceUrl = ApiConfig.facialServiceUrl;

  /// Extrae el embedding facial de una imagen
  Future<List<double>?> extractEmbedding(File imageFile) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          imageFile.path,
          filename: 'face.jpg',
        ),
      });

      final response = await _dio.post(
        '$_facialServiceUrl/api/face/extract-embedding',
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.data['success'] == true) {
        return List<double>.from(response.data['embedding']);
      } else {
        throw Exception(response.data['message'] ?? 'Error extrayendo embedding');
      }
    } catch (e) {
      debugPrint('Error en extractEmbedding: $e');
      rethrow;
    }
  }

  /// Registra el rostro del usuario actual
  Future<void> registerFace(File imageFile) async {
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(
        imageFile.path,
        filename: 'face.jpg',
      ),
    });

    final response = await _dio.post(
      '${ApiConfig.baseUrl}/api/users/register-face',
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
      ),
    );

    if (response.data['success'] != true) {
      throw Exception(response.data['message'] ?? 'Error registrando rostro');
    }
  }
}
