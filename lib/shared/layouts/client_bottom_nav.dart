import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/services/auth_service.dart' show UserRole;
import '../../features/auth/providers/auth_provider.dart';
import '../../features/cliente/providers/carrito_provider.dart';

/// Bottom nav nativo para las 3 pantallas raíz del cliente (Catálogo,
/// Landing/Inicio, Perfil) — cada una vive en su propio branch de un
/// StatefulShellRoute (Navigator independiente por tab, así el historial de
/// "atrás" de cada sección es propio, no uno solo compartido). Puntos vive
/// dentro de Perfil como una pestaña más, no como branch propio. Misma
/// lista de destinos que antes ofrecía el navbar web según el estado de
/// auth:
/// - Sin sesión: Catálogo + Inicio + Iniciar sesión (Iniciar sesión no es
///   un branch del shell, es una ruta plana — sale del shell por completo).
/// - Con sesión: Catálogo + Inicio + Perfil.
class ClientBottomNav extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const ClientBottomNav({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    final items = <_NavItem>[
      const _NavItem(icon: Icons.storefront_rounded, label: 'Catálogo', branchIndex: 0),
      const _NavItem(icon: Icons.home_rounded, label: 'Inicio', branchIndex: 1),
      if (user != null)
        const _NavItem(icon: Icons.person_rounded, label: 'Perfil', branchIndex: 2)
      else
        const _NavItem(icon: Icons.login_rounded, label: 'Ingresar', externalRoute: '/login'),
    ];

    final foundIndex = items.indexWhere((i) => i.branchIndex == navigationShell.currentIndex);
    final activeIndex = foundIndex == -1 ? 0 : foundIndex;

    return BottomNavigationBar(
      currentIndex: activeIndex,
      onTap: (i) {
        final item = items[i];
        if (item.branchIndex != null) {
          navigationShell.goBranch(
            item.branchIndex!,
            initialLocation: item.branchIndex == navigationShell.currentIndex,
          );
        } else if (item.externalRoute != null) {
          context.go(item.externalRoute!);
        }
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

/// Ícono de cerrar sesión para los headers de Landing y Catálogo -- antes
/// solo Perfil ofrecía logout, pero un usuario logueado que nunca entra a
/// Perfil no tenía forma rápida de cerrar sesión desde ahí. Mismo patrón que
/// [ClientVolverAlPanelAction]: solo visible con sesión activa.
class ClientLogoutAction extends StatelessWidget {
  const ClientLogoutAction({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.user == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Cerrar sesión',
      icon: const Icon(Icons.logout_rounded),
      onPressed: () async {
        await auth.logout();
        if (context.mounted) context.read<CarritoProvider>().limpiar();
      },
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final int? branchIndex;
  final String? externalRoute;
  const _NavItem({required this.icon, required this.label, this.branchIndex, this.externalRoute});
}
