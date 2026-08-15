import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bottom nav nativo del rol Administrador — reemplaza el Drawer/sidebar web
/// que tenía AdminLayout. 5 destinos: Dashboard, Productos (agrupa
/// Categorías/Productos/Toppings/Adiciones), Ventas, Confirmar pedidos y
/// Panel Cocina.
class AdminBottomNav extends StatelessWidget {
  final String currentRoute;
  const AdminBottomNav({super.key, required this.currentRoute});

  static final _items = [
    _NavItem(
      icon: Icons.dashboard_rounded,
      label: 'Dashboard',
      path: '/admin/dashboard',
      isActive: (r) => r == '/admin/dashboard',
    ),
    _NavItem(
      icon: Icons.shopping_bag_rounded,
      label: 'Productos',
      path: '/admin/productos',
      isActive: (r) => r == '/admin/productos',
    ),
    _NavItem(
      icon: Icons.receipt_long_rounded,
      label: 'Ventas',
      path: '/admin/ventas',
      isActive: (r) => r == '/admin/ventas',
    ),
    _NavItem(
      icon: Icons.check_circle_rounded,
      label: 'Confirmar',
      path: '/admin/domicilios',
      isActive: (r) => r == '/admin/domicilios',
    ),
    _NavItem(
      icon: Icons.restaurant_menu_rounded,
      label: 'Cocina',
      path: '/cocina',
      isActive: (r) => r == '/cocina',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final activeIndex = _items.indexWhere((i) => i.isActive(currentRoute)).clamp(0, _items.length - 1);
    // BottomNavigationBar nativo: trae el ripple/highlight táctil que el
    // bottom nav custom anterior (GestureDetector) no daba. El theme global
    // fuerza type: fixed, así que los 5 items quedan con ancho igual (sin la
    // animación "shifting" que Material usaría por defecto con más de 3).
    return BottomNavigationBar(
      currentIndex: activeIndex,
      onTap: (i) {
        if (!_items[i].isActive(currentRoute)) context.go(_items[i].path);
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
  final bool Function(String currentRoute) isActive;
  const _NavItem({required this.icon, required this.label, required this.path, required this.isActive});
}
