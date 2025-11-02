// lib/providers/auth_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/token.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/isar_service.dart';
import '../services/sync_service.dart'; // 💡 Importar el servicio de sincronización

// Proveedor de la base de datos Isar
// final isarServiceProvider = Provider((ref) => IsarService());

// Proveedor del ApiService
// NOTA: Asumimos que apiServiceProvider ya está definido en otro lugar (ej. api_service.dart)
// final apiServiceProvider = Provider((ref) => ApiService(ref));

// Proveedor del SyncService (Necesario para la sincronización post-login)
final syncServiceProvider = Provider(
  (ref) => SyncService(ref),
); // 💡 Definir el proveedor del SyncService

// Estado de Autenticación (StateNotifier para manejar estados de carga/error)
class AuthNotifier extends StateNotifier<AsyncValue<User?>> {
  final Ref _ref;
  Token? _token; // Almacena el token JWT de forma privada

  // Getter para el Refresh Token (para el Interceptor)
  String? get refreshToken => _token?.refreshToken;

  AuthNotifier(this._ref) : super(const AsyncValue.loading()) {
    _initialize();
  }

  // Getter para el token (usado por el Interceptor de Dio en api_service.dart)
  String? get accessToken => _token?.accessToken;

  // --- Inicialización (Chequeo Offline) ---

  Future<void> _initialize() async {
    state = const AsyncValue.loading();
    try {
      final user = await _ref.read(isarServiceProvider).getActiveUser();

      // CLAVE: Chequeamos que exista el usuario Y que tenga un token de sesión
      if (user != null && user.accessToken != null) {
        // Asignar el token de Isar a la variable de clase (para el Interceptor)
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

        // 🚀 Nota: Aquí no llamamos a startSync, ya que _initialize puede correr
        // con la app en segundo plano y sin conexión estable.
        // La sincronización debe ser manejada por un listener de conectividad.
      } else {
        state = const AsyncValue.data(null);
        print(
          'DEBUG INIT: No se encontró sesión o usuario en Isar. Mostrando LoginScreen.',
        );
      }
    } catch (e, st) {
      // Si la DB Isar falla
      state = AsyncValue.error(
        'Error al inicializar la base de datos local: $e',
        st,
      );
    }
  }

  // --- Lógica de Login ---

  Future<void> login(String username, String password) async {
    state = const AsyncValue.loading();
    // Asumiendo que apiServiceProvider está definido y es accesible
    final _apiService = _ref.read(apiServiceProvider);
    final _isarService = _ref.read(isarServiceProvider);
    final _syncService = _ref.read(
      syncServiceProvider,
    ); // 💡 Obtener el SyncService

    try {
      // 1. Llama a la API (Login)
      final tokenResult = await _apiService.login(username, password);

      // CLAVE 1: ALMACENAR EL OBJETO TOKEN INMEDIATAMENTE
      _token = tokenResult;

      // 2. Llama a la API para obtener el usuario
      final userResponse = await _apiService.fetchMe();

      // CLAVE 2: Guardar el token junto con el usuario en Isar para persistencia
      final userToSave = userResponse.copyWith(
        accessToken: tokenResult.accessToken,
        refreshToken: tokenResult.refreshToken,
      );
      print('DEBUG LOGIN: accessToken=${tokenResult.accessToken}');
      print('DEBUG LOGIN: refreshToken=${tokenResult.refreshToken}');
      await _isarService.saveUser(userToSave);

      // 3. Éxito ONLINE
      state = AsyncValue.data(userToSave);

      // 🚀 INICIAR SINCRONIZACIÓN DESPUÉS DEL LOGIN EXITOSO
      // Ahora que estamos online y autenticados, vaciamos la cola.
      _syncService.startSync();

      print(
        'DEBUG AUTH: Estado final actualizado a DATA. User: ${userToSave.username}',
      );
    } catch (e, st) {
      print('DEBUG AUTH: Fallo catastrófico en Login: $e');

      // 🚨 MANEJO DE OFFLINE LOGIN: Solo si el fallo es de CONEXIÓN
      if (e.toString().contains('DioException') ||
          e.toString().contains('SocketException')) {
        final isarUser = await _isarService.getActiveUser();

        // CLAVE: Revisa si el usuario ingresado (username) coincide con el usuario guardado
        if (isarUser != null && isarUser.username == username) {
          print(
            'DEBUG AUTH: Fallo de red detectado. Autenticación exitosa en modo OFFLINE con Isar.',
          );

          state = AsyncValue.data(isarUser);
          return; // Salir de la función con éxito (offline)
        }
      }

      // ... (Si no hay usuario guardado o las credenciales no coinciden/error no es de red)
      state = AsyncValue.error(e, st);
    }
  }

  // ⚠️ Este método es llamado por el Interceptor cuando el token expira
  void updateToken(Token newToken) async {
    final _isarService = _ref.read(isarServiceProvider);
    final _syncService = _ref.read(
      syncServiceProvider,
    ); // 💡 Obtener el SyncService

    // 1. Actualizar el token de la clase (usado por el Interceptor)
    _token = newToken;

    // 2. Obtener el usuario actual para actualizar el registro en Isar
    final currentUser = state.value;

    if (currentUser != null) {
      // 3. Crear una copia del usuario con el NUEVO Access y Refresh Token
      final userWithNewToken = currentUser.copyWith(
        accessToken: newToken.accessToken,
        refreshToken: newToken.refreshToken,
      );

      // 4. Guardar en Isar (sobrescribir el registro existente)
      await _isarService.saveUser(userWithNewToken);
    }

    // 🚀 INICIAR SINCRONIZACIÓN DESPUÉS DE RENOVAR EL TOKEN CON ÉXITO
    // Esto asegura que, si el token expiró y se renovó, la conexión está OK para sincronizar.
    _syncService.startSync();

    // 5. Verificación por Log
    print('✅ DEBUG REFRESH: Token actualizado con éxito.');
    print(
      ' -> Nuevo Access Token (Inicio): ${newToken.accessToken.substring(0, 8)}...',
    );
    print(
      ' -> Nuevo Refresh Token (Inicio): ${newToken.refreshToken?.substring(0, 8)}...',
    );
  }

  // --- Lógica de Logout ---

  Future<void> logout() async {
    state = const AsyncValue.loading();
    final _isarService = _ref.read(isarServiceProvider);

    _token = null;

    // COMPROMISO: Borrar la DB para que el Hot Restart NO te loguee.
    await _isarService.cleanDB();
    print('DEBUG LOGOUT: Usuario y sesión eliminados de Isar (Hard Logout).');

    state = const AsyncValue.data(null);
  }
}

// Proveedor global que se utiliza para leer el estado de autenticación
final authProvider = StateNotifierProvider<AuthNotifier, AsyncValue<User?>>(
  (ref) => AuthNotifier(ref),
);
