import '../services/auth_service.dart' show UserRole;
import '../../features/auth/providers/auth_provider.dart' show AuthStatus;

/// Rutas que no requieren sesión iniciada.
const List<String> authRoutes = ['/login', '/register', '/forgot-password'];

/// Rutas públicas del cliente (catálogo/landing sin login).
const List<String> publicRoutes = ['/landing', '/catalogo'];

String homeForRole(UserRole? role) {
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

/// Lógica de redirect de GoRouter, extraída de `_AppRouterState._redirect`
/// (main.dart) para poder importarla directo en tests -- así un test que
/// verifica el redirect usa la MISMA función que corre en producción, no
/// una copia que se puede desincronizar en silencio.
///
/// Ver el comentario extenso en main.dart sobre el bug que motivó separar
/// el caso `AuthStatus.loading` en `/login`/`/register`/`/forgot-password`:
/// esos 3 formularios ponen `AuthStatus.loading` mientras esperan al
/// backend, y como GoRouter reevalúa este redirect en cada
/// `notifyListeners()` (vía `refreshListenable`), sin la excepción de
/// `authRoutes` el redirect rebotaba a `/splash` ANTES de que el backend
/// respondiera -- la pantalla de login quedaba desmontada, así que un login
/// fallido se tragaba el error en silencio y terminaba en /catalogo.
String? computeAuthRedirect({
  required AuthStatus status,
  required String location,
  required UserRole? role,
}) {
  if (status == AuthStatus.initial || status == AuthStatus.loading) {
    if (authRoutes.contains(location)) return null;
    return location == '/splash' ? null : '/splash';
  }

  if (status == AuthStatus.unauthenticated || status == AuthStatus.error) {
    if (authRoutes.contains(location) || publicRoutes.contains(location)) {
      return null; // permitir sin login
    }
    return '/catalogo'; // resto de rutas → catálogo público
  }

  // Autenticado: redirigir fuera de auth/splash al home del rol
  if (location == '/splash' || authRoutes.contains(location)) {
    return homeForRole(role);
  }

  // Guardar acceso cruzado de roles
  if (role == UserRole.domiciliario && location.startsWith('/admin')) {
    return '/domiciliario/pedidos';
  }
  if (role == UserRole.admin && location.startsWith('/domiciliario')) {
    return '/admin/dashboard';
  }
  if (role == UserRole.confirmadorDomicilio && location.startsWith('/domiciliario')) {
    return '/admin/domicilios';
  }
  if (role == UserRole.cocina && !location.startsWith('/cocina')) {
    return '/cocina';
  }

  return null;
}
