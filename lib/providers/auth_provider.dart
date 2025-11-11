// lib/providers/auth_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../models/token.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/isar_service.dart';
import '../services/sync_service.dart';

// Proveedor del SyncService (Necesario para la sincronización post-login)
final syncServiceProvider = Provider((ref) => SyncService(ref));

// Estado de Autenticación (StateNotifier para manejar estados de carga/error)
class AuthNotifier extends StateNotifier<AsyncValue<User?>> {
  final Ref _ref;
  Token? _token;

  User? get user => state.value;

  String? get refreshToken => _token?.refreshToken;

  AuthNotifier(this._ref) : super(const AsyncValue.loading()) {
    _initialize();
  }

  String? get accessToken => _token?.accessToken;

  // --- Inicialización (Chequeo Offline) ---

  Future<void> _initialize() async {
    state = const AsyncValue.loading();
    try {
      final user = await _ref.read(isarServiceProvider).getActiveUser();

      if (user != null && user.accessToken != null) {
        _token = Token(
          accessToken: user.accessToken!,
          refreshToken: user.refreshToken,
          role: user.roleName,
        );
        print('DEBUG INIT: refreshToken desde Isar = ${user.refreshToken}');

        state = AsyncValue.data(user);
        print(
          'DEBUG INIT: Usuario ${user.username} cargado desde Isar (Offline). Redirigiendo a HomeScreen.',
        );
      } else {
        state = const AsyncValue.data(null);
        print(
          'DEBUG INIT: No se encontró sesión o usuario en Isar. Mostrando LoginScreen.',
        );
      }
    } catch (e, st) {
      state = AsyncValue.error(
        'Error al inicializar la base de datos local: $e',
        st,
      );
    }
  }

  // --- Lógica de Login ---

  // 💡 CAMBIO CRUCIAL: Retorna String? (Error Message) en lugar de void
  Future<String?> login(String username, String password) async {
    // Nota: El estado de carga (loading) se gestiona en la UI (LoginScreen)
    // usando setState() para el botón.

    final _apiService = _ref.read(apiServiceProvider);
    final _isarService = _ref.read(isarServiceProvider);
    final _syncService = _ref.read(syncServiceProvider);

    try {
      // 1. Llamada de API y fetch de datos
      final tokenResult = await _apiService.login(username, password);
      _token = tokenResult;

      final userResponse = await _apiService.fetchMe();

      // 2. Guardar datos
      final userToSave = userResponse.copyWith(
        accessToken: tokenResult.accessToken,
        refreshToken: tokenResult.refreshToken,
      );
      print('DEBUG LOGIN: accessToken=${tokenResult.accessToken}');
      print('DEBUG LOGIN: refreshToken=${tokenResult.refreshToken}');
      await _isarService.saveUser(userToSave);

      // 3. Éxito: Actualizar estado y sincronizar
      state = AsyncValue.data(userToSave);

      _syncService.startSync();

      print(
        'DEBUG AUTH: Estado final actualizado a DATA. User: ${userToSave.username}',
      );
      return null; // ✅ Éxito: No hay error.
    } catch (e, st) {
      print('DEBUG AUTH: Fallo en Login: $e');

      String errorMessage = 'Error desconocido. Inténtalo de nuevo.';
      dynamic errorForState = e; // Usamos la excepción original para el estado

      if (e is DioException) {
        // 1. Error de Autenticación (401, 403, Invalid Credentials)
        if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
          errorMessage =
              e.response?.data?['detail'] ??
              'Nombre de usuario o contraseña incorrectos.';

          print(
            'DEBUG AUTH: 🛑 Autenticación fallida con el servidor. No se permite fallback offline.',
          );
          errorForState = Exception(
            errorMessage,
          ); // Mensaje limpio para el estado
        }
        // 2. Error de Conexión (Timeout, Sin Conexión, etc.)
        else if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.receiveTimeout) {
          final isarUser = await _isarService.getActiveUser();

          if (isarUser != null && isarUser.username == username) {
            print(
              'DEBUG AUTH: Fallo de red detectado. Autenticación exitosa en modo OFFLINE con Isar.',
            );
            state = AsyncValue.data(isarUser);
            return null; // ✅ Éxito Offline
          }
          errorMessage = 'Error de conexión. Verifica tu red.';
          errorForState = Exception(errorMessage);
        }
      } else {
        errorMessage = 'Fallo inesperado: ${e.toString()}';
      }

      // 4. Fallo: Actualizar estado de error y retornar el mensaje de error
      state = AsyncValue.error(errorForState, st);
      return errorMessage; // ❌ Fallo: Retorna el mensaje de error para la UI (Snackbar).
    }
  }

  // ⚠️ Este método es llamado por el Interceptor cuando el token expira
  void updateToken(Token newToken) async {
    final _isarService = _ref.read(isarServiceProvider);
    final _syncService = _ref.read(syncServiceProvider);

    _token = newToken;
    final currentUser = state.value;

    if (currentUser != null) {
      final userWithNewToken = currentUser.copyWith(
        accessToken: newToken.accessToken,
        refreshToken: newToken.refreshToken,
      );

      await _isarService.saveUser(userWithNewToken);
    }

    _syncService.startSync();

    print('✅ DEBUG REFRESH: Token actualizado con éxito.');
  }

  // --- Lógica de Logout ---

  Future<void> logout() async {
    state = const AsyncValue.loading();
    final _isarService = _ref.read(isarServiceProvider);

    _token = null;

    await _isarService.cleanDB();
    print('DEBUG LOGOUT: Usuario y sesión eliminados de Isar (Hard Logout).');

    state = const AsyncValue.data(null);
  }
}

// Proveedor global que se utiliza para leer el estado de autenticación
final authProvider = StateNotifierProvider<AuthNotifier, AsyncValue<User?>>(
  (ref) => AuthNotifier(ref),
);
