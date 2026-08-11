import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/models/topping.dart';
import '../../../core/models/adicion.dart';
import '../../../core/models/producto.dart';

// ── Salsas disponibles (idénticas a React) ───────────────────────────────────
const _kSalsas = <Map<String, String>>[
  {'id': 'arequipe',         'nombre': 'Arequipe',          'img': 'https://res.cloudinary.com/diqeuyoqo/image/upload/v1779742573/patatas_arequipe_vhgewf.png'},
  {'id': 'chocolate_negro',  'nombre': 'Chocolate Negro',   'img': 'https://res.cloudinary.com/diqeuyoqo/image/upload/v1779742679/patatas_chocolate_negro_oluxzf.png'},
  {'id': 'chocolate_blanco', 'nombre': 'Chocolate Blanco',  'img': 'https://res.cloudinary.com/diqeuyoqo/image/upload/v1779742648/patatas_chocolate_blanco_t6dwl5.png'},
  {'id': 'mermelada_mora',   'nombre': 'Mermelada de Mora', 'img': 'https://res.cloudinary.com/diqeuyoqo/image/upload/v1779742724/patatas_mermelada_jlcyrs.png'},
];
const _kMaxSalsasGratis  = 2;
const _kPrecioSalsaExtra = 5000.0;
const _kPrecioTopExtra   = 2000.0;

// ── Resultado del modal ──────────────────────────────────────────────────────
class ModalProductoResult {
  final List<Topping> toppings;
  final List<Adicion> adiciones;
  final List<Map<String, dynamic>> salsas;
  final String? tipoChocolate;
  final double cargoExtra;

  const ModalProductoResult({
    required this.toppings,
    required this.adiciones,
    required this.salsas,
    this.tipoChocolate,
    required this.cargoExtra,
  });
}

// Alias para compatibilidad hacia atrás
typedef ToppingsModalResult = ModalProductoResult;

// ── Widget principal ─────────────────────────────────────────────────────────
class ToppingsModal extends StatefulWidget {
  final List<Topping> allToppings;
  final List<Adicion> allAdiciones;
  final Producto producto;

  const ToppingsModal({
    super.key,
    required this.allToppings,
    required this.allAdiciones,
    required this.producto,
  });

  @override
  State<ToppingsModal> createState() => _ToppingsModalState();
}

class _ToppingsModalState extends State<ToppingsModal> {
  int _pasoIdx = 0;
  String? _tipoChocolate;
  String? _coberturaElegida;
  final Map<int, int> _toppingQty   = {}; // id -> cantidad
  final Set<String>   _salsasSel    = {}; // salsa id strings
  final Map<int, int> _adicionQty   = {}; // id -> cantidad

  final _fmt = NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);

  // Computed
  List<Topping> get _toppings => widget.allToppings.where((t) => !t.esSalsa).toList();

  int get _maxGratis   => widget.producto.permiteToppings ? widget.producto.maxToppings : 0;
  int get _totalTops   => _toppingQty.values.fold(0, (s, v) => s + v);
  int get _topCobrados => (_totalTops - _maxGratis).clamp(0, 999);
  int get _topIncluidos => _totalTops - _topCobrados;

  double get _salsasExtra  => ((_salsasSel.length - _kMaxSalsasGratis).clamp(0, 999)) * _kPrecioSalsaExtra;
  double get _topExtra     => _topCobrados * _kPrecioTopExtra;
  double get _adicionTotal {
    double t = 0;
    for (final e in _adicionQty.entries) {
      final a = widget.allAdiciones.firstWhere((a) => a.id == e.key, orElse: () => Adicion(id: 0, nombre: '', precio: 0));
      t += a.precio * e.value;
    }
    return t;
  }
  double get _total    => widget.producto.precio + _topExtra + _salsasExtra + _adicionTotal;
  double get _cargoExtra => _topExtra + _salsasExtra;

  List<String> get _pasos {
    final p = <String>[];
    if (widget.producto.esBowl)           p.add('bowl');
    if (widget.producto.permiteChocolate) p.add('chocolate');
    if (widget.producto.permiteSalsas)    p.add('salsas');
    if (widget.producto.permiteToppings && _toppings.isNotEmpty) p.add('toppings');
    p.add('adiciones');
    return p;
  }

  String get _pasoActual  => _pasos[_pasoIdx];
  bool   get _esUltimo    => _pasoIdx == _pasos.length - 1;
  bool   get _esPrimero   => _pasoIdx == 0;

  void _avanzar() {
    if (_pasoActual == 'chocolate' && _tipoChocolate == null) return;
    if (_pasoActual == 'bowl' && _coberturaElegida == null) return;
    if (_esUltimo) {
      final tFlat = <Topping>[];
      for (final e in _toppingQty.entries) {
        final t = widget.allToppings.firstWhere((x) => x.id == e.key, orElse: () => widget.allToppings.first);
        for (int i = 0; i < e.value; i++) { tFlat.add(t); }
      }
      final aFlat = <Adicion>[];
      for (final e in _adicionQty.entries) {
        final a = widget.allAdiciones.firstWhere((x) => x.id == e.key, orElse: () => widget.allAdiciones.first);
        for (int i = 0; i < e.value; i++) { aFlat.add(a); }
      }
      // Si es bowl, la cobertura reemplaza a las salsas (igual que React)
      final sList = widget.producto.esBowl
          ? (_coberturaElegida != null ? [{'nombre': _coberturaElegida}] : <Map<String, dynamic>>[])
          : _kSalsas.where((s) => _salsasSel.contains(s['id'])).map((s) => Map<String, dynamic>.from(s)).toList();

      Navigator.pop(context, ModalProductoResult(
        toppings: tFlat,
        adiciones: aFlat,
        salsas: sList,
        tipoChocolate: _tipoChocolate,
        cargoExtra: _cargoExtra,
      ));
    } else {
      setState(() => _pasoIdx++);
    }
  }

  void _retroceder() {
    if (_esPrimero) {
      Navigator.pop(context);
    } else {
      setState(() => _pasoIdx--);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: _buildContenido()),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildContenido() {
    switch (_pasoActual) {
      case 'bowl':      return _buildBowl();
      case 'chocolate': return _buildChocolate();
      case 'salsas':    return _buildSalsas();
      case 'toppings':  return _buildToppings();
      default:          return _buildAdiciones();
    }
  }

  // ── Color de respaldo por cobertura (se ve si la imagen no carga) ─────────
  Color _colorCobertura(String nombre) {
    switch (nombre) {
      case 'Chocolate Negro':  return const Color(0xFF1a1a1a);
      case 'Chocolate Blanco': return const Color(0xFFF5E6D0);
      case 'Arequipe':         return const Color(0xFFC8860A);
      default:                 return const Color(0xFFE5E7EB);
    }
  }

  // ── Paso Bowl (cobertura) ────────────────────────────────────────────────
  Widget _buildBowl() {
    const opciones = [
      {'nombre': 'Chocolate Negro',  'img': 'https://res.cloudinary.com/dnoxlv5kn/image/upload/v1778815863/chocolate_negro_ancho_kzqpjd.png'},
      {'nombre': 'Chocolate Blanco', 'img': 'https://res.cloudinary.com/dnoxlv5kn/image/upload/v1778815900/chocolate_blanco_ancho_rw2b5l.png'},
      {'nombre': 'Arequipe',         'img': 'https://res.cloudinary.com/diqeuyoqo/image/upload/v1779742573/patatas_arequipe_vhgewf.png'},
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.producto.imagen != null && widget.producto.imagen!.isNotEmpty)
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: CachedNetworkImage(
                  imageUrl: widget.producto.imagen!,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 10, right: 10,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17)),
                    alignment: Alignment.center,
                    child: const Icon(Icons.close, size: 18),
                  ),
                ),
              ),
            ],
          )
        else
          _header('¿Con qué cobertura?', onClose: () => Navigator.pop(context)),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(widget.producto.nombre, style: GoogleFonts.nunito(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a)))),
              Text(_fmt.format(widget.producto.precio), style: GoogleFonts.nunito(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primary)),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Text('¿Con qué cobertura lo prefieres?',
              style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF999999), letterSpacing: 0.8)),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Row(
            children: opciones.map((op) {
              final sel = _coberturaElegida == op['nombre'];
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _coberturaElegida = op['nombre']),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 130,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: sel ? AppColors.primary : Colors.transparent, width: sel ? 2.5 : 0),
                        boxShadow: [BoxShadow(color: sel ? const Color(0x55CA0B0B) : const Color(0x1F000000), blurRadius: sel ? 20 : 8, offset: const Offset(0, 4))],
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(color: _colorCobertura(op['nombre']!)),
                          CachedNetworkImage(
                            imageUrl: op['img']!,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(color: _colorCobertura(op['nombre']!)),
                          ),
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xB3000000), Colors.transparent]),
                            ),
                          ),
                          Positioned(
                            bottom: 8, left: 0, right: 0,
                            child: Column(
                              children: [
                                Text(op['nombre']!, textAlign: TextAlign.center,
                                    style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                                if (sel) Text('Seleccionado ✓', style: GoogleFonts.nunito(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFFfca5a5))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ── Paso Chocolate ───────────────────────────────────────────────────────
  Widget _buildChocolate() {
    const imgNegro  = 'https://res.cloudinary.com/dnoxlv5kn/image/upload/v1778815863/chocolate_negro_ancho_kzqpjd.png';
    const imgBlanco = 'https://res.cloudinary.com/dnoxlv5kn/image/upload/v1778815900/chocolate_blanco_ancho_rw2b5l.png';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Imagen producto
        if (widget.producto.imagen != null && widget.producto.imagen!.isNotEmpty)
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: CachedNetworkImage(
                  imageUrl: widget.producto.imagen!,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 10, right: 10,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17)),
                    alignment: Alignment.center,
                    child: const Icon(Icons.close, size: 18),
                  ),
                ),
              ),
            ],
          )
        else
          _header('¿Con qué chocolate?'),

        // Nombre y precio
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(widget.producto.nombre, style: GoogleFonts.nunito(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a)))),
              Text(_fmt.format(widget.producto.precio), style: GoogleFonts.nunito(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.primary)),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Text('¿Con qué chocolate lo prefieres?',
              style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF999999), letterSpacing: 0.8)),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Row(
            children: [
              Expanded(child: _chocolateCard('Negro', imgNegro)),
              const SizedBox(width: 12),
              Expanded(child: _chocolateCard('Blanco', imgBlanco)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chocolateCard(String tipo, String imgUrl) {
    final sel = _tipoChocolate == tipo;
    return GestureDetector(
      onTap: () => setState(() => _tipoChocolate = tipo),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 155,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: sel ? AppColors.primary : Colors.transparent, width: sel ? 2.5 : 0),
          boxShadow: [BoxShadow(color: sel ? const Color(0x55CA0B0B) : const Color(0x1F000000), blurRadius: sel ? 20 : 8, offset: const Offset(0, 4))],
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(imageUrl: imgUrl, fit: BoxFit.cover),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xB3000000), Colors.transparent]),
              ),
            ),
            Positioned(
              bottom: 10, left: 0, right: 0,
              child: Column(
                children: [
                  Text(tipo, style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                  if (sel) Text('Seleccionado ✓', style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFFfca5a5))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Paso Salsas ──────────────────────────────────────────────────────────
  Widget _buildSalsas() {
    final salsasGratis  = _salsasSel.length.clamp(0, _kMaxSalsasGratis);
    final salsasCobradas = (_salsasSel.length - _kMaxSalsasGratis).clamp(0, 999);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header('Elige tus salsas 🍫', onClose: () => Navigator.pop(context)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.producto.nombre, style: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a))),
              Text(_fmt.format(widget.producto.precio), style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Text(
            'Las primeras $_kMaxSalsasGratis son gratis · Adicionales: ${_fmt.format(_kPrecioSalsaExtra)} c/u',
            style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF888888)),
          ),
        ),

        // Grid 2x2
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: _kSalsas.length,
                  itemBuilder: (_, i) {
                    final salsa = _kSalsas[i];
                    final sId   = salsa['id']!;
                    final sel   = _salsasSel.contains(sId);
                    final idx   = _salsasSel.toList().indexOf(sId);
                    final esGratis = sel && idx >= 0 && idx < _kMaxSalsasGratis;
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (sel) { _salsasSel.remove(sId); }
                        else { _salsasSel.add(sId); }
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: sel ? AppColors.primary : const Color(0xFFE5E7EB), width: sel ? 2.5 : 1.5),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(imageUrl: salsa['img']!, fit: BoxFit.cover),
                            if (sel) Container(color: AppColors.primary.withValues(alpha: 0.18)),
                            if (sel)
                              Center(
                                child: Container(
                                  width: 28, height: 28,
                                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                                  alignment: Alignment.center,
                                  child: const Text('✓', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
                                ),
                              ),
                            if (sel)
                              Positioned(
                                top: 6, right: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: esGratis ? const Color(0xFF16a34a) : AppColors.primary,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    esGratis ? 'Gratis' : '+${_fmt.format(_kPrecioSalsaExtra)}',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ),
                            Positioned(
                              bottom: 0, left: 0, right: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 7),
                                color: Colors.black.withValues(alpha: 0.45),
                                alignment: Alignment.center,
                                child: Text(salsa['nombre']!,
                                    style: GoogleFonts.nunito(fontSize: 13, fontWeight: sel ? FontWeight.w700 : FontWeight.w500, color: sel ? const Color(0xFFfca5a5) : Colors.white)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _salsasSel.length >= _kMaxSalsasGratis ? const Color(0xFFFEF3C7) : const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _salsasSel.length >= _kMaxSalsasGratis ? const Color(0xFFFDE68A) : const Color(0xFFBBF7D0)),
                  ),
                  child: Text(
                    _salsasSel.isEmpty
                        ? 'Elige hasta $_kMaxSalsasGratis salsas gratis'
                        : salsasCobradas == 0
                            ? '$salsasGratis salsa${salsasGratis > 1 ? 's' : ''} incluida${salsasGratis > 1 ? 's' : ''} ✓'
                            : '$salsasGratis gratis + $salsasCobradas extra = +${_fmt.format(salsasCobradas * _kPrecioSalsaExtra)}',
                    style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600,
                        color: _salsasSel.length >= _kMaxSalsasGratis ? const Color(0xFF92400E) : const Color(0xFF166534)),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Paso Toppings ────────────────────────────────────────────────────────
  Widget _buildToppings() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header('Elige tus toppings', onClose: () => Navigator.pop(context)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _maxGratis > 0
                      ? 'Los primeros $_maxGratis son gratis · Extra: ${_fmt.format(_kPrecioTopExtra)} c/u'
                      : 'Sin toppings gratis · Precio: ${_fmt.format(_kPrecioTopExtra)} c/u',
                  style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF666666)),
                ),
              ),
              if (_totalTops > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _topCobrados > 0 ? const Color(0xFFFFF5F5) : const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _topCobrados > 0
                        ? '+${_fmt.format(_topCobrados * _kPrecioTopExtra)}'
                        : '$_topIncluidos incluidos ✓',
                    style: GoogleFonts.nunito(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: _topCobrados > 0 ? AppColors.primary : const Color(0xFF16a34a),
                    ),
                  ),
                ),
            ],
          ),
        ),

        Flexible(
          child: GridView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8,
              childAspectRatio: 0.88,
            ),
            itemCount: _toppings.length,
            itemBuilder: (_, i) {
              final t   = _toppings[i];
              final qty = _toppingQty[t.id] ?? 0;
              return _toppingCell(t, qty);
            },
          ),
        ),
      ],
    );
  }

  Widget _toppingCell(Topping t, int qty) {
    final sel = qty > 0;
    return GestureDetector(
      onTap: sel ? null : () => setState(() => _toppingQty[t.id] = 1),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? const Color(0xFF1a1a1a) : Colors.transparent),
          boxShadow: [BoxShadow(color: sel ? const Color(0x38000000) : const Color(0x1A000000), blurRadius: sel ? 14 : 6, offset: const Offset(0, 2))],
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            t.img != null && t.img!.isNotEmpty
                ? CachedNetworkImage(imageUrl: t.img!, fit: BoxFit.cover)
                : Container(color: const Color(0xFFF0F0F0), alignment: Alignment.center,
                    child: Text(t.nombre.isNotEmpty ? t.nombre[0].toUpperCase() : '?',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 28, color: Color(0xFFAAAAAA)))),
            // Gradient + nombre
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xB8000000), Colors.transparent]),
                ),
                child: Text(t.nombre, textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
            // Qty controls when selected
            if (sel)
              Container(
                color: Colors.black.withValues(alpha: 0.35),
                alignment: Alignment.center,
                child: Container(
                  decoration: BoxDecoration(color: const Color(0xFF1a1a1a), borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => setState(() {
                          if (qty > 1) { _toppingQty[t.id] = qty - 1; }
                          else { _toppingQty.remove(t.id); }
                        }),
                        child: const Text('−', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text('$qty', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _toppingQty[t.id] = qty + 1),
                        child: const Text('+', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Paso Adiciones ───────────────────────────────────────────────────────
  Widget _buildAdiciones() {
    // Cuando el producto no permite toppings pero existen toppings,
    // se muestran como "extras" a $2,000 c/u (igual a React sinToppings=true)
    final sinToppings = !widget.producto.permiteToppings && _toppings.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header('Adiciones', subtitle: '— Opcional', onClose: () => Navigator.pop(context)),

        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Toppings extras (solo cuando sinToppings=true)
                if (sinToppings) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Text('Toppings extras — \$${(_kPrecioTopExtra / 1000).round()}k c/u',
                        style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF555555))),
                  ),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: _toppings.length,
                    itemBuilder: (_, i) {
                      final t   = _toppings[i];
                      final qty = _toppingQty[t.id] ?? 0;
                      return _toppingCell(t, qty);
                    },
                  ),
                  if (widget.allAdiciones.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                      child: Text('Adiciones',
                          style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF555555))),
                    ),
                ],
                // Adiciones
                if (widget.allAdiciones.isEmpty && !sinToppings)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('No hay adiciones disponibles',
                        style: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF888888))),
                  )
                else if (widget.allAdiciones.isNotEmpty)
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: widget.allAdiciones.length,
                    itemBuilder: (_, i) {
                      final a   = widget.allAdiciones[i];
                      final qty = _adicionQty[a.id] ?? 0;
                      return _adicionCell(a, qty);
                    },
                  ),
                if (sinToppings && widget.allAdiciones.isEmpty)
                  const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _adicionCell(Adicion a, int qty) {
    final sel = qty > 0;
    return GestureDetector(
      onTap: sel ? null : () => setState(() => _adicionQty[a.id] = 1),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? const Color(0xFFD97706) : Colors.transparent),
          boxShadow: [BoxShadow(color: sel ? const Color(0x40D97706) : const Color(0x1A000000), blurRadius: sel ? 14 : 6, offset: const Offset(0, 2))],
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            a.img != null && a.img!.isNotEmpty
                ? CachedNetworkImage(imageUrl: a.img!, fit: BoxFit.cover)
                : Container(color: const Color(0xFFFEF3C7), alignment: Alignment.center,
                    child: Text(a.nombre.isNotEmpty ? a.nombre[0].toUpperCase() : '?',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 28, color: Color(0xFFD97706)))),
            // Gradient + nombre + precio
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xB8000000), Colors.transparent]),
                ),
                child: Column(
                  children: [
                    Text(a.nombre, textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                    if (a.precio > 0)
                      Text('+\$${(a.precio / 1000).round()}k', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFfbbf24))),
                  ],
                ),
              ),
            ),
            if (sel)
              Container(
                color: Colors.black.withValues(alpha: 0.35),
                alignment: Alignment.center,
                child: Container(
                  decoration: BoxDecoration(color: const Color(0xFFD97706), borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => setState(() {
                          if (qty > 1) { _adicionQty[a.id] = qty - 1; }
                          else { _adicionQty.remove(a.id); }
                        }),
                        child: const Text('−', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text('$qty', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _adicionQty[a.id] = qty + 1),
                        child: const Text('+', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Footer con precio y navegación ──────────────────────────────────────
  Widget _buildFooter() {
    final puedeAvanzar = (_pasoActual != 'chocolate' || _tipoChocolate != null)
        && (_pasoActual != 'bowl' || _coberturaElegida != null);
    final base = widget.producto.precio;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Desglose de precio
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Precio base', style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF888888))),
              Text(_fmt.format(base), style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFF888888))),
            ],
          ),
          if (_topExtra > 0) ...[
            const SizedBox(height: 2),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Toppings extra', style: GoogleFonts.nunito(fontSize: 12, color: AppColors.primary)),
              Text('+${_fmt.format(_topExtra)}', style: GoogleFonts.nunito(fontSize: 12, color: AppColors.primary)),
            ]),
          ],
          if (_salsasExtra > 0) ...[
            const SizedBox(height: 2),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Salsas extra', style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFFEA580C))),
              Text('+${_fmt.format(_salsasExtra)}', style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFFEA580C))),
            ]),
          ],
          if (_adicionTotal > 0) ...[
            const SizedBox(height: 2),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Adiciones', style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFFD97706))),
              Text('+${_fmt.format(_adicionTotal)}', style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFFD97706))),
            ]),
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1a1a1a))),
              Text(_fmt.format(_total), style: GoogleFonts.nunito(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 10),

          // Botones
          Row(
            children: [
              if (!_esPrimero) ...[
                GestureDetector(
                  onTap: _retroceder,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE5E7EB), width: 2),
                    ),
                    child: Text('← Atrás', style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF555555))),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: GestureDetector(
                  onTap: puedeAvanzar ? _avanzar : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: puedeAvanzar ? AppColors.primary : const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _esUltimo ? '🛒 Agregar al carrito' : 'Continuar →',
                      style: GoogleFonts.nunito(
                        fontSize: 15, fontWeight: FontWeight.w800,
                        color: puedeAvanzar ? Colors.white : const Color(0xFFAAAAAA),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Helper: header genérico ──────────────────────────────────────────────
  Widget _header(String title, {String? subtitle, VoidCallback? onClose}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF5F5F5)))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1a1a1a))),
                if (subtitle != null)
                  Text(subtitle, style: GoogleFonts.nunito(fontSize: 12, color: const Color(0xFFAAAAAA))),
              ],
            ),
          ),
          if (onClose != null)
            IconButton(onPressed: onClose, icon: const Icon(Icons.close, color: Color(0xFFAAAAAA)), padding: EdgeInsets.zero),
        ],
      ),
    );
  }
}
