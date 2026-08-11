import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_service.dart';

class PedidoExitosoScreen extends StatefulWidget {
  final double distanciaKm;
  const PedidoExitosoScreen({super.key, this.distanciaKm = 0});

  @override
  State<PedidoExitosoScreen> createState() => _PedidoExitosoScreenState();
}

class _PedidoExitosoScreenState extends State<PedidoExitosoScreen> {
  int _tiempoEspera = 30;

  @override
  void initState() {
    super.initState();
    _cargarTiempo();
  }

  Future<void> _cargarTiempo() async {
    try {
      final data = await ApiService.get('/api/configuracion/tiempo-espera');
      final inner = data is Map && data['data'] is Map ? data['data'] as Map : (data is Map ? data : <String, dynamic>{});
      final min = inner['minutos'];
      if (min != null && mounted) {
        setState(() => _tiempoEspera = int.tryParse(min.toString()) ?? 30);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    const pasos = [
      _PasoTimeline(icono: Icons.check_circle_rounded, label: 'Recibido', activo: true),
      _PasoTimeline(icono: Icons.restaurant_rounded,   label: 'En cocina',  activo: false),
      _PasoTimeline(icono: Icons.delivery_dining,      label: 'En camino',  activo: false),
      _PasoTimeline(icono: Icons.home_rounded,         label: 'Entregado',  activo: false),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 32),

              // Emoji + título
              const Text('🎉', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 16),
              Text(
                '¡Pedido recibido!',
                style: GoogleFonts.nunito(fontSize: 26, fontWeight: FontWeight.w900, color: const Color(0xFF1a1a1a)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),

              // Tiempo estimado
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.access_time_rounded, size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Tiempo estimado de entrega: $_tiempoEspera–${_tiempoEspera + 20} min',
                      style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              Text(
                'Tu pedido está siendo preparado.\nEn Mis pedidos puedes ver el estado actualizado en tiempo real.',
                style: GoogleFonts.nunito(fontSize: 14, color: const Color(0xFF666666), height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),

              // Timeline
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(pasos.length, (i) {
                    final paso = pasos[i];
                    return Expanded(
                      child: Column(
                        children: [
                          // Línea conectora izquierda
                          if (i > 0)
                            Row(
                              children: [
                                Expanded(
                                  child: Container(height: 2, color: paso.activo ? AppColors.primary : const Color(0xFFE5E7EB)),
                                ),
                                Container(
                                  width: 32, height: 32,
                                  decoration: BoxDecoration(
                                    color: paso.activo ? AppColors.primary : const Color(0xFFF3F4F6),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: paso.activo ? AppColors.primary : const Color(0xFFD1D5DB), width: 2),
                                  ),
                                  child: Icon(paso.icono, size: 16, color: paso.activo ? Colors.white : const Color(0xFF9CA3AF)),
                                ),
                              ],
                            )
                          else
                            Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(paso.icono, size: 16, color: Colors.white),
                            ),
                          const SizedBox(height: 6),
                          Text(
                            paso.label,
                            style: GoogleFonts.nunito(
                              fontSize: 11,
                              fontWeight: paso.activo ? FontWeight.w700 : FontWeight.w500,
                              color: paso.activo ? AppColors.primary : const Color(0xFF9CA3AF),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 32),

              // Botones
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.go('/perfil'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text('Ver mis pedidos',
                      style: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => context.go('/catalogo'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Volver al catálogo',
                      style: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasoTimeline {
  final IconData icono;
  final String label;
  final bool activo;
  const _PasoTimeline({required this.icono, required this.label, required this.activo});
}
