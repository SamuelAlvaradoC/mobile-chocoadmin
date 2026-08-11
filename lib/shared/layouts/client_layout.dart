import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/auth_service.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/cliente/providers/carrito_provider.dart';
import '../widgets/brand_icons.dart';

/// Navbar standalone reutilizable para pantallas que no usan ClientLayout completo.
class ClientNavbar extends StatefulWidget {
  final String currentRoute;
  const ClientNavbar({super.key, required this.currentRoute});

  @override
  State<ClientNavbar> createState() => _ClientNavbarState();
}

class _ClientNavbarState extends State<ClientNavbar> {
  bool _menuAbierto = false;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return _Navbar(
      user: user,
      menuAbierto: _menuAbierto,
      onToggleMenu: () => setState(() => _menuAbierto = !_menuAbierto),
      onLogout: () {
        context.read<AuthProvider>().logout();
        context.read<CarritoProvider>().limpiar();
        setState(() => _menuAbierto = false);
      },
      currentRoute: widget.currentRoute,
    );
  }
}

class ClientLayout extends StatefulWidget {
  final Widget child;
  const ClientLayout({super.key, required this.child});

  @override
  State<ClientLayout> createState() => _ClientLayoutState();
}

class _ClientLayoutState extends State<ClientLayout> {
  bool _menuAbierto = false;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ── Navbar ────────────────────────────────────────────────────
            _Navbar(
              user: user,
              menuAbierto: _menuAbierto,
              onToggleMenu: () => setState(() => _menuAbierto = !_menuAbierto),
              onLogout: () {
                context.read<AuthProvider>().logout();
                setState(() => _menuAbierto = false);
              },
              currentRoute: GoRouterState.of(context).uri.path,
            ),

            // ── Contenido + Footer ────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    widget.child,
                    const _Footer(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Navbar
// ─────────────────────────────────────────────────────────────────────────────

class _Navbar extends StatelessWidget {
  final AuthUser? user;
  final bool menuAbierto;
  final VoidCallback onToggleMenu;
  final VoidCallback onLogout;
  final String currentRoute;

  const _Navbar({
    required this.user,
    required this.menuAbierto,
    required this.onToggleMenu,
    required this.onLogout,
    required this.currentRoute,
  });

  static const _links = [
    _NavLink(label: 'Inicio',    path: '/landing'),
    _NavLink(label: 'Catálogo',  path: '/catalogo'),
    _NavLink(label: 'Nosotros',  path: '/landing'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 1))],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  // Logo
                  GestureDetector(
                    onTap: () => context.go('/landing'),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: 'https://res.cloudinary.com/dnoxlv5kn/image/upload/v1778822634/logo_sin_fondo_remove_uuu8tt.png',
                            width: 38,
                            height: 38,
                            fit: BoxFit.contain,
                            placeholder: (_, __) => Container(
                              width: 38, height: 38,
                              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                              alignment: Alignment.center,
                              child: Text('CF', style: GoogleFonts.nunito(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              width: 38, height: 38,
                              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                              alignment: Alignment.center,
                              child: Text('CF', style: GoogleFonts.nunito(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text('ChocoFreseo',
                            style: GoogleFonts.nunito(fontSize: 17, fontWeight: FontWeight.w900, color: const Color(0xFF1a1a1a))),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Links (solo si hay espacio suficiente — tablet/desktop)
                  if (MediaQuery.of(context).size.width > 600)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ..._links.map((l) => _NavLinkBtn(
                              label: l.label,
                              active: currentRoute == l.path,
                              onTap: () => context.go(l.path),
                            )),
                        if (user?.role == UserRole.admin)
                          _NavLinkBtn(
                            label: 'Panel Admin',
                            active: false,
                            onTap: () => context.go('/admin/dashboard'),
                            color: AppColors.primary,
                          ),
                        if (user?.role == UserRole.domiciliario)
                          _NavLinkBtn(
                            label: 'Panel Domiciliario',
                            active: false,
                            onTap: () => context.go('/domiciliario/pedidos'),
                          ),
                        if (user?.role == UserRole.confirmadorDomicilio)
                          _NavLinkBtn(
                            label: 'Confirmar Pedidos',
                            active: false,
                            onTap: () => context.go('/admin/domicilios'),
                            color: AppColors.primary,
                          ),
                        if (user?.role == UserRole.cocina)
                          _NavLinkBtn(
                            label: 'Panel Cocina',
                            active: false,
                            onTap: () => context.go('/cocina'),
                          ),
                        const SizedBox(width: 16),
                      ],
                    ),

                  // Acciones
                  if (MediaQuery.of(context).size.width > 600)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (user != null) ...[
                          GestureDetector(
                            onTap: () => context.go('/perfil'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFE0E0E0), width: 1.5),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Icon(Icons.person_rounded, color: Colors.white, size: 16),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(user?.nombre ?? '',
                                      style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF1a1a1a))),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: onLogout,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFE0E0E0), width: 1.5),
                              ),
                              child: Text('Cerrar sesión',
                                  style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF1a1a1a))),
                            ),
                          ),
                        ] else ...[
                          GestureDetector(
                            onTap: () => context.go('/login'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFE0E0E0), width: 1.5),
                              ),
                              child: Text('Iniciar sesión',
                                  style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF1a1a1a))),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () => context.go('/register'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('Registrarse',
                                  style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                            ),
                          ),
                        ],
                      ],
                    ),

                  // Hamburguesa (mobile)
                  if (MediaQuery.of(context).size.width <= 600)
                    IconButton(
                      onPressed: onToggleMenu,
                      icon: Icon(menuAbierto ? Icons.close_rounded : Icons.menu_rounded, color: const Color(0xFF333333), size: 22),
                    ),
                ],
              ),
            ),
          ),

          // Mobile menu
          if (menuAbierto && MediaQuery.of(context).size.width <= 600)
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ..._links.map((l) => _MobileLink(
                        label: l.label,
                        onTap: () {
                          onToggleMenu();
                          context.go(l.path);
                        },
                      )),
                  if (user != null) ...[
                    if (user?.role == UserRole.admin)
                      _MobileLink(label: 'Panel Administrador', onTap: () { onToggleMenu(); context.go('/admin/dashboard'); }),
                    if (user?.role == UserRole.domiciliario)
                      _MobileLink(label: 'Panel Domiciliario', onTap: () { onToggleMenu(); context.go('/domiciliario/pedidos'); }),
                    if (user?.role == UserRole.confirmadorDomicilio)
                      _MobileLink(label: 'Confirmar Pedidos', onTap: () { onToggleMenu(); context.go('/admin/domicilios'); }),
                    if (user?.role == UserRole.cocina)
                      _MobileLink(label: 'Panel Cocina', onTap: () { onToggleMenu(); context.go('/cocina'); }),
                    _MobileLink(label: 'Mi perfil', onTap: () {
                      onToggleMenu();
                      context.go('/perfil');
                    }),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: onLogout,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE0E0E0), width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: Text('Cerrar sesión',
                            style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1a1a1a))),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () { onToggleMenu(); context.go('/login'); },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFE0E0E0), width: 1.5),
                              ),
                              alignment: Alignment.center,
                              child: Text('Iniciar sesión',
                                  style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF1a1a1a))),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: () { onToggleMenu(); context.go('/register'); },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text('Registrarse',
                                  style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NavLink {
  final String label;
  final String path;
  const _NavLink({required this.label, required this.path});
}

class _NavLinkBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? color;

  const _NavLinkBtn({required this.label, required this.active, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? (active ? AppColors.primary : const Color(0xFF666666));
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w700, color: c)),
            const SizedBox(height: 2),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 2,
              width: active ? 100 : 0,
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _MobileLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF5F5F5)))),
        child: Text(label, style: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF444444))),
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
            child: Wrap(
              spacing: 32,
              runSpacing: 32,
              children: [
                // Marca
                SizedBox(
                  width: 260,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      const SizedBox(height: 16),
                      Text(
                        'Postres con estética juvenil y sabores únicos. Puro Freseo desde marzo 2024.',
                        style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.5), height: 1.7),
                      ),
                      const SizedBox(height: 20),
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
                    ],
                  ),
                ),

                // Navegación
                _FooterCol(
                  titulo: 'Navegación',
                  children: const [
                    _FooterLink(label: 'Inicio',         path: '/landing'),
                    _FooterLink(label: 'Catálogo',       path: '/catalogo'),
                    _FooterLink(label: 'Iniciar sesión', path: '/login'),
                    _FooterLink(label: 'Registrarse',    path: '/register'),
                  ],
                ),

                // Nuestras sedes
                _FooterCol(
                  titulo: 'Nuestras sedes',
                  children: const [
                    _FooterContactItem(icon: Icons.location_on_outlined, text: 'La Milagrosa\nCarrera 29 #42-49, Medellín'),
                    _FooterContactItem(icon: Icons.location_on_outlined, text: 'Aranjuez\nCalle 90 #50D-35, Medellín'),
                  ],
                ),

                // Horario y contacto
                _FooterCol(
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
    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
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
