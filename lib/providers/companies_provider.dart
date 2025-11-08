// lib/providers/companies_provider.dart

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/company.dart';
import '../models/sync_queue_item.dart';
import '../services/api_service.dart';
import '../services/isar_service.dart';
import '../services/connectivity_service.dart';
import '../providers/auth_provider.dart';
import '../models/user.dart';

class CompaniesNotifier extends AsyncNotifier<List<Company>> {
  ApiService get _apiService => ref.read(apiServiceProvider);
  IsarService get _isarService => ref.read(isarServiceProvider);
  ConnectivityService get _connectivityService =>
      ref.read(connectivityServiceProvider);

  // 💡 Accede al User? a través del getter 'user' del AuthNotifier
  User? get _currentUser => ref.read(authProvider.notifier).user;

  // ----------------------------------------------------------------------
  // AYUDA: Verifica si el usuario tiene el rol 'global_admin'
  // ----------------------------------------------------------------------
  bool _isGlobalAdmin() {
    final user = _currentUser;
    if (user == null) return false;

    // ✅ Usamos roleName directamente para la verificación
    return user.roleName == 'global_admin';
  }

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
            // 💡 USAR EL MÉTODO DE CASCADA DESPUÉS DE LA ELIMINACIÓN REMOTA
            await _isarService.deleteCompanyAndCascade(targetId);
            break;

          default:
            print(
              'DEBUG SYNC: Operación no manejada por CompaniesNotifier: ${item.operation.name}',
            );
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

    // Identifica y elimina las compañías obsoletas
    final List<String> staleIds = localCompanies
        .where((local) => !onlineIds.contains(local.id))
        .map((local) => local.id)
        .toList();

    for (final id in staleIds) {
      // 💡 USAR EL MÉTODO DE CASCADA PARA LA LIMPIEZA
      await _isarService.deleteCompanyAndCascade(id);
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
      // 💡 CAMBIO CLAVE: Esperar a que TODAS las operaciones pendientes (incluyendo DELETE) se ejecuten en el servidor.
      await _processSyncQueue();

      // 2. Ahora que el servidor está actualizado, traemos los datos frescos.
      final onlineCompanies = await _apiService.fetchCompanies();

      // 3. Sincronizamos localmente, eliminando las obsoletas (las que acabamos de borrar).
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
    // 💡 1. VERIFICACIÓN DE PERMISOS: Bloquear el encolado y la actualización optimista.
    if (!_isGlobalAdmin()) {
      print(
        'ERROR PERMISOS: Intento de CREATE_COMPANY denegado localmente (No Global Admin).',
      );
      throw Exception("Acceso denegado. Se requiere rol 'global_admin'.");
    }

    final previousState = state;
    if (!state.hasValue) return;

    // 2. Actualización optimista temporal (solo si pasó la verificación)
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

    final updatedList = currentList.map((company) {
      return company.id == data.id
          ? company.copyWith(
              name: data.name ?? company.name,
              slug: data.slug ?? company.slug,
            )
          : company;
    }).toList();

    state = AsyncValue.data(updatedList);
    final companyToSave = updatedList.firstWhere((c) => c.id == data.id);

    try {
      final isConnected = await _connectivityService.checkConnection();
      if (isConnected) {
        try {
          final updatedCompany = await _apiService.updateCompany(
            data.id,
            data.toApiJson(),
          );
          await _isarService.saveCompanies([updatedCompany]);
        } catch (e) {
          await _handleOfflineUpdate(data, companyToSave);
        }
      } else {
        await _handleOfflineUpdate(data, companyToSave);
      }
    } catch (e) {
      state = previousState;
      throw Exception('Fallo al actualizar compañía: ${e.toString()}');
    }
  }

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
    // 1. Verificar Permisos (aunque esto debería hacerse en la UI)
    if (!_isGlobalAdmin()) {
      print(
        'ERROR PERMISOS: Intento de DELETE_COMPANY denegado localmente (No Global Admin).',
      );
      throw Exception("Acceso denegado. Se requiere rol 'global_admin'.");
    }

    final previousState = state;
    if (!state.hasValue) return;

    // 2. Actualización optimista del estado de Riverpod
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
          // Si la eliminación remota fue exitosa, eliminamos la compañía y todos sus hijos localmente.
          await _isarService.deleteCompanyAndCascade(companyId);
        } catch (e) {
          // FALLBACK OFFLINE: Si la llamada API falla
          await _handleOfflineDelete(
            companyId,
          ); // Eliminamos el parámetro companyToDelete
        }
      } else {
        // OFFLINE DIRECTO
        await _handleOfflineDelete(
          companyId,
        ); // Eliminamos el parámetro companyToDelete
      }
    } catch (e) {
      // Revertir el estado de Riverpod si hay fallo
      state = previousState;
      throw Exception('Fallo al eliminar compañía: ${e.toString()}');
    }
  }

  // 🎯 LÓGICA CORREGIDA: Eliminar localmente y encolar
  Future<void> _handleOfflineDelete(String companyId) async {
    // 1. Eliminar la compañía localmente
    // 💡 ¡CRUCIAL! Esto asegura que la compañía no se cargue más en la UI.
    // NOTA: Usamos el método de cascada. Esto es un riesgo potencial si el usuario
    // borra offline y luego se conecta, pero garantiza consistencia de la UI.
    // El backend debe manejar la eliminación en cascada de los hijos al sincronizar.
    await _isarService.deleteCompanyAndCascade(companyId);

    // 2. Encolar la operación de eliminación
    final syncItem = SyncQueueItem.create(
      operation: SyncOperation.DELETE_COMPANY,
      endpoint: '/api/v1/platform/companies/$companyId',
      payload: '{}', // Payload vacío para DELETE
    );
    await _isarService.enqueueSyncItem(syncItem);
    print('DEBUG OFFLINE: Compañía eliminada localmente y encolada.');
  }
}

final companiesProvider =
    AsyncNotifierProvider<CompaniesNotifier, List<Company>>(() {
      return CompaniesNotifier();
    });
