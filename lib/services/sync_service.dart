// lib/services/sync_service.dart

import 'dart:convert';
import 'package:dcpos/providers/auth_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sync_queue_item.dart';
import '../models/user.dart';
import '../models/branch.dart'; // ✅ Agregado: Necesario para Branch.fromJson
import '../providers/users_provider.dart';
import '../providers/branches_provider.dart'; // ✅ Agregado: Necesario para invalidar
import 'api_service.dart';
import 'isar_service.dart';
import 'connectivity_service.dart';

final syncServiceProvider = Provider((ref) => SyncService(ref));

class SyncService {
  final Ref _ref;
  bool _isSyncing = false;
  bool _wasConnected = false;

  SyncService(this._ref) {
    _ref.listen<bool>(isConnectedProvider, (_, isConnected) {
      if (isConnected && !_wasConnected) {
        print('🌐 CONECTIVIDAD RESTAURADA: Llamando a startSync()');
        startSync();
      }
      _wasConnected = isConnected;
    }, fireImmediately: true);
  }

  // Helper para extraer ID del endpoint (el último segmento no vacío)
  String _extractTargetId(String endpoint) {
    final parts = endpoint.split('/');
    // Maneja casos como ".../id" o ".../id/"
    if (parts.isNotEmpty && parts.last.isEmpty && parts.length > 1) {
      return parts[parts.length - 2];
    }
    return parts.last;
  }

  Future<void> startSync() async {
    if (_isSyncing) return;
    if (!_ref.read(isConnectedProvider)) {
      print('🔄 SINCRONIZACIÓN CANCELADA: No hay conexión a Internet.');
      return;
    }

    final authNotifier = _ref.read(authProvider.notifier);
    if (authNotifier.accessToken == null) {
      print('DEBUG SYNC: No hay token de acceso. Deteniendo sincronización.');
      return;
    }

    _isSyncing = true;
    final isarService = _ref.read(isarServiceProvider);
    final apiService = _ref.read(apiServiceProvider);

    print('🔄 INICIANDO SINCRONIZACIÓN DE COLA...');

    try {
      while (true) {
        final item = await isarService.getNextSyncItem();
        if (item == null) break;

        final currentItem = item;
        final payloadMap = (currentItem.payload.isNotEmpty)
            ? jsonDecode(currentItem.payload) as Map<String, dynamic>
            : <String, dynamic>{};

        print(
          '-> Procesando [${currentItem.operation.name}] a ${currentItem.endpoint}',
        );

        try {
          // Manejo por tipo de operación
          switch (currentItem.operation) {
            // Usuarios
            case SyncOperation.CREATE_USER:
              {
                final response = await apiService.dio.post(
                  currentItem.endpoint,
                  data: payloadMap,
                );

                final createdUser = User.fromJson(
                  response.data as Map<String, dynamic>,
                );

                if (currentItem.localId != null) {
                  await isarService.deleteUser(currentItem.localId!);
                  await isarService.saveUsers([createdUser]);
                  _ref.invalidate(usersProvider);
                  print(
                    '✅ SYNC: Usuario local ${currentItem.localId} -> ServerID ${createdUser.id}',
                  );
                }
                break;
              }

            case SyncOperation.UPDATE_USER:
              {
                final targetId = _extractTargetId(currentItem.endpoint);

                bool exists = true;
                try {
                  exists = await apiService.userExists(targetId);
                } on DioException catch (e) {
                  print(
                    '❌ ERROR al verificar existencia del recurso $targetId: ${e.message}',
                  );
                  throw e;
                }

                if (!exists) {
                  print(
                    '⚠️ SYNC: Recurso $targetId no existe en backend. Desencolando UPDATE.',
                  );
                  await isarService.dequeueSyncItem(currentItem.id);
                  continue;
                }

                await apiService.dio.patch(
                  currentItem.endpoint,
                  data: payloadMap,
                );
                _ref.invalidate(usersProvider);
                break;
              }

            case SyncOperation.DELETE_USER:
              {
                final targetId = _extractTargetId(currentItem.endpoint);

                try {
                  await apiService.dio.delete(currentItem.endpoint);
                } on DioException catch (e) {
                  if (e.response?.statusCode == 404) {
                    print(
                      '⚠️ SYNC: DELETE recibió 404 para $targetId — asumiendo ya borrado. Desencolando.',
                    );
                  } else {
                    rethrow;
                  }
                }
                break;
              }

            // Branches
            case SyncOperation.CREATE_BRANCH:
              {
                final response = await apiService.dio.post(
                  currentItem.endpoint,
                  data: payloadMap,
                );

                // ✅ FIX CRÍTICO: Deserializar el Map a objeto Branch
                final createdBranch = Branch.fromJson(
                  response.data as Map<String, dynamic>,
                );

                if (currentItem.localId != null) {
                  await isarService.deleteBranch(currentItem.localId!);
                  await isarService.saveBranches([createdBranch]);
                  _ref.invalidate(
                    branchesProvider,
                  ); // ✅ Corregido a branchesProvider
                  print(
                    '✅ SYNC: Branch local ${currentItem.localId} -> ServerID ${createdBranch.id}',
                  );
                }
                break;
              }

            case SyncOperation.UPDATE_BRANCH:
              {
                final response = await apiService.dio.patch(
                  currentItem.endpoint,
                  data: payloadMap,
                );

                // ✅ Deserializar el Map a objeto Branch
                final updatedBranch = Branch.fromJson(
                  response.data as Map<String, dynamic>,
                );

                await isarService.saveBranches([updatedBranch]);
                _ref.invalidate(branchesProvider);
                break;
              }

            case SyncOperation.DELETE_BRANCH:
              {
                final targetId = _extractTargetId(currentItem.endpoint);

                try {
                  await apiService.dio.delete(currentItem.endpoint);
                } on DioException catch (e) {
                  if (e.response?.statusCode == 404) {
                    print(
                      '⚠️ SYNC: DELETE Branch recibió 404 para $targetId — asumiendo ya borrado.',
                    );
                  } else {
                    rethrow;
                  }
                }
                // La eliminación local ya fue manejada por el provider.
                _ref.invalidate(branchesProvider);
                break;
              }

            // Otros casos que delegues...
            default:
              print(
                'Operación no implementada en SyncService: ${currentItem.operation}',
              );
              break;
          }

          // Si todo fue OK, desencolar
          await isarService.dequeueSyncItem(currentItem.id);
        } catch (e) {
          // Manejo más granular de errores
          print('❌ FALLA Sincronización: ${e.toString()}');

          if (e is DioException) {
            final status = e.response?.statusCode;
            if (status == 404) {
              print(
                '❌ SYNC: 404 en operación ${currentItem.operation}. Desencolando y continuando.',
              );
              await isarService.dequeueSyncItem(currentItem.id);
              continue;
            }

            if (status == 401) {
              print(
                '🔐 SYNC: 401 recibido, intercepción para refresh. Deteniendo sync para reintentar más tarde.',
              );
            }
          }

          // Detenemos el procesamiento
          break;
        }
      }

      print('✅ SINCRONIZACIÓN COMPLETADA/DETENIDA.');
    } catch (e) {
      print('❌ Error general en SyncService: $e');
    } finally {
      _isSyncing = false;
    }
  }
}
