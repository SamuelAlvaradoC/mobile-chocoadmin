import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

enum UserRole { cliente, domiciliario, admin, confirmadorDomicilio, cocina, unknown }

class AuthUser {
  final int id;
  final String nombre;
  final String email;
  final UserRole role;
  final String? telefono;
  final String? avatar;
  // Permisos granulares del rol (ej. 'gestionar_ventas', 'anular_venta') —
  // igual que React AuthContext.tienePermiso(), cargados desde /api/auth/mis-permisos.
  final List<String> permisos;

  const AuthUser({
    required this.id,
    required this.nombre,
    required this.email,
    required this.role,
    this.telefono,
    this.avatar,
    this.permisos = const [],
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    String rolStr = '';
    final rolRaw = json['rol'] ?? json['role'];
    if (rolRaw is Map) {
      rolStr = (rolRaw['nombre'] ?? '').toString();
    } else if (rolRaw is String) {
      rolStr = rolRaw;
    }

    // El teléfono real está en tabla clientes → cliente.telefono
    // Igual que React: u.cliente?.telefono || u.telefono || null
    final telefono = (json['cliente'] as Map?)?['telefono']?.toString()
        ?? json['telefono']?.toString();

    final permisosRaw = json['permisos'];
    final permisos = permisosRaw is List
        ? permisosRaw.map((e) => e.toString()).toList()
        : <String>[];

    return AuthUser(
      id: json['id_usuario'] ?? json['id'] ?? 0,
      nombre: json['nombre'] ?? json['name'] ?? '',
      email: json['email'] ?? '',
      role: _parseRole(rolStr),
      telefono: (telefono != null && telefono.isNotEmpty) ? telefono : null,
      avatar: json['avatar'] ?? json['foto'],
      permisos: permisos,
    );
  }

  AuthUser copyWith({List<String>? permisos}) => AuthUser(
        id: id,
        nombre: nombre,
        email: email,
        role: role,
        telefono: telefono,
        avatar: avatar,
        permisos: permisos ?? this.permisos,
      );

  static UserRole _parseRole(String role) {
    switch (role.toLowerCase()) {
      case 'cliente':
        return UserRole.cliente;
      case 'domiciliario':
        return UserRole.domiciliario;
      case 'admin':
      case 'administrador':
        return UserRole.admin;
      case 'confirmador_domicilio':
        return UserRole.confirmadorDomicilio;
      // El backend guarda el rol como 'cocinero' (CARGO_A_ROL en
      // empleados/service.js, ROLES_EMPLEADO en usuarios/service.js) — se
      // acepta también 'cocina' por si algún registro antiguo/manual quedó
      // creado con ese nombre.
      case 'cocinero':
      case 'cocina':
        return UserRole.cocina;
      default:
        return UserRole.unknown;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'email': email,
        'role': role.name,
        'telefono': telefono,
        'avatar': avatar,
      };
}

class AuthService {
  static const _keyToken        = 'token';
  static const _keyUserId       = 'user_id';
  static const _keyUserName     = 'user_name';
  static const _keyUserEmail    = 'user_email';
  static const _keyUserRole     = 'user_role';
  static const _keyUserTelefono = 'user_telefono';
  static const _keyUserAvatar   = 'user_avatar';
  static const _keyUserPermisos = 'user_permisos';

  // ─── Permisos ────────────────────────────────────────────────────────────────

  /// Igual que React AuthContext: GET /auth/mis-permisos → lista de nombres de permiso del rol.
  static Future<List<String>> _fetchPermisos() async {
    final data = await ApiService.get('/api/auth/mis-permisos');
    final raw = data is Map && data['data'] is List
        ? data['data'] as List
        : (data is List ? data : const []);
    return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }

  // ─── Login ──────────────────────────────────────────────────────────────────

  static Future<AuthUser> login(String email, String password) async {
    final resp = await ApiService.post(
      '/api/auth/login',
      {'email': email, 'contrasena': password},
      auth: false,
    );

    final inner = resp is Map && resp['data'] is Map ? resp['data'] as Map : resp as Map;
    final token = inner['token'] as String?;
    if (token == null || token.isEmpty) {
      throw ApiException('Token inválido recibido del servidor');
    }

    final userJson = inner['usuario'] as Map<String, dynamic>?
        ?? inner['user'] as Map<String, dynamic>?
        ?? inner;
    var user = AuthUser.fromJson(userJson as Map<String, dynamic>);

    // Guardar sesión con datos básicos primero (token listo para siguientes calls)
    await _saveSession(token, user);

    // Cargar perfil completo para obtener telefono desde tabla clientes
    try {
      final profileData = await ApiService.get('/api/auth/perfil');
      final inner = profileData is Map && profileData['data'] is Map
          ? profileData['data'] as Map<String, dynamic>
          : (profileData is Map ? Map<String, dynamic>.from(profileData) : <String, dynamic>{});
      if (inner.isNotEmpty) {
        user = AuthUser.fromJson(inner);
      }
    } catch (_) {
      // best-effort — usamos los datos del login si falla
    }

    // Cargar permisos del rol (igual que React: Promise.allSettled junto al perfil)
    try {
      final permisos = await _fetchPermisos();
      user = user.copyWith(permisos: permisos);
    } catch (_) {
      // best-effort — sin permisos, tienePermiso() simplemente será false
    }

    await _saveSession(token, user);
    return user;
  }

  // ─── Registro ───────────────────────────────────────────────────────────────

  static Future<AuthUser> register({
    required String nombre,
    required String email,
    required String password,
  }) async {
    await ApiService.post(
      '/api/auth/register',
      {
        'nombre': nombre,
        'email': email,
        'contrasena': password,
        'id_rol': 4, // ✅ 4 = cliente en la BD
      },
      auth: false,
    );
    // La API no devuelve token al registrar → hacemos login automático
    return login(email, password);
  }

  // ─── Recuperar contraseña ────────────────────────────────────────────────────

  static Future<void> forgotPassword(String email) async {
    await ApiService.post(
      '/api/auth/solicitar-reset',
      {'email': email},
      auth: false,
    );
  }

  static Future<void> resetPassword({
    required String email,
    required String codigo,
    required String newPassword,
  }) async {
    await ApiService.post(
      '/api/auth/verificar-reset',
      {'email': email, 'codigo': codigo, 'nueva_password': newPassword},
      auth: false,
    );
  }

  // ─── Sesión ──────────────────────────────────────────────────────────────────

  static Future<void> _saveSession(String token, AuthUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
    await prefs.setInt(_keyUserId, user.id);
    await prefs.setString(_keyUserName, user.nombre);
    await prefs.setString(_keyUserEmail, user.email);
    await prefs.setString(_keyUserRole, user.role.name);
    if (user.telefono != null) await prefs.setString(_keyUserTelefono, user.telefono!);
    if (user.avatar != null)   await prefs.setString(_keyUserAvatar, user.avatar!);
    await prefs.setStringList(_keyUserPermisos, user.permisos);
  }

  static Future<AuthUser?> getStoredUser() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_keyToken);
    if (token == null || token.isEmpty) return null;

    final roleStr = prefs.getString(_keyUserRole) ?? '';
    return AuthUser(
      id:       prefs.getInt(_keyUserId) ?? 0,
      nombre:   prefs.getString(_keyUserName) ?? '',
      email:    prefs.getString(_keyUserEmail) ?? '',
      role:     UserRole.values.firstWhere((r) => r.name == roleStr, orElse: () => UserRole.unknown),
      telefono: prefs.getString(_keyUserTelefono),
      avatar:   prefs.getString(_keyUserAvatar),
      permisos: prefs.getStringList(_keyUserPermisos) ?? const [],
    );
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken);
  }

  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  static Future<void> logout() async {
    // Invalida el token en el servidor (blacklist) antes de borrarlo localmente.
    // Best-effort: si falla (sin internet, token ya expirado, etc.) igual se
    // limpia la sesión local para no dejar al usuario atascado.
    try {
      await ApiService.post('/api/auth/logout', {});
    } catch (_) {}

    await clearSessionLocal();
  }

  /// Limpia la sesión guardada localmente SIN llamar al backend. Se usa
  /// cuando ya se sabe que el token es inválido (401 de sesión expirada,
  /// ver ApiService.onUnauthorized) -- llamar a /api/auth/logout con un
  /// token que el servidor ya rechazó no tiene sentido y arriesgaría otro
  /// 401 en cascada.
  static Future<void> clearSessionLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyUserName);
    await prefs.remove(_keyUserEmail);
    await prefs.remove(_keyUserRole);
    await prefs.remove(_keyUserTelefono);
    await prefs.remove(_keyUserAvatar);
    await prefs.remove(_keyUserPermisos);
  }

  // ─── Perfil ──────────────────────────────────────────────────────────────────

  static Future<AuthUser> getProfile() async {
    final data = await ApiService.get('/api/auth/perfil');
    final inner = data is Map && data['data'] is Map
        ? data['data'] as Map<String, dynamic>
        : data as Map<String, dynamic>;
    var user = AuthUser.fromJson(inner);
    try {
      user = user.copyWith(permisos: await _fetchPermisos());
    } catch (_) {
      // best-effort — conservar los permisos ya guardados si falla
      final stored = await getStoredUser();
      if (stored != null) user = user.copyWith(permisos: stored.permisos);
    }
    final token = await getToken();
    if (token != null) await _saveSession(token, user);
    return user;
  }

  /// Actualiza el perfil y persiste los cambios en SharedPreferences
  static Future<AuthUser> updateProfile({
    required String nombre,
    required String telefono,
  }) async {
    await ApiService.patch('/api/auth/perfil', {
      'nombre': nombre,
      'telefono': telefono,
    });
    // Recargar el perfil actualizado
    return getProfile();
  }
}