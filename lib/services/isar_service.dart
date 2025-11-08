// lib/services/isar_service.dart

import 'package:dcpos/models/branch.dart';
import 'package:dcpos/models/company.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../models/role.dart';
import '../models/user.dart';
import '../models/sync_queue_item.dart';

// ----------------------------------------------------------------------
// FUNCIÓN DE AYUDA: fastHash para IDs de Isar
// ----------------------------------------------------------------------

// Isar requiere una función hash rápida para convertir un String (como un UUID)
// en un int (IsarId) para la clave primaria.
int fastHash(String string) {
  var hash = 0xcbf29ce484222325;

  var i = 0;
  while (i < string.length) {
    var codeUnit = string.codeUnitAt(i++);

    // Multiplicar por 1099511628211 (prime number) y XOR
    hash ^= codeUnit;
    hash *= 0x100000001b3;
  }

  // Convertir a un entero de 32 bits (porque IsarId es de 32 bits por defecto)
  return hash.toSigned(32);
}

class IsarService {
  late Future<Isar> db;

  IsarService() {
    db = openDB();
  }

  Future<Isar> openDB() async {
    if (Isar.instanceNames.isEmpty) {
      final dir = await getApplicationSupportDirectory();
      return await Isar.open(
        // Asegurar que todos los esquemas necesarios se abren
        [
          UserSchema,
          RoleSchema,
          SyncQueueItemSchema,
          CompanySchema,
          BranchSchema,
        ],
        directory: dir.path,
        inspector: true, // Útil para depuración
      );
    }
    return Isar.getInstance()!;
  }

  // ----------------------------------------------------
  // --- MÉTODOS CRUD BÁSICOS (Sesión y Colección) ---
  // ----------------------------------------------------

  // Guarda el único usuario de la SESIÓN ACTIVA (con tokens)
  Future<void> saveUser(User user) async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.users.clear();
      await isar.users.put(user);
    });
    print(
      'DEBUG ISAR: Usuario ${user.username} guardado exitosamente (Sesión).',
    );
  }

  // Guarda una lista de usuarios (usado para CACHÉ/CARGA INICIAL de la lista)
  Future<void> saveUsers(List<User> users) async {
    final isar = await db;
    await isar.writeTxn(() async {
      // Usamos putAll para guardar/actualizar la lista de usuarios.
      await isar.users.putAll(users);
    });
    print(
      'DEBUG ISAR: ${users.length} usuarios de la lista guardados/actualizados.',
    );
  }

  // Devolvemos el único usuario de la sesión activa (con tokens)
  Future<User?> getActiveUser() async {
    final isar = await db;
    // Buscamos el primer (o único) usuario guardado como sesión activa
    return isar.users.where().findFirst();
  }

  // Obtiene la lista COMPLETA de usuarios (para el UsersNotifier)
  Future<List<User>> getAllUsers() async {
    final isar = await db;
    return await isar.users.where().findAll();
  }

  // 🚨 MÉTODO PARA ELIMINAR UN ÚNICO USUARIO
  Future<void> deleteUser(String userId) async {
    final isar = await db;
    await isar.writeTxn(() async {
      final count = await isar.users
          .filter()
          .idEqualTo(userId) // Filtramos por el ID externo (String)
          .deleteAll(); // Eliminamos el registro encontrado.

      print(
        'DEBUG ISAR: Eliminados $count usuarios con ID $userId localmente.',
      );
    });
  }

  // Limpia la DB (Usado en el Logout, borra toda la sesión)
  Future<void> cleanDB() async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.users.clear();
      await isar.roles.clear();
      await isar.syncQueueItems.clear();
    });
    print('DEBUG ISAR: Base de datos limpiada (Hard Logout).');
  }

  // ----------------------------------------------------
  // --- Métodos para Roles y SyncQueue ---
  // ----------------------------------------------------

  Future<void> saveRoles(List<Role> roles) async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.roles.putAll(roles); // putAll usa el id único para put/update
    });
  }

  // Obtiene todos los roles para el modo offline
  Future<List<Role>> getAllRoles() async {
    final isar = await db;
    return isar.roles.where().findAll();
  }

  // 🚨 MÉTODO DE SINCRONIZACIÓN DE ID REAL
  Future<void> updateLocalUserWithRealId(String localId, User newUser) async {
    final isar = await db;
    await isar.writeTxn(() async {
      // 1. Encontrar y eliminar el usuario temporal por su ID temporal
      final localUserIsarId = await isar.users
          .filter()
          .idEqualTo(localId)
          .isarIdProperty()
          .findFirst();

      if (localUserIsarId != null) {
        await isar.users.delete(localUserIsarId);
      }

      // 2. Guardar el nuevo registro (con el ID real/UUID devuelto por el API)
      await isar.users.put(newUser);
    });
    print(
      'DEBUG ISAR SYNC: Usuario con ID temporal $localId actualizado a ID real ${newUser.id}.',
    );
  }

  // ----------------------------------------------------------------------
  // 💡 MÉTODOS PARA COMPANY (CON ELIMINACIÓN EN CASCADA)
  // ----------------------------------------------------------------------

  Future<List<Company>> getAllCompanies() async {
    final isar = await db;
    return isar.companys.filter().isDeletedEqualTo(false).findAll();
  }

  Future<void> saveCompanies(List<Company> companies) async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.companys.putAll(companies);
    });
  }

  // Método simple de eliminación de Company (ya no se usa directamente para la cascada)
  // Lo mantenemos por si la cola de sincronización lo necesita para una limpieza superficial.
  Future<void> _deleteCompanyRecord(String companyId) async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.companys.filter().idEqualTo(companyId).deleteAll();
    });
  }

  // 🎯 NUEVO MÉTODO CRÍTICO: Elimina Company y sus relaciones (Users, Branches)
  Future<void> deleteCompanyAndCascade(String companyId) async {
    final isar = await db;
    await isar.writeTxn(() async {
      // 1. Eliminar la Compañía
      final companyDeletedCount = await isar.companys
          .filter()
          .idEqualTo(companyId)
          .deleteAll();

      print(
        '✅ [Isar] Compañía ID $companyId eliminada. ($companyDeletedCount registros)',
      );

      // 2. Eliminar Usuarios relacionados (donde companyId == companyId)
      final deletedUsersCount = await isar.users
          .filter()
          .companyIdEqualTo(companyId) // Filtra por la clave foránea en User
          .deleteAll();

      print(
        '✅ [Isar] Se eliminaron $deletedUsersCount usuarios asociados a $companyId.',
      );

      // 3. Eliminar Sucursales (Branches) relacionadas (donde companyId == companyId)
      final deletedBranchesCount = await isar.branchs
          .filter()
          .companyIdEqualTo(companyId) // Filtra por la clave foránea en Branch
          .deleteAll();

      print(
        '✅ [Isar] Se eliminaron $deletedBranchesCount sucursales asociadas a $companyId.',
      );
    });
  }

  // Actualiza el ID temporal por el ID real después de la sincronización de CREACIÓN
  Future<void> updateLocalCompanyWithRealId(
    String localId,
    Company newCompany,
  ) async {
    final isar = await db;
    await isar.writeTxn(() async {
      final localCompanyIsarId = await isar.companys
          .filter()
          .idEqualTo(localId)
          .isarIdProperty()
          .findFirst();

      if (localCompanyIsarId != null) {
        await isar.companys.delete(localCompanyIsarId);
      }
      // Guardar el nuevo registro con el ID real
      await isar.companys.put(newCompany);
    });
  }

  // ----------------------------------------------------------------------
  // 💡 NUEVOS MÉTODOS PARA BRANCH
  // ----------------------------------------------------------------------
  Future<List<Branch>> getAllBranches() async {
    final isar = await db;
    return isar.branchs.filter().isDeletedEqualTo(false).findAll();
  }

  // Obtener branches por companyId (útil para la UI)
  Future<List<Branch>> getBranchesByCompanyId(String companyId) async {
    final isar = await db;
    return isar.branchs
        .filter()
        .isDeletedEqualTo(false)
        .and()
        .companyIdEqualTo(companyId)
        .findAll();
  }

  Future<void> saveBranches(List<Branch> branches) async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.branchs.putAll(branches);
    });
  }

  Future<void> deleteBranch(String branchId) async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.branchs.filter().idEqualTo(branchId).deleteAll();
    });
  }

  // Actualiza el ID temporal por el ID real después de la sincronización de CREACIÓN
  Future<void> updateLocalBranchWithRealId(
    String localId,
    Branch newBranch,
  ) async {
    final isar = await db;
    await isar.writeTxn(() async {
      final localBranchIsarId = await isar.branchs
          .filter()
          .idEqualTo(localId)
          .isarIdProperty()
          .findFirst();

      if (localBranchIsarId != null) {
        await isar.branchs.delete(localBranchIsarId);
      }
      // Guardar el nuevo registro con el ID real
      await isar.branchs.put(newBranch);
    });
  }

  // ----------------------------------------------------------------------
  // --- MÉTODOS DE COLA DE SINCRONIZACIÓN (SyncQueue) ---
  // ----------------------------------------------------------------------

  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.syncQueueItems.put(item);
    });
    print(
      'DEBUG ISAR: Operación ${item.operation.name} encolada para ${item.endpoint}.',
    );
  }

  // Obtiene el siguiente elemento de la cola, ordenado por tiempo de creación.
  Future<SyncQueueItem?> getNextSyncItem() async {
    final isar = await db;
    // Busca el primer elemento (el más antiguo) para mantener el orden FIFO (First-In, First-Out).
    return isar.syncQueueItems.where().sortByCreatedAt().findFirst();
  }

  // Elimina el elemento de la cola después de una sincronización exitosa.
  Future<void> dequeueSyncItem(int id) async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.syncQueueItems.delete(id);
    });
    print('DEBUG ISAR: Operación sincronizada y desencolada (ID: $id).');
  }
}

final isarServiceProvider = Provider((ref) => IsarService());
