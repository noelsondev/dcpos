// lib/providers/users_provider.dart

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user.dart';
import '../models/sync_queue_item.dart';
import '../services/api_service.dart';
import '../services/isar_service.dart';
import '../services/connectivity_service.dart';
import 'auth_provider.dart';

// --- JERARQUÍA DE ROLES ---
const Map<String, int> _ROLE_HIERARCHY = {
  "global_admin": 0,
  "company_admin": 1,
  "cashier": 2,
  "accountant": 3,
  "guest": 99,
};

class UsersNotifier extends AsyncNotifier<List<User>> {
  ApiService get _apiService => ref.read(apiServiceProvider);
  IsarService get _isarService => ref.read(isarServiceProvider);
  ConnectivityService get _connectivityService =>
      ref.read(connectivityServiceProvider);

  // ---------------------------------------------------------------------------
  // PROCESAR COLA DE SINCRONIZACIÓN
  // ---------------------------------------------------------------------------
  Future<void> _processSyncQueue() async {
    final isConnected = await _connectivityService.checkConnection();
    if (!isConnected) return;

    SyncQueueItem? item;
    while ((item = await _isarService.getNextSyncItem()) != null) {
      try {
        final targetId = item!.endpoint.split('/').last;

        switch (item.operation) {
          case SyncOperation.CREATE_USER:
            final data = jsonDecode(item.payload);
            final newUser = await _apiService.createUser(data);

            if (item.localId != null) {
              await _isarService.updateLocalUserWithRealId(
                item.localId!,
                newUser,
              );
            }
            break;

          case SyncOperation.UPDATE_USER:
            final data = jsonDecode(item.payload);
            await _apiService.updateUser(targetId, data);
            break;

          case SyncOperation.DELETE_USER:
            await _apiService.deleteUser(targetId);
            break;

          default:
            break;
        }

        await _isarService.dequeueSyncItem(item.id);
      } catch (e) {
        break; // detener si falla
      }
    }
  }

  // ---------------------------------------------------------------------------
  // SINCRONIZAR BASE LOCAL
  // ---------------------------------------------------------------------------
  Future<void> _syncLocalDatabase(List<User> onlineUsers) async {
    final localUsers = await _isarService.getAllUsers();

    final onlineIds = onlineUsers.map((e) => e.id).toSet();
    final stale = localUsers
        .where((e) => !onlineIds.contains(e.id))
        .map((e) => e.id)
        .toList();

    for (final id in stale) {
      await _isarService.deleteUser(id);
    }

    await _isarService.saveUsers(onlineUsers);
  }

  @override
  Future<List<User>> build() async {
    final local = await _isarService.getAllUsers();
    final visibleLocal = local.where((e) => !e.isDeleted).toList();

    if (visibleLocal.isNotEmpty) {
      state = AsyncValue.data(visibleLocal);
    }

    try {
      await _processSyncQueue();

      final online = await _apiService.fetchAllUsers();
      await _syncLocalDatabase(online);
      return online;
    } catch (_) {
      if (visibleLocal.isNotEmpty) return visibleLocal;
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // OFFLINE CREATE
  // ---------------------------------------------------------------------------
  Future<void> _handleOfflineCreate(
    UserCreateLocal data,
    String targetRoleName,
    List<User> prev,
  ) async {
    if (data.localId == null) {
      throw Exception("localId no fue generado.");
    }

    final syncItem = SyncQueueItem.create(
      operation: SyncOperation.CREATE_USER,
      endpoint: "/api/v1/users/",
      payload: jsonEncode(data.toJson()),
      localId: data.localId!,
    );

    await _isarService.enqueueSyncItem(syncItem);

    final tempUser = User(
      id: data.localId!,
      username: data.username,
      roleId: data.roleId,
      roleName: targetRoleName,
      createdAt: DateTime.now().toIso8601String(),
      isActive: data.isActive,
      companyId: data.companyId,
      branchId: data.branchId,
      isDeleted: false,
    );

    await _isarService.saveUsers([tempUser]);
    state = AsyncValue.data([...prev, tempUser]);
  }

  // ---------------------------------------------------------------------------
  // OFFLINE UPDATE
  // ---------------------------------------------------------------------------
  Future<void> _handleOfflineUpdate(
    UserUpdateLocal data,
    String? targetRoleName,
    List<User> list,
  ) async {
    final original = list.firstWhere((u) => u.id == data.id);

    final updatedList = list.map((user) {
      if (user.id != data.id) return user;

      return user.copyWith(
        username: data.username ?? user.username,
        roleId: data.roleId ?? user.roleId,
        roleName: targetRoleName ?? user.roleName,
        isActive: data.isActive ?? user.isActive,
      );
    }).toList();

    final updatedUser = updatedList.firstWhere((u) => u.id == data.id);

    final syncItem = SyncQueueItem.create(
      operation: SyncOperation.UPDATE_USER,
      endpoint: "/api/v1/users/${data.id}",
      payload: jsonEncode(data.toJson()),
    );

    await _isarService.enqueueSyncItem(syncItem);
    await _isarService.saveUsers([updatedUser]);
    state = AsyncValue.data(updatedList);
  }

  // ---------------------------------------------------------------------------
  // CREATE USER
  // ---------------------------------------------------------------------------
  Future<void> createUser(UserCreateLocal data, String targetRoleName) async {
    final prev = state;
    if (!state.hasValue) return;

    try {
      final currentUser = ref.read(authProvider).value;
      if (currentUser == null ||
          !_canCreateUserWithRole(currentUser.roleName, targetRoleName)) {
        throw Exception(
          'Permiso denegado: No puede crear un usuario con rol "$targetRoleName".',
        );
      }

      final online = await _connectivityService.checkConnection();

      if (!online) {
        return _handleOfflineCreate(data, targetRoleName, prev.value!);
      }

      try {
        final newUser = await _apiService.createUser(data.toJson());
        await _isarService.saveUsers([newUser]);

        state = AsyncValue.data([...prev.value!, newUser]);
      } catch (_) {
        return _handleOfflineCreate(data, targetRoleName, prev.value!);
      }
    } catch (e) {
      throw Exception("Fallo al crear usuario: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // UPDATE USER
  // ---------------------------------------------------------------------------
  Future<void> editUser(UserUpdateLocal data, String? targetRoleName) async {
    final prev = state;
    if (!state.hasValue) return;

    final list = prev.value!;
    final original = list.firstWhere((u) => u.id == data.id);

    final finalRole = targetRoleName ?? original.roleName;

    try {
      final currentUser = ref.read(authProvider).value;
      if (currentUser == null ||
          !_canModifyTargetUserRole(currentUser.roleName, finalRole)) {
        throw Exception(
          'Permiso denegado: No puede modificar usuario con rol "$finalRole".',
        );
      }

      final online = await _connectivityService.checkConnection();

      if (!online) {
        return _handleOfflineUpdate(data, targetRoleName, list);
      }

      try {
        final updatedUser = await _apiService.updateUser(
          data.id,
          data.toJson(),
        );

        await _isarService.saveUsers([updatedUser]);

        state = AsyncValue.data(
          list.map((u) => u.id == data.id ? updatedUser : u).toList(),
        );
      } catch (_) {
        return _handleOfflineUpdate(data, targetRoleName, list);
      }
    } catch (e) {
      state = prev;
      throw Exception("Fallo al editar usuario: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // DELETE USER
  // ---------------------------------------------------------------------------
  Future<void> deleteUser(String id) async {
    final prev = state;
    if (!state.hasValue) return;

    final list = prev.value!;
    final user = list.firstWhere((u) => u.id == id);

    final currentUser = ref.read(authProvider).value;
    if (currentUser == null ||
        !_canModifyTargetUserRole(currentUser.roleName, user.roleName)) {
      throw Exception(
        "Permiso denegado: No puede eliminar al usuario con rol '${user.roleName}'.",
      );
    }

    final newList = list.where((u) => u.id != id).toList();
    state = AsyncValue.data(newList);

    final online = await _connectivityService.checkConnection();

    if (!online) {
      final marked = user.copyWith(isDeleted: true);
      await _isarService.saveUsers([marked]);

      await _isarService.enqueueSyncItem(
        SyncQueueItem.create(
          operation: SyncOperation.DELETE_USER,
          endpoint: "/api/v1/users/$id",
          payload: "{}",
        ),
      );
      return;
    }

    try {
      await _apiService.deleteUser(id);
      await _isarService.deleteUser(id);
    } catch (_) {
      final marked = user.copyWith(isDeleted: true);
      await _isarService.saveUsers([marked]);

      await _isarService.enqueueSyncItem(
        SyncQueueItem.create(
          operation: SyncOperation.DELETE_USER,
          endpoint: "/api/v1/users/$id",
          payload: "{}",
        ),
      );
    }
  }

  // 🔄 REFRESH
  Future<void> fetchOnlineUsers() async {
    state = await AsyncValue.guard(() async {
      await _processSyncQueue();
      final online = await _apiService.fetchAllUsers();
      await _syncLocalDatabase(online);
      return online;
    });
  }

  // ---------------------------------------------------------------------------
  // RBAC HELPERS
  // ---------------------------------------------------------------------------
  int _getRolePriority(String roleName) {
    final norm = roleName.toLowerCase().replaceAll(" ", "_");
    return _ROLE_HIERARCHY[norm] ?? _ROLE_HIERARCHY["guest"]!;
  }

  bool _canCreateUserWithRole(String creatorRole, String targetRole) {
    if (targetRole == "global_admin") return false;
    return _getRolePriority(creatorRole) < _getRolePriority(targetRole);
  }

  bool _canModifyTargetUserRole(String modifierRole, String targetRole) {
    return _getRolePriority(modifierRole) < _getRolePriority(targetRole);
  }
}

final usersProvider = AsyncNotifierProvider<UsersNotifier, List<User>>(
  () => UsersNotifier(),
);
