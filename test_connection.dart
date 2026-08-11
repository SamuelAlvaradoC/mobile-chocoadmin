import 'dart:io';
// ignore_for_file: avoid_print
void main() async {
  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    final req = await client.getUrl(
      Uri.parse('https://mi-api-qpjo.onrender.com/api/catalogo/productos')
    );
    final res = await req.close();
    print('Status: ${res.statusCode}');
    final body = await res.transform(systemEncoding.decoder).join();
    final preview = body.length > 300 ? body.substring(0, 300) : body;
    print('Body preview: $preview');
  } catch(e) {
    print('Error: $e');
  }
}
