// Prueba unitaria pura de computeAuthRedirect (core/routing/auth_redirect.dart)
// -- la MISMA función que usa _AppRouterState._redirect en main.dart, sin
// copiarla. Cubre puntualmente el bug reportado: "credenciales inválidas me
// dejan entrar" -- la causa real era que, mientras Login/Register/
// ForgotPassword ponen AuthStatus.loading para enviar el formulario, el
// redirect global rebotaba a /splash ANTES de que el backend respondiera,
// desmontando la pantalla y tragándose el error.
import 'package:flutter_test/flutter_test.dart';

import 'package:chocoadmin/core/routing/auth_redirect.dart';
import 'package:chocoadmin/core/services/auth_service.dart';
import 'package:chocoadmin/features/auth/providers/auth_provider.dart';

void main() {
  group('computeAuthRedirect -- AuthStatus.loading en pantallas de auth', () {
    for (final loc in authRoutes) {
      test('$loc con status=loading NO rebota a /splash (se queda enviando el formulario)', () {
        final redirect = computeAuthRedirect(
          status: AuthStatus.loading,
          location: loc,
          role: null,
        );
        expect(redirect, isNull,
            reason: 'antes del fix esto devolvía /splash, desmontando la pantalla a mitad de un login/registro/recuperación en curso');
      });
    }

    test('/splash con status=loading SÍ se queda en splash (arranque normal de la app)', () {
      expect(computeAuthRedirect(status: AuthStatus.loading, location: '/splash', role: null), isNull);
    });

    test('cualquier otra ruta con status=loading (o initial) SÍ rebota a /splash -- caso real: abrir la app de cero', () {
      expect(computeAuthRedirect(status: AuthStatus.loading, location: '/catalogo', role: null), '/splash');
      expect(computeAuthRedirect(status: AuthStatus.initial, location: '/perfil', role: null), '/splash');
    });
  });

  group('computeAuthRedirect -- después de un login fallido (status=error)', () {
    test('se queda en /login mostrando el error, no lo manda a /catalogo', () {
      final redirect = computeAuthRedirect(
        status: AuthStatus.error,
        location: '/login',
        role: null,
      );
      expect(redirect, isNull,
          reason: 'con el bug real, para este punto el location ya no era /login (se había ido a /splash), así que caía al catálogo público sin avisar nada');
    });
  });

  group('computeAuthRedirect -- login exitoso sí navega al home del rol', () {
    test('admin autenticado en /login es redirigido a /admin/dashboard', () {
      expect(
        computeAuthRedirect(status: AuthStatus.authenticated, location: '/login', role: UserRole.admin),
        '/admin/dashboard',
      );
    });
    test('cliente autenticado en /login es redirigido a /catalogo (home por defecto)', () {
      expect(
        computeAuthRedirect(status: AuthStatus.authenticated, location: '/login', role: UserRole.cliente),
        '/catalogo',
      );
    });
  });
}
