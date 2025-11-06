// lib/services/sync_service.dart

import 'dart:convert';
import 'package:dcpos/providers/auth_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sync_queue_item.dart';
import '../models/user.dart';
import '../providers/users_provider.dart';
import 'api_service.dart';
import 'isar_service.dart';
import 'connectivity_service.dart';

// Asumimos que estos proveedores están definidos en otro lugar
// final isarServiceProvider = Provider((ref) => IsarService());
// final apiServiceProvider = Provider((ref) => ApiService(ref));

final syncServiceProvider = Provider((ref) => SyncService(ref));

class SyncService {
  final Ref _ref;
  bool _isSyncing = false;
  // Almacena el estado anterior para detectar el "cambio a online"
  bool _wasConnected = false;

  SyncService(this._ref) {
    // 🚀 CONFIGURAR LISTENER DE CONECTIVIDAD EN EL CONSTRUCTOR
    _ref.listen<bool>(isConnectedProvider, (_, isConnected) {
      if (isConnected && !_wasConnected) {
        // Detecta el cambio de Offline a Online
        print('🌐 CONECTIVIDAD RESTAURADA: Llamando a startSync()');
        startSync();
      }
      _wasConnected = isConnected;
    }, fireImmediately: true); // Verifica el estado inmediatamente al inicio
  }

  // Función principal para intentar sincronizar la cola
  Future<void> startSync() async {
    if (_isSyncing) return;

    // Leer el valor del StateProvider directamente
    if (!_ref.read(isConnectedProvider)) {
      print('🔄 SINCRONIZACIÓN CANCELADA: No hay conexión a Internet.');
      return;
    }

    // Aseguramos que el AuthProvider tenga un token
    if (_ref.read(authProvider.notifier).accessToken == null) {
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

        if (item == null) {
          break; // La cola está vacía.
        }

        // 🚀 FIX: Capturamos el valor no-nulo en una variable no-nullable.
        final currentItem = item;

        final payloadMap = jsonDecode(currentItem.payload);
        print(
          '-> Procesando [${currentItem.operation.name}] a ${currentItem.endpoint}',
        );

        try {
          dynamic response;

          switch (currentItem.operation) {
            case SyncOperation.CREATE_USER:
              response = await apiService.dio.post(
                currentItem.endpoint, // '/users/'
                data: payloadMap,
              );

              // 🚨 CORRECCIÓN CRÍTICA: Reemplazar el usuario temporal con el real
              final createdUser = User.fromJson(response.data);

              if (currentItem.localId != null) {
                // 1. Eliminar el usuario temporal (usando el ID local)
                await isarService.deleteUser(currentItem.localId!);

                // 2. Guardar el usuario final con el ID real del servidor
                await isarService.saveUsers([createdUser]);

                // 3. Forzar el refresco de la UI
                _ref.invalidate(usersProvider);

                print(
                  '✅ SYNC: Usuario local ${currentItem.localId} actualizado a ServerID ${createdUser.id}',
                );
              }
              break;

            case SyncOperation.UPDATE_USER:
              // 🚨 CORRECCIÓN: Usar item.endpoint directamente (ya debe contener el ID)
              response = await apiService.dio.patch(
                currentItem
                    .endpoint, // Ejemplo: '/users/uuid-real-del-servidor'
                data: payloadMap,
              );
              _ref.invalidate(usersProvider);
              break;

            case SyncOperation.DELETE_USER:
              response = await apiService.dio.delete(
                currentItem
                    .endpoint, // Ejemplo: '/users/uuid-real-del-servidor'
              );
              // La eliminación física ya se maneja en el Notifier si la red está ON.
              // Aquí solo debemos desencolar. La invalidación es opcional ya que DELETE
              // solo borra un registro.
              // _ref.invalidate(usersProvider);
              break;

            case SyncOperation.CREATE_COMPANY:
            case SyncOperation.UPDATE_COMPANY:
            case SyncOperation.DELETE_COMPANY:
            case SyncOperation.CREATE_BRANCH:
            case SyncOperation.UPDATE_BRANCH:
            case SyncOperation.DELETE_BRANCH:
              // Estas operaciones se manejan en sus respectivos Notifiers (BranchesNotifier, CompaniesNotifier)
              // Aquí solo las desencolamos si son exitosas (aunque deberían ser manejadas por el notifier al recargar)
              // Para mantener la lógica separada, solo agregamos el caso aquí para evitar el 'default'.
              print(
                'Operación de Compañía/Sucursal gestionada en su propio Notifier. Saltando.',
              );
              break;

            default:
              print('Operación no implementada: ${currentItem.operation}');
              break;
          }

          // Si la llamada es exitosa, desencolar
          await isarService.dequeueSyncItem(currentItem.id);
        } catch (e) {
          // 🚨 Manejo de Falla: Detiene la cola y muestra el error del servidor.
          print('❌ FALLA Sincronización: ${e.toString()}');

          if (e is DioException &&
              e.response?.data != null &&
              e.response?.data is Map) {
            final serverDetail =
                e.response?.data?['detail'] ??
                'Error desconocido en el servidor.';
            print('❌ DETALLE DEL SERVIDOR: $serverDetail');
          }
          break; // Romper el bucle y esperar una nueva llamada a startSync
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
