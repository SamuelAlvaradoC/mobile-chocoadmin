import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brand_icons.dart';

/// Botón flotante circular de WhatsApp -- mismo número/link (wa.me) que ya
/// se usa en el resto de la app (Perfil, panel Domiciliario, panel Ventas).
/// Solo para pantallas de cliente: nunca en Admin, Cocina, Confirmador ni
/// Domiciliario.
class WhatsAppFab extends StatelessWidget {
  const WhatsAppFab({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'whatsapp_fab',
      backgroundColor: const Color(0xFF25D366),
      tooltip: 'Escríbenos por WhatsApp',
      onPressed: () => launchUrl(
        Uri.parse('https://wa.me/573159914624'),
        mode: LaunchMode.externalApplication,
      ),
      child: const LogoWhatsApp(size: 28, color: Colors.white),
    );
  }
}
