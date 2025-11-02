// lib/providers/users_provider.dart

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  // 🔑 SOLUCIÓN: Usamos Getters para acceder a los servicios, evitando el LateInitializationError al hacer reload.
  ApiService get _apiService => ref.read(apiServiceProvider);
  IsarService get _isarService => ref.read(isarServiceProvider);
  ConnectivityService get _connectivityService =>
      ref.read(connectivityServiceProvider);

  // 💡 FUNCIÓN CLAVE: Sincroniza Isar para que coincida exactamente con la data online (incluyendo la eliminación).
  Future<void> _syncLocalDatabase(List<User> onlineUsers) async {
    final localUsers = await _isarService.getAllUsers();

    // 1. Identificar usuarios obsoletos (en Isar pero no en el API)
    final Set<String> onlineUserIds = onlineUsers.map((u) => u.id).toSet();
    final List<String> staleUserIds = localUsers
        .where((localUser) => !onlineUserIds.contains(localUser.id))
        .map((localUser) => localUser.id)
        .toList();

    // 2. Eliminar los usuarios obsoletos (la limpieza)
    for (final userId in staleUserIds) {
      // Esto depende de la corrección en IsarService.deleteUser()
      await _isarService.deleteUser(userId);
    }

    // 3. Insertar/Actualizar los usuarios del API
    await _isarService.saveUsers(onlineUsers);
  }

  @override
  Future<List<User>> build() async {
    // Carga Rápida y Sincronización
    final localUsers = await _isarService.getAllUsers();

    // Filtramos los que están marcados para borrado lógico (isDeleted=false)
    final activeLocalUsers = localUsers
        .where((u) => u.isDeleted == false)
        .toList();

    if (activeLocalUsers.isNotEmpty) {
      state = AsyncValue.data(activeLocalUsers);
    }

    try {
      final onlineUsers = await _apiService.fetchAllUsers();

      // 🛑 Aplicar limpieza y sincronización
      await _syncLocalDatabase(onlineUsers);

      return onlineUsers;
    } catch (e) {
      if (activeLocalUsers.isNotEmpty) return activeLocalUsers;
      throw Exception(
        'Fallo al cargar usuarios online y no hay datos offline: $e',
      );
    }
  }

  // --- LÓGICA DE AYUDA RBAC ---

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

  // ----------------------------------------------------
  // --- MÉTODOS CRUD CON LÓGICA OFFLINE ---
  // ----------------------------------------------------

  Future<void> createUser(UserCreateLocal data) async {
    final isConnected = await _connectivityService.checkConnection();
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
      if (!isConnected && data.localId == null) {
        throw Exception(
          'Error interno: localId no fue generado para operación offline.',
        );
      }

      if (!isConnected) {
        final syncItem = SyncQueueItem.create(
          operation: SyncOperation.CREATE_USER,
          endpoint: '/api/v1/users/',
          payload: jsonEncode(data.toJson()),
          localId: data.localId!,
        );
        await _isarService.enqueueSyncItem(syncItem);

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
        );
        await _isarService.saveUsers([tempUser]);
        state = AsyncValue.data([...previousState.value!, tempUser]);
      } else {
        final newUser = await _apiService.createUser(data.toJson());
        await _isarService.saveUsers([newUser]);
        state = AsyncValue.data([...previousState.value!, newUser]);
      }
    } catch (e, st) {
      throw Exception('Fallo al crear usuario: ${e.toString()}');
    }
  }

  Future<void> editUser(UserUpdateLocal data) async {
    final isConnected = await _connectivityService.checkConnection();
    final previousState = state;
    final userDataMap = data.toJson();

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

      final updatedList = userList.map((user) {
        return user.id == data.id
            ? user.copyWith(
                username: data.username ?? user.username,
                roleName: data.roleName ?? user.roleName,
                roleId: data.roleId ?? user.roleId,
              )
            : user;
      }).toList();

      final userToSave = updatedList.firstWhere((u) => u.id == data.id);

      if (!isConnected) {
        final syncItem = SyncQueueItem.create(
          operation: SyncOperation.UPDATE_USER,
          endpoint: '/api/v1/users/${data.id}',
          payload: jsonEncode(userDataMap),
        );
        await _isarService.enqueueSyncItem(syncItem);
        await _isarService.saveUsers([userToSave]);
        state = AsyncValue.data(updatedList);
      } else {
        final updatedUser = await _apiService.updateUser(data.id, userDataMap);
        await _isarService.saveUsers([updatedUser]);

        final finalUpdatedList = userList.map((user) {
          return user.id == data.id ? updatedUser : user;
        }).toList();
        state = AsyncValue.data(finalUpdatedList);
      }
    } catch (e, st) {
      state = previousState;
      throw Exception('Fallo al editar usuario: ${e.toString()}');
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
        final userMarkedForDeletion = userToDelete.copyWith(isDeleted: true);
        await _isarService.saveUsers([userMarkedForDeletion]);

        final syncItem = SyncQueueItem.create(
          operation: SyncOperation.DELETE_USER,
          endpoint: '/api/v1/users/$userId',
          payload: '{}',
        );
        await _isarService.enqueueSyncItem(syncItem);
      } else {
        // ONLINE: Llamar API y DELECIÓN LOCAL
        await _apiService.deleteUser(userId);
        await _isarService.deleteUser(userId);
      }
    } catch (e, st) {
      state = previousState;
      throw Exception('Fallo al eliminar usuario: ${e.toString()}');
    }
  }

  // Refresca la lista de usuarios desde el servidor
  Future<void> fetchOnlineUsers() async {
    state = await AsyncValue.guard(() async {
      final onlineUsers = await _apiService.fetchAllUsers();

      // 🛑 Aplicar limpieza y sincronización
      await _syncLocalDatabase(onlineUsers);

      return onlineUsers;
    });
  }
}

final usersProvider = AsyncNotifierProvider<UsersNotifier, List<User>>(() {
  return UsersNotifier();
});
