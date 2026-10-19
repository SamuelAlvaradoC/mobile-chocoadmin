import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';

const urlTerminos   = 'https://www.chocofreseo.com/terminos';
const urlPrivacidad = 'https://www.chocofreseo.com/privacidad';

/// "Al registrarte aceptas los Términos y condiciones y la Política de
/// privacidad", con enlaces a las páginas de la web (se abren en el
/// navegador). [abrirUrl] se puede reemplazar en los tests.
class AvisoLegalRegistro extends StatefulWidget {
  const AvisoLegalRegistro({super.key, this.abrirUrl});

  final Future<void> Function(String url)? abrirUrl;

  @override
  State<AvisoLegalRegistro> createState() => _AvisoLegalRegistroState();
}

class _AvisoLegalRegistroState extends State<AvisoLegalRegistro> {
  late final TapGestureRecognizer _terminos = TapGestureRecognizer()..onTap = () => _abrir(urlTerminos);
  late final TapGestureRecognizer _privacidad = TapGestureRecognizer()..onTap = () => _abrir(urlPrivacidad);

  Future<void> _abrir(String url) async {
    final abrir = widget.abrirUrl;
    if (abrir != null) return abrir(url);
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    _terminos.dispose();
    _privacidad.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enlace = GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary);
    return Text.rich(
      TextSpan(
        style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF888888), fontWeight: FontWeight.w600, height: 1.5),
        children: [
          const TextSpan(text: 'Al registrarte aceptas los '),
          TextSpan(text: 'Términos y condiciones', style: enlace, recognizer: _terminos),
          const TextSpan(text: ' y la '),
          TextSpan(text: 'Política de privacidad', style: enlace, recognizer: _privacidad),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
