// Prueba real de la validación en tiempo real de LoginScreen:
// _validarEmail/_validarPassword ya existían, solo se llamaban al enviar --
// ahora se conectan al onChanged (debounce 400ms) y al blur (FocusNode).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chocoadmin/core/services/api_service.dart';
import 'package:chocoadmin/features/auth/providers/auth_provider.dart';
import 'package:chocoadmin/features/auth/screens/login_screen.dart';

Widget _harness() => MaterialApp(
      home: MultiProvider(providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ], child: const LoginScreen()),
    );

Future<void> _setSize(WidgetTester tester) async {
  tester.view.physicalSize = const Size(600, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _escribirYEsperarDebounce(WidgetTester tester, Finder campo, String valor) async {
  await tester.enterText(campo, valor);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    ApiService.client = MockClient((_) async => http.Response('No mockeado', 400));
  });

  testWidgets('correo con formato inválido marca error tras el debounce', (tester) async {
    await _setSize(tester);
    await tester.pumpWidget(_harness());
    await tester.pump();

    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(0), 'correoinvalido');

    expect(find.textContaining('El correo no tiene un formato válido'), findsOneWidget);
  });

  testWidgets('un dominio de una sola letra (ej. samuel@M.gamil.com) sigue siendo válido', (tester) async {
    await _setSize(tester);
    await tester.pumpWidget(_harness());
    await tester.pump();

    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(0), 'samuel@M.gamil.com');

    expect(find.textContaining('El correo no tiene un formato válido'), findsNothing);
  });

  testWidgets('NO exige longitud mínima de contraseña -- solo que no esté vacía', (tester) async {
    await _setSize(tester);
    await tester.pumpWidget(_harness());
    await tester.pump();

    // 1 solo caracter -- no debe marcar error de longitud (a diferencia de Registro).
    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(1), 'a');
    expect(find.textContaining('caracteres'), findsNothing);

    // Vacía sí debe marcar error.
    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(1), '');
    expect(find.text('Ingresa tu contraseña'), findsOneWidget);
  });

  testWidgets('corregir el correo hace desaparecer el error solo', (tester) async {
    await _setSize(tester);
    await tester.pumpWidget(_harness());
    await tester.pump();

    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(0), 'correoinvalido');
    expect(find.textContaining('El correo no tiene un formato válido'), findsOneWidget);

    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(0), 'valido@ejemplo.com');
    expect(find.textContaining('El correo no tiene un formato válido'), findsNothing);
  });

  testWidgets('el envío real sigue funcionando de principio a fin con datos válidos', (tester) async {
    await _setSize(tester);
    var llamadas = 0;
    ApiService.client = MockClient((req) async {
      if (req.url.path.contains('/api/auth/login')) {
        llamadas++;
        return http.Response(
          '{"data":{"token":"tok","usuario":{"id_usuario":1,"nombre":"Cliente","email":"valido@ejemplo.com","rol":{"nombre":"cliente"}}}}',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('No mockeado', 404);
    });

    await tester.pumpWidget(_harness());
    await tester.pump();

    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(0), 'valido@ejemplo.com');
    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(1), 'cualquiercosa');

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(llamadas, 1, reason: 'el envío real debe seguir llamando al backend con datos válidos');
  });
}
