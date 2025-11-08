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

// Definiciones de tipos (asumimos que CompanyCreateLocal y CompanyUpdateLocal existen)

class CompaniesNotifier extends AsyncNotifier<List<Company>> {
  ApiService get _apiService => ref.read(apiServiceProvider);
  IsarService get _isarService => ref.read(isarServiceProvider);
  ConnectivityService get _connectivityService =>
      ref.read(connectivityServiceProvider);

  // 💡 Accede al User? a través del getter 'user' del AuthNotifier
  User? get _currentUser => ref.read(authProvider.notifier).user;

  // ----------------------------------------------------------------------
  // 🎯 LÓGICA DE PERMISOS
  // ----------------------------------------------------------------------

  // 1. Verifica si el usuario tiene el rol 'global_admin' (Uso para Fetch/UI)
  bool _isGlobalAdmin() {
    final user = _currentUser;
    if (user == null) return false;

    return user.roleName == 'global_admin';
  }

  // 2. ✅ NUEVA LÓGICA: Verifica si el usuario tiene rol 'admin' (Global o Company) para CREAR/ELIMINAR
  bool _canPerformAdminAction() {
    final user = _currentUser;
    if (user == null) return false;

    // Asume que la creación requiere cualquier rol que contenga 'admin'
    return user.roleName.contains('admin');
  }

  // ----------------------------------------------------------------------
  // LÓGICA DE SINCRONIZACIÓN Y COLA (MANEJO DE ERRORES PERMANENTES)
  // ----------------------------------------------------------------------

  Future<void> _processSyncQueue() async {
    final isConnected = await _connectivityService.checkConnection();
    if (!isConnected) return;

    SyncQueueItem? item;
    while ((item = await _isarService.getNextSyncItem()) != null) {
      try {
        final targetId = item!.endpoint.split('/').last;
        final data = jsonDecode(item.payload);

        if (!item!.operation.name.contains('COMPANY')) {
          // Se mantiene la lógica de asumir que otro Notifier maneja esto.
        }

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
            await _isarService.deleteCompanyAndCascade(targetId);
            break;

          default:
            print(
              'DEBUG SYNC: Operación no manejada por CompaniesNotifier: ${item.operation.name}. Dejando en cola.',
            );
            return;
        }
        // Si la operación fue exitosa
        await _isarService.dequeueSyncItem(item.id);
      } catch (e) {
        print(
          'ERROR SYNC: Fallo la sincronización de ${item!.operation.name}: $e',
        );

        final errorMessage = e.toString().toLowerCase();

        // 🎯 Lógica para detectar errores permanentes y DESCARTAR el item
        if (errorMessage.contains('acceso denegado') ||
            errorMessage.contains('403') ||
            errorMessage.contains('not found') ||
            errorMessage.contains('404')) {
          print(
            'DEBUG SYNC: Descartando item ${item.operation.name} por error permanente (Permiso/4xx).',
          );
          await _isarService.dequeueSyncItem(item.id);
          // Continua el bucle para procesar el siguiente elemento
          continue;
        }

        // Si es cualquier otro error (ej. red, servidor caído 5xx), rompemos el bucle
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
      await _isarService.deleteCompanyAndCascade(id);
    }
    await _isarService.saveCompanies(onlineCompanies);
  }

  // ----------------------------------------------------------------------
  // CICLO DE VIDA Y FETCH
  // ----------------------------------------------------------------------

  @override
  Future<List<Company>> build() async {
    final user = _currentUser;
    if (user == null) {
      return [];
    }

    final localCompanies = await _isarService.getAllCompanies();

    if (localCompanies.isNotEmpty) {
      state = AsyncValue.data(localCompanies);
    }

    try {
      // 1. Procesar cola de sincronización
      await _processSyncQueue();

      // 2. Determinar la lista de compañías a obtener
      List<Company> onlineCompanies = [];

      // Utilizamos la verificación estricta de Global Admin para la lógica de FETCH
      final bool isGlobalAdmin = _isGlobalAdmin();
      final String? userCompanyId = user.companyId;

      if (isGlobalAdmin) {
        onlineCompanies = await _apiService.fetchCompanies();
      } else if (userCompanyId != null) {
        onlineCompanies = await _apiService.fetchCompanies(
          companyId: userCompanyId,
        );
      } else {
        return [];
      }

      // 3. Sincronizar y devolver
      await _syncLocalDatabase(onlineCompanies);
      return onlineCompanies;
    } catch (e) {
      if (localCompanies.isNotEmpty) {
        return localCompanies;
      }
      throw Exception(
        'Fallo al cargar compañías online y no hay datos offline: ${e.toString()}',
      );
    }
  }

  // ----------------------------------------------------------------------
  // CRUD CON FALLBACK OFFLINE
  // ----------------------------------------------------------------------

  Future<void> createCompany(CompanyCreateLocal data) async {
    // 1. 🛑 VERIFICACIÓN DE PERMISOS: Bloquea localmente a Cashier/Accountant si no son Admin.
    if (!_canPerformAdminAction()) {
      print(
        'ERROR PERMISOS: Intento de CREATE_COMPANY denegado localmente (Rol insuficiente).',
      );
      throw Exception(
        "Acceso denegado. Se requiere rol 'admin' (Global o Company).",
      );
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
          rethrow;
        }
      } else {
        // OFFLINE DIRECTO
        await _handleOfflineCreate(data, tempCompany);
      }
    } catch (e) {
      // Revertir el estado de Riverpod si hay fallo después de la actualización optimista
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
          rethrow;
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
    // 1. 🛑 Verificar Permisos: Bloquea localmente.
    if (!_canPerformAdminAction()) {
      print(
        'ERROR PERMISOS: Intento de DELETE_COMPANY denegado localmente (Rol insuficiente).',
      );
      throw Exception(
        "Acceso denegado. Se requiere rol 'admin' (Global o Company).",
      );
    }

    final previousState = state;
    if (!state.hasValue) return;

    // 2. Actualización optimista del estado de Riverpod
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
          await _handleOfflineDelete(companyId);
          rethrow;
        }
      } else {
        // OFFLINE DIRECTO
        await _handleOfflineDelete(companyId);
      }
    } catch (e) {
      // Revertir el estado de Riverpod si hay fallo
      state = previousState;
      throw Exception('Fallo al eliminar compañía: ${e.toString()}');
    }
  }

  // LÓGICA CORREGIDA: Eliminar localmente y encolar
  Future<void> _handleOfflineDelete(String companyId) async {
    // 1. Eliminar la compañía localmente
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
