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
        ],
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: Color(0xFF1a1a1a)),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
      ),
      drawer: _DomiciliarioDrawer(
        currentRoute: currentRoute,
        onLogout: () => auth.logout(),
      ),
      body: body,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drawer
// ─────────────────────────────────────────────────────────────────────────────

class _DomiciliarioDrawer extends StatelessWidget {
  final String currentRoute;
  final VoidCallback onLogout;

  const _DomiciliarioDrawer({
    required this.currentRoute,
    required this.onLogout,
  });

  static const _items = [
    _DrawerItem(
      icon: Icons.local_shipping_outlined,
      label: 'Pedidos',
      path: '/domiciliario/pedidos',
    ),
    _DrawerItem(
      icon: Icons.attach_money,
      label: 'Total del día',
      path: '/domiciliario/caja',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // ── Header (logo + nombre + borde rojo, igual React) ──
            Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.primary, width: 2)),
              ),
              child: Row(
                children: [
                  Image.network(
                    'https://res.cloudinary.com/dnoxlv5kn/image/upload/v1778822634/logo_sin_fondo_remove_uuu8tt.png',
                    width: 36,
                    height: 36,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'ChocoFreseo',
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1a1a1a),
                    ),
                  ),
                ],
              ),
            ),
            // ── Nav ─────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 16),
                children: [
                  ..._items.map((item) {
                    final activo = currentRoute.startsWith(item.path);
                    return _DrawerTile(
                      icon: item.icon,
                      label: item.label,
                      activo: activo,
                      onTap: () {
                        Navigator.pop(context);
                        context.go(item.path);
                      },
                    );
                  }),
                ],
              ),
            ),

            // ── Footer "ChocoFreseo © 2026" (igual que React) ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
              ),
              child: Text(
                'ChocoFreseo © 2026',
                style: GoogleFonts.nunito(
                    fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFFBBBBBB)),
              ),
            ),

            // ── Cerrar sesión ────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  onLogout();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.logout_rounded, size: 18, color: AppColors.error),
                      const SizedBox(width: 8),
                      Text(
                        'Cerrar sesión',
                        style: GoogleFonts.nunito(
                            fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.error),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem {
  final IconData icon;
  final String label;
  final String path;
  const _DrawerItem({required this.icon, required this.label, required this.path});
}

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool activo;
  final VoidCallback onTap;

  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.activo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      decoration: BoxDecoration(
        color: activo ? const Color(0xFFFFF5F5) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        children: [
          ListTile(
            leading: Icon(
              icon,
              size: 18,
              color: activo ? AppColors.primary : const Color(0xFF888888),
            ),
            title: Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: activo ? FontWeight.w800 : FontWeight.w600,
                color: activo ? AppColors.primary : const Color(0xFF888888),
              ),
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onTap: onTap,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
            dense: true,
          ),
          // Indicador izquierdo (React: border-left: 3px solid #CA0B0B)
          if (activo)
            Positioned(
              left: 0, top: 0, bottom: 0,
              child: Container(
                width: 3,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(10),
                    bottomLeft: Radius.circular(10),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
