import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../providers/resena_flow_provider.dart';

/// Igual patrón que ResenaBanner.jsx en React web: aviso fijo arriba cuando
/// hay un pedido entregado sin reseñar. Vive en el `banner` de
/// RootShellScaffold del shell Cliente (mismo lugar que WhatsAppFab), visible
/// en cualquiera de sus tabs. Puramente presentacional -- todo el estado
/// (fetch, descarte persistido, "más reciente") vive en ResenaFlowProvider.
class ResenaPendienteBanner extends StatelessWidget {
  final void Function(int idVenta) onDejarResena;
  const ResenaPendienteBanner({super.key, required this.onDejarResena});

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<ResenaFlowProvider>();
    final pedido = flow.masReciente;
    if (pedido == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '¿Cómo estuvo tu pedido? Cuéntanos qué tal.',
              style: GoogleFonts.nunito(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => onDejarResena(pedido.id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
              child: Text(
                'Dejar reseña',
                style: GoogleFonts.nunito(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          IconButton(
            onPressed: () => context.read<ResenaFlowProvider>().descartar(pedido),
            icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.only(left: 8),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
