import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/models/adicion.dart';
import '../../../core/models/topping.dart';

class AdicionesModal extends StatefulWidget {
  final List<Adicion> adiciones;
  final String productoNombre;
  final double productoPrecio;
  final List<Topping> toppingsSeleccionados;

  const AdicionesModal({
    super.key,
    required this.adiciones,
    required this.productoNombre,
    required this.productoPrecio,
    this.toppingsSeleccionados = const [],
  });

  @override
  State<AdicionesModal> createState() => _AdicionesModalState();
}

class _AdicionesModalState extends State<AdicionesModal> {
  final Set<int> _seleccionados = {};
  final _fmt = NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);

  void _toggle(Adicion a) {
    setState(() {
      if (_seleccionados.contains(a.id)) {
        _seleccionados.remove(a.id);
      } else {
        _seleccionados.add(a.id);
      }
    });
  }

  double get _subtotal {
    final adicionesTotal = widget.adiciones
        .where((a) => _seleccionados.contains(a.id))
        .fold(0.0, (s, a) => s + a.precio);
    return widget.productoPrecio + adicionesTotal;
  }

  @override
  Widget build(BuildContext context) {
    final selList = widget.adiciones.where((a) => _seleccionados.contains(a.id)).toList();

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.screenPadding),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.productoNombre,
                          style: Theme.of(context).textTheme.headlineSmall,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      Row(children: [
                        Text('Agrega algo extra',
                            style: Theme.of(context).textTheme.bodySmall),
                        Text(' — Opcional',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textHint)),
                      ]),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Resumen toppings seleccionados
          if (widget.toppingsSeleccionados.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.screenPadding),
              child: Row(
                children: [
                  Text('Toppings: ', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: widget.toppingsSeleccionados.map((t) => Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(t.nombre, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
                        )).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 8),
          const Divider(height: 1),

          // Grid de adiciones
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
            child: GridView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.all(AppSizes.screenPadding),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.85,
              ),
              itemCount: widget.adiciones.length,
              itemBuilder: (_, i) {
                final a = widget.adiciones[i];
                final sel = _seleccionados.contains(a.id);
                return GestureDetector(
                  onTap: () => _toggle(a),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.success.withValues(alpha: 0.07) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: sel ? AppColors.success : const Color(0xFFDDDDDD),
                        width: sel ? 2 : 1,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('🍯', style: TextStyle(fontSize: 26)),
                              const SizedBox(height: 4),
                              Text(
                                a.nombre,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                              if (a.precio > 0)
                                Text(
                                  '+${_fmt.format(a.precio)}',
                                  style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w700),
                                ),
                            ],
                          ),
                        ),
                        if (sel)
                          Positioned(
                            top: 6, right: 6,
                            child: Container(
                              width: 18, height: 18,
                              decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                              alignment: Alignment.center,
                              child: const Text('✓', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Subtotal row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.screenPadding, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Subtotal', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                Text(
                  _fmt.format(_subtotal),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
              ],
            ),
          ),

          const Divider(height: 1),
          const SizedBox(height: 12),

          // Footer buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.screenPadding),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, selList),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                    Text('Agregar al carrito'),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward_ios_rounded, size: 12),
                  ]),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
