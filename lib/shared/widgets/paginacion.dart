// Paginación reutilizable para las listas del panel Admin -- puerto directo
// del componente React equivalente (chocofreseo/src/components/Paginacion.jsx):
// mismo algoritmo de rango inteligente con "...", siempre visible (incluso
// con 1 sola página, con los controles deshabilitados) y selector
// "Mostrar: 10/50/100/Todos" opcional. La estética (chips ≥44px, layout en
// columna, scroll horizontal en vez de wrap) es la adaptación móvil --
// el comportamiento es el mismo.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';

/// Sentinel para "ver todos los registros" en el selector "Mostrar".
const String todosPorPagina = 'todos';

/// Opciones por defecto del selector "Mostrar" -- mismos valores que React.
const List<Object> opcionesPorPaginaDefault = [10, 50, 100, todosPorPagina];

/// Tap target mínimo (guía Android/iOS) para los botones de la barra.
const double _tapTarget = 44.0;

/// Puro y testeable sin montar el widget -- mismo algoritmo que
/// calcularRangoPaginas en React. `delta` = cuántas páginas mostrar a cada
/// lado de la actual.
List<Object> calcularRangoPaginas(int pagina, int totalPaginas, {int delta = 2}) {
  final total = totalPaginas < 1 ? 1 : totalPaginas;
  if (total <= 1) return const [1];

  var izquierda = pagina - delta;
  if (izquierda < 2) izquierda = 2;
  var derecha = pagina + delta;
  if (derecha > total - 1) derecha = total - 1;

  // Si el hueco entre el extremo y el inicio/fin del rango es de una sola
  // página, se muestra esa página en vez de "..." -- un "..." que esconde
  // un único número se ve peor que simplemente mostrarlo.
  if (izquierda == 3) izquierda = 2;
  if (derecha == total - 2) derecha = total - 1;

  final rango = <Object>[1];
  if (izquierda > 2) rango.add('...');
  for (var i = izquierda; i <= derecha; i++) {
    rango.add(i);
  }
  if (derecha < total - 1) rango.add('...');
  rango.add(total);
  return rango;
}

/// Selector "Mostrar: 10/50/100/Todos" solo -- separado de [Paginacion] para
/// poder colocarlo en cualquier layout (ej. junto a un filtro) sin arrastrar
/// los chips de número de página. [Paginacion] lo reutiliza internamente.
class SelectorPorPagina extends StatelessWidget {
  final Object porPagina;
  final ValueChanged<Object> onCambiarPorPagina;
  final List<Object> opciones;

  const SelectorPorPagina({
    super.key,
    required this.porPagina,
    required this.onCambiarPorPagina,
    this.opciones = opcionesPorPaginaDefault,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Mostrar:',
          style: GoogleFonts.nunito(fontSize: 12.5, fontWeight: FontWeight.w600, color: const Color(0xFF888888)),
        ),
        const SizedBox(width: 8),
        Container(
          constraints: const BoxConstraints(minHeight: _tapTarget),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE0E0E0)),
            color: Colors.white,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<Object>(
              value: porPagina,
              isDense: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF888888)),
              style: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF333333), fontWeight: FontWeight.w600),
              items: opciones
                  .map((op) => DropdownMenuItem<Object>(
                        value: op,
                        child: Text(op == todosPorPagina ? 'Todos' : '$op'),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) onCambiarPorPagina(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Barra de paginación completa: "Mostrar" (opcional) + Anterior/números
/// (con "...")/Siguiente. Siempre se renderiza, incluso con 1 sola página
/// (en ese caso Anterior/Siguiente quedan deshabilitados) -- layout
/// consistente en todas las listas del panel en vez de que la fila aparezca
/// y desaparezca según cuántos registros haya.
class Paginacion extends StatelessWidget {
  final int pagina;
  final int totalPaginas;
  final ValueChanged<int> onCambiarPagina;
  final Object? porPagina;
  final ValueChanged<Object>? onCambiarPorPagina;
  final List<Object> opcionesPorPagina;
  final int delta;

  const Paginacion({
    super.key,
    required this.pagina,
    required this.totalPaginas,
    required this.onCambiarPagina,
    this.porPagina,
    this.onCambiarPorPagina,
    this.opcionesPorPagina = opcionesPorPaginaDefault,
    this.delta = 2,
  });

  @override
  Widget build(BuildContext context) {
    final mostrarSelector = porPagina != null && onCambiarPorPagina != null;
    final rango = calcularRangoPaginas(pagina, totalPaginas, delta: delta);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mostrarSelector) ...[
            SelectorPorPagina(
              porPagina: porPagina!,
              onCambiarPorPagina: onCambiarPorPagina!,
              opciones: opcionesPorPagina,
            ),
            const SizedBox(height: 10),
          ],
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PagTextBtn(
                  label: '‹ Anterior',
                  enabled: pagina > 1,
                  onTap: () => onCambiarPagina(pagina - 1 < 1 ? 1 : pagina - 1),
                ),
                const SizedBox(width: 6),
                ...rango.map((p) {
                  if (p == '...') return const _Elipsis();
                  final n = p as int;
                  return _PagNumBtn(
                    numero: n,
                    activo: n == pagina,
                    onTap: () => onCambiarPagina(n),
                  );
                }),
                const SizedBox(width: 6),
                _PagTextBtn(
                  label: 'Siguiente ›',
                  enabled: pagina < totalPaginas,
                  onTap: () => onCambiarPagina(pagina + 1 > totalPaginas ? totalPaginas : pagina + 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Elipsis extends StatelessWidget {
  const _Elipsis();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: _tapTarget,
      height: _tapTarget,
      child: Center(
        child: Text('···', style: TextStyle(color: Color(0xFFAAAAAA), fontWeight: FontWeight.w700, fontSize: 13)),
      ),
    );
  }
}

class _PagNumBtn extends StatelessWidget {
  final int numero;
  final bool activo;
  final VoidCallback onTap;
  const _PagNumBtn({required this.numero, required this.activo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        width: _tapTarget,
        height: _tapTarget,
        child: Material(
          color: activo ? AppColors.primary : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Center(
              child: Text(
                '$numero',
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: activo ? Colors.white : const Color(0xFF444444),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PagTextBtn extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _PagTextBtn({required this.label, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _tapTarget,
      child: Material(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: enabled ? const Color(0xFF444444) : const Color(0xFFBBBBBB),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
