import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import 'adiciones_screen.dart';
import 'categorias_screen.dart';
import 'productos_screen.dart';
import 'toppings_screen.dart';

/// Módulo "Productos" del admin — une Categorías, Productos, Toppings y
/// Adiciones (antes 4 rutas separadas en el drawer web) en una sola pantalla
/// con un selector de chips, siguiendo el mismo patrón de tab/segmented que
/// ya se usa en otras partes rediseñadas (ej. Perfil de cliente). Las 4
/// sub-pantallas ya no tienen su propio AppBar/Scaffold: comparten el de
/// este módulo, solo aportan su contenido (header interno, lista, buscador).
class ProductosModuloScreen extends StatefulWidget {
  const ProductosModuloScreen({super.key});

  @override
  State<ProductosModuloScreen> createState() => _ProductosModuloScreenState();
}

class _ProductosModuloScreenState extends State<ProductosModuloScreen> {
  int _seleccionado = 1; // arranca en "Productos", el más usado

  static const _secciones = [
    (icon: Icons.category_rounded, label: 'Categorías'),
    (icon: Icons.shopping_bag_rounded, label: 'Productos'),
    (icon: Icons.icecream_rounded, label: 'Toppings'),
    (icon: Icons.add_circle_rounded, label: 'Adiciones'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Productos'),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < _secciones.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _ChipSeccion(
                        icon: _secciones[i].icon,
                        label: _secciones[i].label,
                        active: _seleccionado == i,
                        onTap: () => setState(() => _seleccionado = i),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
          Expanded(
            // IndexedStack mantiene las 4 pantallas montadas: al volver a un
            // chip no se recarga desde cero (conserva scroll, búsqueda, etc.)
            child: IndexedStack(
              index: _seleccionado,
              children: const [
                CategoriasScreen(),
                ProductosScreen(),
                ToppingsScreen(),
                AdicionesScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipSeccion extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ChipSeccion({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Material + InkWell (en vez de GestureDetector) para ripple táctil;
    // ConstrainedBox asegura los ~44px mínimos de alto tocable.
    final radius = BorderRadius.circular(AppSizes.radiusCircle);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Material(
        color: active ? AppColors.primary : AppColors.background,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: active ? AppColors.primary : const Color(0xFFE0E0E0)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: active ? Colors.white : const Color(0xFF888888)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : const Color(0xFF888888),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
