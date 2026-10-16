/// Combinaciones fijas de fruta para productos con permite_frutas=true.
/// El valor `id` es lo único que se guarda en detalle_venta.frutas — el nombre
/// visible siempre se arma con nombreConFrutas(), nunca se guarda como texto.
class ComboFruta {
  final String id;
  final String etiqueta;
  final String img;
  const ComboFruta({required this.id, required this.etiqueta, required this.img});
}

const List<ComboFruta> combosFrutas = [
  ComboFruta(
    id: 'fresa_cereza',
    etiqueta: 'Fresa/Cereza',
    img: 'https://www.chocofreseo.com/img/combos/fresa-cereza.jpg',
  ),
  ComboFruta(
    id: 'fresa_durazno',
    etiqueta: 'Fresa/Durazno',
    img: 'https://www.chocofreseo.com/img/combos/fresa-durazno.jpg',
  ),
  ComboFruta(
    id: 'cereza_durazno',
    etiqueta: 'Cereza/Durazno',
    img: 'https://www.chocofreseo.com/img/combos/cereza-durazno.png',
  ),
];

final Map<String, String> _etiquetaPorId = {
  for (final c in combosFrutas) c.id: c.etiqueta,
};

/// Nombre visible del producto en carrito/checkout/detalle/historial. Único
/// punto que arma este texto — todo lo demás debe llamar esta función en vez
/// de reconstruir el nombre por su cuenta.
String nombreConFrutas(String nombreBase, String? frutas) {
  if (nombreBase.isEmpty) return nombreBase;
  final etiqueta = frutas != null ? _etiquetaPorId[frutas] : null;
  return etiqueta != null ? '$nombreBase $etiqueta' : nombreBase;
}
