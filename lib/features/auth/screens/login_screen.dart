import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/auth_service.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl  = TextEditingController();
  final _passCtrl   = TextEditingController();

  String? _emailError;
  String? _passError;
  String? _generalError;

  bool _loading     = false;
  bool _obscurePass = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
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
      setState(() => _passError = 'Ingresa tu contraseña');
      return false;
    }
    setState(() => _passError = null);
    return true;
  }

  String _parsearErrorBackend(String error) {
    final e = error.toLowerCase();
    if (e.contains('credenciales') || e.contains('incorrectas') || e.contains('invalid') || e.contains('wrong')) {
      return 'El correo o la contraseña son incorrectos';
    }
    if (e.contains('no existe') || e.contains('not found') || e.contains('usuario no')) {
      return 'No existe una cuenta con ese correo';
    }
    if (e.contains('desactivad') || e.contains('inactiv') || e.contains('disabled')) {
      return 'Usuario inactivo. Por favor, contáctate con el administrador.';
    }
    if (e.contains('conexión') || e.contains('internet') || e.contains('timeout')) {
      return 'Sin conexión a internet, verifica tu red';
    }
    return error;
  }

  Future<void> _handleLogin() async {
    setState(() { _generalError = null; _emailError = null; _passError = null; });
    final email = _emailCtrl.text.trim();
    final pass  = _passCtrl.text.trim();
    final emailOk = _validarEmail(email);
    final passOk  = _validarPassword(pass);
    if (!emailOk || !passOk) return;
    setState(() => _loading = true);
    try {
      // AuthProvider.login() nunca lanza — atrapa sus propios errores y
      // devuelve un bool. Antes este código ignoraba ese resultado y
      // navegaba igual aunque el login fallara (credenciales incorrectas
      // dejaban "seguir" a /landing sin haber iniciado sesión, sin mostrar
      // ningún error).
      final auth = context.read<AuthProvider>();
      final ok = await auth.login(email, pass);
      if (!mounted) return;
      if (!ok) {
        setState(() => _generalError = _parsearErrorBackend(auth.errorMessage ?? 'El correo o la contraseña son incorrectos'));
        return;
      }
      final role = auth.user?.role;
      // Igual que React Login.jsx: solo admin/domiciliario tienen ruta directa;
      // cualquier otro rol (cliente, confirmador_domicilio, cocinero, etc.)
      // cae en /landing.
      if (role == UserRole.admin) {
        context.go('/admin/dashboard');
      } else if (role == UserRole.domiciliario) {
        context.go('/domiciliario/pedidos');
      } else {
        context.go('/landing');
      }
    } catch (e) {
      setState(() => _generalError = _parsearErrorBackend(e.toString().replaceFirst('Exception: ', '')));
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
        Text('El sabor que\nte enamora',
            style: GoogleFonts.nunito(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.white, height: 1.15)),
        const SizedBox(height: 20),
        Text('Helados, waffles y crepes artesanales hechos con amor para ti.',
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
    GestureDetector(
      onTap: () => context.go('/landing'),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: Color(0xFF666666)),
          const SizedBox(width: 6),
          Text('Volver al inicio',
              style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF666666))),
        ]),
      ),
    ),
    Text('Bienvenido de nuevo', style: GoogleFonts.nunito(fontSize: 26, fontWeight: FontWeight.w900, color: const Color(0xFF1a1a1a))),
    const SizedBox(height: 6),
    Text('Ingresa tus datos para continuar', style: GoogleFonts.nunito(fontSize: 14, color: const Color(0xFF888888), fontWeight: FontWeight.w600)),
    const SizedBox(height: 32),

    _lbl('Correo electrónico'),
    _inputField(controller: _emailCtrl, hint: 'correo@ejemplo.com',
        type: TextInputType.emailAddress, error: _emailError,
        onChanged: (_) => setState(() => _emailError = null)),
    const SizedBox(height: 20),

    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      _lbl('Contraseña'),
      GestureDetector(
        onTap: () => context.go('/forgot-password'),
        child: Text('¿Olvidaste tu contraseña?',
            style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
      ),
    ]),
    const SizedBox(height: 8),
    _passInput(),

    if (_generalError != null) ...[const SizedBox(height: 16), _err(_generalError!)],
    const SizedBox(height: 20),

    SizedBox(width: double.infinity, child: ElevatedButton(
      onPressed: _loading ? null : _handleLogin,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0,
      ),
      child: _loading
          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
          : Text('Iniciar sesión', style: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
    )),
    const SizedBox(height: 20),

    Row(children: [
      const Expanded(child: Divider(color: Color(0xFFE0E0E0), thickness: 1)),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('o', style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFFAAAAAA)))),
      const Expanded(child: Divider(color: Color(0xFFE0E0E0), thickness: 1)),
    ]),
    const SizedBox(height: 20),

    Center(child: RichText(text: TextSpan(
      style: GoogleFonts.nunito(fontSize: 14, color: const Color(0xFF888888), fontWeight: FontWeight.w600),
      children: [
        const TextSpan(text: '¿No tienes cuenta? '),
        WidgetSpan(child: GestureDetector(
          onTap: () => context.go('/register'),
          child: Text('Regístrate gratis',
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

  Widget _passInput() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    TextField(
      controller: _passCtrl, obscureText: _obscurePass,
      onChanged: (_) => setState(() => _passError = null),
      style: GoogleFonts.nunito(fontSize: 14, color: const Color(0xFF1a1a1a)),
      decoration: _inputDec('••••••••', hasError: _passError != null).copyWith(
        suffixIcon: IconButton(
          icon: Icon(_obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 18, color: const Color(0xFF888888)),
          onPressed: () => setState(() => _obscurePass = !_obscurePass),
        ),
      ),
    ),
    if (_passError != null) ...[
      const SizedBox(height: 5),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline, size: 13, color: Color(0xFFE53935)),
        const SizedBox(width: 4),
        Expanded(child: Text(_passError!, style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFFE53935)))),
      ]),
    ],
  ]);

  InputDecoration _inputDec(String hint, {bool hasError = false}) => InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.nunito(fontSize: 14, color: const Color(0xFFAAAAAA)),
    filled: true,
    fillColor: hasError ? const Color(0xFFFFF5F5) : const Color(0xFFFAFAFA),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    border:        OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: hasError ? const Color(0xFFE53935) : const Color(0xFFE0E0E0), width: 1.5)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: hasError ? const Color(0xFFE53935) : const Color(0xFFE0E0E0), width: 1.5)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: hasError ? const Color(0xFFE53935) : AppColors.primary, width: 1.5)),
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