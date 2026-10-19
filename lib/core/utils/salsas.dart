// ── Salsas disponibles (idénticas a React) ───────────────────────────────────
const kSalsasDisponibles = <Map<String, String>>[
  {'id': 'arequipe',         'nombre': 'Arequipe',          'img': 'https://www.chocofreseo.com/img/salsas/arequipe.png'},
  {'id': 'chocolate_negro',  'nombre': 'Chocolate Negro',   'img': 'https://www.chocofreseo.com/img/salsas/chocolate-negro.png'},
  {'id': 'chocolate_blanco', 'nombre': 'Chocolate Blanco',  'img': 'https://www.chocofreseo.com/img/salsas/chocolate-blanco.png'},
  {'id': 'mermelada_mora',   'nombre': 'Mermelada de Mora', 'img': 'https://www.chocofreseo.com/img/salsas/mermelada-mora.png'},
];
/// Salsa guardada en el carrito a partir de su id (como la manda la API).
/// La cobertura de los bowls se guarda solo con su nombre.
Map<String, dynamic> salsaDesdeId(String valor) {
  for (final s in kSalsasDisponibles) {
    if (s['id'] == valor) return Map<String, dynamic>.from(s);
  }
  return {'nombre': valor};
}
