import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_service.dart';

// Si se llegó aquí empujado desde Login (context.push), volver hace pop y
// cae de nuevo sobre esa misma pantalla -- back "estilo web". Si se llegó
// directo (sin nada que popear, ej. deep link), .go('/login') es el
// fallback -- evita apilar un Login nuevo encima de otro ya existente.
void _volverALogin(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/login');
  }
}

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  int _paso = 1; // 1=email, 2=código+nueva pass

  // Paso 1
  final _emailCtrl = TextEditingController();

  // Paso 2
  final _codigoCtrl    = TextEditingController();
  final _nuevaCtrl     = TextEditingController();
  final _confirmarCtrl = TextEditingController();
  bool _obscureNueva     = true;
  bool _obscureConfirmar = true;

  String? _error;
  bool _loading = false;
  bool _exito   = false;
  String? _devToken;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codigoCtrl.dispose();
    _nuevaCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  // ── Paso 1: solicitar código ──────────────────────────────────
  Future<void> _handleSolicitar() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Ingresa tu correo electrónico');
      return;
    }
    if (!RegExp(r'\S+@\S+\.\S+').hasMatch(email)) {
      setState(() => _error = 'Ingresa un correo válido');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ApiService.post('/api/auth/solicitar-reset', {'email': email}, auth: false);
      final inner = data is Map && data['data'] is Map ? data['data'] as Map : (data is Map ? data : const {});
      if (mounted) {
        setState(() {
          _loading = false;
          _devToken = inner['dev_token']?.toString();
          _paso = 2;
        });
      }
    } on ApiException catch (e) {
      // Igual que React: solo avanza al paso 2 si la solicitud tuvo éxito;
      // si falla (ej. sin conexión), se queda en el paso 1 mostrando el error.
      if (mounted) setState(() { _loading = false; _error = e.message; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'No se pudo procesar la solicitud'; });
    }
  }

  // ── Paso 2: verificar código y cambiar contraseña ─────────────
  Future<void> _handleCambiar() async {
    final codigo    = _codigoCtrl.text.trim();
    final nueva     = _nuevaCtrl.text;
    final confirmar = _confirmarCtrl.text;

    if (codigo.length != 6) {
      setState(() => _error = 'Ingresa el código de 6 dígitos'); return;
    }
    if (nueva.isEmpty) {
      setState(() => _error = 'Ingresa la nueva contraseña'); return;
    }
    if (nueva.length < 8) {
      setState(() => _error = 'La contraseña debe tener mínimo 8 caracteres'); return;
    }
    if (nueva != confirmar) {
      setState(() => _error = 'Las contraseñas no coinciden'); return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      await ApiService.post('/api/auth/verificar-reset', {
        'email':           _emailCtrl.text.trim(),
        'codigo':          codigo,
        'nueva_password':  nueva,
      }, auth: false);
      if (mounted) setState(() { _loading = false; _exito = true; });
    } on ApiException catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.message; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Error al cambiar la contraseña'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 700;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(child: isWide ? _wide() : _mobile()),
    );
  }

  Widget _wide() => Row(children: [
    Flexible(flex: 45, child: _izquierda()),
    Flexible(flex: 55, child: _derecha()),
  ]);

  Widget _mobile() => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(children: [
      const SizedBox(height: 40),
      Column(children: [
        CachedNetworkImage(
          imageUrl: 'https://res.cloudinary.com/dnoxlv5kn/image/upload/v1778822634/logo_sin_fondo_remove_uuu8tt.png',
          width: 100, height: 100, fit: BoxFit.contain,
          placeholder: (_, __) => const SizedBox(width: 100, height: 100),
          errorWidget: (_, __, ___) => Text('CF',
              style: GoogleFonts.nunito(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.primary)),
        ),
        const SizedBox(height: 8),
        Text('ChocoFreseo',
            style: GoogleFonts.nunito(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.primary)),
        Text('Puro Freseo',
            style: GoogleFonts.nunito(fontSize: 13, color: const Color(0xFF888888), fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 40),
      _formBox(),
    ]),
  );

  Widget _izquierda() => Container(
    height: double.infinity, color: AppColors.primary, padding: const EdgeInsets.all(48),
    child: Stack(children: [
      Positioned(bottom: -60, right: -60, child: _deco(260)),
      Positioned(top: 30, right: 30,      child: _deco(160)),
      Positioned(top: 0, right: -20,      child: _deco(90)),
      Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CachedNetworkImage(
            imageUrl: 'https://res.cloudinary.com/dnoxlv5kn/image/upload/v1778822634/logo_sin_fondo_remove_uuu8tt.png',
            width: 48, height: 48, fit: BoxFit.contain,
            placeholder: (_, __) => const SizedBox(width: 48, height: 48),
            errorWidget: (_, __, ___) => Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: Text('CF', style: GoogleFonts.nunito(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 15)),
            ),
          ),
          const SizedBox(width: 12),
          Text('ChocoFreseo', style: GoogleFonts.nunito(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
        ]),
        const SizedBox(height: 60),
        Text('No te\npreocupes',
            style: GoogleFonts.nunito(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.white, height: 1.15)),
        const SizedBox(height: 20),
        Text('Te ayudamos a recuperar el acceso a tu cuenta en segundos.',
            style: GoogleFonts.nunito(fontSize: 15, color: Colors.white.withValues(alpha: 0.75), fontWeight: FontWeight.w600, height: 1.6)),
      ]),
    ]),
  );

  Widget _derecha() => Container(
    color: Colors.white,
    child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400), child: _formBox()),
    )),
  );

  Widget _formBox() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (!_exito)
        GestureDetector(
          onTap: () => _volverALogin(context),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: Color(0xFF666666)),
              const SizedBox(width: 6),
              Text('Volver a iniciar sesión',
                  style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF666666))),
            ]),
          ),
        ),
      if (_exito) _exitoWidget()
      else if (_paso == 1) _paso1Widget()
      else _paso2Widget(),
    ],
  );

  // ── Éxito ─────────────────────────────────────────────────────
  Widget _exitoWidget() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Center(child: Icon(Icons.check_circle_rounded, size: 56, color: Color(0xFF22C55E))),
      const SizedBox(height: 24),
      Text('Contraseña actualizada',
          style: GoogleFonts.nunito(fontSize: 26, fontWeight: FontWeight.w900, color: const Color(0xFF1a1a1a))),
      const SizedBox(height: 8),
      Text('Tu contraseña se cambió correctamente. Ya puedes iniciar sesión.',
          style: GoogleFonts.nunito(fontSize: 14, color: const Color(0xFF888888), fontWeight: FontWeight.w600)),
      const SizedBox(height: 28),
      SizedBox(width: double.infinity, child: ElevatedButton(
        onPressed: () => context.go('/login'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
        child: Text('Iniciar sesión',
            style: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
      )),
    ],
  );

  // ── Paso 1: email ─────────────────────────────────────────────
  Widget _paso1Widget() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Recuperar contraseña',
          style: GoogleFonts.nunito(fontSize: 26, fontWeight: FontWeight.w900, color: const Color(0xFF1a1a1a))),
      const SizedBox(height: 6),
      Text('Ingresa tu correo y te enviaremos un código de verificación',
          style: GoogleFonts.nunito(fontSize: 14, color: const Color(0xFF888888), fontWeight: FontWeight.w600)),
      const SizedBox(height: 32),

      _label('Correo electrónico'),
      _input(
        controller: _emailCtrl,
        hint: 'correo@ejemplo.com',
        keyboardType: TextInputType.emailAddress,
        onChanged: (_) => setState(() => _error = null),
      ),

      if (_error != null) _errorBox(_error!),
      const SizedBox(height: 20),

      SizedBox(width: double.infinity, child: ElevatedButton(
        onPressed: _loading ? null : _handleSolicitar,
        style: _btnStyle(),
        child: _loading
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
            : Text('Enviar código',
                style: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
      )),
      const SizedBox(height: 20),
      Center(child: GestureDetector(
        onTap: () => _volverALogin(context),
        child: Text('← Volver al inicio de sesión',
            style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary)),
      )),
    ],
  );

  // ── Paso 2: código + nueva contraseña ─────────────────────────
  Widget _paso2Widget() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Nueva contraseña',
          style: GoogleFonts.nunito(fontSize: 26, fontWeight: FontWeight.w900, color: const Color(0xFF1a1a1a))),
      const SizedBox(height: 6),
      RichText(text: TextSpan(
        style: GoogleFonts.nunito(fontSize: 14, color: const Color(0xFF888888), fontWeight: FontWeight.w600),
        children: [
          const TextSpan(text: 'Ingresa el código de 6 dígitos enviado a '),
          TextSpan(text: _emailCtrl.text,
              style: GoogleFonts.nunito(fontWeight: FontWeight.w800, color: const Color(0xFF1a1a1a))),
        ],
      )),
      if (_devToken != null && _devToken!.isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            border: Border.all(color: const Color(0xFFF59E0B)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: RichText(text: TextSpan(
            style: GoogleFonts.nunito(fontSize: 13),
            children: [
              TextSpan(text: 'Código de desarrollo: ',
                  style: GoogleFonts.nunito(fontWeight: FontWeight.w700, color: const Color(0xFF92400E))),
              TextSpan(text: _devToken,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w900,
                      color: Color(0xFF78350F), letterSpacing: 3)),
            ],
          )),
        ),
      ],
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          border: Border.all(color: const Color(0xFFFFD54F)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          const Icon(Icons.timer_outlined, size: 16, color: Color(0xFFF57F17)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'El código es válido por 5 minutos. Si venció, solicita uno nuevo.',
              style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFFF57F17)),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 20),

      _label('Código de verificación'),
      TextField(
        controller: _codigoCtrl,
        keyboardType: TextInputType.number,
        maxLength: 6,
        textAlign: TextAlign.center,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => setState(() => _error = null),
        style: GoogleFonts.nunito(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 12, color: AppColors.primary),
        decoration: InputDecoration(
          counterText: '',
          hintText: '• • • • • •',
          hintStyle: GoogleFonts.nunito(fontSize: 22, color: const Color(0xFFCCCCCC), letterSpacing: 8),
          filled: true, fillColor: const Color(0xFFFAFAFA),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0), width: 1.5)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0), width: 1.5)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        ),
      ),
      const SizedBox(height: 16),

      _label('Nueva contraseña'),
      _input(
        controller: _nuevaCtrl,
        hint: '••••••••',
        obscureText: _obscureNueva,
        onChanged: (_) => setState(() => _error = null),
        suffixIcon: IconButton(
          icon: Icon(_obscureNueva ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: const Color(0xFFAAAAAA), size: 20),
          onPressed: () => setState(() => _obscureNueva = !_obscureNueva),
        ),
      ),
      const SizedBox(height: 16),

      _label('Confirmar contraseña'),
      _input(
        controller: _confirmarCtrl,
        hint: '••••••••',
        obscureText: _obscureConfirmar,
        onChanged: (_) => setState(() => _error = null),
        suffixIcon: IconButton(
          icon: Icon(_obscureConfirmar ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: const Color(0xFFAAAAAA), size: 20),
          onPressed: () => setState(() => _obscureConfirmar = !_obscureConfirmar),
        ),
      ),

      if (_error != null) _errorBox(_error!),
      const SizedBox(height: 20),

      SizedBox(width: double.infinity, child: ElevatedButton(
        onPressed: _loading ? null : _handleCambiar,
        style: _btnStyle(),
        child: _loading
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
            : Text('Cambiar contraseña',
                style: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
      )),
      const SizedBox(height: 20),
      Center(child: GestureDetector(
        onTap: () => setState(() { _paso = 1; _error = null; _codigoCtrl.clear(); }),
        child: Text('← Volver',
            style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary)),
      )),
    ],
  );

  // ── Helpers de UI ─────────────────────────────────────────────
  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF333333))),
  );

  Widget _input({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    bool obscureText = false,
    void Function(String)? onChanged,
    Widget? suffixIcon,
  }) => TextField(
    controller: controller,
    keyboardType: keyboardType,
    obscureText: obscureText,
    onChanged: onChanged,
    style: GoogleFonts.nunito(fontSize: 14, color: const Color(0xFF1a1a1a)),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.nunito(fontSize: 14, color: const Color(0xFFAAAAAA)),
      suffixIcon: suffixIcon,
      filled: true, fillColor: const Color(0xFFFAFAFA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0), width: 1.5)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0), width: 1.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
    ),
  );

  Widget _errorBox(String msg) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        border: Border.all(color: const Color(0xFFFDA4AF)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(msg, style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
    ),
  );

  ButtonStyle _btnStyle() => ElevatedButton.styleFrom(
    backgroundColor: AppColors.primary,
    padding: const EdgeInsets.symmetric(vertical: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    elevation: 0,
  );

  Widget _deco(double size) => Container(
    width: size, height: size,
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.07), shape: BoxShape.circle),
  );
}
