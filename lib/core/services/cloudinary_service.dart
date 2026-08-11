import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../constants/app_config.dart';

class CloudinaryService {
  static const String _cloudName    = AppConfig.cloudinaryCloudName;
  static const String _uploadPreset = AppConfig.cloudinaryUploadPreset;
  static const String _uploadUrl    = 'https://api.cloudinary.com/v1_1/$_cloudName/image/upload';

  /// Sube una imagen a Cloudinary con el preset sin firma y devuelve la URL segura.
  /// Devuelve `null` si falla.
  static Future<String?> subirImagen(File imagen) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_uploadUrl));
      request.fields['upload_preset'] = _uploadPreset;
      request.files.add(await http.MultipartFile.fromPath('file', imagen.path));

      final streamed = await request.send();
      final body     = await streamed.stream.bytesToString();

      if (streamed.statusCode == 200) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        return json['secure_url'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
