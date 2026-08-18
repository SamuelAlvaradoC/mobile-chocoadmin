// Verifica el hallazgo reportado: "en Checkout, si estoy en el método de
// pago y le doy back, me devuelve directamente al catálogo -- debería ser
// paso por paso (Pago -> Dirección -> Datos -> Catálogo), igual que las
// flechitas que ya tiene la pantalla". checkout_screen.dart ya tenía ese
// flujo correcto para su propia flechita de AppBar (_handleBack), pero el
// back del SISTEMA en /checkout (ruta plana, sin nada que popear) lo
// resolvía el _checkoutExitHandler global de main.dart, que saltaba directo
// a /catalogo sin conocer el paso actual -- ver CheckoutBackController en
// shared/widgets/double_back_to_exit.dart, el puente agregado para que el
// dispatcher global pueda delegar en el _handleBack() real de la pantalla
// montada.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chocoadmin/core/models/producto.dart';
import 'package:chocoadmin/core/services/api_service.dart';
import 'package:chocoadmin/features/auth/providers/auth_provider.dart';
import 'package:chocoadmin/features/cliente/providers/carrito_provider.dart';
import 'package:chocoadmin/features/cliente/screens/checkout_screen.dart';
import 'package:chocoadmin/shared/widgets/double_back_to_exit.dart';

Producto _producto() => const Producto(
      id: 1,
      nombre: 'Fresas con crema',
      precio: 12000,
      permiteToppings: false,
    );

// Copia real de _checkoutExitHandler en main.dart -- mismo patrón que
// navigation_5_roles_test.dart usa para los demás handlers de main.dart.
Future<bool> _checkoutExitHandler(BuildContext context) async {
  if (!CheckoutBackController.intentar()) {
    GoRouter.of(context).go('/catalogo');
  }
  return false;
}

({GoRouter router, Widget widget}) _buildApp(CarritoProvider carrito) {
  final router = GoRouter(
    initialLocation: '/checkout',
    routes: [
      GoRoute(path: '/catalogo', builder: (_, __) => const Scaffold(body: Text('Home Catálogo'))),
      GoRoute(path: '/checkout', builder: (_, __) => const CheckoutScreen()),
    ],
  );

  final widget = MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider.value(value: carrito),
    ],
    child: MaterialApp.router(
      routeInformationProvider: router.routeInformationProvider,
      routeInformationParser: router.routeInformationParser,
      routerDelegate: router.routerDelegate,
      backButtonDispatcher: ShellAwareBackButtonDispatcher(
        router,
        nonHomeToHome: const {},
        flatRouteHandlers: {'/checkout': _checkoutExitHandler},
      ),
    ),
  );

  return (router: router, widget: widget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    ApiService.client = MockClient((_) async => http.Response('No mockeado', 400));
    CheckoutBackController.limpiar();
  });

  testWidgets('en el primer paso (Datos), el back del sistema va a /catalogo -- comportamiento preexistente, no se rompió', (tester) async {
    final carrito = CarritoProvider();
    carrito.agregar(producto: _producto(), toppings: const [], adiciones: const []);

    ApiService.client = MockClient((req) async => http.Response('{"data":{}}', 200,
        headers: {'content-type': 'application/json; charset=utf-8'}));

    final app = _buildApp(carrito);
    await tester.pumpWidget(app.widget);
    await tester.pumpAndSettle();
    expect(find.text('Datos de entrega'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Home Catálogo'), findsOneWidget);
  });

  testWidgets('en el segundo paso (Dirección), el back del sistema retrocede a Datos -- NO salta directo a /catalogo', (tester) async {
    final carrito = CarritoProvider();
    carrito.agregar(producto: _producto(), toppings: const [], adiciones: const []);

    ApiService.client = MockClient((req) async {
      if (req.method == 'PATCH' && req.url.path.contains('/api/auth/perfil')) {
        return http.Response('{"data":{}}', 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }
      if (req.url.path.contains('/api/auth/mis-direcciones')) {
        return http.Response(jsonEncode({'data': []}), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('No mockeado', 404);
    });

    final app = _buildApp(carrito);
    await tester.pumpWidget(app.widget);
    await tester.pumpAndSettle();
    expect(find.text('Datos de entrega'), findsOneWidget);

    // Completa el paso 1 (teléfono válido) para avanzar de verdad al paso 2,
    // igual que un usuario real -- no se fuerza el estado desde afuera.
    await tester.enterText(find.byType(TextField).first, '3001234567');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Dirección de entrega'), findsOneWidget,
        reason: 'debe haber avanzado de verdad al paso 2 antes de probar el back');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Datos de entrega'), findsOneWidget,
        reason: 'el back del sistema debe retroceder un paso (a Datos), no saltar a /catalogo de un solo golpe');
    expect(find.text('Home Catálogo'), findsNothing,
        reason: 'este era exactamente el síntoma reportado: perder los pasos ya completados de un solo back');
  });

  group('CheckoutBackController (el puente en sí)', () {
    test('sin ninguna pantalla registrada, intentar() devuelve false', () {
      expect(CheckoutBackController.intentar(), isFalse);
    });

    test('con un callback registrado, intentar() lo invoca y devuelve true', () {
      var invocado = false;
      CheckoutBackController.registrar(() => invocado = true);
      expect(CheckoutBackController.intentar(), isTrue);
      expect(invocado, isTrue);
    });

    test('limpiar() desregistra el callback -- intentar() vuelve a devolver false', () {
      CheckoutBackController.registrar(() {});
      CheckoutBackController.limpiar();
      expect(CheckoutBackController.intentar(), isFalse);
    });
  });
}
