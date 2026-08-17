import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/services/api_service.dart';

/// Pantalla propia para "Mis puntos" — antes era una card fija arriba de
/// Perfil (PerfilScreen), ahora es su propio ítem del bottom nav. Misma
/// llamada a la API (GET /api/puntos/mis-puntos), mismo cálculo de saldo.
class PuntosScreen extends StatefulWidget {
  const PuntosScreen({super.key});

  @override
  State<PuntosScreen> createState() => _PuntosScreenState();
}

class _PuntosScreenState extends State<PuntosScreen> {
  int _puntos = 0;
  double _saldo = 0;
  bool _loading = true;

  final _fmtMoneda = NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.get('/api/puntos/mis-puntos');
      final inner = data is Map && data['data'] is Map ? data['data'] as Map : (data is Map ? data : <String, dynamic>{});
      if (mounted) {
        setState(() {
          _puntos = (inner['puntos'] ?? 0) is int
              ? inner['puntos'] as int
              : int.tryParse(inner['puntos']?.toString() ?? '0') ?? 0;
          _saldo = double.tryParse((inner['saldo_pesos'] ?? (_puntos * 12.5)).toString()) ?? (_puntos * 12.5);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Mis puntos'), centerTitle: true),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.md),
          children: [
            Container(
              padding: const EdgeInsets.all(AppSizes.lg),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, Color(0xFF8B0000)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                boxShadow: [
                  BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: _loading
                  ? const Center(
                      child: SizedBox(height: 40, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('MIS PUNTOS CHOCOFRESEO',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white70, letterSpacing: 1)),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('$_puntos',
                                      style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white, height: 1)),
                                  const Text('puntos disponibles', style: TextStyle(fontSize: 12, color: Colors.white70)),
                                ],
                              ),
                            ),
                            Container(width: 1, height: 50, color: Colors.white30),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_fmtMoneda.format(_saldo),
                                        style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white, height: 1)),
                                    const Text('saldo disponible', style: TextStyle(fontSize: 12, color: Colors.white70)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text('1 punto = \$12.50 · Se acumulan con cada compra',
                            style: TextStyle(fontSize: 11, color: Colors.white60)),
                      ],
                    ),
            ),
            const SizedBox(height: AppSizes.md),
            Container(
              padding: const EdgeInsets.all(AppSizes.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: AppColors.textSecondary, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Usa tus puntos como descuento al hacer un pedido, en el paso de pago del carrito.',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
