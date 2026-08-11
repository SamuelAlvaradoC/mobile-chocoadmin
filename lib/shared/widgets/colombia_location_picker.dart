import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/api_service.dart';

// ── Constantes idénticas a React FormDireccion.jsx ────────────────────────────

const _kTiposVia = ['Calle', 'Carrera', 'Diagonal', 'Avenida', 'Transversal'];

// ── FormDireccion ─────────────────────────────────────────────────────────────
// Réplica exacta de src/components/common/FormDireccion.jsx: el costo de
// domicilio sale SIEMPRE de elegir un barrio del catálogo administrado desde
// el panel (id_barrio + precio_domicilio) — React nunca usa mapa/GPS aquí.
// isClient solo cambia detalles cosméticos menores (igual que layout='client'
// en React), no la lógica.
class FormDireccion extends StatefulWidget {
  final Map<String, dynamic> value;
  final void Function(String field, dynamic value) onChange;
  final Map<String, String> errors;
  final bool isClient;

  const FormDireccion({
    super.key,
    this.value = const {},
    required this.onChange,
    this.errors = const {},
    this.isClient = false,
  });

  @override
  State<FormDireccion> createState() => _FormDireccionState();
}

class _FormDireccionState extends State<FormDireccion> {
  late final TextEditingController _numeroViaCtrl;
  late final TextEditingController _numeralCtrl;
  late final TextEditingController _complementoCtrl;
  late final TextEditingController _referenciaCtrl;

  String _tipoVia = '';
  List<Map<String, dynamic>> _ciudades = [];
  List<Map<String, dynamic>> _barrios = [];
  bool _cargandoBarrios = false;

  @override
  void initState() {
    super.initState();
    _tipoVia         = widget.value['tipo_via']?.toString() ?? '';
    _numeroViaCtrl   = TextEditingController(text: widget.value['numero']?.toString()      ?? '');
    _numeralCtrl     = TextEditingController(text: widget.value['numeral']?.toString()     ?? '');
    _complementoCtrl = TextEditingController(text: widget.value['complemento']?.toString() ?? '');
    _referenciaCtrl  = TextEditingController(text: widget.value['referencia']?.toString()  ?? '');

    _cargarCiudades();
    final idCiudad = widget.value['id_ciudad'];
    if (idCiudad != null) _cargarBarrios(idCiudad);

    // Emitir departamento fijo (igual que useEffect en React)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.value['departamento'] != 'Antioquia') {
        widget.onChange('departamento', 'Antioquia');
      }
    });
  }

  @override
  void dispose() {
    _numeroViaCtrl.dispose();
    _numeralCtrl.dispose();
    _complementoCtrl.dispose();
    _referenciaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarCiudades() async {
    try {
      final data = await ApiService.get('/api/ciudades/activas');
      final raw = data is List ? data : (data is Map && data['data'] is List ? data['data'] as List : []);
      if (mounted) setState(() => _ciudades = raw.cast<Map<String, dynamic>>());
    } catch (_) {
      if (mounted) setState(() => _ciudades = []);
    }
  }

  Future<void> _cargarBarrios(dynamic idCiudad) async {
    setState(() { _cargandoBarrios = true; _barrios = []; });
    try {
      final data = await ApiService.get('/api/barrios/activos', queryParams: {'id_ciudad': idCiudad.toString()});
      final raw = data is List ? data : (data is Map && data['data'] is List ? data['data'] as List : []);
      if (mounted) setState(() => _barrios = raw.cast<Map<String, dynamic>>());
    } catch (_) {
      if (mounted) setState(() => _barrios = []);
    }
    if (mounted) setState(() => _cargandoBarrios = false);
  }

  // direccionPreview — mismo algoritmo que React
  String get _dirPreview {
    final nv = _numeroViaCtrl.text.trim();
    final n  = _numeralCtrl.text.trim();
    final c  = _complementoCtrl.text.trim();
    return [
      _tipoVia,
      nv,
      n.isNotEmpty ? '#$n' : '',
      c.isNotEmpty ? '-$c' : '',
    ].where((s) => s.isNotEmpty).join(' ');
  }

  void _emitDirLinea() => widget.onChange('direccion_linea', _dirPreview);

  void _handleCiudad(Map<String, dynamic>? ciudad) {
    widget.onChange('id_ciudad', ciudad?['id_ciudad']);
    widget.onChange('ciudad',    ciudad?['nombre'] ?? '');
    widget.onChange('id_barrio', null);
    widget.onChange('barrio',    '');
    widget.onChange('costo_domicilio', 0);
    setState(() => _barrios = []);
    if (ciudad != null) _cargarBarrios(ciudad['id_ciudad']);
  }

  void _handleBarrio(Map<String, dynamic>? barrio) {
    if (barrio == null) {
      widget.onChange('id_barrio', null);
      widget.onChange('barrio',    '');
      widget.onChange('costo_domicilio', 0);
      return;
    }
    widget.onChange('id_barrio', barrio['id_barrio']);
    widget.onChange('barrio',    barrio['nombre']);
    widget.onChange('costo_domicilio', (barrio['precio_domicilio'] as num?)?.toDouble() ?? 0.0);
    widget.onChange('distancia_km', 0.0);
  }

  // ── Helpers visuales ──────────────────────────────────────────────────────

  Widget _lbl(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF555555))),
      );

  Widget _errTxt(String? msg) {
    if (msg == null || msg.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 2),
      child: Text('⚠ $msg',
          style: const TextStyle(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.w600)),
    );
  }

  InputDecoration _dec({String? hint, bool err = false, bool disabled = false}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 13),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: err ? AppColors.error : const Color(0xFFE5E7EB))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: err ? AppColors.error : const Color(0xFFE5E7EB))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
                color: err ? AppColors.error : AppColors.primary, width: 1.5)),
        filled: true,
        fillColor: disabled ? const Color(0xFFF5F5F5) : Colors.white,
      );

  Widget _dropdownField({
    required String hint,
    required String? value,
    required List<String> items,
    required void Function(String?) onChanged,
    bool err = false,
  }) =>
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: err ? AppColors.error : const Color(0xFFE5E7EB)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            hint: Text(hint, style: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 13)),
            value: value,
            items: items
                .map((e) =>
                    DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13))))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      );

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final idCiudadActual = widget.value['id_ciudad'];
    final barrioActual   = widget.value['barrio']?.toString() ?? '';
    final costoDomicilio = (widget.value['costo_domicilio'] as num?)?.toDouble() ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Aviso: el costo depende del barrio ────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F9FF),
            border: Border.all(color: const Color(0xFFBAE6FD)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline, size: 14, color: Color(0xFF0369A1)),
            SizedBox(width: 7),
            Expanded(
              child: Text('El costo de domicilio depende del barrio seleccionado',
                  style: TextStyle(fontSize: 12, color: Color(0xFF0369A1), fontWeight: FontWeight.w600)),
            ),
          ]),
        ),

        // ── Departamento (fijo) ───────────────────────────────────────────
        _lbl('Departamento'),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: const Row(children: [
            Expanded(child: Text('Antioquia', style: TextStyle(fontSize: 13, color: Color(0xFF888888)))),
            Icon(Icons.lock_outline, size: 14, color: Color(0xFFAAAAAA)),
          ]),
        ),
        const SizedBox(height: 12),

        // ── Ciudad | Barrio ──────────────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _lbl('Ciudad / Municipio *'),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: widget.errors['ciudad'] != null ? AppColors.error : const Color(0xFFE5E7EB)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<dynamic>(
                        isExpanded: true,
                        hint: const Text('Seleccionar...', style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 13)),
                        value: idCiudadActual,
                        items: _ciudades
                            .map((c) => DropdownMenuItem(value: c['id_ciudad'], child: Text(c['nombre'] ?? '', style: const TextStyle(fontSize: 13))))
                            .toList(),
                        onChanged: (v) {
                          final ciudad = _ciudades.firstWhere((c) => c['id_ciudad'] == v, orElse: () => {});
                          _handleCiudad(ciudad.isEmpty ? null : ciudad);
                        },
                      ),
                    ),
                  ),
                  _errTxt(widget.errors['ciudad']),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _lbl('Barrio *'),
                  _cargandoBarrios
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: const Row(children: [
                            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 8),
                            Text('Cargando...', style: TextStyle(fontSize: 12, color: Color(0xFF888888))),
                          ]),
                        )
                      : Autocomplete<Map<String, dynamic>>(
                          displayStringForOption: (b) => b['nombre']?.toString() ?? '',
                          optionsBuilder: (TextEditingValue v) {
                            if (idCiudadActual == null) return const Iterable<Map<String, dynamic>>.empty();
                            if (v.text.isEmpty) return _barrios;
                            final q = v.text.toLowerCase();
                            return _barrios.where((b) => (b['nombre']?.toString().toLowerCase().contains(q) ?? false));
                          },
                          onSelected: _handleBarrio,
                          fieldViewBuilder: (context, ctrl, focusNode, onSubmit) {
                            if (ctrl.text != barrioActual && !focusNode.hasFocus) ctrl.text = barrioActual;
                            return TextField(
                              controller: ctrl,
                              focusNode: focusNode,
                              enabled: idCiudadActual != null,
                              style: const TextStyle(fontSize: 13),
                              decoration: _dec(
                                hint: idCiudadActual == null ? 'Primero selecciona ciudad' : 'Buscar barrio...',
                                err: widget.errors['barrio'] != null,
                                disabled: idCiudadActual == null,
                              ),
                              onChanged: (v) {
                                // Igual que React SearchableBarrio: si el texto no
                                // coincide con una selección real, se limpia el barrio.
                                if (v != barrioActual) _handleBarrio(null);
                              },
                            );
                          },
                          optionsViewBuilder: (context, onSelected, options) => Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(8),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 200, minWidth: 160),
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder: (context, i) {
                                    final b = options.elementAt(i);
                                    return ListTile(
                                      dense: true,
                                      title: Text(b['nombre'] ?? '', style: const TextStyle(fontSize: 13)),
                                      onTap: () => onSelected(b),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                  _errTxt(widget.errors['barrio']),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Costo domicilio (solo modo cliente) ───────────────────────────
        if (widget.isClient && costoDomicilio > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              border: Border.all(color: const Color(0xFFBBF7D0)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Domicilio', style: TextStyle(fontSize: 12, color: Color(0xFF166534), fontWeight: FontWeight.w600)),
              Text('\$${costoDomicilio.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF166534), fontWeight: FontWeight.w800)),
            ]),
          ),
        ],

        // ── Tipo de vía ──────────────────────────────────────────────────
        _lbl('Tipo de vía *'),
        _dropdownField(
          hint: 'Seleccionar tipo...',
          value: _tipoVia.isEmpty ? null : _tipoVia,
          items: _kTiposVia,
          err: widget.errors['tipo_via'] != null,
          onChanged: (v) {
            setState(() => _tipoVia = v ?? '');
            widget.onChange('tipo_via', v ?? '');
            _emitDirLinea();
          },
        ),
        _errTxt(widget.errors['tipo_via']),
        const SizedBox(height: 12),

        // ── Número  #Numeral  -Complemento ──────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _lbl('Número *'),
                  TextField(
                    controller: _numeroViaCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: _dec(hint: '55', err: widget.errors['numero'] != null),
                    onChanged: (v) { widget.onChange('numero', v); _emitDirLinea(); setState(() {}); },
                  ),
                  _errTxt(widget.errors['numero']),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 26, left: 6, right: 4),
              child: Text('#', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF888888))),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _lbl('# Numeral *'),
                  TextField(
                    controller: _numeralCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: _dec(hint: '30', err: widget.errors['numeral'] != null),
                    onChanged: (v) { widget.onChange('numeral', v); _emitDirLinea(); setState(() {}); },
                  ),
                  _errTxt(widget.errors['numeral']),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 26, left: 6, right: 4),
              child: Text('-', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF888888))),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _lbl('Complemento *'),
                  TextField(
                    controller: _complementoCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: _dec(hint: '45', err: widget.errors['complemento'] != null),
                    onChanged: (v) { widget.onChange('complemento', v); _emitDirLinea(); setState(() {}); },
                  ),
                  _errTxt(widget.errors['complemento']),
                ],
              ),
            ),
          ],
        ),

        // ── Preview direccion_linea ───────────────────────────────────────
        if (_dirPreview.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '📍 $_dirPreview'
              '${barrioActual.isNotEmpty ? ", $barrioActual" : ""}'
              '${(widget.value['ciudad']?.toString() ?? '').isNotEmpty ? ", ${widget.value['ciudad']}" : ""}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF555555), fontStyle: FontStyle.italic),
            ),
          ),
        ],
        const SizedBox(height: 12),

        // ── Referencia ────────────────────────────────────────────────────
        _lbl('Referencia / Indicaciones adicionales'),
        TextField(
          controller: _referenciaCtrl,
          style: const TextStyle(fontSize: 13),
          maxLines: 2,
          decoration: _dec(hint: 'Ej: Casa esquinera, portón azul, frente al parque... (opcional)'),
          onChanged: (v) => widget.onChange('referencia', v),
        ),
      ],
    );
  }
}

// ── ColombiaLocationPicker (legacy) ──────────────────────────────────────────
class ColombiaLocationPicker extends StatelessWidget {
  final String? initialDepartamento;
  final String? initialCiudad;
  final void Function(String departamento, String ciudad) onChanged;

  const ColombiaLocationPicker({
    super.key,
    this.initialDepartamento,
    this.initialCiudad,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FormDireccion(
      value: {
        'ciudad':       initialCiudad       ?? '',
        'departamento': initialDepartamento  ?? 'Antioquia',
      },
      onChange: (f, v) {
        if (f == 'ciudad') {
          onChanged(initialDepartamento ?? 'Antioquia', v?.toString() ?? '');
        }
      },
    );
  }
}
