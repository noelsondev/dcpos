// lib/providers/branches_provider.dart

import 'dart:convert';
import 'package:dcpos/providers/companies_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../models/branch.dart';
import '../models/sync_queue_item.dart';
import '../services/api_service.dart';
import '../services/isar_service.dart';
import '../services/connectivity_service.dart';
import '../services/sync_service.dart';

// Asegúrate de que BranchCreateLocal y BranchUpdateLocal están definidos/importados.

// Este proveedor gestionará la lista de TODAS las sucursales, aunque la UI las filtre por compañía.

class BranchesNotifier extends AsyncNotifier<List<Branch>> {
  ApiService get _apiService => ref.read(apiServiceProvider);
  IsarService get _isarService => ref.read(isarServiceProvider);
  ConnectivityService get _connectivityService =>
      ref.read(connectivityServiceProvider);
  SyncService get _syncService => ref.read(syncServiceProvider);

  // ----------------------------------------------------------------------
  // LÓGICA DE SINCRONIZACIÓN Y FETCH
  // ----------------------------------------------------------------------
  Future<void> _syncLocalDatabase(List<Branch> onlineBranches) async {
    final localBranches = await _isarService.getAllBranches();
    final Set<String> onlineIds = onlineBranches.map((b) => b.id).toSet();

    // Limpieza de sucursales obsoletas
    final List<String> staleIds = localBranches
        .where((local) => !onlineIds.contains(local.id))
        .map((local) => local.id)
        .toList();
    for (final id in staleIds) {
      await _isarService.deleteBranch(id);
    }
    await _isarService.saveBranches(onlineBranches);
  }

  // ----------------------------------------------------------------------
  // CICLO DE VIDA Y FETCH
  // ----------------------------------------------------------------------
  @override
  Future<List<Branch>> build() async {
    final localBranches = await _isarService.getAllBranches();

    if (localBranches.isNotEmpty) {
      state = AsyncValue.data(localBranches);
    }

    try {
      // 🛑 Forzar la sincronización antes de un fetch masivo.
      _syncService.startSync();

      // Obtener todas las ramas de todas las compañías que el usuario ve
      final companies = await ref.read(companiesProvider.future);
      final List<Branch> allOnlineBranches = [];

      // 💡 Por cada compañía, pedir sus ramas (asumiendo que el API lo permite)
      for (final company in companies) {
        final branches = await _apiService.fetchBranches(company.id);
        allOnlineBranches.addAll(branches);
      }

      await _syncLocalDatabase(allOnlineBranches);
      return allOnlineBranches;
    } on DioException catch (e) {
      if (localBranches.isNotEmpty) {
        return localBranches;
      }
      throw Exception('Fallo al cargar sucursales online: ${e.message}');
    } catch (e) {
      if (localBranches.isNotEmpty) return localBranches;
      throw Exception('Fallo al cargar sucursales: $e');
    }
  }

  // ----------------------------------------------------------------------
  // CRUD CON FALLBACK OFFLINE (Implementación Completa)
  // ----------------------------------------------------------------------

  Future<void> createBranch(BranchCreateLocal data) async {
    state = const AsyncValue.loading();
    final localId = data.localId!;

    // 1. Optimistic Update (Crear Branch con localId)
    final tempBranch = Branch(
      id: localId,
      companyId: data.companyId,
      name: data.name,
      address: data.address,
    );
    final currentList = state.value ?? [];
    await _isarService.saveBranches([tempBranch]);
    final newList = [...currentList.where((b) => b.id != localId), tempBranch];
    state = AsyncValue.data(newList);
    print('DEBUG OFFLINE: Sucursal creada localmente y encolada.');

    try {
      // 2. Intentar Online
      final newBranch = await _apiService.createBranch(
        data.companyId,
        data.toApiJson(),
      );

      // 3. Éxito: Actualizar el registro en Isar con el ID real
      await _isarService.updateLocalBranchWithRealId(localId, newBranch);

      // 4. Actualizar estado
      final updatedList = newList.map<Branch>((b) {
        return b.id == localId ? newBranch : b;
      }).toList();
      state = AsyncValue.data(updatedList);
      print('✅ ONLINE: Sucursal creada y sincronizada exitosamente.');
    } on DioException catch (e) {
      // 5. Fallback Offline: Encolar la operación
      if (e.response?.statusCode == null || e.response!.statusCode! < 500) {
        final syncItem = SyncQueueItem.create(
          operation: SyncOperation.CREATE_BRANCH,
          // ✅ CORRECCIÓN: Eliminar /api/v1/ para evitar duplicación
          endpoint: '/platform/companies/${data.companyId}/branches',
          payload: jsonEncode(data.toJson()),
          localId: localId,
        );
        await _isarService.enqueueSyncItem(syncItem);
        // Mantener el estado optimistic update
      } else {
        // Error 5xx o de red: Se mantendrá en el estado local temporal.
        rethrow;
      }
    }
  }

  Future<void> updateBranch(BranchUpdateLocal data) async {
    // 1. Optimistic Update
    final currentList = state.value ?? [];
    final oldBranch = currentList.firstWhere((b) => b.id == data.id);

    final branchToUpdateLocal = oldBranch.copyWith(
      name: data.name ?? oldBranch.name,
      address: data.address ?? oldBranch.address,
    );

    await _isarService.saveBranches([branchToUpdateLocal]);
    final newList = currentList.map((b) {
      return b.id == data.id ? branchToUpdateLocal : b;
    }).toList();
    state = AsyncValue.data(newList);
    print('DEBUG OFFLINE: Sucursal actualizada localmente y encolada.');

    try {
      // 2. Intentar Online
      final updatedBranch = await _apiService.updateBranch(
        data.companyId,
        data.id,
        data.toApiJson(),
      );

      // 3. Éxito: Actualizar en Isar
      await _isarService.saveBranches([updatedBranch]);

      // 4. Actualizar estado
      final updatedList = newList.map((b) {
        return b.id == data.id ? updatedBranch : b;
      }).toList();
      state = AsyncValue.data(updatedList);
      print('✅ ONLINE: Sucursal actualizada y sincronizada exitosamente.');
    } on DioException catch (e) {
      // 5. Fallback Offline: Encolar la operación
      if (e.response?.statusCode == null || e.response!.statusCode! < 500) {
        final syncItem = SyncQueueItem.create(
          operation: SyncOperation.UPDATE_BRANCH,
          // ✅ CORRECCIÓN: Eliminar /api/v1/ para evitar duplicación
          endpoint: '/platform/companies/${data.companyId}/branches/${data.id}',
          payload: jsonEncode(data.toJson()),
        );
        await _isarService.enqueueSyncItem(syncItem);
        // Mantener el estado optimistic update
      } else {
        rethrow;
      }
    }
  }

  Future<void> deleteBranch(String companyId, String branchId) async {
    // 1. Optimistic Update
    final currentList = state.value ?? [];
    final branchToDelete = currentList.firstWhere((b) => b.id == branchId);

    // Actualizar lista de UI (quitarla visualmente)
    final newList = currentList.where((b) => b.id != branchId).toList();
    state = AsyncValue.data(newList);

    try {
      // 2. Intentar Online
      await _apiService.deleteBranch(companyId, branchId);

      // 3. Éxito: Eliminar finalmente de Isar
      await _isarService.deleteBranch(branchId);
      print('✅ ONLINE: Sucursal eliminada y sincronizada exitosamente.');
    } on DioException catch (e) {
      // 4. Fallback Offline: Guardar en Isar como 'isDeleted: true' y encolar
      if (e.response?.statusCode == null || e.response!.statusCode! < 500) {
        await _handleOfflineDelete(companyId, branchId, branchToDelete);
      } else {
        rethrow;
      }
    }
  }

  // Función auxiliar para el manejo de la eliminación offline
  Future<void> _handleOfflineDelete(
    String companyId,
    String branchId,
    Branch branchToDelete,
  ) async {
    // Marcar como eliminado en Isar y guardar.
    final branchMarkedForDeletion = branchToDelete.copyWith(isDeleted: true);
    await _isarService.saveBranches([branchMarkedForDeletion]);

    // Encolar la operación de eliminación
    final syncItem = SyncQueueItem.create(
      operation: SyncOperation.DELETE_BRANCH,
      // ✅ CORRECCIÓN: Eliminar /api/v1/ para evitar duplicación
      endpoint: '/platform/companies/$companyId/branches/$branchId',
      payload: '{}',
    );
    await _isarService.enqueueSyncItem(syncItem);
    print('DEBUG OFFLINE: Sucursal marcada para eliminación y encolada.');
  }
}

final branchesProvider = AsyncNotifierProvider<BranchesNotifier, List<Branch>>(
  () {
    return BranchesNotifier();
  },
);
