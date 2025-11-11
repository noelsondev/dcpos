// lib/providers/users_provider.dart

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Importamos Dio para poder usar DioException en la lógica de errores.
import 'package:dio/dio.dart';

import '../models/user.dart'; // Contiene User, UserCreateLocal, UserUpdateLocal
import '../models/sync_queue_item.dart';
import '../services/api_service.dart';
import '../services/isar_service.dart';
import '../services/connectivity_service.dart';
import 'auth_provider.dart';

// Nota: Se asume que isarServiceProvider, apiServiceProvider y connectivityServiceProvider están definidos.

// --- JERARQUÍA DE ROLES DE EJEMPLO (Prioridad: menor número = más privilegio) ---
const Map<String, int> _ROLE_HIERARCHY = {
  "global_admin": 0,
  "company_admin": 1,
  "cashier": 2,
  "accountant": 3,
  'guest': 99,
};

// --- NOTIFIER PRINCIPAL ---

class UsersNotifier extends AsyncNotifier<List<User>> {
  // Getters para servicios
  ApiService get _apiService => ref.read(apiServiceProvider);
  IsarService get _isarService => ref.read(isarServiceProvider);
  ConnectivityService get _connectivityService =>
      ref.read(connectivityServiceProvider);

  // 💡 UTILIDAD DE ERROR INTERNA: Extrae el mensaje de un DioException para logueo
  String _getApiErrorMessage(
    dynamic error, {
    String defaultMsg = 'Error en el servidor o conexión.',
  }) {
    if (error is DioException) {
      final responseData = error.response?.data;
      if (responseData != null && responseData is Map) {
        // Intenta extraer 'detail' o 'message' del cuerpo de la respuesta
        final serverDetail =
            responseData['detail'] ??
            responseData['message'] ??
            responseData.toString();

        // Retorna un mensaje formateado para logueo
        return 'API Error ${error.response!.statusCode}: ${serverDetail}';
      }
      return 'Error de red: ${error.message}';
    } else if (error is Exception) {
      // Limpia el prefijo 'Exception: ' para excepciones de lógica
      return error.toString().replaceFirst('Exception: ', '');
    }
    return defaultMsg;
  }
  // --------------------------------------------------------------------------------

  // 💡 FUNCIÓN CLAVE: Procesa la cola de sincronización
  Future<void> _processSyncQueue() async {
    final isConnected = await _connectivityService.checkConnection();
    if (!isConnected) return; // Salir si no hay conexión

    SyncQueueItem? item;
    // Procesar la cola hasta que esté vacía o falle una operación
    while ((item = await _isarService.getNextSyncItem()) != null) {
      try {
        // Para UPDATE y DELETE, extraemos el ID del endpoint (ej: /users/ID)
        final targetId = item!.endpoint.split('/').last;

        switch (item.operation) {
          case SyncOperation.CREATE_USER:
            final data = jsonDecode(item.payload);
            final newUser = await _apiService.createUser(data);
            // 🚨 Paso crucial para manejar IDs temporales
            if (item.localId != null) {
              await _isarService.updateLocalUserWithRealId(
                item.localId!,
                newUser,
              );
            }
            break;

          case SyncOperation.UPDATE_USER:
            final data = jsonDecode(item.payload);
            // Usamos el targetId extraído del endpoint
            await _apiService.updateUser(targetId, data);
            // La siguiente _syncLocalDatabase confirmará el cambio del API.
            break;

          case SyncOperation.DELETE_USER:
            // Usamos el targetId extraído del endpoint
            await _apiService.deleteUser(targetId);
            // Eliminamos de Isar ya que la API confirmó la eliminación
            await _isarService.deleteUser(targetId);
            break;

          default:
            print('DEBUG SYNC: Operación desconocida: ${item.operation.name}');
            break;
        }

        // En éxito, eliminar el item de la cola
        await _isarService.dequeueSyncItem(item.id);
        print(
          'DEBUG SYNC: Operación ${item.operation.name} sincronizada exitosamente.',
        );
      } catch (e) {
        // 🚨 MANEJO DE ERROR CON UTILIDAD INTERNA (para logueo)
        final errorMsg = _getApiErrorMessage(
          e,
          defaultMsg:
              'Fallo al sincronizar ${item!.operation.name}. Deteniendo cola.',
        );
        print('❌ ERROR SYNC: $errorMsg');
        break; // Romper el bucle y esperar una nueva conexión
      }
    }
  }

  // --------------------------------------------------------------------------------

  // Lógica de limpieza y sincronización (sin cambios)
  Future<void> _syncLocalDatabase(List<User> onlineUsers) async {
    final localUsers = await _isarService.getAllUsers();
    final Set<String> onlineUserIds = onlineUsers.map((u) => u.id).toSet();
    final List<String> staleUserIds = localUsers
        .where((localUser) => !onlineUserIds.contains(localUser.id))
        .map((localUser) => localUser.id)
        .toList();
    for (final userId in staleUserIds) {
      await _isarService.deleteUser(userId);
    }
    // Guardar los datos del API.
    await _isarService.saveUsers(onlineUsers);
  }

  @override
  Future<List<User>> build() async {
    final localUsers = await _isarService.getAllUsers();
    final activeLocalUsers = localUsers
        .where((u) => u.isDeleted == false)
        .toList();

    if (activeLocalUsers.isNotEmpty) {
      state = AsyncValue.data(activeLocalUsers);
    }

    try {
      // 🛑 PRIMERO PROCESAMOS LA COLA al inicio
      await _processSyncQueue();

      final onlineUsers = await _apiService.fetchAllUsers();
      await _syncLocalDatabase(onlineUsers);
      return onlineUsers
          .where((u) => !u.isDeleted)
          .toList(); // Aseguramos que solo retornamos activos
    } catch (e) {
      if (activeLocalUsers.isNotEmpty) return activeLocalUsers;
      throw Exception(
        'Fallo al cargar usuarios online y no hay datos offline: $e',
      );
    }
  }

  // -------------------------------------------------------------------
  // MÉTODOS PRIVADOS OFFLINE (Usando isPendingSync: true)
  // -------------------------------------------------------------------
  Future<void> _handleOfflineCreate(
    UserCreateLocal data,
    List<User> previousList,
  ) async {
    if (data.localId == null) {
      throw Exception(
        'Error interno: localId no fue generado para operación offline.',
      );
    }

    final syncItem = SyncQueueItem.create(
      operation: SyncOperation.CREATE_USER,
      endpoint: '/api/v1/users/',
      payload: jsonEncode(data.toJson()),
      localId: data.localId!,
    );
    await _isarService.enqueueSyncItem(syncItem);

    // Creamos el usuario temporal con isPendingSync: true
    final tempUser = User(
      id: data.localId!,
      username: data.username,
      roleId: data.roleId,
      roleName: data.roleName,
      createdAt: DateTime.now().toIso8601String(),
      isActive: data.isActive,
      companyId: data.companyId,
      branchId: data.branchId,
      isDeleted: false,
      isPendingSync: true, // 👈 Ahora el modelo User lo soporta
    );
    await _isarService.saveUsers([tempUser]);

    state = AsyncValue.data([...previousList, tempUser]);
    print('DEBUG OFFLINE: Fallback a modo offline (Creación encolada).');
  }

  Future<void> _handleOfflineUpdate(
    UserUpdateLocal data,
    List<User> userList,
  ) async {
    final userDataMap = data.toJson();

    final userToSave = userList
        .firstWhere((u) => u.id == data.id)
        .copyWith(
          username:
              data.username ??
              userList.firstWhere((u) => u.id == data.id).username,
          roleName:
              data.roleName ??
              userList.firstWhere((u) => u.id == data.id).roleName,
          roleId:
              data.roleId ?? userList.firstWhere((u) => u.id == data.id).roleId,
          isPendingSync: true, // 👈 Ahora el modelo User lo soporta
        );

    final updatedList = userList.map((user) {
      return user.id == data.id ? userToSave : user;
    }).toList();

    final syncItem = SyncQueueItem.create(
      operation: SyncOperation.UPDATE_USER,
      endpoint: '/api/v1/users/${data.id}',
      payload: jsonEncode(userDataMap),
    );
    await _isarService.enqueueSyncItem(syncItem);
    await _isarService.saveUsers([userToSave]);

    state = AsyncValue.data(updatedList);
    print('DEBUG OFFLINE: Fallback a modo offline (Edición encolada).');
  }

  // -------------------------------------------------------------------
  // MÉTODOS CRUD CON LOGUEO DE ERROR
  // -------------------------------------------------------------------

  Future<void> createUser(UserCreateLocal data) async {
    final previousState = state;
    if (!state.hasValue) return;

    try {
      final currentUser = ref.read(authProvider).value;
      if (currentUser == null ||
          !_canCreateUserWithRole(currentUser.roleName, data.roleName)) {
        throw Exception(
          'Permiso denegado: No puede crear el usuario con el rol "${data.roleName}".',
        );
      }

      final isConnected = await _connectivityService.checkConnection();

      if (!isConnected) {
        await _handleOfflineCreate(data, previousState.value!);
        return;
      }

      try {
        final newUser = await _apiService.createUser(data.toJson());
        await _isarService.saveUsers([newUser]);
        state = AsyncValue.data([...previousState.value!, newUser]);
      } catch (e) {
        // 🚨 FALLBACK: Logueamos el error usando la utilidad y encolamos
        final errorMsg = _getApiErrorMessage(
          e,
          defaultMsg: 'Error al conectar. Encolando creación...',
        );
        print('⚠️ FALLBACK CREATE: $errorMsg');
        await _handleOfflineCreate(data, previousState.value!);
      }
    } catch (e, st) {
      // Lanzar para que la UI use SnackbarUtils.showError(context, e)
      throw Exception('Fallo al crear usuario: ${_getApiErrorMessage(e)}');
    }
  }

  Future<void> editUser(UserUpdateLocal data) async {
    final previousState = state;
    if (!state.hasValue || data.id == null) return;

    try {
      final userList = previousState.value!;
      final originalUser = userList.firstWhere((u) => u.id == data.id);
      final targetRole = data.roleName ?? originalUser.roleName;

      final currentUser = ref.read(authProvider).value;
      if (currentUser == null ||
          !_canModifyTargetUserRole(currentUser.roleName, targetRole)) {
        throw Exception(
          'Permiso denegado: No puede modificar el usuario con rol "$targetRole".',
        );
      }

      final isConnected = await _connectivityService.checkConnection();

      if (!isConnected) {
        await _handleOfflineUpdate(data, userList);
        return;
      }

      try {
        final userDataMap = data.toJson();
        final updatedUser = await _apiService.updateUser(data.id!, userDataMap);
        await _isarService.saveUsers([updatedUser]);

        final finalUpdatedList = userList.map((user) {
          return user.id == data.id ? updatedUser : user;
        }).toList();
        state = AsyncValue.data(finalUpdatedList);
      } catch (e) {
        // 🚨 FALLBACK: Logueamos el error usando la utilidad y encolamos
        final errorMsg = _getApiErrorMessage(
          e,
          defaultMsg: 'Error al conectar. Encolando edición...',
        );
        print('⚠️ FALLBACK EDIT: $errorMsg');
        await _handleOfflineUpdate(data, userList);
      }
    } catch (e, st) {
      state = previousState;
      // Lanzar para que la UI use SnackbarUtils.showError(context, e)
      throw Exception('Fallo al editar usuario: ${_getApiErrorMessage(e)}');
    }
  }

  Future<void> deleteUser(String userId) async {
    final isConnected = await _connectivityService.checkConnection();
    final previousState = state;

    if (!state.hasValue) return;

    try {
      final userList = previousState.value!;
      final userToDelete = userList.firstWhere((u) => u.id == userId);
      final targetRole = userToDelete.roleName;

      final currentUser = ref.read(authProvider).value;
      if (currentUser == null ||
          !_canModifyTargetUserRole(currentUser.roleName, targetRole)) {
        throw Exception(
          'Permiso denegado: No puede eliminar al usuario con rol "$targetRole".',
        );
      }

      // Optimistically update state (remueve el usuario de la lista mostrada)
      final updatedList = userList.where((u) => u.id != userId).toList();
      state = AsyncValue.data(updatedList);

      if (!isConnected) {
        // OFFLINE: Marcar y encolar
        final userMarkedForDeletion = userToDelete.copyWith(
          isDeleted: true,
          isPendingSync: true,
        );
        await _isarService.saveUsers([userMarkedForDeletion]);

        final syncItem = SyncQueueItem.create(
          operation: SyncOperation.DELETE_USER,
          endpoint: '/api/v1/users/$userId',
          payload: '{}',
        );
        await _isarService.enqueueSyncItem(syncItem);
      } else {
        // ONLINE: Llamar API y DELECIÓN LOCAL
        try {
          await _apiService.deleteUser(userId);
          await _isarService.deleteUser(userId);
        } catch (e) {
          // 🚨 FALLBACK para DELETE: logueamos, marcamos y encolamos
          final errorMsg = _getApiErrorMessage(
            e,
            defaultMsg: 'Error al conectar. Encolando eliminación...',
          );
          print('⚠️ FALLBACK DELETE: $errorMsg');

          final userMarkedForDeletion = userToDelete.copyWith(
            isDeleted: true,
            isPendingSync: true,
          );
          await _isarService.saveUsers([userMarkedForDeletion]);

          final syncItem = SyncQueueItem.create(
            operation: SyncOperation.DELETE_USER,
            endpoint: '/api/v1/users/$userId',
            payload: '{}',
          );
          await _isarService.enqueueSyncItem(syncItem);
        }
      }
    } catch (e, st) {
      state = previousState;
      // Lanzar para que la UI use SnackbarUtils.showError(context, e)
      throw Exception('Fallo al eliminar usuario: ${_getApiErrorMessage(e)}');
    }
  }

  // Refresca la lista de usuarios desde el servidor
  Future<void> fetchOnlineUsers() async {
    state = await AsyncValue.guard(() async {
      // 🛑 PRIMERO PROCESAMOS LA COLA
      await _processSyncQueue();

      final onlineUsers = await _apiService.fetchAllUsers();
      await _syncLocalDatabase(onlineUsers);
      return onlineUsers
          .where((u) => !u.isDeleted)
          .toList(); // Asegurar solo activos
    });
  }

  // --- LÓGICA DE AYUDA RBAC (Sin cambios) ---
  int _getRolePriority(String? roleName) {
    if (roleName == null) return _ROLE_HIERARCHY['guest']!;
    final normalizedRoleName = roleName.toLowerCase().replaceAll(' ', '_');
    if (_ROLE_HIERARCHY.containsKey(normalizedRoleName)) {
      return _ROLE_HIERARCHY[normalizedRoleName]!;
    }
    return _ROLE_HIERARCHY['guest']!;
  }

  bool _canCreateUserWithRole(String creatingUserRole, String targetUserRole) {
    final creatorPriority = _getRolePriority(creatingUserRole);
    final targetPriority = _getRolePriority(targetUserRole);
    if (targetPriority == _ROLE_HIERARCHY['global_admin']) return false;
    return creatorPriority < targetPriority;
  }

  bool _canModifyTargetUserRole(
    String modifyingUserRole,
    String targetUserRole,
  ) {
    final modifierPriority = _getRolePriority(modifyingUserRole);
    final targetPriority = _getRolePriority(targetUserRole);
    return modifierPriority < targetPriority;
  }
}

final usersProvider = AsyncNotifierProvider<UsersNotifier, List<User>>(() {
  return UsersNotifier();
});
