import 'package:flutter/material.dart';
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
import 'features/domiciliario/providers/domiciliario_provider.dart';

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

// Domiciliario
import 'features/domiciliario/screens/pedidos_screen.dart';
import 'features/domiciliario/screens/cierre_caja_screen.dart';

// Cliente landing
import 'features/cliente/screens/landing_screen.dart';

// Admin
import 'features/admin/screens/dashboard_screen.dart';
import 'features/admin/screens/ventas_screen.dart';
import 'features/admin/screens/domicilios_screen.dart';
import 'features/admin/screens/resenas_screen.dart';
import 'features/admin/screens/usuarios_screen.dart';
import 'features/admin/screens/roles_screen.dart';
import 'features/admin/screens/clientes_screen.dart';
import 'features/admin/screens/empleados_screen.dart';
import 'features/admin/screens/categorias_screen.dart';
import 'features/admin/screens/productos_screen.dart';
import 'features/admin/screens/toppings_screen.dart';
import 'features/admin/screens/adiciones_screen.dart';
import 'features/admin/screens/ciudades_screen.dart';
import 'features/admin/screens/barrios_screen.dart';

// Cocina
import 'features/cocina/screens/cocina_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_CO', null);
  GoogleFonts.config.allowRuntimeFetching = true;
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
        ChangeNotifierProvider(create: (_) => DomiciliarioProvider()),
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
        GoRoute(path: '/catalogo', builder: (_, __) => const CatalogoScreen()),
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
        GoRoute(path: '/perfil', builder: (_, __) => const PerfilScreen()),

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
        GoRoute(path: '/admin/resenas', builder: (_, __) => const ResenasScreen()),
        GoRoute(path: '/admin/usuarios', builder: (_, __) => const UsuariosScreen()),
        GoRoute(path: '/admin/roles', builder: (_, __) => const RolesScreen()),
        GoRoute(path: '/admin/clientes', builder: (_, __) => const ClientesScreen()),
        GoRoute(path: '/admin/empleados', builder: (_, __) => const EmpleadosScreen()),
        GoRoute(path: '/admin/categorias', builder: (_, __) => const CategoriasScreen()),
        GoRoute(path: '/admin/productos', builder: (_, __) => const ProductosScreen()),
        GoRoute(path: '/admin/toppings', builder: (_, __) => const ToppingsScreen()),
        GoRoute(path: '/admin/adiciones', builder: (_, __) => const AdicionesScreen()),
        GoRoute(path: '/admin/ciudades', builder: (_, __) => const CiudadesScreen()),
        GoRoute(path: '/admin/barrios', builder: (_, __) => const BarriosScreen()),

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
