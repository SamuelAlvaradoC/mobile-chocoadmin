import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/constants/app_theme.dart';
import 'core/services/auth_service.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/cliente/providers/catalogo_provider.dart';
import 'features/cliente/providers/carrito_provider.dart';

// Auth
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/auth/screens/forgot_password_screen.dart';

// Splash
import 'shared/screens/splash_screen.dart';

// Cliente
import 'features/cliente/screens/catalogo_screen.dart';
import 'features/cliente/screens/checkout_screen.dart';
import 'features/cliente/screens/pedido_exitoso_screen.dart';
import 'features/cliente/screens/perfil_screen.dart';
import 'features/cliente/screens/puntos_screen.dart';
import 'shared/layouts/client_bottom_nav.dart';
import 'shared/layouts/root_shell_scaffold.dart';

// Domiciliario
import 'features/domiciliario/screens/pedidos_screen.dart';
import 'features/domiciliario/screens/cierre_caja_screen.dart';

// Cliente landing
import 'features/cliente/screens/landing_screen.dart';

// Admin
import 'features/admin/screens/dashboard_screen.dart';
import 'features/admin/screens/ventas_screen.dart';
import 'features/admin/screens/domicilios_screen.dart';
import 'features/admin/screens/productos_modulo_screen.dart';

// Cocina
import 'features/cocina/screens/cocina_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_CO', null);
  GoogleFonts.config.allowRuntimeFetching = true;
  // Status bar transparente con íconos oscuros: el AppBar es blanco
  // (AppColors.surface) en toda la app, así que se funde con el contenido
  // en vez de mostrar la barra gris/blanca por defecto del sistema.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));
  runApp(const ChocAdminApp());
}

class ChocAdminApp extends StatelessWidget {
  const ChocAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CatalogoProvider()),
        ChangeNotifierProvider(create: (_) => CarritoProvider()),
      ],
      child: const _AppRouter(),
    );
  }
}

class _AppRouter extends StatefulWidget {
  const _AppRouter();

  @override
  State<_AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<_AppRouter> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    _router = GoRouter(
      initialLocation: '/splash',
      redirect: _redirect,
      refreshListenable: authProvider,
      routes: [
        GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),

        // ── Auth ────────────────────────────────────────────
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
        GoRoute(
            path: '/forgot-password',
            builder: (_, __) => const ForgotPasswordScreen()),

        // ── Cliente ─────────────────────────────────────────
        GoRoute(path: '/landing', builder: (_, __) => const LandingScreen()),
        GoRoute(
          path: '/checkout',
          builder: (_, state) {
            final extra = state.extra as Map<String, dynamic>?;
            return CheckoutScreen(initialPuntosUsados: extra?['puntosAUsar'] as int? ?? 0);
          },
        ),
        GoRoute(
            path: '/pedido-exitoso',
            builder: (_, state) {
              final extra = state.extra as Map<String, dynamic>?;
              return PedidoExitosoScreen(
                  distanciaKm: (extra?['distanciaKm'] as num?)?.toDouble() ?? 0);
            }),

        // Shell del rol Cliente: Catálogo/Puntos/Perfil, cada uno con su
        // propio Navigator (historial de "atrás" independiente por tab).
        // Checkout y PedidoExitoso quedan fuera a propósito (no tendría
        // sentido que "atrás" devuelva a mitad de un pedido ya hecho).
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => RootShellScaffold(
            navigationShell: navigationShell,
            bottomNavBuilder: (shell) => ClientBottomNav(navigationShell: shell),
          ),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(path: '/catalogo', builder: (_, __) => const CatalogoScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/puntos', builder: (_, __) => const PuntosScreen()),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(path: '/perfil', builder: (_, __) => const PerfilScreen()),
            ]),
          ],
        ),

        // ── Domiciliario ─────────────────────────────────────
        GoRoute(
            path: '/domiciliario/pedidos',
            builder: (_, __) => const PedidosScreen()),
        GoRoute(
            path: '/domiciliario/caja',
            builder: (_, __) => const CierreCajaScreen()),

        // ── Admin ────────────────────────────────────────────
        GoRoute(path: '/admin/dashboard', builder: (_, __) => const DashboardScreen()),
        GoRoute(path: '/admin/ventas', builder: (_, __) => const VentasScreen()),
        GoRoute(path: '/admin/domicilios', builder: (_, __) => const DomiciliosScreen()),
        GoRoute(path: '/admin/productos', builder: (_, __) => const ProductosModuloScreen()),

        // ── Cocina ───────────────────────────────────────────
        GoRoute(path: '/cocina', builder: (_, __) => const CocinaScreen()),
      ],
    );
  }

  String? _redirect(BuildContext context, GoRouterState state) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final location = state.matchedLocation;

    if (auth.status == AuthStatus.initial ||
        auth.status == AuthStatus.loading) {
      return location == '/splash' ? null : '/splash';
    }

    // Rutas que no requieren autenticación
    const authRoutes   = ['/login', '/register', '/forgot-password'];
    const publicRoutes = ['/landing', '/catalogo'];

    if (auth.status == AuthStatus.unauthenticated ||
        auth.status == AuthStatus.error) {
      if (authRoutes.contains(location) || publicRoutes.contains(location)) {
        return null; // permitir sin login
      }
      return '/catalogo'; // resto de rutas → catálogo público
    }

    // Autenticado: redirigir fuera de auth/splash al home del rol
    if (location == '/splash' || authRoutes.contains(location)) {
      return _homeForRole(auth.user?.role);
    }

    // Guardar acceso cruzado de roles
    if (auth.user?.role == UserRole.domiciliario &&
        (location.startsWith('/admin'))) {
      return '/domiciliario/pedidos';
    }
    if (auth.user?.role == UserRole.admin &&
        (location.startsWith('/domiciliario'))) {
      return '/admin/dashboard';
    }
    if (auth.user?.role == UserRole.confirmadorDomicilio &&
        (location.startsWith('/domiciliario'))) {
      return '/admin/domicilios';
    }
    if (auth.user?.role == UserRole.cocina &&
        !location.startsWith('/cocina')) {
      return '/cocina';
    }

    return null;
  }

  String _homeForRole(UserRole? role) {
    switch (role) {
      case UserRole.domiciliario:
        return '/domiciliario/pedidos';
      case UserRole.admin:
        return '/admin/dashboard';
      case UserRole.confirmadorDomicilio:
        return '/admin/domicilios';
      case UserRole.cocina:
        return '/cocina';
      default:
        return '/catalogo'; // clientes y no autenticados → catálogo
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.status == AuthStatus.initial) auth.checkSession();
    });

    return MaterialApp.router(
      title: 'ChocAdmin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: _router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es', 'CO'),
        Locale('en', 'US'),
      ],
    );
  }
}
