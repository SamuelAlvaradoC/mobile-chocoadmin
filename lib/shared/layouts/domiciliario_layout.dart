import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../features/auth/providers/auth_provider.dart';

const _kLogoUrl =
    'https://res.cloudinary.com/dnoxlv5kn/image/upload/v1778822634/logo_sin_fondo_remove_uuu8tt.png';

class DomiciliarioLayout extends StatelessWidget {
  final Widget body;
  final String currentRoute;

  const DomiciliarioLayout({
    super.key,
    required this.body,
    required this.currentRoute,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FD),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1a1a1a),
        elevation: 0,
        surfaceTintColor: Colors.white,
        shadowColor: const Color(0xFFF0F0F0),
        scrolledUnderElevation: 1,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            CachedNetworkImage(
              imageUrl: _kLogoUrl,
              width: 32, height: 32, fit: BoxFit.contain,
              placeholder: (_, __) => const SizedBox(width: 32, height: 32),
              errorWidget: (_, __, ___) => const SizedBox(width: 32, height: 32),
            ),
            const SizedBox(width: 8),
            Text('ChocoFreseo',
                style: GoogleFonts.nunito(
                    fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a))),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.store_outlined, color: Color(0xFF1a1a1a)),
            tooltip: 'Ir a la tienda',
            onPressed: () => context.go('/landing'),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppColors.error),
            tooltip: 'Cerrar sesión',
            onPressed: () => auth.logout(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: _DomiciliarioBottomNav(currentRoute: currentRoute),
      body: body,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom nav — reemplaza el Drawer/hamburguesa (solo 2 destinos: Pedidos y
// Caja del día, caben perfecto como bottom nav en vez de sidebar web).
// ─────────────────────────────────────────────────────────────────────────────

class _DomiciliarioBottomNav extends StatelessWidget {
  final String currentRoute;
  const _DomiciliarioBottomNav({required this.currentRoute});

  static const _items = [
    _NavItem(icon: Icons.local_shipping_outlined, activeIcon: Icons.local_shipping_rounded, label: 'Pedidos', path: '/domiciliario/pedidos'),
    _NavItem(icon: Icons.payments_outlined, activeIcon: Icons.payments_rounded, label: 'Caja del día', path: '/domiciliario/caja'),
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
                    active: currentRoute.startsWith(item.path),
                    onTap: () {
                      if (!currentRoute.startsWith(item.path)) context.go(item.path);
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
  final IconData activeIcon;
  final String label;
  final String path;
  const _NavItem({required this.icon, required this.activeIcon, required this.label, required this.path});
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
          Icon(active ? item.activeIcon : item.icon, color: color, size: 24),
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
