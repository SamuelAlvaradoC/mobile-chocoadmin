import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/layouts/admin_layout.dart';
import 'pedidos_screen.dart';
import 'ventas_screen.dart';

/// Módulo "Ventas" del admin — une las pantallas Ventas (historial de
/// entregados) y Pedidos (todo lo demás: pendiente/confirmado/cocina/listo/
/// despachado/anulado, con el wizard de crear venta) en una sola pantalla
/// con un selector de chips, mismo patrón que ProductosModuloScreen. Antes
/// de esto, Pedidos había tomado el cupo de branch del bottom nav que tenía
/// Ventas -- se revirtió: el usuario quiere un solo punto de entrada
/// "Ventas" en la navegación principal, con Ventas/Pedidos como pestañas
/// internas, no dos destinos separados.
///
/// A diferencia de ProductosModuloScreen (Scaffold + AppBar propio), este
/// módulo se envuelve en AdminLayout -- es el mismo top bar (avatar/nombre +
/// Tienda/Salir) que ya usan Dashboard y Pedidos, y es el que Ventas tenía
/// antes de la separación. VentasScreen y AdminPedidosScreen ya no tienen su
/// propio AdminLayout/Scaffold: solo aportan su contenido (header interno,
/// filtros, lista), igual que Categorías/Productos/Toppings/Adiciones dentro
/// del módulo Productos.
class VentasModuloScreen extends StatefulWidget {
  const VentasModuloScreen({super.key});

  @override
  State<VentasModuloScreen> createState() => _VentasModuloScreenState();
}

class _VentasModuloScreenState extends State<VentasModuloScreen> {
  // Arranca en "Ventas" -- es el nombre bajo el que se llega a este módulo
  // desde el bottom nav, así que tocar "Ventas" debe mostrar Ventas primero
  // (mismo comportamiento que tenía antes de existir este módulo).
  int _seleccionado = 0;

  // El IndexedStack de más abajo mantiene ambas pantallas montadas -- una
  // acción en una pestaña (ej. "Devolver a listo" en Ventas) no refresca
  // sola a la otra. Se recarga la pestaña destino cada vez que se le entra,
  // igual que en React una navegación entre /admin/ventas y /admin/pedidos
  // siempre vuelve a pedir los datos.
  Future<void> Function()? _recargarVentas;
  Future<void> Function()? _recargarPedidos;

  void _seleccionar(int i) {
    setState(() => _seleccionado = i);
    if (i == 0) {
      _recargarVentas?.call();
    } else {
      _recargarPedidos?.call();
    }
  }

  static const _secciones = [
    (icon: Icons.payments_outlined, label: 'Ventas'),
    (icon: Icons.receipt_long_rounded, label: 'Pedidos'),
  ];

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                for (int i = 0; i < _secciones.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _ChipVentasPedidos(
                      icon: _secciones[i].icon,
                      label: _secciones[i].label,
                      active: _seleccionado == i,
                      onTap: () => _seleccionar(i),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
          Expanded(
            // IndexedStack mantiene ambas pantallas montadas: al volver a
            // una pestaña no se recarga desde cero (conserva scroll,
            // búsqueda y filtros) -- la recarga de datos la dispara
            // _seleccionar de todas formas, ver comentario arriba.
            child: IndexedStack(
              index: _seleccionado,
              children: [
                VentasScreen(onReady: (fn) => _recargarVentas = fn),
                AdminPedidosScreen(onReady: (fn) => _recargarPedidos = fn),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip de pestaña Ventas/Pedidos -- deliberadamente más chico que
/// _ChipSeccion de ProductosModuloScreen (icono 16/fuente 13/padding
/// 16h·13v/alto mín. 44): acá solo hay 2 opciones en vez de 4, y el usuario
/// pidió explícitamente que se vean con menos protagonismo para que la
/// jerarquía visual quede clara.
class _ChipVentasPedidos extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ChipVentasPedidos({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 34),
      child: Material(
        color: active ? AppColors.primary : Colors.white,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: active ? AppColors.primary : const Color(0xFFE0E0E0)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: active ? Colors.white : const Color(0xFF888888)),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: GoogleFonts.nunito(
                    fontSize: 12,
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
