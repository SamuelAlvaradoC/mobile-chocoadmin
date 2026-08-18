import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../widgets/brand_icons.dart';
import 'client_bottom_nav.dart' show ClientVolverAlPanelAction, ClientLogoutAction;

/// AppBar nativo de Landing -- antes era un navbar tipo web (links de
/// escritorio + menú hamburguesa con drawer) heredado del port de React,
/// inconsistente con el resto de la app (AppBar + bottom nav nativos, sin
/// hamburguesa en ningún otro lado). Se reemplaza por lo mismo que usa
/// Catálogo: logo + "ChocoFreseo", el ícono de "volver a mi panel" si el
/// usuario es staff, y el de cerrar sesión -- Landing ya es un branch del
/// bottom nav (pestaña "Inicio"), así que no necesita su propio acceso de
/// vuelta al inicio.
class ClientLayout extends StatelessWidget {
  final Widget child;
  const ClientLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: 'https://res.cloudinary.com/dnoxlv5kn/image/upload/v1778822634/logo_sin_fondo_remove_uuu8tt.png',
                width: 28,
                height: 28,
                fit: BoxFit.contain,
                placeholder: (_, __) => const SizedBox(width: 28, height: 28),
                errorWidget: (_, __, ___) => const SizedBox(width: 28, height: 28),
              ),
            ),
            const SizedBox(width: 8),
            const Text('ChocoFreseo'),
          ],
        ),
        actions: const [ClientVolverAlPanelAction(), ClientLogoutAction()],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            child,
            const _Footer(),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Footer
// ─────────────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer();

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1a1a1a),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Marca -- en su propia fila (antes competía por espacio en
                // el mismo Wrap que las otras 3 columnas, y al ser la más
                // ancha las empujaba a apilarse una debajo de la otra).
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: 'https://res.cloudinary.com/dnoxlv5kn/image/upload/v1778822634/logo_sin_fondo_remove_uuu8tt.png',
                        width: 36,
                        height: 36,
                        fit: BoxFit.contain,
                        placeholder: (_, __) => Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                          alignment: Alignment.center,
                          child: Text('CF', style: GoogleFonts.nunito(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                          alignment: Alignment.center,
                          child: Text('CF', style: GoogleFonts.nunito(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('ChocoFreseo',
                        style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Postres con estética juvenil y sabores únicos. Puro Freseo desde marzo 2024.',
                  style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.5), height: 1.7),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SocialBtn(
                      icon: const LogoInstagram(size: 18, color: Colors.white),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [Color(0xFF833AB4), Color(0xFFFD1D1D), Color(0xFFF77737)],
                      ),
                      onTap: () => _launch('https://instagram.com/chocofreseo'),
                    ),
                    _SocialBtn(icon: const LogoTikTok(size: 18, color: Colors.white), color: const Color(0xFF000000), onTap: () => _launch('https://tiktok.com/@chocofreseo')),
                    _SocialBtn(icon: const LogoTikTok(size: 18, color: Colors.white), color: const Color(0xFF000000), onTap: () => _launch('https://tiktok.com/@sorprendetupaladar')),
                    _SocialBtn(icon: const LogoFacebook(size: 18, color: Colors.white), color: const Color(0xFF1877F2), onTap: () => _launch('https://www.facebook.com/share/1NiKgTtfUb/')),
                    _SocialBtn(icon: const LogoWhatsApp(size: 18, color: Colors.white), color: const Color(0xFF25D366), onTap: () => _launch('https://wa.me/573159914624')),
                  ],
                ),

                const SizedBox(height: 36),

                // Navegación / Sedes / Horario -- grilla de 2 columnas con
                // ancho calculado en vez de columnas de 160 fijas (que en
                // la mayoría de celulares no alcanzaban a poner 2 por fila
                // y terminaban una debajo de la otra).
                LayoutBuilder(
                  builder: (context, constraints) {
                    const spacing = 24.0;
                    final colWidth = (constraints.maxWidth - spacing) / 2;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: 32,
                      children: [
                        SizedBox(
                          width: colWidth,
                          child: _FooterCol(
                            titulo: 'Navegación',
                            children: const [
                              _FooterLink(label: 'Inicio',         path: '/landing'),
                              _FooterLink(label: 'Catálogo',       path: '/catalogo'),
                              _FooterLink(label: 'Iniciar sesión', path: '/login'),
                              _FooterLink(label: 'Registrarse',    path: '/register'),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: colWidth,
                          child: _FooterCol(
                            titulo: 'Nuestras sedes',
                            children: const [
                              _FooterContactItem(icon: Icons.location_on_outlined, text: 'La Milagrosa\nCarrera 29 #42-49, Medellín'),
                              _FooterContactItem(icon: Icons.location_on_outlined, text: 'Aranjuez\nCalle 90 #50D-35, Medellín'),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: colWidth,
                          child: _FooterCol(
                            titulo: 'Horario y contacto',
                            children: [
                              const _FooterHorario(dia: 'Todos los días', hora: '1:00 PM — 8:00 PM'),
                              _FooterContactItem(
                                iconWidget: const LogoWhatsApp(size: 14, color: Color(0xFF25D366)),
                                text: '315-991-46-24',
                                onTap: () => _launch('https://wa.me/573159914624'),
                              ),
                              const _FooterContactItem(icon: Icons.email_outlined,  text: 'chocofreseo@gmail.com'),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),

          // Bottom
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08)))),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              children: [
                Text('© 2026 ChocoFreseo. Todos los derechos reservados.',
                    style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.3))),
                Text('ChocoFreseo es Puro Freseo',
                    style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.3))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SocialBtn extends StatelessWidget {
  final Widget icon;
  final VoidCallback onTap;
  final Color? color;
  final Gradient? gradient;

  const _SocialBtn({required this.icon, required this.onTap, this.color, this.gradient});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: gradient == null ? (color ?? Colors.white.withValues(alpha: 0.12)) : null,
          gradient: gradient,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: icon,
      ),
    );
  }
}

class _FooterCol extends StatelessWidget {
  final String titulo;
  final List<Widget> children;

  const _FooterCol({required this.titulo, required this.children});

  @override
  Widget build(BuildContext context) {
    // El ancho ya lo controla el SizedBox del LayoutBuilder que envuelve
    // cada columna (client_layout.dart) -- acá solo el contenido.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo,
            style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5)),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

class _FooterLink extends StatelessWidget {
  final String label;
  final String path;

  const _FooterLink({required this.label, required this.path});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => context.go(path),
        child: Text(label,
            style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.5))),
      ),
    );
  }
}

class _FooterContactItem extends StatelessWidget {
  final IconData? icon;
  final Widget? iconWidget;
  final String text;
  final VoidCallback? onTap;

  const _FooterContactItem({this.icon, this.iconWidget, required this.text, this.onTap});

  @override
  Widget build(BuildContext context) {
    final fila = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        iconWidget ?? Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.4)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.5))),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: onTap != null ? GestureDetector(onTap: onTap, child: fila) : fila,
    );
  }
}

class _FooterHorario extends StatelessWidget {
  final String dia;
  final String hora;

  const _FooterHorario({required this.dia, required this.hora});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dia,  style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.4))),
          Text(hora, style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}
