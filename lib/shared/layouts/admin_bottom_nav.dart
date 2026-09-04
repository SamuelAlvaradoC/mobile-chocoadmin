import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bottom nav nativo del rol Administrador. 5 destinos: Dashboard, Productos,
/// Ventas, Confirmar pedidos y Panel Cocina.
///
/// Solo los primeros 3 son branches reales de un StatefulShellRoute (cada
/// uno con su propio Navigator). Confirmar pedidos y Panel Cocina son
/// pantallas COMPARTIDAS con los roles confirmador/cocina (que no tienen
/// bottom nav) — go_router exige una ruta única por path, así que no pueden
/// ser branches del shell de admin a la vez que rutas planas para esos
/// otros roles. Se quedan como rutas planas para todos, y el admin las
/// alcanza con context.go (sale del shell), igual que cualquier navegación
/// a una ruta fuera de un shell.
///
/// Por eso este widget tiene dos modos:
/// - Dentro del shell (Dashboard/Productos/Ventas): se le pasa
///   [navigationShell] y los taps sobre esos 3 usan goBranch().
/// - Fuera del shell (parado en /cocina o /admin/domicilios como admin): se
///   le pasa [currentRoute] y TODOS los taps usan context.go(), incluyendo
///   Dashboard/Productos/Ventas (que re-entran al shell desde cero).
class AdminBottomNav extends StatelessWidget {
  final StatefulNavigationShell? navigationShell;
  final String? currentRoute;

  const AdminBottomNav.shell({super.key, required StatefulNavigationShell this.navigationShell})
      : currentRoute = null;

  const AdminBottomNav.flat({super.key, required String this.currentRoute})
      : navigationShell = null;

  static const _items = [
    _NavItem(icon: Icons.dashboard_rounded, label: 'Dashboard', path: '/admin/dashboard', branchIndex: 0),
    _NavItem(icon: Icons.shopping_bag_rounded, label: 'Productos', path: '/admin/productos', branchIndex: 1),
    _NavItem(icon: Icons.receipt_long_rounded, label: 'Ventas', path: '/admin/ventas', branchIndex: 2),
    _NavItem(icon: Icons.check_circle_rounded, label: 'Confirmar', path: '/admin/domicilios', branchIndex: null),
    _NavItem(icon: Icons.restaurant_menu_rounded, label: 'Cocina', path: '/cocina', branchIndex: null),
  ];

  @override
  Widget build(BuildContext context) {
    final shell = navigationShell;
    // Dentro del shell, Confirmar/Cocina (branchIndex null) nunca están
    // activos -- si estuvieras ahí, no estarías dentro del shell.
    final activeIndex = shell != null
        ? shell.currentIndex
        : _items.indexWhere((i) => i.path == currentRoute).clamp(0, _items.length - 1);

    return BottomNavigationBar(
      currentIndex: activeIndex,
      onTap: (i) {
        final item = _items[i];
        if (shell != null && item.branchIndex != null) {
          shell.goBranch(item.branchIndex!, initialLocation: item.branchIndex == shell.currentIndex);
        } else if (item.path != currentRoute) {
          context.go(item.path);
        }
      },
      items: [
        for (final item in _items)
          BottomNavigationBarItem(icon: Icon(item.icon), label: item.label),
      ],
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final String path;
  final int? branchIndex;
  const _NavItem({required this.icon, required this.label, required this.path, required this.branchIndex});
}
