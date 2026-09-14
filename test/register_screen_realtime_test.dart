// Prueba real (no mock de la lógica) de la validación en tiempo real de
// RegisterScreen: los validadores por campo ya existían (_validarNombre,
// _validarEmail, etc.) pero solo se llamaban al enviar -- ahora se conectan
// al onChanged (con debounce de 400ms) y al blur (FocusNode).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chocoadmin/core/services/api_service.dart';
import 'package:chocoadmin/features/auth/providers/auth_provider.dart';
import 'package:chocoadmin/features/auth/screens/register_screen.dart';

Widget _harness() => MaterialApp(
      home: MultiProvider(providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ], child: const RegisterScreen()),
    );

Future<void> _setSize(WidgetTester tester) async {
  tester.view.physicalSize = const Size(600, 1200);
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

  testWidgets('nombre de 1 letra marca error tras el debounce', (tester) async {
    await _setSize(tester);
    await tester.pumpWidget(_harness());
    await tester.pump();

    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(0), 'A');

    expect(find.text('El nombre debe tener al menos 3 caracteres'), findsOneWidget);
  });

  testWidgets('nombre con números se rechaza (solo letras y espacios)', (tester) async {
    await _setSize(tester);
    await tester.pumpWidget(_harness());
    await tester.pump();

    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(0), 'Ana123');

    expect(find.text('El nombre solo puede contener letras y espacios'), findsOneWidget);
  });

  testWidgets('nombre con espacio y tildes/ñ es válido', (tester) async {
    await _setSize(tester);
    await tester.pumpWidget(_harness());
    await tester.pump();

    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(0), 'José Muñoz');

    expect(find.text('El nombre debe tener al menos 3 caracteres'), findsNothing);
    expect(find.text('El nombre solo puede contener letras y espacios'), findsNothing);
  });

  testWidgets('correo con formato inválido marca error tras el debounce', (tester) async {
    await _setSize(tester);
    await tester.pumpWidget(_harness());
    await tester.pump();

    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(1), 'correoinvalido');

    expect(find.textContaining('El correo no tiene un formato válido'), findsOneWidget);
  });

  testWidgets('un dominio de una sola letra (ej. samuel@M.gamil.com) sigue siendo válido', (tester) async {
    await _setSize(tester);
    await tester.pumpWidget(_harness());
    await tester.pump();

    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(1), 'samuel@M.gamil.com');

    expect(find.textContaining('El correo no tiene un formato válido'), findsNothing);
  });

  testWidgets('contraseña de 5 caracteres marca error tras el debounce', (tester) async {
    await _setSize(tester);
    await tester.pumpWidget(_harness());
    await tester.pump();

    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(2), '12345');

    expect(find.text('La contraseña debe tener mínimo 8 caracteres'), findsOneWidget);
  });

  testWidgets('confirmar contraseña distinta marca error de no coincidencia', (tester) async {
    await _setSize(tester);
    await tester.pumpWidget(_harness());
    await tester.pump();

    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(2), 'Contrasena123');
    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(3), 'OtraCosa123');

    expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
  });

  testWidgets('corregir todos los campos hace desaparecer los errores solos', (tester) async {
    await _setSize(tester);
    await tester.pumpWidget(_harness());
    await tester.pump();

    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(0), 'A');
    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(1), 'correoinvalido');
    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(2), '12345');
    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(3), 'otra');

    expect(find.text('El nombre debe tener al menos 3 caracteres'), findsOneWidget);
    expect(find.textContaining('El correo no tiene un formato válido'), findsOneWidget);
    expect(find.text('La contraseña debe tener mínimo 8 caracteres'), findsOneWidget);
    expect(find.text('Las contraseñas no coinciden'), findsOneWidget);

    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(0), 'José Muñoz');
    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(1), 'jose@ejemplo.com');
    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(2), 'Contrasena123');
    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(3), 'Contrasena123');

    expect(find.text('El nombre debe tener al menos 3 caracteres'), findsNothing);
    expect(find.textContaining('El correo no tiene un formato válido'), findsNothing);
    expect(find.text('La contraseña debe tener mínimo 8 caracteres'), findsNothing);
    expect(find.text('Las contraseñas no coinciden'), findsNothing);
  });

  testWidgets('cambiar la contraseña re-valida "confirmar" si ya tenía texto', (tester) async {
    await _setSize(tester);
    await tester.pumpWidget(_harness());
    await tester.pump();

    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(2), 'Contrasena123');
    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(3), 'Contrasena123');
    expect(find.text('Las contraseñas no coinciden'), findsNothing);

    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(2), 'OtraContrasena456');
    expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
  });

  testWidgets('el botón de enviar sigue funcionando de principio a fin con datos válidos', (tester) async {
    await _setSize(tester);
    var llamadas = 0;
    ApiService.client = MockClient((req) async {
      if (req.url.path.contains('/api/auth/register')) {
        llamadas++;
        return http.Response(
          '{"data":{"token":"tok","usuario":{"id_usuario":1,"nombre":"Jose Munoz","email":"jose@ejemplo.com","rol":{"nombre":"cliente"}}}}',
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (req.url.path.contains('/api/auth/login')) {
        return http.Response(
          '{"data":{"token":"tok","usuario":{"id_usuario":1,"nombre":"Jose Munoz","email":"jose@ejemplo.com","rol":{"nombre":"cliente"}}}}',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('No mockeado', 404);
    });

    await tester.pumpWidget(_harness());
    await tester.pump();

    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(0), 'Jose Munoz');
    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(1), 'jose@ejemplo.com');
    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(2), 'Contrasena123');
    await _escribirYEsperarDebounce(tester, find.byType(TextField).at(3), 'Contrasena123');

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(llamadas, 1, reason: 'el envío real debe seguir llamando al backend con datos válidos');
  });
}
