import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_config.dart';
import '../../../shared/layouts/client_layout.dart';
import '../../../shared/widgets/brand_icons.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  // Ancla para el scroll del botón "Conócenos" del hero, igual que el
  // href="#nosotros" de React (Hero.jsx:51).
  static final GlobalKey nosotrosKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return ClientLayout(
      child: Column(
        children: [
          _Hero(nosotrosKey: nosotrosKey),
          const _VideoRedes(),
          const _ProductosEstrella(),
          const _ComoFunciona(),
          _Conocenos(key: nosotrosKey),
          const _CtaFinal(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HERO
// ─────────────────────────────────────────────────────────────────────────────

class _Hero extends StatefulWidget {
  final GlobalKey nosotrosKey;
  const _Hero({required this.nosotrosKey});
  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  bool? _tiendaAbierta;
  String? _estadoTienda; // 'schedule' | 'closed'
  int? _horaApertura;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetchEstado();
    // Igual que React useEstadoTienda: refresca cada 2 min.
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _fetchEstado());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchEstado() async {
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.apiBaseUrl}/configuracion/estado-tienda'),
      );
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body) as Map;
        final inner = data['data'] is Map ? data['data'] as Map : data;
        setState(() {
          _tiendaAbierta = inner['abierto'] == true;
          _estadoTienda  = inner['estado']?.toString();
          _horaApertura  = int.tryParse((inner['hora_apertura'] ?? '').toString());
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 700;

    return Container(
      width: double.infinity,
      color: AppColors.primary,
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 64 : 28,
        vertical: isWide ? 80 : 56,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(bottom: -60, right: -60, child: _deco(400)),
          Positioned(top: -40,    left: 300,  child: _deco(200)),
          Positioned(top: 120,    left: -30,  child: _deco(120)),
          isWide
              ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Expanded(child: _HeroContenido(
                      tiendaAbierta: _tiendaAbierta, estadoTienda: _estadoTienda,
                      horaApertura: _horaApertura, nosotrosKey: widget.nosotrosKey)),
                  const SizedBox(width: 60),
                  _HeroImagen(),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _HeroContenido(
                      tiendaAbierta: _tiendaAbierta, estadoTienda: _estadoTienda,
                      horaApertura: _horaApertura, nosotrosKey: widget.nosotrosKey),
                  const SizedBox(height: 40),
                  Center(child: _HeroImagen()),
                ]),
        ],
      ),
    );
  }

  Widget _deco(double size) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.08),
      shape: BoxShape.circle,
    ),
  );
}

// Igual que React utils/formatHora.js
String _formatHora12(int hora24) {
  final period = hora24 < 12 ? 'AM' : 'PM';
  final h12 = hora24 % 12 == 0 ? 12 : hora24 % 12;
  return '$h12:00 $period';
}

class _HeroContenido extends StatelessWidget {
  final bool? tiendaAbierta;
  final String? estadoTienda;
  final int? horaApertura;
  final GlobalKey nosotrosKey;
  const _HeroContenido({this.tiendaAbierta, this.estadoTienda, this.horaApertura, required this.nosotrosKey});

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final titleSize = sw < 390 ? 30.0 : (sw < 430 ? 36.0 : 42.0);
    final subtitleSize = sw < 390 ? 13.0 : 15.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Estado tienda badge
        if (tiendaAbierta != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: tiendaAbierta! ? const Color(0xFF22C55E) : Colors.grey.shade700,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 7, height: 7,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  tiendaAbierta!
                      ? 'Abierto ahora'
                      : 'Cerrado · ${estadoTienda == 'closed' ? 'Temporalmente' : (horaApertura != null ? 'Abrimos ${_formatHora12(horaApertura!)}' : 'ahora')}',
                  style: GoogleFonts.nunito(
                    fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white,
                  ),
                ),
              ]),
            ),
          ),

        // Título
        Text(
          'ChocoFreseo es puro Freseo',
          style: GoogleFonts.nunito(
            fontSize: titleSize, fontWeight: FontWeight.w900,
            color: Colors.white, height: 1.1,
          ),
        ),
        const SizedBox(height: 16),

        // Subtítulo
        Text(
          'Postres únicos con estética juvenil y sabores que no habías probado antes. Pídenos a domicilio o visítanos en Aranjuez o La Milagrosa.',
          style: GoogleFonts.nunito(
            fontSize: subtitleSize,
            color: Colors.white.withValues(alpha: 0.8),
            fontWeight: FontWeight.w600,
            height: 1.7,
          ),
        ),
        const SizedBox(height: 28),

        // Botones
        Wrap(spacing: 14, runSpacing: 12, children: [
          GestureDetector(
            onTap: () => context.go('/catalogo'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 20, offset: Offset(0, 4))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Pedir ahora',
                    style: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primary)),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded, color: AppColors.primary, size: 18),
              ]),
            ),
          ),
          GestureDetector(
            onTap: () {
              final ctx = nosotrosKey.currentContext;
              if (ctx != null) {
                Scrollable.ensureVisible(ctx,
                    duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
              ),
              child: Text('Conócenos',
                  style: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ),
        ]),
      ],
    );
  }
}

class _HeroImagen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final imgSize = sw < 480 ? (sw * 0.72).clamp(200.0, 260.0) : 300.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          CachedNetworkImage(
            imageUrl: 'https://res.cloudinary.com/diqeuyoqo/image/upload/v1780607775/40bc9e7c-2c1d-48a5-a4b8-fdcd46a17a4e_al6zv9.jpg',
            width: imgSize,
            height: imgSize,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              width: imgSize, height: imgSize,
              color: Colors.white.withValues(alpha: 0.1),
              alignment: Alignment.center,
              child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            ),
            errorWidget: (_, __, ___) => Container(
              width: imgSize, height: imgSize,
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          // Igual que .hero-imagen-overlay en Hero.css (React): el fondo de
          // la foto es un rojo más anaranjado/saturado que el rojo marca
          // (#CA0B0B), por eso se notaba el corte de la imagen como una
          // calcomanía pegada encima. Un overlay en BlendMode.multiply al
          // 35% tiñe la foto hacia el rojo marca sin aplanarla (conserva
          // luces/sombras), igual que mix-blend-mode:multiply en CSS.
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFCA0B0B).withValues(alpha: 0.35),
                  backgroundBlendMode: BlendMode.multiply,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CÓMO FUNCIONA
// ─────────────────────────────────────────────────────────────────────────────

class _ComoFunciona extends StatelessWidget {
  const _ComoFunciona();

  static const _pasos = [
    _Paso(num: '01', icon: Icons.shopping_bag_outlined,  titulo: 'Elige tu antojo',    desc: 'Explora el catálogo, personaliza con toppings, untables y adiciones'),
    _Paso(num: '02', icon: Icons.location_on_outlined,   titulo: 'Marca tu ubicación', desc: 'Pon el pin en el mapa y calculamos el domicilio automáticamente'),
    _Paso(num: '03', icon: Icons.credit_card,            titulo: 'Elige cómo pagar',   desc: 'Efectivo, transferencia o mixto. Sin complicaciones'),
    _Paso(num: '04', icon: Icons.delivery_dining,        titulo: 'Recíbelo con freseo',    desc: 'Tu pedido llega directo a tu puerta, fresquito y delicioso'),
  ];

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    return Container(
      color: const Color(0xFF1a1a1a),
      padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 28),
      child: Column(
        children: [
          Text('ASÍ DE SIMPLE',
              style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.primary, letterSpacing: 4)),
          const SizedBox(height: 12),
          Text('El proceso con más freseo',
              style: GoogleFonts.nunito(
                fontSize: sw < 390 ? 26.0 : 32.0,
                fontWeight: FontWeight.w900, color: Colors.white, height: 1.1,
              ),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text('De tu antojo a tu puerta en pocos pasos',
              style: GoogleFonts.nunito(fontSize: 14, color: Colors.white.withValues(alpha: 0.5)),
              textAlign: TextAlign.center),
          const SizedBox(height: 48),
          LayoutBuilder(
            builder: (context, constraints) {
              // Mismo criterio que Productos estrella: ancho exacto para
              // que los 4 pasos queden en una grilla de 2x2 en vez de una
              // columna de 4, sin importar el tamaño de pantalla. Además,
              // como el texto de cada paso tiene largos distintos, se
              // agrupan de a 2 en un IntrinsicHeight para que ambas
              // tarjetas de cada fila igualen su alto -- si no, quedaban
              // "escalonadas" según cuál descripción era más larga.
              const spacing = 14.0;
              final cardWidth = (constraints.maxWidth - spacing) / 2;
              final filas = <Widget>[];
              for (var i = 0; i < _pasos.length; i += 2) {
                if (i > 0) filas.add(const SizedBox(height: spacing));
                filas.add(IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PasoCard(paso: _pasos[i], index: i, width: cardWidth),
                      const SizedBox(width: spacing),
                      if (i + 1 < _pasos.length)
                        _PasoCard(paso: _pasos[i + 1], index: i + 1, width: cardWidth)
                      else
                        SizedBox(width: cardWidth),
                    ],
                  ),
                ));
              }
              return Column(children: filas);
            },
          ),
          const SizedBox(height: 48),
          GestureDetector(
            onTap: () => context.go('/catalogo'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Color(0x33CA0B0B), blurRadius: 20, offset: Offset(0, 6))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Pedir ahora',
                    style: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 18),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _Paso {
  final String num;
  final IconData icon;
  final String titulo;
  final String desc;
  const _Paso({required this.num, required this.icon, required this.titulo, required this.desc});
}

class _PasoCard extends StatelessWidget {
  final _Paso paso;
  final int index;
  final double width;
  const _PasoCard({required this.paso, required this.index, required this.width});

  @override
  Widget build(BuildContext context) {
    final bg = index % 2 == 0
        ? Colors.white.withValues(alpha: 0.04)
        : AppColors.primary.withValues(alpha: 0.08);
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.2),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(paso.icon, color: AppColors.primary, size: 21),
          ),
          const SizedBox(height: 14),
          Text('PASO ${paso.num}',
              style: GoogleFonts.nunito(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.primary, letterSpacing: 1.5)),
          const SizedBox(height: 6),
          Text(paso.titulo,
              style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 6),
          Text(paso.desc,
              style: GoogleFonts.nunito(fontSize: 12, color: Colors.white.withValues(alpha: 0.5), height: 1.5)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PRODUCTOS ESTRELLA
// ─────────────────────────────────────────────────────────────────────────────

class _Estrella {
  final String nombre;
  final List<String> keywords;
  const _Estrella(this.nombre, this.keywords);
}

class _ProductosEstrella extends StatefulWidget {
  const _ProductosEstrella();
  @override
  State<_ProductosEstrella> createState() => _ProductosEstrellaState();
}

class _ProductosEstrellaState extends State<_ProductosEstrella> {
  static const _estrella = [
    _Estrella('Cherry Cream',     ['cherry cream']),
    _Estrella('ChocoNachos',      ['choco nachos', 'choconachos']),
    _Estrella('Krispi Cream',     ['krispi cream']),
    _Estrella('ChocoSpaguetis',   ['spaguetti']),
    _Estrella('Choco Frappé',     ['frappe']),
    _Estrella('Fresas con crema', ['fresas con crema']),
    _Estrella('Krispi Bowl',      ['krispi bowl']),
    _Estrella('Melofresa',        ['melofresa']),
  ];

  List<Map<String, dynamic>> _productosDB = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  String? _getImg(_Estrella e) {
    for (final p in _productosDB) {
      final nombre = (p['nombre'] as String? ?? '').toLowerCase();
      for (final k in e.keywords) {
        if (nombre.contains(k.toLowerCase())) {
          return (p['img'] ?? p['imagen_url']) as String?;
        }
      }
    }
    return null;
  }

  Future<void> _fetch() async {
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.apiBaseUrl}/catalogo/productos'),
      );
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final list = data is List ? data : (data['productos'] ?? data['data'] ?? data) as List;
        setState(() {
          _productosDB = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _loading = false;
        });
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    return Container(
      color: const Color(0xFFF7F8FD),
      padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 28),
      child: Column(
        children: [
          Text('Nuestros productos estrella ⭐',
              style: GoogleFonts.nunito(
                fontSize: sw < 390 ? 22.0 : 28.0,
                fontWeight: FontWeight.w900, color: const Color(0xFF1a1a1a),
              ),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Creaciones únicas que no encontrarás en ningún otro lugar',
              style: GoogleFonts.nunito(fontSize: 14, color: const Color(0xFF666666), height: 1.6),
              textAlign: TextAlign.center),
          const SizedBox(height: 40),
          if (_loading)
            const CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.5)
          else
            LayoutBuilder(
              builder: (context, constraints) {
                // Antes el ancho de cada card salía de un clamp fijo (150-200)
                // que en la mayoría de celulares terminaba siendo más ancho
                // que la mitad del espacio disponible -- por eso cada
                // producto quedaba solo en su fila en vez de ir de a 2. Acá
                // se calcula el ancho exacto para que 2 quepan siempre,
                // sin importar el tamaño de pantalla.
                const spacing = 14.0;
                final cardWidth = (constraints.maxWidth - spacing) / 2;
                return Wrap(
                  spacing: spacing, runSpacing: spacing,
                  alignment: WrapAlignment.center,
                  children: _estrella.map((e) => _ProductoEstellaCard(
                    nombre: e.nombre,
                    imageUrl: _getImg(e),
                    width: cardWidth,
                  )).toList(),
                );
              },
            ),
          const SizedBox(height: 36),
          GestureDetector(
            onTap: () => context.go('/catalogo'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Color(0x33CA0B0B), blurRadius: 20, offset: Offset(0, 6))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Ver catálogo completo',
                    style: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductoEstellaCard extends StatelessWidget {
  final String nombre;
  final String? imageUrl;
  final double width;
  const _ProductoEstellaCard({required this.nombre, this.imageUrl, required this.width});

  @override
  Widget build(BuildContext context) {
    // Misma proporción 200:160 de siempre (1.25), pero escalada al ancho
    // real de la card en vez de una altura fija de 160 -- si no, con cards
    // angostas (2 por fila) la imagen quedaría recortada/desproporcionada.
    final cardHeight = width / 1.25;
    final imgUrl = imageUrl ?? '';

    final fallback = Container(
      width: width, height: cardHeight,
      color: const Color(0xFF2a2a2a),
      alignment: Alignment.center,
      child: Text(nombre.toUpperCase(),
          style: GoogleFonts.nunito(
            fontSize: 14, fontWeight: FontWeight.w900,
            color: Colors.white.withValues(alpha: 0.15),
          ),
          textAlign: TextAlign.center),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        width: width,
        height: cardHeight,
        child: Stack(
          children: [
            imgUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: imgUrl,
                    width: width, height: cardHeight, fit: BoxFit.cover,
                    placeholder: (_, __) => Container(width: width, height: cardHeight, color: const Color(0xFF2a2a2a)),
                    errorWidget: (_, __, ___) => fallback,
                  )
                : fallback,
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xBF000000)],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(12, 28, 12, 12),
                child: Text(nombre,
                    style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CONÓCENOS
// ─────────────────────────────────────────────────────────────────────────────

class _Conocenos extends StatelessWidget {
  const _Conocenos({super.key});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 700;
    final sw = MediaQuery.of(context).size.width;

    final imagenPlaceholder = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: CachedNetworkImage(
            imageUrl: 'https://res.cloudinary.com/diqeuyoqo/image/upload/v1781960585/951d154f-bddd-4c5a-b606-e5a38e309433_d2nfnl.jpg',
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: const Color(0xFFFDE8E8)),
            errorWidget: (_, __, ___) => Container(color: const Color(0xFFFDE8E8)),
          ),
        ),
      ),
    );

    final contenido = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('NUESTRA HISTORIA',
            style: GoogleFonts.nunito(
              fontSize: 11, fontWeight: FontWeight.w800,
              color: AppColors.primary, letterSpacing: 1.5)),
        const SizedBox(height: 12),
        Text('Conócenos',
            style: GoogleFonts.nunito(
              fontSize: sw < 390 ? 24.0 : 28.0,
              fontWeight: FontWeight.w900, color: const Color(0xFF1a1a1a))),
        const SizedBox(height: 14),
        Text(
          'ChocoFreseo nació en marzo de 2024 en Medellín, creado por una pareja de jóvenes con una visión única: postres con estética reggaetonera y juvenil. Nos hicimos reconocidos por llevar la comida salada al mundo dulce — ChocoNachos, ChocoSpaguetis y más experiencias que no habías probado antes.',
          style: GoogleFonts.nunito(fontSize: 14, color: const Color(0xFF555555), height: 1.6),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _SedeCard(nombre: '📍 Sede La Milagrosa', direccion: 'Carrera 29 #42-49\nLa Milagrosa, Medellín')),
          const SizedBox(width: 12),
          Expanded(child: _SedeCard(nombre: '📍 Sede Aranjuez', direccion: 'Calle 90 #50D-35\nAranjuez, Medellín')),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          const Icon(Icons.access_time_rounded, size: 16, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(
                text: 'Horario: ',
                style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF555555)),
              ),
              TextSpan(
                text: 'Todos los días · 1:00 PM – 8:00 PM',
                style: GoogleFonts.nunito(fontSize: 14, color: const Color(0xFF555555)),
              ),
            ])),
          ),
        ]),
      ],
    );

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 28),
      child: isWide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 5, child: imagenPlaceholder),
              const SizedBox(width: 40),
              Expanded(flex: 7, child: contenido),
            ])
          : Column(children: [
              imagenPlaceholder,
              const SizedBox(height: 32),
              contenido,
            ]),
    );
  }
}

class _SedeCard extends StatelessWidget {
  final String nombre;
  final String direccion;
  const _SedeCard({required this.nombre, required this.direccion});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF0F0F0)),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(nombre,
              style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
          const SizedBox(height: 6),
          Text(direccion,
              style: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF555555), height: 1.5)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VIDEO / REDES SOCIALES
// ─────────────────────────────────────────────────────────────────────────────

class _VideoRedes extends StatelessWidget {
  const _VideoRedes();

  static Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 28),
      child: Column(
        children: [
          Text('Aprende a pedir en 1 minuto',
              style: GoogleFonts.nunito(
                fontSize: sw < 390 ? 26.0 : 32.0,
                fontWeight: FontWeight.w900, color: const Color(0xFF1a1a1a), height: 1.2,
              ),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Mira este video rápido y descubre lo fácil que es hacer tu pedido en ChocoFreseo. Mientras tanto, síguenos en nuestras redes:',
              style: GoogleFonts.nunito(fontSize: 14, color: const Color(0xFF666666), height: 1.6),
              textAlign: TextAlign.center),
          const SizedBox(height: 36),

          const _VideoPlayer(),
          const SizedBox(height: 36),

          // Botones redes sociales
          Wrap(
            spacing: 12, runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              _SocialLinkBtn(
                icon: const LogoTikTok(size: 20, color: Colors.white), label: '@chocofreseo', sublabel: 'TikTok',
                bgColor: const Color(0xFF000000),
                onTap: () => _launch('https://tiktok.com/@chocofreseo'),
              ),
              _SocialLinkBtn(
                icon: const LogoInstagram(size: 20, color: Colors.white), label: '@chocofreseo', sublabel: 'Instagram',
                gradient: const LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF833AB4), Color(0xFFFD1D1D), Color(0xFFF77737)],
                ),
                onTap: () => _launch('https://instagram.com/chocofreseo'),
              ),
              _SocialLinkBtn(
                icon: const LogoTikTok(size: 20, color: Colors.white), label: '@sorprendetupaladar', sublabel: 'TikTok',
                bgColor: const Color(0xFF000000),
                onTap: () => _launch('https://tiktok.com/@sorprendetupaladar'),
              ),
              _SocialLinkBtn(
                icon: const LogoFacebook(size: 20, color: Colors.white), label: 'ChocoFreseo', sublabel: 'Facebook',
                bgColor: const Color(0xFF1877F2),
                onTap: () => _launch('https://www.facebook.com/share/1NiKgTtfUb/'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Reproductor del video tutorial "Aprende a pedir en 1 minuto" -- con
// controles nativos (Chewie), sin autoplay, igual criterio que el <video>
// de React (Landing.jsx). El controller solo se crea una vez el video
// termina de inicializar (initState es async), por eso el spinner
// mientras tanto.
class _VideoPlayer extends StatefulWidget {
  const _VideoPlayer();

  @override
  State<_VideoPlayer> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends State<_VideoPlayer> {
  static const _url =
      'https://res.cloudinary.com/diqeuyoqo/video/upload/v1787968751/ChocoFreseo_video_landing_v2_fark9e.mp4';

  late final VideoPlayerController _videoController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    _videoController = VideoPlayerController.networkUrl(Uri.parse(_url));
    _videoController.initialize().then((_) {
      if (!mounted) return;
      setState(() {
        _chewieController = ChewieController(
          videoPlayerController: _videoController,
          autoPlay: false,
          looping: false,
          aspectRatio: _videoController.value.aspectRatio,
          materialProgressColors: ChewieProgressColors(
            playedColor: AppColors.primary,
            handleColor: AppColors.primary,
          ),
          // Sin esto, Chewie fuerza landscape-only al entrar a fullscreen
          // (default: si el video es más ancho que alto, solo permite
          // landscapeLeft/Right -- ver chewie_player.dart:onEnterFullScreen).
          // Con las 4 orientaciones permitidas, el fullscreen respeta como
          // esté sostenido el celular en ese momento.
          deviceOrientationsOnEnterFullScreen: const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ],
          // El default de Chewie es DeviceOrientation.values (las 4), lo
          // cual dejaría el celular rotable libremente en el resto de la
          // app al salir del fullscreen -- pero main.dart bloquea toda la
          // app a solo portrait, así que hay que volver a eso explícito.
          deviceOrientationsAfterFullScreen: const [
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ],
        );
        // Chewie oculta la barra de sistema con SystemUiMode.manual +
        // overlays vacíos al entrar a fullscreen -- en celulares con
        // navegación por gestos, Android le agrega su propio aviso "Para
        // salir de la pantalla completa, arrastra desde la parte superior y
        // presiona Atrás", más largo que el de navegación por botones.
        // immersiveSticky (barras reaparecen momentáneamente con un swipe y
        // se ocultan solas) usa el flujo que Android trata como estándar, en
        // vez del que dispara ese aviso largo -- se aplica después de que
        // Chewie termina su propio cambio (postFrameCallback) para que no
        // nos lo sobreescriba.
        _chewieController!.addListener(_onChewieChange);
      });
    });
  }

  void _onChewieChange() {
    if (_chewieController?.isFullScreen == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      });
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 560),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a1a),
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.hardEdge,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: _chewieController != null
            ? Chewie(controller: _chewieController!)
            : const Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
    );
  }
}

class _SocialLinkBtn extends StatelessWidget {
  final Widget icon;
  final String label;
  final String sublabel;
  final Color? bgColor;
  final Gradient? gradient;
  final VoidCallback onTap;
  const _SocialLinkBtn({required this.icon, required this.label, required this.sublabel, this.bgColor, this.gradient, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: gradient == null ? bgColor : null,
          gradient: gradient,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          icon,
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(sublabel,
                style: GoogleFonts.nunito(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.6))),
            Text(label,
                style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
          ]),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CTA FINAL — Formulario de reseñas
// ─────────────────────────────────────────────────────────────────────────────

class _CtaFinal extends StatefulWidget {
  const _CtaFinal();
  @override
  State<_CtaFinal> createState() => _CtaFinalState();
}

class _CtaFinalState extends State<_CtaFinal> {
  String? _sede;
  String? _frecuencia;
  int _calAtencion = 0;
  int _calProducto = 0;
  String? _recomendaria;
  String? _tiempoAdecuado;
  final _loQueGustoCtrl      = TextEditingController();
  final _productoDeseadoCtrl = TextEditingController();
  final _mejoraCtrl          = TextEditingController();
  bool _enviando = false;
  bool _enviado  = false;
  String? _error;

  @override
  void dispose() {
    _loQueGustoCtrl.dispose();
    _productoDeseadoCtrl.dispose();
    _mejoraCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_sede == null || _frecuencia == null || _calAtencion == 0 ||
        _calProducto == 0 || _recomendaria == null || _tiempoAdecuado == null) {
      setState(() => _error = 'Por favor completa todos los campos requeridos.');
      return;
    }
    setState(() { _enviando = true; _error = null; });
    try {
      final res = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/resenas'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sede':                  _sede,
          'frecuencia':            _frecuencia,
          'calificacion_atencion': _calAtencion,
          'calificacion_producto': _calProducto,
          'recomendaria':          _recomendaria,
          'tiempo_adecuado':       _tiempoAdecuado,
          'lo_que_gusto':          _loQueGustoCtrl.text.trim(),
          'producto_deseado':      _productoDeseadoCtrl.text.trim(),
          'mejora':                _mejoraCtrl.text.trim(),
        }),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        if (mounted) setState(() { _enviado = true; _enviando = false; });
      } else {
        if (mounted) setState(() { _error = 'Error al enviar. Intenta de nuevo.'; _enviando = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = 'Sin conexión. Intenta de nuevo.'; _enviando = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;

    if (_enviado) {
      return Container(
        width: double.infinity,
        color: AppColors.primary,
        padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 28),
        child: Column(children: [
          const Text('🎉', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text('¡Gracias por tu reseña!',
              style: GoogleFonts.nunito(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white),
              textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text('Tu opinión nos ayuda a mejorar cada día.',
              style: GoogleFonts.nunito(fontSize: 15, color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
        ]),
      );
    }

    return Container(
      width: double.infinity,
      color: AppColors.primary,
      padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 28),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('TU OPINIÓN',
                style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.8)),
          ),
          const SizedBox(height: 12),
          Text('¿Cómo fue tu\nexperiencia?',
              style: GoogleFonts.nunito(
                fontSize: sw < 390 ? 26.0 : 32.0,
                fontWeight: FontWeight.w900, color: Colors.white, height: 1.2,
              ),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Cuéntanos cómo te fue. Tu reseña ayuda a otros clientes y a nosotros a mejorar.',
            style: GoogleFonts.nunito(
              fontSize: 14, color: Colors.white.withValues(alpha: 0.8),
              fontWeight: FontWeight.w600, height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 36),

          // Form card
          Container(
            constraints: const BoxConstraints(maxWidth: 560),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 32, offset: Offset(0, 8))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sede
                _FormLabel('¿En qué sede?'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _ChipOpt(label: 'La Milagrosa',  selected: _sede == 'La Milagrosa', onTap: () => setState(() => _sede = 'La Milagrosa')),
                  _ChipOpt(label: 'Aranjuez',      selected: _sede == 'Aranjuez',     onTap: () => setState(() => _sede = 'Aranjuez')),
                  _ChipOpt(label: 'Cocina Oculta', selected: _sede == 'WhatsApp',     onTap: () => setState(() => _sede = 'WhatsApp')),
                ]),
                const SizedBox(height: 20),

                // Frecuencia
                _FormLabel('¿Con qué frecuencia nos visitas?'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _ChipOpt(label: 'Primera vez',      selected: _frecuencia == 'primera_vez',      onTap: () => setState(() => _frecuencia = 'primera_vez')),
                  _ChipOpt(label: 'De vez en cuando', selected: _frecuencia == 'de_vez_en_cuando', onTap: () => setState(() => _frecuencia = 'de_vez_en_cuando')),
                  _ChipOpt(label: 'Casi siempre',     selected: _frecuencia == 'casi_siempre',     onTap: () => setState(() => _frecuencia = 'casi_siempre')),
                ]),
                const SizedBox(height: 20),

                // Calificación atención
                _FormLabel('Calificación de la atención'),
                const SizedBox(height: 8),
                _StarRow(value: _calAtencion, onChanged: (v) => setState(() => _calAtencion = v)),
                const SizedBox(height: 20),

                // Calificación producto
                _FormLabel('Calificación del producto'),
                const SizedBox(height: 8),
                _StarRow(value: _calProducto, onChanged: (v) => setState(() => _calProducto = v)),
                const SizedBox(height: 20),

                // Recomienda
                _FormLabel('¿Nos recomendarías?'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  _ChipOpt(label: 'Sí, claro', selected: _recomendaria == 'si',      onTap: () => setState(() => _recomendaria = 'si')),
                  _ChipOpt(label: 'Tal vez',   selected: _recomendaria == 'tal_vez', onTap: () => setState(() => _recomendaria = 'tal_vez')),
                  _ChipOpt(label: 'No',        selected: _recomendaria == 'no',      onTap: () => setState(() => _recomendaria = 'no')),
                ]),
                const SizedBox(height: 20),

                // Tiempo adecuado
                _FormLabel('¿El tiempo de entrega fue adecuado?'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  _ChipOpt(label: 'Sí',             selected: _tiempoAdecuado == 'si',             onTap: () => setState(() => _tiempoAdecuado = 'si')),
                  _ChipOpt(label: 'Podría mejorar', selected: _tiempoAdecuado == 'podria_mejorar', onTap: () => setState(() => _tiempoAdecuado = 'podria_mejorar')),
                  _ChipOpt(label: 'No',             selected: _tiempoAdecuado == 'no',             onTap: () => setState(() => _tiempoAdecuado = 'no')),
                ]),
                const SizedBox(height: 20),

                // Textareas opcionales
                _FormLabel('¿Qué fue lo que más te gustó? (opcional)'),
                const SizedBox(height: 8),
                TextField(
                  controller: _loQueGustoCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'El sabor, la atención, la presentación...',
                    hintStyle: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF999999)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
                  ),
                  style: GoogleFonts.nunito(fontSize: 14),
                ),
                const SizedBox(height: 16),
                _FormLabel('¿Qué postre quisieras ver próximamente? (opcional)'),
                const SizedBox(height: 8),
                TextField(
                  controller: _productoDeseadoCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Dinos qué antojo nos falta...',
                    hintStyle: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF999999)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
                  ),
                  style: GoogleFonts.nunito(fontSize: 14),
                ),
                const SizedBox(height: 16),
                _FormLabel('¿En qué podríamos mejorar? (opcional)'),
                const SizedBox(height: 8),
                TextField(
                  controller: _mejoraCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Tu opinión nos ayuda a crecer...',
                    hintStyle: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF999999)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
                  ),
                  style: GoogleFonts.nunito(fontSize: 14),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!,
                      style: GoogleFonts.nunito(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _enviando ? null : _enviar,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: _enviando
                          ? const SizedBox(height: 20, width: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text('Enviar reseña',
                              style: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FormLabel extends StatelessWidget {
  final String text;
  const _FormLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF444444)));
}

class _ChipOpt extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ChipOpt({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? AppColors.primary : const Color(0xFFE0E0E0)),
        ),
        child: Text(label,
            style: GoogleFonts.nunito(
              fontSize: 13, fontWeight: FontWeight.w700,
              color: selected ? Colors.white : const Color(0xFF444444),
            )),
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _StarRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) => GestureDetector(
        onTap: () => onChanged(i + 1),
        child: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(
            i < value ? Icons.star_rounded : Icons.star_outline_rounded,
            color: i < value ? const Color(0xFFF59E0B) : const Color(0xFFD1D5DB),
            size: 28,
          ),
        ),
      )),
    );
  }
}
