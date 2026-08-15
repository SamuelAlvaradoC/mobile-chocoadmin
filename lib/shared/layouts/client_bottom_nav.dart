import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/auth_service.dart' show UserRole;
import '../../features/auth/providers/auth_provider.dart';

/// Bottom nav nativo para las 3 pantallas raíz del cliente (Catálogo, Puntos,
/// Perfil) — reemplaza el ClientNavbar (navbar web con hamburguesa) que
/// tenían estas pantallas. Misma lista de destinos que antes ofrecía el
/// navbar según el estado de auth, solo que como barra inferior:
/// - Sin sesión: Catálogo + Iniciar sesión (antes: botones "Iniciar sesión"/
///   "Registrarse" del navbar).
/// - Con sesión: Catálogo + Puntos + Perfil (antes: avatar → /perfil +
///   PerfilScreen mostraba la card de puntos).
class ClientBottomNav extends StatelessWidget {
  final String currentRoute;
  const ClientBottomNav({super.key, required this.currentRoute});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    final items = <_NavItem>[
      const _NavItem(icon: Icons.storefront_rounded, label: 'Catálogo', path: '/catalogo'),
      if (user != null) ...[
        const _NavItem(icon: Icons.stars_rounded, label: 'Puntos', path: '/puntos'),
        const _NavItem(icon: Icons.person_rounded, label: 'Perfil', path: '/perfil'),
      ] else
        const _NavItem(icon: Icons.login_rounded, label: 'Ingresar', path: '/login'),
    ];

    final activeIndex = items.indexWhere((i) => i.path == currentRoute).clamp(0, items.length - 1);

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
        boxShadow: [BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              for (int i = 0; i < items.length; i++)
                Expanded(
                  child: _NavButton(
                    item: items[i],
                    active: i == activeIndex,
                    onTap: () {
                      if (items[i].path != currentRoute) context.go(items[i].path);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ícono de atajo para volver al panel operativo — solo visible cuando un
/// usuario staff (admin/domiciliario/confirmador/cocina) está navegando la
/// tienda como si fuera cliente. Antes era uno de los botones condicionales
/// del ClientNavbar ("Panel Admin", "Panel Domiciliario", etc.); ahora vive
/// como acción del AppBar de Catálogo para no competir con el bottom nav.
class ClientVolverAlPanelAction extends StatelessWidget {
  const ClientVolverAlPanelAction({super.key});

  static String? _rutaPanel(UserRole? role) {
    switch (role) {
      case UserRole.admin:
        return '/admin/dashboard';
      case UserRole.domiciliario:
        return '/domiciliario/pedidos';
      case UserRole.confirmadorDomicilio:
        return '/admin/domicilios';
      case UserRole.cocina:
        return '/cocina';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().user?.role;
    final ruta = _rutaPanel(role);
    if (ruta == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Volver a mi panel',
      icon: const Icon(Icons.dashboard_customize_rounded),
      onPressed: () => context.go(ruta),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final String path;
  const _NavItem({required this.icon, required this.label, required this.path});
}

class _NavButton extends StatelessWidget {
  final _NavItem item;
  final bool active;
  final VoidCallback onTap;

  const _NavButton({required this.item, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : const Color(0xFF9A9A9A);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, color: color, size: 24),
          const SizedBox(height: 3),
          Text(
            item.label,
            style: GoogleFonts.nunito(fontSize: 11, fontWeight: active ? FontWeight.w800 : FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}
