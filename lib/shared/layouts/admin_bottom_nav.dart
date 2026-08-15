import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';

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
      isActive: (r) => r == '/admin/categorias' || r == '/admin/productos' || r == '/admin/toppings' || r == '/admin/adiciones',
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
              for (final item in _items)
                Expanded(
                  child: _NavButton(
                    item: item,
                    active: item.isActive(currentRoute),
                    onTap: () {
                      if (!item.isActive(currentRoute)) context.go(item.path);
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

class _NavItem {
  final IconData icon;
  final String label;
  final String path;
  final bool Function(String currentRoute) isActive;
  const _NavItem({required this.icon, required this.label, required this.path, required this.isActive});
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
          Icon(item.icon, color: color, size: 23),
          const SizedBox(height: 3),
          Text(
            item.label,
            style: GoogleFonts.nunito(fontSize: 10.5, fontWeight: active ? FontWeight.w800 : FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}
