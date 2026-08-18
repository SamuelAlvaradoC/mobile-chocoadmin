import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/constants/app_theme.dart';
import 'core/services/api_service.dart';
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
import 'shared/layouts/client_bottom_nav.dart';
import 'shared/layouts/root_shell_scaffold.dart';
import 'shared/widgets/double_back_to_exit.dart';

// Domiciliario
import 'features/domiciliario/screens/pedidos_screen.dart';
import 'features/domiciliario/screens/cierre_caja_screen.dart';
import 'shared/layouts/domiciliario_layout.dart' show DomiciliarioBottomNav;

// Cliente landing
import 'features/cliente/screens/landing_screen.dart';

// Admin
import 'features/admin/screens/dashboard_screen.dart';
import 'features/admin/screens/ventas_screen.dart';
import 'features/admin/screens/domicilios_screen.dart';
import 'features/admin/screens/productos_modulo_screen.dart';
import 'shared/layouts/admin_bottom_nav.dart';

// Cocina
import 'features/cocina/screens/cocina_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_CO', null);
  GoogleFonts.config.allowRuntimeFetching = true;
  // App de pedidos, sin ningún layout pensado para landscape -- fijada en
  // portrait a nivel de Flutter (además del screenOrientation en
  // AndroidManifest.xml, que evita el flash de orientación incorrecta
  // mientras el engine todavía está arrancando).
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
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
        // El carrito se sincroniza (carga/persiste) con el id del usuario
        // autenticado -- ver comentario en CarritoProvider.sincronizarUsuario.
        // Se dispara al arrancar la app y cada vez que AuthProvider cambia
        // (login/logout), así que el carrito guardado de un cliente nunca se
        // muestra bajo la sesión de otro en el mismo dispositivo.
        ChangeNotifierProxyProvider<AuthProvider, CarritoProvider>(
          create: (_) => CarritoProvider(),
          update: (_, auth, carrito) =>
              (carrito ?? CarritoProvider())..sincronizarUsuario(auth.user?.id),
        ),
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
  bool _manejandoSesionExpirada = false;

  // Recuerda el último branch del shell admin visitado (Dashboard/Productos/
  // Ventas), para que el back desde una ruta plana (Cocina, Confirmador de
  // domicilios) regrese ahí en vez de siempre al Dashboard -- back "estilo
  // navegador", no un destino fijo. Se actualiza como side-effect en
  // _redirect (se ejecuta en cada navegación) porque es el único punto
  // central por el que pasa toda ruta antes de construirse.
  String _ultimaRutaAdminShell = '/admin/dashboard';

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

        // Shell del rol Cliente: Catálogo/Landing/Perfil, cada uno con su
        // propio Navigator (historial de "atrás" independiente por tab).
        // Landing (home del shell) volvió a tener bottom nav propio --
        // antes de esta sesión era una ruta plana con su propio navbar tipo
        // web (hamburguesa), ahora es un branch más como el resto de la
        // app. Puntos vive dentro de Perfil como una pestaña más (no como
        // branch propio -- antes lo era, se revirtió). Checkout y
        // PedidoExitoso quedan fuera a propósito (no tendría sentido que
        // "atrás" devuelva a mitad de un pedido ya hecho).
        //
        // El back en la raíz de cada branch (ir al tab home, o doble-back-
        // para-salir si ya es home) lo maneja ShellAwareBackButtonDispatcher
        // (double_back_to_exit.dart), conectado más abajo en
        // MaterialApp.router. No usa PopScope ni onExit -- ver el comentario
        // completo en double_back_to_exit.dart y root_shell_scaffold.dart
        // sobre por qué ninguno de los dos funciona en la raíz de un branch.
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => RootShellScaffold(
            navigationShell: navigationShell,
            bottomNavBuilder: (shell) => ClientBottomNav(navigationShell: shell),
          ),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/catalogo',
                builder: (_, __) => const CatalogoScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/landing',
                builder: (_, __) => const LandingScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/perfil',
                builder: (_, __) => const PerfilScreen(),
              ),
            ]),
          ],
        ),

        // ── Domiciliario ─────────────────────────────────────
        // 2 branches (Pedidos y Caja), sin Navigator.push internos en
        // ninguna de las 2 pantallas (confirmado por grep) -- el unico caso
        // de atras que aplica aqui es "raiz de tab no-home -> home" y
        // "raiz de home -> doble-back-para-salir", resuelto via
        // ShellAwareBackButtonDispatcher.
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => RootShellScaffold(
            navigationShell: navigationShell,
            bottomNavBuilder: (shell) => DomiciliarioBottomNav(navigationShell: shell),
          ),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/domiciliario/pedidos',
                builder: (_, __) => const PedidosScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/domiciliario/caja',
                builder: (_, __) => const CierreCajaScreen(),
              ),
            ]),
          ],
        ),

        // ── Admin ────────────────────────────────────────────
        // Solo Dashboard/Productos/Ventas son branches reales del shell:
        // Confirmar pedidos (/admin/domicilios) y Panel Cocina (/cocina) son
        // pantallas COMPARTIDAS con los roles confirmador/cocina (que no
        // tienen bottom nav) -- go_router exige una ruta unica por path, asi
        // que no pueden ser branches del shell a la vez que rutas planas
        // para esos otros roles. Se quedan planas (ver mas abajo) y el admin
        // las alcanza con context.go (AdminBottomNav lo maneja solo).
        //
        // Verificado pantalla por pantalla (no de forma generica): Dashboard
        // solo abre showDatePicker/showModalBottomSheet (Tiempo estimado,
        // Horario) -- ninguno usa rootNavigator:true, todos resuelven al
        // Navigator de este branch. El modulo Productos (Categorias/
        // Productos/Toppings/Adiciones, 8 Navigator.push entre los 4 en
        // total para crear/editar) igual: cada sub-pantalla vive dentro del
        // IndexedStack de ProductosModuloScreen, que es la pantalla del
        // branch -- ningun Navigator intermedio se interpone. Ventas (el
        // mas cargado: crear/editar/detalle via Navigator.push, mas el
        // bottom sheet de personalizar producto DENTRO de crear/editar) se
        // comporta igual: al pushearse sobre el context de VentasScreen o
        // de una fila/pantalla ya empujada sobre el branch, todo queda en el
        // mismo Navigator del branch. Los showDialog/showDatePicker sueltos
        // (confirmaciones, motivo de anulacion, visor de comprobante) usan
        // el rootNavigator por defecto de Flutter, pero eso no afecta el
        // back -- un dialog siempre es la ruta activa mas alta sin importar
        // que Navigator lo aloje, y lo cierra el back antes que se llegue a
        // consultar el onExit de la raiz del branch (solo se llega ahi si
        // NINGUN Navigator tiene nada que popear).
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => RootShellScaffold(
            navigationShell: navigationShell,
            bottomNavBuilder: (shell) => AdminBottomNav.shell(navigationShell: shell),
          ),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/admin/dashboard',
                builder: (_, __) => const DashboardScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/admin/productos',
                builder: (_, __) => const ProductosModuloScreen(),
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/admin/ventas',
                builder: (_, __) => const VentasScreen(),
              ),
            ]),
          ],
        ),

        // Confirmar pedidos y Panel Cocina: rutas planas compartidas con
        // los roles confirmador/cocina (ver comentario arriba). El back
        // consciente del rol (admin vuelve al Dashboard, confirmador/cocina
        // aplican doble-back-para-salir) vive en los `flatRouteHandlers` de
        // ShellAwareBackButtonDispatcher, más abajo en este archivo.
        GoRoute(
          path: '/admin/domicilios',
          builder: (_, __) => const DomiciliosScreen(),
        ),

        // ── Cocina ───────────────────────────────────────────
        GoRoute(
          path: '/cocina',
          builder: (_, __) => const CocinaScreen(),
        ),
      ],
    );

    // Interceptor global de sesión expirada: ApiService no tiene
    // BuildContext propio (es una clase estática), así que expone este
    // enganche y acá se resuelve con lo que main.dart sí tiene -- el
    // GoRouter y el AuthProvider. Solo se dispara para un 401 en un
    // endpoint que SÍ requería sesión (ver auth:true en ApiService), nunca
    // para el 401 de "credenciales incorrectas" del login mismo.
    ApiService.onUnauthorized = () async {
      if (_manejandoSesionExpirada) return;
      _manejandoSesionExpirada = true;
      try {
        // Primero se limpia la sesión (y se espera a que notifique) para
        // que _redirect ya vea status==unauthenticated cuando se navegue a
        // /login -- si no, seguiría viendo status==authenticated y
        // rebotaría de vuelta al home del rol.
        await authProvider.sessionExpired();
        _router.go('/login');
        final ctx = _router.routerDelegate.navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          ScaffoldMessenger.of(ctx).clearSnackBars();
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(content: Text('Tu sesión expiró, inicia sesión de nuevo')),
          );
        }
      } finally {
        _manejandoSesionExpirada = false;
      }
    };
  }

  static const _ramasAdminShell = {
    '/admin/dashboard',
    '/admin/productos',
    '/admin/ventas',
  };

  String? _redirect(BuildContext context, GoRouterState state) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final location = state.matchedLocation;

    if (_ramasAdminShell.contains(location)) {
      _ultimaRutaAdminShell = location;
    }

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

  // Handler compartido para las rutas planas /admin/domicilios y /cocina
  // (ver comentario en las rutas): admin vuelve al branch del shell admin
  // que tenía abierto antes (Dashboard/Productos/Ventas -- ver
  // _ultimaRutaAdminShell), no siempre al Dashboard; confirmador/cocina
  // aplican doble-back-para-salir.
  Future<bool> _staffFlatRouteExitHandler(BuildContext context) async {
    final role = context.read<AuthProvider>().user?.role;
    if (role == UserRole.admin) {
      _router.go(_ultimaRutaAdminShell);
      return false;
    }
    return BackExitController.attemptExit(context);
  }

  // Login/Register/ForgotPassword se ALCANZAN (entrada inicial) con
  // context.go() desde varios lados -- el diálogo de "inicia sesión para
  // comprar", el ítem "Ingresar" del bottom nav -- así que en ese punto
  // go_router no tiene un "de dónde vine" al que volver. Este handler solo
  // se consulta cuando de verdad no hay nada que popear (router.canPop()
  // false): si el usuario llegó cruzando ENTRE estas 3 pantallas (Login <->
  // Register <-> ForgotPassword usan context.push() entre ellas, ver esos
  // 3 archivos), el back normal ya resuelve solo, sin pasar por acá.
  // /catalogo es el destino más común desde donde se abren estas 3.
  Future<bool> _authScreenExitHandler(BuildContext context) async {
    _router.go('/catalogo');
    return false;
  }

  // /checkout tiene su propia flechita en el AppBar que vuelve a /catalogo
  // (ver checkout_screen.dart) -- el back del sistema debe hacer lo mismo,
  // no caer al doble-back-para-salir por defecto (que sacaría de la app a
  // mitad de un pedido).
  Future<bool> _checkoutExitHandler(BuildContext context) async {
    _router.go('/catalogo');
    return false;
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
      title: 'ChocoFreseo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // No se usa `routerConfig:` porque MaterialApp.router prohíbe
      // combinarlo con un backButtonDispatcher propio (assertion en
      // app.dart: "If the routerConfig is provided, all the other router
      // delegates must not be provided") -- hay que pasar las piezas de
      // GoRouter por separado para poder conectar
      // ShellAwareBackButtonDispatcher (ver double_back_to_exit.dart).
      routeInformationProvider: _router.routeInformationProvider,
      routeInformationParser: _router.routeInformationParser,
      routerDelegate: _router.routerDelegate,
      backButtonDispatcher: ShellAwareBackButtonDispatcher(
        _router,
        nonHomeToHome: const {
          '/catalogo': '/landing',
          '/perfil': '/landing',
          '/domiciliario/caja': '/domiciliario/pedidos',
          '/admin/productos': '/admin/dashboard',
          '/admin/ventas': '/admin/dashboard',
        },
        flatRouteHandlers: {
          '/admin/domicilios': _staffFlatRouteExitHandler,
          '/cocina': _staffFlatRouteExitHandler,
          '/login': _authScreenExitHandler,
          '/register': _authScreenExitHandler,
          '/forgot-password': _authScreenExitHandler,
          '/checkout': _checkoutExitHandler,
        },
      ),
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
