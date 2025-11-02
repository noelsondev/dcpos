// lib/providers/branches_provider.dart

import 'dart:convert';
import 'package:dcpos/providers/companies_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/branch.dart';
import '../models/sync_queue_item.dart';
import '../services/api_service.dart';
import '../services/isar_service.dart';
import '../services/connectivity_service.dart';

// Este proveedor gestionará la lista de TODAS las sucursales, aunque la UI las filtre por compañía.

class BranchesNotifier extends AsyncNotifier<List<Branch>> {
  ApiService get _apiService => ref.read(apiServiceProvider);
  IsarService get _isarService => ref.read(isarServiceProvider);
  ConnectivityService get _connectivityService =>
      ref.read(connectivityServiceProvider);

  // ----------------------------------------------------------------------
  // LÓGICA DE SINCRONIZACIÓN Y COLA
  // ----------------------------------------------------------------------

  Future<void> _processSyncQueue() async {
    final isConnected = await _connectivityService.checkConnection();
    if (!isConnected) return;

    SyncQueueItem? item;
    while ((item = await _isarService.getNextSyncItem()) != null) {
      try {
        final parts = item!.endpoint.split('/');
        final targetId = parts.last;
        // Asume que la Company ID es la penúltima parte si el endpoint es /.../company_id/branches/branch_id
        final companyId = parts.length >= 7 ? parts[parts.length - 4] : '';
        final data = jsonDecode(item.payload);

        switch (item.operation) {
          case SyncOperation.CREATE_BRANCH: // 💡 NUEVO
            // El payload tiene la data, pero necesitamos la companyId para el API.
            // Debemos extraer companyId del localId/payload/endpoint (el más fiable es el localId si se guardó)
            final localBranchData = BranchCreateLocal.fromJson(data);
            final newBranch = await _apiService.createBranch(
              localBranchData.companyId,
              localBranchData.toJson(),
            );

            if (item.localId != null) {
              await _isarService.updateLocalBranchWithRealId(
                item.localId!,
                newBranch,
              );
            }
            break;

          case SyncOperation.UPDATE_BRANCH: // 💡 NUEVO
            await _apiService.updateBranch(targetId, data);
            break;

          case SyncOperation.DELETE_BRANCH: // 💡 NUEVO
            // El targetId es el branchId. Necesitamos companyId para el API.
            if (companyId.isEmpty)
              throw Exception(
                'Company ID no encontrada en el endpoint para DELETE_BRANCH.',
              );
            await _apiService.deleteBranch(companyId, targetId);
            await _isarService.deleteBranch(
              targetId,
            ); // Limpieza final de local DB
            break;

          // Omitir operaciones de Users y Companies
          default:
            print(
              'DEBUG SYNC: Operación no manejada por BranchesNotifier: ${item.operation.name}',
            );
            // Si no es una operación de Branch, la volvemos a encolar y salimos
            await _isarService.enqueueSyncItem(item);
            return;
        }
        await _isarService.dequeueSyncItem(item.id);
      } catch (e) {
        print(
          'ERROR SYNC: Fallo la sincronización de ${item!.operation.name}: $e',
        );
        break;
      }
    }
  }

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
      await _processSyncQueue(); // 🛑 Sincronizar cambios locales antes de obtener

      // Nota: El API no tiene un endpoint para 'todas las branches'
      // Asumimos que podemos obtener todas las ramas de todas las compañías que el usuario ve
      // Para simplificar, asumiremos que si el usuario tiene permiso, el API lo devolverá
      // con un fetchAllBranches si existe. Como no existe, tenemos que hacerlo por Company.

      // Para este ejemplo, simplificaremos asumiendo que el usuario está asociado a una o más compañías:
      final companies = await ref.read(companiesProvider.future);
      final List<Branch> allOnlineBranches = [];

      for (final company in companies) {
        final branches = await _apiService.fetchBranches(company.id);
        allOnlineBranches.addAll(branches);
      }

      await _syncLocalDatabase(allOnlineBranches);
      return allOnlineBranches;
    } catch (e) {
      if (localBranches.isNotEmpty) return localBranches;
      throw Exception(
        'Fallo al cargar sucursales online y no hay datos offline: $e',
      );
    }
  }

  // ----------------------------------------------------------------------
  // CRUD CON FALLBACK OFFLINE
  // ----------------------------------------------------------------------

  Future<void> createBranch(BranchCreateLocal data) async {
    // Lógica similar a Company: Optimistic Update, Try Online, Fallback Offline
    // ... (Implementación completa)
  }

  Future<void> updateBranch(BranchUpdateLocal data) async {
    // Lógica similar a Company: Optimistic Update, Try Online, Fallback Offline
    // ... (Implementación completa)
  }

  Future<void> deleteBranch(String companyId, String branchId) async {
    // Lógica similar a Company: Optimistic Update, Try Online, Fallback Offline
    // ... (Implementación completa)
  }
}

final branchesProvider = AsyncNotifierProvider<BranchesNotifier, List<Branch>>(
  () {
    return BranchesNotifier();
  },
);
