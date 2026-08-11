import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../providers/auth_provider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nombreCtrl  = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();

  String? _nombreError;
  String? _emailError;
  String? _passError;
  String? _confirmError;
  String? _generalError;

  bool _loading     = false;
  bool _obscurePass = true;
  bool _obscureConf = true;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool _validarNombre(String nombre) {
    if (nombre.isEmpty) {
      setState(() => _nombreError = 'Ingresa tu nombre completo');
      return false;
    }
    if (nombre.length < 2) {
      setState(() => _nombreError = 'El nombre debe tener al menos 2 caracteres');
      return false;
    }
    setState(() => _nombreError = null);
    return true;
  }

  bool _validarEmail(String email) {
    if (email.isEmpty) {
      setState(() => _emailError = 'Ingresa tu correo electrónico');
      return false;
    }
    final regex = RegExp(r'^[\w\.-]+@[\w\.-]+\.\w{2,}$');
    if (!regex.hasMatch(email)) {
      setState(() => _emailError = 'El correo no tiene un formato válido\nEjemplo: usuario@gmail.com');
      return false;
    }
    setState(() => _emailError = null);
    return true;
  }

  bool _validarPassword(String pass) {
    if (pass.isEmpty) {
      setState(() => _passError = 'Ingresa una contraseña');
      return false;
    }
    if (pass.length < 8) {
      setState(() => _passError = 'La contraseña debe tener mínimo 8 caracteres');
      return false;
    }
    setState(() => _passError = null);
    return true;
  }

  bool _validarConfirm(String pass, String confirm) {
    if (confirm.isEmpty) {
      setState(() => _confirmError = 'Repite tu contraseña');
      return false;
    }
    if (pass != confirm) {
      setState(() => _confirmError = 'Las contraseñas no coinciden');
      return false;
    }
    setState(() => _confirmError = null);
    return true;
  }

  String _parsearErrorBackend(String error) {
    final e = error.toLowerCase();
    if (e.contains('ya existe') || e.contains('already') || e.contains('duplicado') || e.contains('registrado')) {
      return 'Ya existe una cuenta con ese correo electrónico';
    }
    if (e.contains('conexión') || e.contains('internet') || e.contains('timeout')) {
      return 'Sin conexión a internet, verifica tu red';
    }
    return error;
  }

  Future<void> _handleRegistro() async {
    setState(() { _generalError = null; _nombreError = null; _emailError = null; _passError = null; _confirmError = null; });
    final n = _nombreCtrl.text.trim();
    final e = _emailCtrl.text.trim();
    final p = _passCtrl.text.trim();
    final c = _confirmCtrl.text.trim();
    final nombreOk  = _validarNombre(n);
    final emailOk   = _validarEmail(e);
    final passOk    = _validarPassword(p);
    final confirmOk = _validarConfirm(p, c);
    if (!nombreOk || !emailOk || !passOk || !confirmOk) return;
    setState(() => _loading = true);
    try {
      final ok = await context.read<AuthProvider>().register(
        nombre: n, email: e, password: p,
      );
      if (!mounted) return;
      if (!ok) {
        final msg = context.read<AuthProvider>().errorMessage ?? 'Error al crear la cuenta';
        setState(() => _generalError = _parsearErrorBackend(msg));
        return;
      }
      // Igual que React Registro.jsx: el registro público siempre crea un
      // cliente y navega a /landing, sin ramas por rol.
      context.go('/landing');
    } catch (ex) {
      if (mounted) setState(() => _generalError = _parsearErrorBackend(ex.toString().replaceFirst('Exception: ', '')));
    } finally {
      if (mounted) setState(() => _loading = false);
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
        Text('Únete a la\nfamilia',
            style: GoogleFonts.nunito(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.white, height: 1.15)),
        const SizedBox(height: 20),
        Text('Regístrate y disfruta de los mejores helados y waffles artesanales a domicilio.',
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

  Widget _formBox() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Crear cuenta', style: GoogleFonts.nunito(fontSize: 26, fontWeight: FontWeight.w900, color: const Color(0xFF1a1a1a))),
    const SizedBox(height: 4),
    Text('🎁 ¡Gana 200 puntos solo por registrarte!',
        style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF16A34A))),
    const SizedBox(height: 28),

    _lbl('Nombre completo'),
    _inputField(controller: _nombreCtrl, hint: 'Ej: Ana Gómez', error: _nombreError,
        onChanged: (_) => setState(() => _nombreError = null)),
    const SizedBox(height: 20),

    _lbl('Correo electrónico'),
    _inputField(controller: _emailCtrl, hint: 'correo@ejemplo.com',
        type: TextInputType.emailAddress, error: _emailError,
        onChanged: (_) => setState(() => _emailError = null)),
    const SizedBox(height: 20),

    _lbl('Contraseña'),
    _passField(_passCtrl, 'Mínimo 8 caracteres', _obscurePass, _passError,
        () => setState(() => _obscurePass = !_obscurePass),
        (_) => setState(() => _passError = null)),
    const SizedBox(height: 20),

    _lbl('Confirmar contraseña'),
    _passField(_confirmCtrl, 'Repite tu contraseña', _obscureConf, _confirmError,
        () => setState(() => _obscureConf = !_obscureConf),
        (_) => setState(() => _confirmError = null)),

    if (_generalError != null) ...[const SizedBox(height: 16), _err(_generalError!)],
    const SizedBox(height: 20),

    SizedBox(width: double.infinity, child: ElevatedButton(
      onPressed: _loading ? null : _handleRegistro,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0,
      ),
      child: _loading
          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
          : Text('Crear cuenta', style: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
    )),
    const SizedBox(height: 20),

    Center(child: RichText(text: TextSpan(
      style: GoogleFonts.nunito(fontSize: 14, color: const Color(0xFF888888), fontWeight: FontWeight.w600),
      children: [
        const TextSpan(text: '¿Ya tienes cuenta? '),
        WidgetSpan(child: GestureDetector(
          onTap: () => context.go('/login'),
          child: Text('Inicia sesión',
              style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary)),
        )),
      ],
    ))),
  ]);

  Widget _lbl(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF333333))),
  );

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    TextInputType type = TextInputType.text,
    String? error,
    ValueChanged<String>? onChanged,
  }) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    TextField(
      controller: controller, keyboardType: type, onChanged: onChanged,
      style: GoogleFonts.nunito(fontSize: 14, color: const Color(0xFF1a1a1a)),
      decoration: _inputDec(hint, hasError: error != null),
    ),
    if (error != null) ...[
      const SizedBox(height: 5),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline, size: 13, color: Color(0xFFE53935)),
        const SizedBox(width: 4),
        Expanded(child: Text(error, style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFFE53935)))),
      ]),
    ],
  ]);

  Widget _passField(TextEditingController c, String hint, bool obscure, String? error,
      VoidCallback toggle, ValueChanged<String> onChanged) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    TextField(
      controller: c, obscureText: obscure, onChanged: onChanged,
      style: GoogleFonts.nunito(fontSize: 14, color: const Color(0xFF1a1a1a)),
      decoration: _inputDec(hint, hasError: error != null).copyWith(
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 18, color: const Color(0xFF888888)),
          onPressed: toggle,
        ),
      ),
    ),
    if (error != null) ...[
      const SizedBox(height: 5),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline, size: 13, color: Color(0xFFE53935)),
        const SizedBox(width: 4),
        Expanded(child: Text(error, style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFFE53935)))),
      ]),
    ],
  ]);

  InputDecoration _inputDec(String hint, {bool hasError = false}) => InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.nunito(fontSize: 14, color: const Color(0xFFAAAAAA)),
    filled: true,
    fillColor: hasError ? const Color(0xFFFFF5F5) : const Color(0xFFFAFAFA),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: hasError ? const Color(0xFFE53935) : const Color(0xFFE0E0E0), width: 1.5)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: hasError ? const Color(0xFFE53935) : const Color(0xFFE0E0E0), width: 1.5)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: hasError ? const Color(0xFFE53935) : AppColors.primary, width: 1.5)),
  );

  Widget _err(String msg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: const Color(0xFFFFF5F5), border: Border.all(color: const Color(0xFFFDA4AF)), borderRadius: BorderRadius.circular(8)),
    child: Row(children: [
      const Icon(Icons.error_outline, size: 16, color: Color(0xFFE53935)),
      const SizedBox(width: 8),
      Expanded(child: Text(msg, style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFFE53935)))),
    ]),
  );

  Widget _deco(double size) => Container(
    width: size, height: size,
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.07), shape: BoxShape.circle),
  );
}