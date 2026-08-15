import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

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

    // BottomNavigationBar nativo de Material: toma colores/tipografía de
    // bottomNavigationBarTheme (app_theme.dart) y trae gratis el ripple/
    // highlight táctil que el bottom nav custom anterior no tenía.
    return BottomNavigationBar(
      currentIndex: activeIndex,
      onTap: (i) {
        if (items[i].path != currentRoute) context.go(items[i].path);
      },
      items: [
        for (final item in items)
          BottomNavigationBarItem(icon: Icon(item.icon), label: item.label),
      ],
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
