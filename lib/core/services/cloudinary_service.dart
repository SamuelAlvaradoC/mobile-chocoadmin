import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../constants/app_config.dart';

class CloudinaryService {
  static const String _cloudName    = AppConfig.cloudinaryCloudName;
  static const String _uploadPreset = AppConfig.cloudinaryUploadPreset;
  static const String _uploadUrl    = 'https://api.cloudinary.com/v1_1/$_cloudName/image/upload';

  /// Tiempo máximo para subir una imagen (ya comprimida por image_picker).
  /// Sin esto, con la red caída la subida quedaba "cargando" para siempre.
  static const Duration timeout = Duration(seconds: 30);

  /// Sube una imagen a Cloudinary con el preset sin firma y devuelve la URL
  /// segura. Devuelve `null` si falla por cualquier motivo (red, timeout,
  /// cuenta deshabilitada, respuesta inválida) -- quien llama decide el mensaje.
  /// [carpeta] solo se usa para pruebas (ej. 'test-diagnostico').
  static Future<String?> subirImagen(File imagen, {String? carpeta}) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_uploadUrl));
      request.fields['upload_preset'] = _uploadPreset;
      if (carpeta != null) request.fields['folder'] = carpeta;
      request.files.add(await http.MultipartFile.fromPath('file', imagen.path));

      final streamed = await request.send().timeout(timeout);
      final body     = await streamed.stream.bytesToString().timeout(timeout);

      if (streamed.statusCode == 200) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        final url = json['secure_url'] as String?;
        return (url != null && url.isNotEmpty) ? url : null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
