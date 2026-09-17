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

/// Tap target mínimo (guía Android/iOS) para los botones de la barra --
/// siempre el área TOCABLE, nunca el tamaño visible (ver [_Chip]).
const double _tapTarget = 44.0;

/// Alto del chip/pill VISIBLE (bastante menor a [_tapTarget] a propósito --
/// el resto del área tocable queda como padding invisible alrededor).
const double _chipAlto = 28.0;

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
          style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF888888)),
        ),
        const SizedBox(width: 6),
        // El SizedBox exterior mantiene el área tocable en 44px aunque el
        // chip visible (Container centrado) sea bastante más chico.
        SizedBox(
          height: _tapTarget,
          child: Center(
            child: Container(
              height: _chipAlto,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE0E0E0)),
                color: Colors.white,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<Object>(
                  value: porPagina,
                  isDense: true,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Color(0xFF888888)),
                  style: GoogleFonts.nunito(fontSize: 12, height: 1.0, color: const Color(0xFF333333), fontWeight: FontWeight.w600),
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

    // Footer de ancho completo (edge-to-edge, sin márgenes/esquinas de
    // tarjeta) -- mismo lenguaje visual que el bottom nav (fondo sólido +
    // línea divisoria arriba, no una card flotante con sombra). El ancho
    // SIEMPRE es el 100% del contenedor padre (width: double.infinity);
    // lo único que cambia con más/menos páginas es cuántos números entran
    // en la fila de la derecha (con scroll horizontal si no caben).
    return Container(
      width: double.infinity,
      height: _alturaFooter,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      // Una sola fila de alto fijo: "Mostrar" a la izquierda, paginación a
      // la derecha -- el layout no cambia de forma entre pantallas, solo
      // el contenido scrolleable de la derecha cuando hay muchas páginas.
      child: Row(
        children: [
          if (mostrarSelector)
            SelectorPorPagina(
              porPagina: porPagina!,
              onCambiarPorPagina: onCambiarPorPagina!,
              opciones: opcionesPorPagina,
            ),
          Expanded(
            // reverse:true ancla el contenido corto (el caso real hoy: 3-5
            // páginas) contra el borde derecho en vez de dejarlo pegado a
            // la izquierda -- y si algún día una lista crece tanto que el
            // rango con "..." no entra en una pantalla angosta, sigue
            // siendo scrolleable en vez de desbordar.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PagTextBtn(
                    label: '‹ Anterior',
                    enabled: pagina > 1,
                    onTap: () => onCambiarPagina(pagina - 1 < 1 ? 1 : pagina - 1),
                  ),
                  const SizedBox(width: 4),
                  ...rango.map((p) {
                    if (p == '...') return const _Elipsis();
                    final n = p as int;
                    return _PagNumBtn(
                      numero: n,
                      activo: n == pagina,
                      onTap: () => onCambiarPagina(n),
                    );
                  }),
                  const SizedBox(width: 4),
                  _PagTextBtn(
                    label: 'Siguiente ›',
                    enabled: pagina < totalPaginas,
                    onTap: () => onCambiarPagina(pagina + 1 > totalPaginas ? totalPaginas : pagina + 1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Alto total y fijo del footer -- igual sin importar cuántas páginas haya
/// ni si el selector "Mostrar" está presente, para que nunca cambie de
/// forma entre pantallas. Como cada pantalla lo coloca como hermano de
/// Expanded(ListView) dentro de un Column (nunca Stack/Positioned), el
/// propio Column ya le resta este alto al viewport de la lista -- la
/// última fila jamás queda detrás, sin necesidad de padding extra a mano.
const double _alturaFooter = _tapTarget + 16;

class _Elipsis extends StatelessWidget {
  const _Elipsis();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 22,
      height: _chipAlto,
      child: Center(
        child: Text('···', style: TextStyle(color: Color(0xFFAAAAAA), fontWeight: FontWeight.w700, fontSize: 12)),
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
    // El SizedBox exterior (44px) es el área tocable; el Container interno
    // centrado es el chip visible, notoriamente más chico.
    return SizedBox(
      width: _tapTarget,
      height: _tapTarget,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Center(
            child: Container(
              width: _chipAlto,
              height: _chipAlto,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: activo ? AppColors.primary : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$numero',
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  height: 1.0,
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
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: enabled ? onTap : null,
          child: Center(
            child: Container(
              height: _chipAlto,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  height: 1.0,
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
