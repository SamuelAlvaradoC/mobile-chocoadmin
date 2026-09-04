import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../features/auth/providers/auth_provider.dart';

/// AppBar compartido por Dashboard y Ventas (avatar/nombre + Tienda/Salir).
/// El bottom nav ya no vive aquí -- lo provee RootShellScaffold a nivel del
/// StatefulShellRoute de Admin, para que Dashboard/Productos/Ventas tengan
/// cada uno su propio Navigator independiente.
class AdminLayout extends StatefulWidget {
  final Widget body;
  final Future<void> Function()? onRefresh;

  const AdminLayout({
    super.key,
    required this.body,
    this.onRefresh,
  });

  @override
  State<AdminLayout> createState() => _AdminLayoutState();
}

class _AdminLayoutState extends State<AdminLayout> {
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
    final user = context.watch<AuthProvider>().user;
    final nombre = user?.nombre ?? 'Admin';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Container(
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
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      // Avatar + nombre
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
                          style: GoogleFonts.nunito(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
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
                      if (widget.onRefresh != null) ...[
                        GestureDetector(
                          onTap: _refrescar,
                          child: Container(
                            width: 34,
                            height: 34,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: _refrescando
                                ? const SizedBox(
                                    width: 15, height: 15,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF555555)),
                                  )
                                : const Icon(Icons.refresh_rounded, size: 18, color: Color(0xFF555555)),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      _TopBtn(
                        label: 'Tienda',
                        icon: Icons.store_outlined,
                        bg: const Color(0xFFF5F5F5),
                        fg: const Color(0xFF555555),
                        onTap: () => context.go('/landing'),
                      ),
                      const SizedBox(width: 8),
                      _TopBtn(
                        label: 'Salir',
                        icon: Icons.logout_rounded,
                        bg: const Color(0xFF1a1a1a),
                        fg: Colors.white,
                        onTap: () => context.read<AuthProvider>().logout(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: widget.body,
    );
  }
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
