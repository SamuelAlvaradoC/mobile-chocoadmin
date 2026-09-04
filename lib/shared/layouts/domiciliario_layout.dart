import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../features/auth/providers/auth_provider.dart';

const _kLogoUrl =
    'https://res.cloudinary.com/dnoxlv5kn/image/upload/v1778822634/logo_sin_fondo_remove_uuu8tt.png';

/// AppBar compartido por Pedidos y Caja del día. El bottom nav ya no vive
/// aquí -- lo provee RootShellScaffold a nivel del StatefulShellRoute (ver
/// DomiciliarioBottomNav más abajo), para que cada tab tenga su propio
/// Navigator independiente.
class DomiciliarioLayout extends StatefulWidget {
  final Widget body;
  final Future<void> Function()? onRefresh;

  const DomiciliarioLayout({
    super.key,
    required this.body,
    this.onRefresh,
  });

  @override
  State<DomiciliarioLayout> createState() => _DomiciliarioLayoutState();
}

class _DomiciliarioLayoutState extends State<DomiciliarioLayout> {
  bool _refrescando = false;

  Future<void> _refrescar() async {
    if (widget.onRefresh == null || _refrescando) return;
    setState(() => _refrescando = true);
    try {
      await widget.onRefresh!();
    } finally {
      if (mounted) setState(() => _refrescando = false);
    }
  }

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
          if (widget.onRefresh != null)
            IconButton(
              icon: _refrescando
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1a1a1a)),
                    )
                  : const Icon(Icons.refresh_rounded, color: Color(0xFF1a1a1a)),
              tooltip: 'Refrescar',
              onPressed: _refrescando ? null : _refrescar,
            ),
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
      body: widget.body,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom nav — vive a nivel de shell (RootShellScaffold), no dentro de cada
// pantalla. Recibe el StatefulNavigationShell del StatefulShellRoute en vez
// de un currentRoute string.
// ─────────────────────────────────────────────────────────────────────────────

class DomiciliarioBottomNav extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const DomiciliarioBottomNav({super.key, required this.navigationShell});

  static const _items = [
    _NavItem(icon: Icons.local_shipping_outlined, activeIcon: Icons.local_shipping_rounded, label: 'Pedidos'),
    _NavItem(icon: Icons.payments_outlined, activeIcon: Icons.payments_rounded, label: 'Caja del día'),
  ];

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: navigationShell.currentIndex,
      onTap: (i) => navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex),
      items: [
        for (final item in _items)
          BottomNavigationBarItem(
            icon: Icon(item.icon),
            activeIcon: Icon(item.activeIcon),
            label: item.label,
          ),
      ],
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem({required this.icon, required this.activeIcon, required this.label});
}
