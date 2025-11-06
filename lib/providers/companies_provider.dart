// lib/providers/companies_provider.dart

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/company.dart';
import '../models/sync_queue_item.dart';
import '../services/api_service.dart';
import '../services/isar_service.dart';
import '../services/connectivity_service.dart';

// Definición de proveedores de servicio (asumida)
// final apiServiceProvider = Provider((ref) => ApiService());
// final isarServiceProvider = Provider((ref) => IsarService());
// final connectivityServiceProvider = Provider((ref) => ConnectivityService());

class CompaniesNotifier extends AsyncNotifier<List<Company>> {
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
        final targetId = item!.endpoint.split('/').last;
        final data = jsonDecode(item.payload);

        switch (item.operation) {
          case SyncOperation.CREATE_COMPANY:
            final newCompany = await _apiService.createCompany(data);
            if (item.localId != null) {
              await _isarService.updateLocalCompanyWithRealId(
                item.localId!,
                newCompany,
              );
            }
            break;

          case SyncOperation.UPDATE_COMPANY:
            await _apiService.updateCompany(targetId, data);
            break;

          case SyncOperation.DELETE_COMPANY:
            await _apiService.deleteCompany(targetId);
            await _isarService.deleteCompany(
              targetId,
            ); // Limpieza final de local DB
            break;

          // Omitir operaciones de Users y Branches
          default:
            print(
              'DEBUG SYNC: Operación no manejada por CompaniesNotifier: ${item.operation.name}',
            );
            // Si no es una operación de Company, la volvemos a encolar y salimos
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

  Future<void> _syncLocalDatabase(List<Company> onlineCompanies) async {
    final localCompanies = await _isarService.getAllCompanies();
    final Set<String> onlineIds = onlineCompanies.map((c) => c.id).toSet();

    // Limpieza de compañías obsoletas
    final List<String> staleIds = localCompanies
        .where((local) => !onlineIds.contains(local.id))
        .map((local) => local.id)
        .toList();
    for (final id in staleIds) {
      await _isarService.deleteCompany(id);
    }
    await _isarService.saveCompanies(onlineCompanies);
  }

  // ----------------------------------------------------------------------
  // CICLO DE VIDA Y FETCH
  // ----------------------------------------------------------------------

  @override
  Future<List<Company>> build() async {
    final localCompanies = await _isarService.getAllCompanies();

    if (localCompanies.isNotEmpty) {
      state = AsyncValue.data(localCompanies);
    }

    try {
      await _processSyncQueue(); // 🛑 Sincronizar cambios locales antes de obtener
      final onlineCompanies = await _apiService.fetchCompanies();
      await _syncLocalDatabase(onlineCompanies);
      return onlineCompanies;
    } catch (e) {
      if (localCompanies.isNotEmpty) return localCompanies;
      throw Exception(
        'Fallo al cargar compañías online y no hay datos offline: $e',
      );
    }
  }

  // ----------------------------------------------------------------------
  // CRUD CON FALLBACK OFFLINE
  // ----------------------------------------------------------------------

  Future<void> createCompany(CompanyCreateLocal data) async {
    final previousState = state;
    if (!state.hasValue) return;

    // 1. Actualización optimista temporal
    final tempCompany = Company(
      id: data.localId!,
      name: data.name,
      slug: data.slug,
    );
    state = AsyncValue.data([...previousState.value!, tempCompany]);

    try {
      final isConnected = await _connectivityService.checkConnection();
      if (isConnected) {
        try {
          // ONLINE
          final newCompany = await _apiService.createCompany(data.toJson());
          await _isarService.saveCompanies([newCompany]);

          // Reemplazar la temporal con la real en el estado de Riverpod
          final updatedList = previousState.value!
              .where((c) => c.id != data.localId)
              .toList();
          state = AsyncValue.data([...updatedList, newCompany]);
        } catch (e) {
          // FALLBACK OFFLINE: Si la llamada API falla
          await _handleOfflineCreate(data, tempCompany);
        }
      } else {
        // OFFLINE DIRECTO
        await _handleOfflineCreate(data, tempCompany);
      }
    } catch (e) {
      state = previousState;
      throw Exception('Fallo al crear compañía: ${e.toString()}');
    }
  }

  Future<void> _handleOfflineCreate(
    CompanyCreateLocal data,
    Company tempCompany,
  ) async {
    final syncItem = SyncQueueItem.create(
      operation: SyncOperation.CREATE_COMPANY,
      endpoint: '/api/v1/platform/companies',
      payload: jsonEncode(data.toJson()),
      localId: data.localId!,
    );
    await _isarService.enqueueSyncItem(syncItem);
    await _isarService.saveCompanies([tempCompany]);
    print('DEBUG OFFLINE: Compañía creada y encolada.');
  }

  Future<void> updateCompany(CompanyUpdateLocal data) async {
    final previousState = state;
    if (!state.hasValue) return;
    final currentList = previousState.value!;

    // 1. Actualización optimista local (Crea la versión optimista)
    final updatedList = currentList.map((company) {
      return company.id == data.id
          ? company.copyWith(
              name: data.name ?? company.name,
              slug: data.slug ?? company.slug,
            )
          : company;
    }).toList();

    state = AsyncValue.data(updatedList);

    // 💡 DEFINICIÓN CRUCIAL: Aquí se define 'companyToSave'
    final companyToSave = updatedList.firstWhere((c) => c.id == data.id);

    try {
      final isConnected = await _connectivityService.checkConnection();
      if (isConnected) {
        try {
          // ONLINE
          // Usamos toApiJson() para enviar solo los campos modificados
          final updatedCompany = await _apiService.updateCompany(
            data.id,
            data.toApiJson(),
          );
          await _isarService.saveCompanies([updatedCompany]);
        } catch (e) {
          // FALLBACK OFFLINE
          await _handleOfflineUpdate(data, companyToSave);
        }
      } else {
        // OFFLINE DIRECTO
        await _handleOfflineUpdate(data, companyToSave);
      }
    } catch (e) {
      state = previousState;
      throw Exception('Fallo al actualizar compañía: ${e.toString()}');
    }
  }

  // ----------------------------------------------------------------------
  // FUNCIÓN AUXILIAR DE MANEJO OFFLINE
  // ----------------------------------------------------------------------

  Future<void> _handleOfflineUpdate(
    CompanyUpdateLocal data,
    Company companyToSave,
  ) async {
    final syncItem = SyncQueueItem.create(
      operation: SyncOperation.UPDATE_COMPANY,
      endpoint: '/api/v1/platform/companies/${data.id}',
      payload: jsonEncode(data.toApiJson()),
      localId: data.id,
    );
    await _isarService.enqueueSyncItem(syncItem);
    await _isarService.saveCompanies([companyToSave]);
    print('DEBUG OFFLINE: Compañía actualizada y encolada.');
  }

  Future<void> deleteCompany(String companyId) async {
    final previousState = state;
    if (!state.hasValue) return;

    // 1. Optimistic Update: Eliminar del estado de Riverpod
    final companyToDelete = previousState.value!.firstWhere(
      (c) => c.id == companyId,
    );
    final updatedList = previousState.value!
        .where((c) => c.id != companyId)
        .toList();
    state = AsyncValue.data(updatedList);

    try {
      final isConnected = await _connectivityService.checkConnection();
      if (isConnected) {
        try {
          // ONLINE
          await _apiService.deleteCompany(companyId);
          await _isarService.deleteCompany(companyId);
        } catch (e) {
          // FALLBACK OFFLINE
          await _handleOfflineDelete(companyId, companyToDelete);
        }
      } else {
        // OFFLINE DIRECTO
        await _handleOfflineDelete(companyId, companyToDelete);
      }
    } catch (e) {
      state = previousState;
      throw Exception('Fallo al eliminar compañía: ${e.toString()}');
    }
  }

  Future<void> _handleOfflineDelete(
    String companyId,
    Company companyToDelete,
  ) async {
    // Marcar como eliminada en Isar y encolar
    final companyMarkedForDeletion = companyToDelete.copyWith(isDeleted: true);
    await _isarService.saveCompanies([companyMarkedForDeletion]);

    final syncItem = SyncQueueItem.create(
      operation: SyncOperation.DELETE_COMPANY,
      endpoint: '/api/v1/platform/companies/$companyId',
      payload: '{}',
    );
    await _isarService.enqueueSyncItem(syncItem);
    print('DEBUG OFFLINE: Compañía marcada para eliminación y encolada.');
  }
}

final companiesProvider =
    AsyncNotifierProvider<CompaniesNotifier, List<Company>>(() {
      return CompaniesNotifier();
    });
