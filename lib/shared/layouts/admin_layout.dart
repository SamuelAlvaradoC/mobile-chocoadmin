import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/auth_service.dart' show UserRole;
import '../../features/auth/providers/auth_provider.dart';

class AdminLayout extends StatefulWidget {
  final Widget body;
  final String currentRoute;

  const AdminLayout({
    super.key,
    required this.body,
    required this.currentRoute,
  });

  @override
  State<AdminLayout> createState() => _AdminLayoutState();
}

class _AdminLayoutState extends State<AdminLayout> {
  // Misma estructura que React Sidebar.jsx (menu[]). React filtra por permiso
  // exacto vía tienePermiso(); Flutter no tiene esa infraestructura de permisos
  // todavía, así que se filtra por rol como aproximación: admin ve todo,
  // confirmador_domicilio solo ve "Confirmar pedidos".
  static const _menuCompleto = [
    _MenuItem(icon: Icons.dashboard_rounded, label: 'Dashboard', path: '/admin/dashboard'),
    _MenuItem(icon: Icons.shopping_bag_rounded, label: 'Productos', hijos: [
      _MenuItem(label: 'Categorías', path: '/admin/categorias'),
      _MenuItem(label: 'Productos',  path: '/admin/productos'),
      _MenuItem(label: 'Toppings',   path: '/admin/toppings'),
      _MenuItem(label: 'Adiciones',  path: '/admin/adiciones'),
    ]),
    _MenuItem(icon: Icons.receipt_long_rounded, label: 'Ventas', path: '/admin/ventas'),
    _MenuItem(icon: Icons.check_circle_rounded, label: 'Confirmar pedidos', path: '/admin/domicilios'),
    _MenuItem(icon: Icons.restaurant_menu_rounded, label: 'Panel Cocina', path: '/cocina'),
  ];

  static const _menuConfirmador = [
    _MenuItem(icon: Icons.check_circle_rounded, label: 'Confirmar pedidos', path: '/admin/domicilios'),
  ];

  static const _menuCocina = [
    _MenuItem(icon: Icons.restaurant_menu_rounded, label: 'Panel Cocina', path: '/cocina'),
  ];

  List<_MenuItem> _menuPara(UserRole? role) {
    if (role == UserRole.confirmadorDomicilio) return _menuConfirmador;
    if (role == UserRole.cocina) return _menuCocina;
    return _menuCompleto;
  }

  final Set<String> _gruposAbiertos = {};

  // Fix 2: Spanish role labels matching React ROL_LABELS
  static String _rolLabel(UserRole? role) {
    switch (role) {
      case UserRole.admin:
        return 'Administrador';
      case UserRole.confirmadorDomicilio:
        return 'Confirmador de pedidos';
      case UserRole.cocina:
        return 'Cocinero';
      case UserRole.domiciliario:
        return 'Domiciliario';
      case UserRole.cliente:
        return 'Cliente';
      default:
        return 'Usuario';
    }
  }

  // Fix 4: Panel labels matching React PANEL_LABELS
  static String _panelLabel(UserRole? role) {
    switch (role) {
      case UserRole.admin:
        return 'PANEL ADMIN';
      case UserRole.confirmadorDomicilio:
        return 'PANEL PEDIDOS';
      case UserRole.cocina:
        return 'PANEL COCINA';
      case UserRole.domiciliario:
        return 'PANEL DOMI';
      default:
        return 'PANEL ADMIN';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user    = context.watch<AuthProvider>().user;
    final nombre  = user?.nombre ?? 'Admin';
    final rolNombre = _rolLabel(user?.role);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Builder(
          builder: (ctx) => Container(
            color: Colors.white,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 64,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
                    boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1))],
                    color: Colors.white,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        // Hamburguesa
                        IconButton(
                          icon: const Icon(Icons.menu_rounded, color: Color(0xFF1a1a1a), size: 22),
                          onPressed: () => Scaffold.of(ctx).openDrawer(),
                        ),
                        const SizedBox(width: 4),

                        // Izquierda: nombre del usuario
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              nombre,
                              style: GoogleFonts.nunito(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF1a1a1a),
                                letterSpacing: -0.3,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),

                        // Derecha: avatar + nombre/rol + divider + botones
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Avatar + info
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    nombre.isNotEmpty ? nombre[0].toUpperCase() : 'A',
                                    style: GoogleFonts.nunito(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      nombre,
                                      style: GoogleFonts.nunito(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF1a1a1a),
                                      ),
                                    ),
                                    Text(
                                      rolNombre,
                                      style: GoogleFonts.nunito(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFFAAAAAA),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            const SizedBox(width: 12),
                            Container(width: 1, height: 28, color: const Color(0xFFF0F0F0)),
                            const SizedBox(width: 12),

                            // Fix 5: Hide "Tienda" for domiciliario and cocina roles (matches React)
                            if (user?.role != UserRole.domiciliario && user?.role != UserRole.cocina) ...[
                              _TopBtn(
                                label: 'Tienda',
                                icon: Icons.store_outlined,
                                bg: const Color(0xFFF5F5F5),
                                fg: const Color(0xFF555555),
                                onTap: () => context.go('/landing'),
                              ),
                              const SizedBox(width: 8),
                            ],

                            // Botón Salir
                            _TopBtn(
                              label: 'Salir',
                              icon: Icons.logout_rounded,
                              bg: const Color(0xFF1a1a1a),
                              fg: Colors.white,
                              onTap: () => context.read<AuthProvider>().logout(),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      drawer: _buildDrawer(context),
      body: widget.body,
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final userRole = context.watch<AuthProvider>().user?.role;
    return Drawer(
      width: 220,
      backgroundColor: Colors.white,
      elevation: 0,
      shape: const RoundedRectangleBorder(),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(1, 0))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Logo
            SafeArea(
              bottom: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.primary, width: 2)),
                ),
                child: Row(
                  children: [
                    CachedNetworkImage(
                      imageUrl: 'https://res.cloudinary.com/dnoxlv5kn/image/upload/v1778822634/logo_sin_fondo_remove_uuu8tt.png',
                      width: 36,
                      height: 36,
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) => Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text('CF', style: GoogleFonts.nunito(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ChocoFreseo',
                          style: GoogleFonts.nunito(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1a1a1a),
                          ),
                        ),
                        // Fix 4: Dynamic panel label based on role
                        Text(
                          _panelLabel(userRole),
                          style: GoogleFonts.nunito(
                            fontSize: 9,
                            color: const Color(0xFF999999),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Nav
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: _menuPara(context.watch<AuthProvider>().user?.role)
                    .map((item) => _buildMenuGroup(context, item))
                    .toList(),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ChocoFreseo © 2026',
                      style: GoogleFonts.nunito(fontSize: 11, color: const Color(0xFFBBBBBB), fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('v1.0.0',
                      style: GoogleFonts.nunito(fontSize: 10, color: const Color(0xFFDDDDDD))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuGroup(BuildContext context, _MenuItem item) {
    if (item.hijos.isEmpty) {
      final active = widget.currentRoute == item.path;
      return _NavLink(
        icon: item.icon,
        label: item.label,
        active: active,
        onTap: () {
          Navigator.pop(context);
          context.go(item.path!);
        },
      );
    }

    final tieneHijoActivo = item.hijos.any((h) => widget.currentRoute == h.path);
    final abierto = _gruposAbiertos.contains(item.label) || tieneHijoActivo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() {
            if (_gruposAbiertos.contains(item.label)) {
              _gruposAbiertos.remove(item.label);
            } else {
              _gruposAbiertos.add(item.label);
            }
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 10),
            child: Row(
              children: [
                Icon(item.icon, size: 18, color: tieneHijoActivo ? AppColors.primary : const Color(0xFF888888)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(item.label,
                      style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w600,
                          color: tieneHijoActivo ? const Color(0xFF1a1a1a) : const Color(0xFF888888))),
                ),
                Icon(abierto ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                    size: 16, color: abierto ? AppColors.primary : const Color(0xFFCCCCCC)),
              ],
            ),
          ),
        ),
        if (abierto)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 12, bottom: 4),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(8),
                border: const Border(left: BorderSide(color: Color(0xFFF0E0E0), width: 2)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: item.hijos.map((hijo) {
                  final active = widget.currentRoute == hijo.path;
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      context.go(hijo.path!);
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: active ? const Color(0xFFFFF5F5) : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(children: [
                        Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(shape: BoxShape.circle, color: active ? AppColors.primary : const Color(0xFFDDDDDD))),
                        Text(hijo.label, style: GoogleFonts.nunito(fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                            color: active ? AppColors.primary : const Color(0xFF888888))),
                      ]),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data classes
// ─────────────────────────────────────────────────────────────────────────────

class _MenuItem {
  final IconData? icon;
  final String label;
  final String? path;
  final List<_MenuItem> hijos;
  const _MenuItem({this.icon, required this.label, this.path, this.hijos = const []});
}

// ─────────────────────────────────────────────────────────────────────────────
// Topbar button
// ─────────────────────────────────────────────────────────────────────────────

class _TopBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  const _TopBtn({required this.label, required this.icon, required this.bg, required this.fg, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
            Text(label, style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nav link (item sin hijos)
// ─────────────────────────────────────────────────────────────────────────────

class _NavLink extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavLink({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFFF5F5) : Colors.transparent,
          border: active
              ? const Border(left: BorderSide(color: AppColors.primary, width: 3))
              : const Border(left: BorderSide(color: Colors.transparent, width: 3)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: active ? AppColors.primary : const Color(0xFF888888)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: active ? AppColors.primary : const Color(0xFF888888),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

