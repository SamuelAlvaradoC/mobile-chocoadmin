import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/layouts/admin_layout.dart';

class ResenasScreen extends StatefulWidget {
  const ResenasScreen({super.key});

  @override
  State<ResenasScreen> createState() => _ResenasScreenState();
}

class _ResenasScreenState extends State<ResenasScreen> {
  bool   _cargando   = true;
  String _filtroSede = '';
  String _filtroFecha = '';

  List<Map<String, dynamic>> _lista = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final data = await ApiService.get('/api/resenas');
      List raw = data is List ? data : (data is Map && data['data'] is List ? data['data'] as List : []);
      setState(() => _lista = raw.cast<Map<String, dynamic>>());
    } catch (_) {
      setState(() => _lista = []);
    }
    setState(() => _cargando = false);
  }

  List<Map<String, dynamic>> get _filtradas {
    return _lista.where((r) {
      final matchSede  = _filtroSede.isEmpty  || r['sede'] == _filtroSede;
      final matchFecha = _filtroFecha.isEmpty || (r['fecha']?.toString() ?? '').startsWith(_filtroFecha);
      return matchSede && matchFecha;
    }).toList();
  }

  Future<void> _seleccionarFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_filtroFecha) ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      locale: const Locale('es', 'CO'),
    );
    if (picked != null) {
      setState(() => _filtroFecha = DateFormat('yyyy-MM-dd').format(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtradas = _filtradas;

    return AdminLayout(
      currentRoute: '/admin/resenas',
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.screenPadding),
          children: [
            // Header
            Text('Reseñas', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('${_lista.length} reseñas registradas', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: AppSizes.md),

            // Filtros
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                // Filtro sede
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _filtroSede,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF555555)),
                      items: const [
                        DropdownMenuItem(value: '',             child: Text('Todas las sedes')),
                        DropdownMenuItem(value: 'Aranjuez',    child: Text('Sede Aranjuez')),
                        DropdownMenuItem(value: 'La Milagrosa', child: Text('Sede La Milagrosa')),
                        DropdownMenuItem(value: 'WhatsApp',    child: Text('Cocina Oculta (WhatsApp)')),
                      ],
                      onChanged: (v) => setState(() => _filtroSede = v ?? ''),
                    ),
                  ),
                ),

                // Filtro fecha
                GestureDetector(
                  onTap: _seleccionarFecha,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        _filtroFecha.isEmpty ? 'Filtrar por fecha' : _filtroFecha,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _filtroFecha.isEmpty ? const Color(0xFF888888) : const Color(0xFF333333)),
                      ),
                    ]),
                  ),
                ),

                // Limpiar fecha
                if (_filtroFecha.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(() => _filtroFecha = ''),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Text('✕ Limpiar fecha', style: TextStyle(fontSize: 13)),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: AppSizes.md),

            // Lista
            if (_cargando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              )
            else if (filtradas.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Text('No hay reseñas con estos filtros', style: TextStyle(color: AppColors.textSecondary, fontSize: 14))),
              )
            else
              ...filtradas.map((r) => _ResenaCard(resena: r)),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Card individual de reseña
// ────────────────────────────────────────────────────────────────────────────

class _ResenaCard extends StatelessWidget {
  final Map<String, dynamic> resena;
  const _ResenaCard({required this.resena});

  static const _frecuenciaLabel = {
    'primera_vez':       'Primera vez',
    'de_vez_en_cuando':  'De vez en cuando',
    'casi_siempre':      'Habitual',
  };

  static List<String> _parseLista(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    if (raw is String && raw.isNotEmpty) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is List) return parsed.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      } catch (_) {}
      return raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final r = resena;
    final sede      = r['sede']?.toString() ?? '';
    final frecuencia = _frecuenciaLabel[r['frecuencia']] ?? r['frecuencia']?.toString() ?? '';
    final fechaStr  = _formatFecha(r['fecha']?.toString());
    final calAtencion = (r['calificacion_atencion'] as num?)?.toInt() ?? 0;
    final calProducto = (r['calificacion_producto']  as num?)?.toInt() ?? 0;
    final recomendaria  = r['recomendaria']?.toString()  ?? '';
    final tiempoAdecuado = r['tiempo_adecuado']?.toString() ?? '';
    final loQueGusto   = r['lo_que_gusto']?.toString()    ?? '';
    final prodDeseado  = r['producto_deseado']?.toString() ?? '';
    final mejora       = r['mejora']?.toString()           ?? '';
    final nombreCliente   = r['nombre_cliente']?.toString() ?? r['nombre']?.toString() ?? '';
    final sugerenciaMejora = r['sugerencia_mejora']?.toString() ?? '';
    final listaDeseos = _parseLista(r['lista_deseos']);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.sm),
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF0F0F0)),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Fila superior: sede + frecuencia + fecha
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              if (sede.isNotEmpty)
                _Chip(label: sede, bg: const Color(0xFFFFF5F5), fg: AppColors.primary),
              if (frecuencia.isNotEmpty)
                _Chip(label: frecuencia, bg: const Color(0xFFF5F5F5), fg: const Color(0xFF555555), fontSize: 11, fontWeight: FontWeight.w400),
            ]),
          ),
          if (fechaStr.isNotEmpty)
            Text(fechaStr, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ]),
        if (nombreCliente.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.person_outline, size: 13, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(nombreCliente, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          ]),
        ],
        const SizedBox(height: 8),

        // Calificaciones + recomendación + tiempo
        Wrap(spacing: 16, runSpacing: 4, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Atención: ', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            _Estrellas(valor: calAtencion),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Producto: ', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            _Estrellas(valor: calProducto),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('¿Recomienda? ', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            _RecomendaIcon(valor: recomendaria),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Tiempo: ', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            _TiempoIcon(valor: tiempoAdecuado),
          ]),
        ]),

        // Texto libre
        if (loQueGusto.isNotEmpty) ...[
          const SizedBox(height: 6),
          RichText(text: TextSpan(style: const TextStyle(fontSize: 13, color: Color(0xFF555555)), children: [
            const TextSpan(text: 'Lo que más gustó: ', style: TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: loQueGusto),
          ])),
        ],
        if (prodDeseado.isNotEmpty) ...[
          const SizedBox(height: 4),
          RichText(text: TextSpan(style: const TextStyle(fontSize: 13, color: Color(0xFF555555)), children: [
            const TextSpan(text: 'Postre deseado: ', style: TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: prodDeseado),
          ])),
        ],
        if (mejora.isNotEmpty) ...[
          const SizedBox(height: 4),
          RichText(text: TextSpan(style: const TextStyle(fontSize: 13, color: Color(0xFF555555)), children: [
            const TextSpan(text: 'Mejoras: ', style: TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: mejora),
          ])),
        ],
        if (sugerenciaMejora.isNotEmpty) ...[
          const SizedBox(height: 4),
          RichText(text: TextSpan(style: const TextStyle(fontSize: 13, color: Color(0xFF555555)), children: [
            const TextSpan(text: 'Sugerencia: ', style: TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: sugerenciaMejora),
          ])),
        ],
        if (listaDeseos.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Lista de deseos:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
              ...listaDeseos.map((d) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(d, style: const TextStyle(fontSize: 11, color: Color(0xFF2563EB), fontWeight: FontWeight.w600)),
              )),
            ],
          ),
        ],
      ]),
    );
  }

  String _formatFecha(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return DateFormat("d MMM y, HH:mm", 'es_CO').format(dt);
    } catch (_) {
      return raw;
    }
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final double fontSize;
  final FontWeight fontWeight;
  const _Chip({
    required this.label,
    required this.bg,
    required this.fg,
    this.fontSize = 12,
    this.fontWeight = FontWeight.w700,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: fontSize, fontWeight: fontWeight, color: fg)),
    );
  }
}

class _Estrellas extends StatelessWidget {
  final int valor;
  const _Estrellas({required this.valor});

  @override
  Widget build(BuildContext context) {
    return Text(
      '${'★' * valor.clamp(0, 5)}${'☆' * (5 - valor.clamp(0, 5))}',
      style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 14),
    );
  }
}

class _RecomendaIcon extends StatelessWidget {
  final String valor;
  const _RecomendaIcon({required this.valor});

  @override
  Widget build(BuildContext context) {
    switch (valor) {
      case 'si':
        return const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle, size: 13, color: Color(0xFF16A34A)),
          SizedBox(width: 2),
          Text('Sí', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF16A34A))),
        ]);
      case 'tal_vez':
        return const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.help, size: 13, color: Color(0xFFF59E0B)),
          SizedBox(width: 2),
          Text('Tal vez', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFF59E0B))),
        ]);
      case 'no':
        return const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cancel, size: 13, color: AppColors.primary),
          SizedBox(width: 2),
          Text('No', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
        ]);
      default:
        return Text(valor, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700));
    }
  }
}

class _TiempoIcon extends StatelessWidget {
  final String valor;
  const _TiempoIcon({required this.valor});

  @override
  Widget build(BuildContext context) {
    switch (valor) {
      case 'si':
        return const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle, size: 13, color: Color(0xFF16A34A)),
          SizedBox(width: 2),
          Text('Adecuado', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF16A34A))),
        ]);
      case 'podria_mejorar':
        return const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.refresh, size: 13, color: Color(0xFFF59E0B)),
          SizedBox(width: 2),
          Text('Podría mejorar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFF59E0B))),
        ]);
      case 'no':
        return const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cancel, size: 13, color: AppColors.primary),
          SizedBox(width: 2),
          Text('No', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
        ]);
      default:
        return Text(valor, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700));
    }
  }
}
