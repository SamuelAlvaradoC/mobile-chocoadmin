import 'package:flutter/material.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/auth_service.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthProvider extends ChangeNotifier {
  AuthStatus _status = AuthStatus.initial;
  AuthUser? _user;
  String? _errorMessage;

  AuthStatus get status => _status;
  AuthUser? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _status == AuthStatus.loading;

  // Igual que React AuthContext.tienePermiso(nombre)
  bool tienePermiso(String nombre) => _user?.permisos.contains(nombre) ?? false;

  Future<void> checkSession() async {
    _status = AuthStatus.loading;
    notifyListeners();

    try {
      final user = await AuthService.getStoredUser();
      if (user != null && user.role != UserRole.unknown) {
        _user = user;
        _status = AuthStatus.authenticated;
        // Refresco de permisos en segundo plano, sin bloquear el arranque —
        // necesario para sesiones que ya estaban logueadas antes de que
        // existiera el sistema de permisos (quedarían con permisos=[] hasta
        // volver a iniciar sesión si no se refrescan acá).
        if (user.permisos.isEmpty) {
          AuthService.getProfile().then((refreshed) {
            _user = refreshed;
            notifyListeners();
          }).catchError((_) {});
        }
      } else {
        _status = AuthStatus.unauthenticated;
      }
    } catch (_) {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      _user = await AuthService.login(email, password);
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _status = AuthStatus.error;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Error inesperado';
      _status = AuthStatus.error;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register({
    required String nombre,
    required String email,
    required String password,
  }) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      _user = await AuthService.register(
        nombre: nombre,
        email: email,
        password: password,
      );
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _status = AuthStatus.error;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Error inesperado';
      _status = AuthStatus.error;
      notifyListeners();
      return false;
    }
  }

  Future<bool> forgotPassword(String email) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      await AuthService.forgotPassword(email);
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _status = AuthStatus.error;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await AuthService.logout();
    _user = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    if (_status == AuthStatus.error) {
      _status = _user != null
          ? AuthStatus.authenticated
          : AuthStatus.unauthenticated;
    }
    notifyListeners();
  }
}
