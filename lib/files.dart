// lib/models/branch.dart

import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:isar/isar.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';

part 'branch.g.dart';

// ----------------------------------------------------------------------
// 1. MODELO PRINCIPAL (DB y API Fetch)
// ----------------------------------------------------------------------
@CopyWith()
@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
@Collection()
class Branch {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  final String id;

  final String companyId;
  final String name;
  final String? address;

  final bool isDeleted;

  Branch({
    required this.id,
    required this.companyId,
    required this.name,
    this.address,
    this.isDeleted = false,
  });

  factory Branch.fromJson(Map<String, dynamic> json) => _$BranchFromJson(json);
  Map<String, dynamic> toJson() => _$BranchToJson(this);
}

// ----------------------------------------------------------------------
// 2. MODELO DE CREACIÓN (Offline-First) - Para la Cola de Sincronización
// ----------------------------------------------------------------------
@JsonSerializable(explicitToJson: true)
class BranchCreateLocal {
  final String? localId;
  final String name;
  final String? address;
  final String companyId;

  BranchCreateLocal({
    String? localId,
    required this.name,
    this.address,
    required this.companyId,
  }) : localId = localId ?? const Uuid().v4();

  // 💡 Usado para la solicitud al API (solo datos)
  Map<String, dynamic> toApiJson() {
    return {'name': name, if (address != null) 'address': address};
  }

  // 💡 Usado para guardar en SyncQueueItem.payload (datos completos)
  Map<String, dynamic> toJson() => _$BranchCreateLocalToJson(this);

  factory BranchCreateLocal.fromJson(Map<String, dynamic> json) =>
      _$BranchCreateLocalFromJson(json);
}

// ----------------------------------------------------------------------
// 3. MODELO DE ACTUALIZACIÓN (Offline-First) - CORREGIDO
// ----------------------------------------------------------------------
// 💡 CORRECCIÓN: createFactory: false
@JsonSerializable(
  includeIfNull: false,
  explicitToJson: true,
  createFactory: false,
)
class BranchUpdateLocal {
  @JsonKey(ignore: true)
  final String id;
  @JsonKey(ignore: true)
  final String companyId;

  final String? name;
  final String? address;

  BranchUpdateLocal({
    required this.id, // Ahora funciona correctamente
    required this.companyId,
    this.name,
    this.address,
  });

  // Usado para la solicitud PATCH al API
  Map<String, dynamic> toApiJson() => _$BranchUpdateLocalToJson(this);
}

// lib/models/company.dart

import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:isar/isar.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';

part 'company.g.dart';

// ----------------------------------------------------------------------
// 1. MODELO PRINCIPAL (DB y API Fetch)
// ----------------------------------------------------------------------
@CopyWith()
@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
@Collection()
class Company {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  final String id;

  final String name;
  final String slug;

  final bool isDeleted;

  Company({
    required this.id,
    required this.name,
    required this.slug,
    this.isDeleted = false,
  });

  factory Company.fromJson(Map<String, dynamic> json) =>
      _$CompanyFromJson(json);
  Map<String, dynamic> toJson() => _$CompanyToJson(this);
}

// ----------------------------------------------------------------------
// 2. MODELO DE CREACIÓN (Offline-First)
// ----------------------------------------------------------------------
@JsonSerializable(explicitToJson: true)
class CompanyCreateLocal {
  final String? localId;
  final String name;
  final String slug;

  CompanyCreateLocal({String? localId, required this.name, required this.slug})
    : localId = localId ?? const Uuid().v4();

  // 💡 Usado para la solicitud al API (solo datos)
  Map<String, dynamic> toApiJson() {
    return {'name': name, 'slug': slug};
  }

  // 💡 Usado para guardar en SyncQueueItem.payload (datos completos)
  Map<String, dynamic> toJson() => _$CompanyCreateLocalToJson(this);

  factory CompanyCreateLocal.fromJson(Map<String, dynamic> json) =>
      _$CompanyCreateLocalFromJson(json);
}

// ----------------------------------------------------------------------
// 3. MODELO DE ACTUALIZACIÓN (Offline-First) - CORREGIDO
// ----------------------------------------------------------------------
@JsonSerializable(
  includeIfNull: false,
  explicitToJson: true,
  createFactory: false,
)
class CompanyUpdateLocal {
  @JsonKey(ignore: true)
  final String id; // Backend ID

  final String? name;
  final String? slug;

  CompanyUpdateLocal({required this.id, this.name, this.slug});

  // 💡 ESTE ES EL MÉTODO QUE DEBEMOS LLAMAR AHORA
  Map<String, dynamic> toApiJson() => _$CompanyUpdateLocalToJson(this);
}

// lib/models/role.dart

import 'package:isar/isar.dart';

// Importante: Debes ejecutar 'dart run build_runner build' después de este cambio
part 'role.g.dart';

@Collection()
class Role {
  Id isarId = Isar.autoIncrement; // ID para Isar

  @Index(unique: true)
  final String id; // ID real del backend (para unicidad)
  final String name;

  Role({required this.id, required this.name});

  factory Role.fromJson(Map<String, dynamic> json) {
    return Role(id: json['id'] as String, name: json['name'] as String);
  }
}

// lib/models/sync_queue_item.dart

import 'package:isar/isar.dart';
import 'package:json_annotation/json_annotation.dart';

part 'sync_queue_item.g.dart';

@JsonEnum(fieldRename: FieldRename.screamingSnake)
enum SyncOperation {
  // Operaciones de Usuario
  CREATE_USER,
  UPDATE_USER,
  DELETE_USER,

  // Operaciones de Compañía
  CREATE_COMPANY,
  UPDATE_COMPANY,
  DELETE_COMPANY,

  // Operaciones de Sucursal
  CREATE_BRANCH,
  UPDATE_BRANCH,
  DELETE_BRANCH,
}

@JsonSerializable()
@Collection()
class SyncQueueItem {
  Id id = Isar.autoIncrement;

  @Enumerated(EnumType.name)
  final SyncOperation operation;

  /// El endpoint REST al que se debe enviar el payload (ej: /api/v1/users/)
  final String endpoint;

  /// El payload (cuerpo) de la solicitud API, guardado como JSON string.
  final String payload;

  /// UUID local generado si es un CREATE, usado para identificar el item local temporalmente.
  final String? localId;

  /// Fecha de creación del ítem en la cola. Se usa para procesar los ítems en orden (FIFO).
  final DateTime createdAt;

  // Constructor principal simple (usado por Isar y json_serializable/manual)
  SyncQueueItem({
    required this.operation,
    required this.endpoint,
    required this.payload,
    this.localId,
    required this.createdAt,
  });

  /// Fábrica auxiliar para crear el ítem con la hora actual (`DateTime.now()`) automáticamente.
  factory SyncQueueItem.create({
    required SyncOperation operation,
    required String endpoint,
    required String payload,
    String? localId,
  }) {
    return SyncQueueItem(
      operation: operation,
      endpoint: endpoint,
      payload: payload,
      localId: localId,
      createdAt: DateTime.now(),
    );
  }

  factory SyncQueueItem.fromJson(Map<String, dynamic> json) =>
      _$SyncQueueItemFromJson(json);

  Map<String, dynamic> toJson() => _$SyncQueueItemToJson(this);
}

// lib/models/token.dart (Modificado)

import 'package:json_annotation/json_annotation.dart';

part 'token.g.dart';

@JsonSerializable()
class Token {
  @JsonKey(name: 'access_token')
  final String accessToken;

  @JsonKey(name: 'token_type')
  final String tokenType;

  // ⚠️ Nuevo campo Refresh Token
  @JsonKey(name: 'refresh_token')
  final String? refreshToken;

  final String? role;

  Token({
    required this.accessToken,
    this.tokenType = 'bearer',
    this.refreshToken, // Añadir al constructor
    required this.role,
  });

  factory Token.fromJson(Map<String, dynamic> json) => _$TokenFromJson(json);
  Map<String, dynamic> toJson() => _$TokenToJson(this);
}

// lib/models/user.dart

import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:isar/isar.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';

part 'user.g.dart';

// Función hash simple para Isar (debe ser la misma en todos los archivos .dart)
int fastHash(String string) {
  var hash = 2166136261;
  for (var i = 0; i < string.length; i++) {
    hash ^= string.codeUnitAt(i);
    hash *= 16777619;
  }
  return hash;
}

// ----------------------------------------------------------------------
// 📝 MODELO DE BASE DE DATOS Y API
// ----------------------------------------------------------------------

@JsonSerializable()
@CopyWith()
@Collection()
class User {
  Id get isarId =>
      fastHash(id); // Generar IsarId a partir del UUID del servidor

  @JsonKey(required: true)
  @Index(unique: true)
  final String id; // UUID del servidor

  @JsonKey(required: true)
  @Index(unique: true)
  final String username;

  @JsonKey(name: 'role_id', required: true)
  @Index()
  final String roleId;

  @JsonKey(name: 'role_name', required: true)
  final String roleName;

  final bool isActive;

  // 💡 Campo para Borrado Lógico (para Offline-First)
  final bool isDeleted;

  // Campos relacionados con la jerarquía (pueden ser nulos)
  @JsonKey(name: 'company_id')
  final String? companyId;

  @JsonKey(name: 'branch_id')
  final String? branchId;

  // Tokens (NO VIENEN EN /auth/me, pero se guardan para persistencia)
  final String? accessToken;
  final String? refreshToken;

  // Metadatos
  @JsonKey(name: 'created_at')
  final String createdAt;

  User({
    required this.id,
    required this.username,
    required this.roleId,
    required this.roleName,
    required this.createdAt,
    this.isActive = true,
    this.isDeleted = false, // Valor por defecto añadido
    this.companyId,
    this.branchId,
    this.accessToken,
    this.refreshToken,
  });

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);
}

// ----------------------------------------------------------------------
// 🚨 MODELO PARA LA COLA DE SINCRONIZACIÓN (OFFLINE FIRST)
// ----------------------------------------------------------------------

// Este es el modelo que el Admin crea en la app.
@JsonSerializable()
class UserCreateLocal {
  @JsonKey(required: true)
  final String username;

  @JsonKey(required: true)
  final String password;

  @JsonKey(name: 'role_id', required: true)
  final String roleId;

  @JsonKey(name: 'role_name', required: true)
  final String roleName;

  final bool isActive;

  final String? companyId;
  final String? branchId;

  // 💡 CAMBIO CRÍTICO 1: Hacer 'localId' nullable.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final String? localId;

  UserCreateLocal({
    required this.username,
    required this.password,
    required this.roleId,
    required this.roleName,
    this.isActive = true,
    this.companyId,
    this.branchId,
    // 💡 CAMBIO CRÍTICO 2: Quitar 'required' del constructor.
    this.localId,
  });

  factory UserCreateLocal.fromJson(Map<String, dynamic> json) =>
      _$UserCreateLocalFromJson(json);
  Map<String, dynamic> toJson() => _$UserCreateLocalToJson(this);
}

// 🚨 MODELO PARA LA ACTUALIZACIÓN (Necesitas esto para la edición)
@JsonSerializable(includeIfNull: false) // No incluye campos nulos en el JSON
class UserUpdateLocal {
  // ✅ CORREGIDO: Usamos 'id' para ser consistentes.
  final String id;

  // ✅ CORREGIDO: Añadido roleId que es esencial para la edición.
  @JsonKey(name: 'role_id')
  final String? roleId;

  final String? username;
  final String? password;

  //CLAVE: Añadido 'roleName'.
  // 'includeToJson: false' evita que se serialice al enviarlo a la API,
  // pero permite acceder a él en el Notifier para la lógica.
  @JsonKey(includeToJson: false)
  final String? roleName;

  final bool? isActive;
  final String? companyId;
  final String? branchId;

  UserUpdateLocal({
    required this.id, // ID del servidor
    this.username,
    this.password,
    this.roleName,
    this.roleId,
    this.isActive,
    this.companyId,
    this.branchId,
  });

  factory UserUpdateLocal.fromJson(Map<String, dynamic> json) =>
      _$UserUpdateLocalFromJson(json);

  Map<String, dynamic> toJson() => _$UserUpdateLocalToJson(this);
}

// lib/providers/auth_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/token.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/isar_service.dart';
import '../services/sync_service.dart'; // 💡 Importar el servicio de sincronización

// Proveedor de la base de datos Isar
// final isarServiceProvider = Provider((ref) => IsarService());

// Proveedor del ApiService
// NOTA: Asumimos que apiServiceProvider ya está definido en otro lugar (ej. api_service.dart)
// final apiServiceProvider = Provider((ref) => ApiService(ref));

// Proveedor del SyncService (Necesario para la sincronización post-login)
final syncServiceProvider = Provider(
  (ref) => SyncService(ref),
); // 💡 Definir el proveedor del SyncService

// Estado de Autenticación (StateNotifier para manejar estados de carga/error)
class AuthNotifier extends StateNotifier<AsyncValue<User?>> {
  final Ref _ref;
  Token? _token; // Almacena el token JWT de forma privada

  // Getter para el Refresh Token (para el Interceptor)
  String? get refreshToken => _token?.refreshToken;

  AuthNotifier(this._ref) : super(const AsyncValue.loading()) {
    _initialize();
  }

  // Getter para el token (usado por el Interceptor de Dio en api_service.dart)
  String? get accessToken => _token?.accessToken;

  // --- Inicialización (Chequeo Offline) ---

  Future<void> _initialize() async {
    state = const AsyncValue.loading();
    try {
      final user = await _ref.read(isarServiceProvider).getActiveUser();

      // CLAVE: Chequeamos que exista el usuario Y que tenga un token de sesión
      if (user != null && user.accessToken != null) {
        // Asignar el token de Isar a la variable de clase (para el Interceptor)
        _token = Token(
          accessToken: user.accessToken!,
          refreshToken: user.refreshToken,
          role: user.roleName,
        );
        print('DEBUG INIT: refreshToken desde Isar = ${user.refreshToken}');

        state = AsyncValue.data(user);
        print(
          'DEBUG INIT: Usuario ${user.username} cargado desde Isar (Offline). Redirigiendo a HomeScreen.',
        );

        // 🚀 Nota: Aquí no llamamos a startSync, ya que _initialize puede correr
        // con la app en segundo plano y sin conexión estable.
        // La sincronización debe ser manejada por un listener de conectividad.
      } else {
        state = const AsyncValue.data(null);
        print(
          'DEBUG INIT: No se encontró sesión o usuario en Isar. Mostrando LoginScreen.',
        );
      }
    } catch (e, st) {
      // Si la DB Isar falla
      state = AsyncValue.error(
        'Error al inicializar la base de datos local: $e',
        st,
      );
    }
  }

  // --- Lógica de Login ---

  Future<void> login(String username, String password) async {
    state = const AsyncValue.loading();
    // Asumiendo que apiServiceProvider está definido y es accesible
    final _apiService = _ref.read(apiServiceProvider);
    final _isarService = _ref.read(isarServiceProvider);
    final _syncService = _ref.read(
      syncServiceProvider,
    ); // 💡 Obtener el SyncService

    try {
      // 1. Llama a la API (Login)
      final tokenResult = await _apiService.login(username, password);

      // CLAVE 1: ALMACENAR EL OBJETO TOKEN INMEDIATAMENTE
      _token = tokenResult;

      // 2. Llama a la API para obtener el usuario
      final userResponse = await _apiService.fetchMe();

      // CLAVE 2: Guardar el token junto con el usuario en Isar para persistencia
      final userToSave = userResponse.copyWith(
        accessToken: tokenResult.accessToken,
        refreshToken: tokenResult.refreshToken,
      );
      print('DEBUG LOGIN: accessToken=${tokenResult.accessToken}');
      print('DEBUG LOGIN: refreshToken=${tokenResult.refreshToken}');
      await _isarService.saveUser(userToSave);

      // 3. Éxito ONLINE
      state = AsyncValue.data(userToSave);

      // 🚀 INICIAR SINCRONIZACIÓN DESPUÉS DEL LOGIN EXITOSO
      // Ahora que estamos online y autenticados, vaciamos la cola.
      _syncService.startSync();

      print(
        'DEBUG AUTH: Estado final actualizado a DATA. User: ${userToSave.username}',
      );
    } catch (e, st) {
      print('DEBUG AUTH: Fallo catastrófico en Login: $e');

      // 🚨 MANEJO DE OFFLINE LOGIN: Solo si el fallo es de CONEXIÓN
      if (e.toString().contains('DioException') ||
          e.toString().contains('SocketException')) {
        final isarUser = await _isarService.getActiveUser();

        // CLAVE: Revisa si el usuario ingresado (username) coincide con el usuario guardado
        if (isarUser != null && isarUser.username == username) {
          print(
            'DEBUG AUTH: Fallo de red detectado. Autenticación exitosa en modo OFFLINE con Isar.',
          );

          state = AsyncValue.data(isarUser);
          return; // Salir de la función con éxito (offline)
        }
      }

      // ... (Si no hay usuario guardado o las credenciales no coinciden/error no es de red)
      state = AsyncValue.error(e, st);
    }
  }

  // ⚠️ Este método es llamado por el Interceptor cuando el token expira
  void updateToken(Token newToken) async {
    final _isarService = _ref.read(isarServiceProvider);
    final _syncService = _ref.read(
      syncServiceProvider,
    ); // 💡 Obtener el SyncService

    // 1. Actualizar el token de la clase (usado por el Interceptor)
    _token = newToken;

    // 2. Obtener el usuario actual para actualizar el registro en Isar
    final currentUser = state.value;

    if (currentUser != null) {
      // 3. Crear una copia del usuario con el NUEVO Access y Refresh Token
      final userWithNewToken = currentUser.copyWith(
        accessToken: newToken.accessToken,
        refreshToken: newToken.refreshToken,
      );

      // 4. Guardar en Isar (sobrescribir el registro existente)
      await _isarService.saveUser(userWithNewToken);
    }

    // 🚀 INICIAR SINCRONIZACIÓN DESPUÉS DE RENOVAR EL TOKEN CON ÉXITO
    // Esto asegura que, si el token expiró y se renovó, la conexión está OK para sincronizar.
    _syncService.startSync();

    // 5. Verificación por Log
    print('✅ DEBUG REFRESH: Token actualizado con éxito.');
    print(
      ' -> Nuevo Access Token (Inicio): ${newToken.accessToken.substring(0, 8)}...',
    );
    print(
      ' -> Nuevo Refresh Token (Inicio): ${newToken.refreshToken?.substring(0, 8)}...',
    );
  }

  // --- Lógica de Logout ---

  Future<void> logout() async {
    state = const AsyncValue.loading();
    final _isarService = _ref.read(isarServiceProvider);

    _token = null;

    // COMPROMISO: Borrar la DB para que el Hot Restart NO te loguee.
    await _isarService.cleanDB();
    print('DEBUG LOGOUT: Usuario y sesión eliminados de Isar (Hard Logout).');

    state = const AsyncValue.data(null);
  }
}

// Proveedor global que se utiliza para leer el estado de autenticación
final authProvider = StateNotifierProvider<AuthNotifier, AsyncValue<User?>>(
  (ref) => AuthNotifier(ref),
);

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
          case SyncOperation.CREATE_COMPANY: // 💡 NUEVO
            final newCompany = await _apiService.createCompany(data);
            if (item.localId != null) {
              await _isarService.updateLocalCompanyWithRealId(
                item.localId!,
                newCompany,
              );
            }
            break;

          case SyncOperation.UPDATE_COMPANY: // 💡 NUEVO
            await _apiService.updateCompany(targetId, data);
            break;

          case SyncOperation.DELETE_COMPANY: // 💡 NUEVO
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
      operation: SyncOperation.CREATE_COMPANY, // 💡 NUEVO
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
          await _handleOfflineUpdate(
            data,
            companyToSave,
          ); // Se pasa como argumento
        }
      } else {
        // OFFLINE DIRECTO
        await _handleOfflineUpdate(
          data,
          companyToSave,
        ); // Se pasa como argumento
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
    Company companyToSave, // 💡 DEFINICIÓN COMO PARÁMETRO
  ) async {
    final syncItem = SyncQueueItem.create(
      operation: SyncOperation.UPDATE_COMPANY,
      endpoint: '/api/v1/platform/companies/${data.id}',
      payload: jsonEncode(
        data.toApiJson(),
      ), // toApiJson() es el que tiene los datos cambiados
      localId: data.id,
    );
    await _isarService.enqueueSyncItem(syncItem);
    await _isarService.saveCompanies([
      companyToSave,
    ]); // Usamos companyToSave aquí
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
      operation: SyncOperation.DELETE_COMPANY, // 💡 NUEVO
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

// lib/providers/roles_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/role.dart'; // 💡 IMPORTACIÓN AÑADIDA
import '../services/api_service.dart';
import '../services/isar_service.dart';

// Asumimos que isarServiceProvider y apiServiceProvider están definidos en sus respectivos archivos.

class RolesNotifier extends AsyncNotifier<List<Role>> {
  late final ApiService _apiService;
  late final IsarService _isarService;

  @override
  Future<List<Role>> build() async {
    _apiService = ref.watch(apiServiceProvider);
    _isarService = ref.watch(isarServiceProvider);

    // 1. Cargar roles localmente (Offline-First)
    final localRoles = await _isarService.getAllRoles();

    if (localRoles.isNotEmpty) {
      state = AsyncValue.data(localRoles);
    }

    // 2. Cargar datos del servidor
    try {
      final onlineRoles = await _apiService.fetchAllRoles();

      // 3. Guardar los roles online en Isar para la caché
      await _isarService.saveRoles(onlineRoles);

      return onlineRoles;
    } catch (e) {
      if (localRoles.isNotEmpty) return localRoles;
      throw Exception('Fallo al cargar roles: $e');
    }
  }

  // Permite refrescar la lista de roles explícitamente desde el servidor
  Future<void> fetchOnlineRoles() async {
    state = await AsyncValue.guard(() async {
      final onlineRoles = await _apiService.fetchAllRoles();
      await _isarService.saveRoles(onlineRoles);
      return onlineRoles;
    });
  }
}

final rolesProvider = AsyncNotifierProvider<RolesNotifier, List<Role>>(() {
  return RolesNotifier();
});

// --- PROVEEDOR DERIVADO: Mapa de Roles por Nombre ---

final rolesMapProvider = Provider<Map<String, Role>>((ref) {
  final rolesState = ref.watch(rolesProvider);

  return rolesState.maybeWhen(
    data: (roles) => {for (var role in roles) role.name: role},
    // Si hay error o está cargando, devuelve un mapa vacío.
    orElse: () => {},
  );
});

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
  // Getters para servicios
  ApiService get _apiService => ref.read(apiServiceProvider);
  IsarService get _isarService => ref.read(isarServiceProvider);
  ConnectivityService get _connectivityService =>
      ref.read(connectivityServiceProvider);

  // 💡 FUNCIÓN CLAVE: Procesa la cola de sincronización
  Future<void> _processSyncQueue() async {
    final isConnected = await _connectivityService.checkConnection();
    if (!isConnected) return; // Salir si no hay conexión

    SyncQueueItem? item;
    // Procesar la cola hasta que esté vacía o falle una operación
    while ((item = await _isarService.getNextSyncItem()) != null) {
      try {
        // Para UPDATE y DELETE, extraemos el ID del endpoint (ej: /users/ID)
        final targetId = item!.endpoint.split('/').last;

        switch (item.operation) {
          case SyncOperation.CREATE_USER:
            final data = jsonDecode(item.payload);
            final newUser = await _apiService.createUser(data);
            // 🚨 Paso crucial para manejar IDs temporales
            if (item.localId != null) {
              // REQUIERE IsarService.updateLocalUserWithRealId
              await _isarService.updateLocalUserWithRealId(
                item.localId!,
                newUser,
              );
            }
            break;

          case SyncOperation.UPDATE_USER:
            final data = jsonDecode(item.payload);
            // Usamos el targetId extraído del endpoint
            await _apiService.updateUser(targetId, data);
            // La siguiente _syncLocalDatabase confirmará el cambio del API.
            break;

          case SyncOperation.DELETE_USER:
            // Usamos el targetId extraído del endpoint
            await _apiService.deleteUser(targetId);
            // La siguiente _syncLocalDatabase eliminará el dato obsoleto de Isar.
            break;
          default:
            print('DEBUG SYNC: Operación desconocida: ${item.operation.name}');
            break;
        }

        // En éxito, eliminar el item de la cola
        await _isarService.dequeueSyncItem(item.id);
        print(
          'DEBUG SYNC: Operación ${item.operation.name} sincronizada exitosamente.',
        );
      } catch (e) {
        // Si alguna operación falla (ej. servidor rechaza la data),
        // detenemos la cola para no perder la orden de dependencia.
        print(
          'ERROR SYNC: Fallo la sincronización de ${item!.operation.name}: $e',
        );
        break;
      }
    }
  }

  // Lógica de limpieza y sincronización (sin cambios)
  Future<void> _syncLocalDatabase(List<User> onlineUsers) async {
    final localUsers = await _isarService.getAllUsers();
    final Set<String> onlineUserIds = onlineUsers.map((u) => u.id).toSet();
    final List<String> staleUserIds = localUsers
        .where((localUser) => !onlineUserIds.contains(localUser.id))
        .map((localUser) => localUser.id)
        .toList();
    for (final userId in staleUserIds) {
      await _isarService.deleteUser(userId);
    }
    await _isarService.saveUsers(onlineUsers);
  }

  @override
  Future<List<User>> build() async {
    final localUsers = await _isarService.getAllUsers();
    final activeLocalUsers = localUsers
        .where((u) => u.isDeleted == false)
        .toList();

    if (activeLocalUsers.isNotEmpty) {
      state = AsyncValue.data(activeLocalUsers);
    }

    try {
      // 🛑 PRIMERO PROCESAMOS LA COLA al inicio
      await _processSyncQueue();

      final onlineUsers = await _apiService.fetchAllUsers();
      await _syncLocalDatabase(onlineUsers);
      return onlineUsers;
    } catch (e) {
      if (activeLocalUsers.isNotEmpty) return activeLocalUsers;
      throw Exception(
        'Fallo al cargar usuarios online y no hay datos offline: $e',
      );
    }
  }

  // -------------------------------------------------------------------
  // 💡 MÉTODOS PRIVADOS OFFLINE (Sin cambios, ya manejan el encolamiento)
  // -------------------------------------------------------------------
  Future<void> _handleOfflineCreate(
    UserCreateLocal data,
    List<User> previousList,
  ) async {
    // ⚠️ Validación crucial para el modo offline
    if (data.localId == null) {
      throw Exception(
        'Error interno: localId no fue generado para operación offline.',
      );
    }

    // 1. Encolar la operación
    final syncItem = SyncQueueItem.create(
      operation: SyncOperation.CREATE_USER,
      endpoint: '/api/v1/users/',
      payload: jsonEncode(data.toJson()),
      localId: data.localId!,
    );
    await _isarService.enqueueSyncItem(syncItem);

    // 2. Actualización optimista (creación del usuario temporal)
    final tempUser = User(
      id: data.localId!, // Usamos el ID temporal
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

    // 3. Actualizar el estado de Riverpod
    state = AsyncValue.data([...previousList, tempUser]);

    print('DEBUG OFFLINE: Fallback a modo offline (Creación encolada).');
  }

  Future<void> _handleOfflineUpdate(
    UserUpdateLocal data,
    List<User> userList,
  ) async {
    final userDataMap = data.toJson();

    // 1. Crear la lista actualizada y el usuario a guardar (Optimistic Update)
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

    // 2. Encolar la operación
    final syncItem = SyncQueueItem.create(
      operation: SyncOperation.UPDATE_USER,
      endpoint: '/api/v1/users/${data.id}',
      payload: jsonEncode(userDataMap),
    );
    await _isarService.enqueueSyncItem(syncItem);

    // 3. Guardar la actualización optimista en Isar
    await _isarService.saveUsers([userToSave]);

    // 4. Actualizar el estado de Riverpod
    state = AsyncValue.data(updatedList);

    print('DEBUG OFFLINE: Fallback a modo offline (Edición encolada).');
  }

  // --- MÉTODOS CRUD CORREGIDOS CON FALLBACK (Sin cambios en el cuerpo) ---

  Future<void> createUser(UserCreateLocal data) async {
    final previousState = state;
    if (!state.hasValue) return;

    try {
      // 1. RBAC: VALIDACIÓN DE CREACIÓN
      final currentUser = ref.read(authProvider).value;
      if (currentUser == null ||
          !_canCreateUserWithRole(currentUser.roleName, data.roleName)) {
        throw Exception(
          'Permiso denegado: No puede crear el usuario con el rol "${data.roleName}".',
        );
      }

      // 2. Intentar ONLINE
      final isConnected = await _connectivityService.checkConnection();

      if (!isConnected) {
        await _handleOfflineCreate(data, previousState.value!);
        return;
      }

      try {
        // ONLINE: LLAMAR DIRECTO AL API
        final newUser = await _apiService.createUser(data.toJson());
        await _isarService.saveUsers([newUser]);
        state = AsyncValue.data([...previousState.value!, newUser]);
      } catch (e) {
        // 🚨 FALLBACK: Si falla la llamada al API
        await _handleOfflineCreate(data, previousState.value!);
      }
    } catch (e, st) {
      throw Exception('Fallo al crear usuario: ${e.toString()}');
    }
  }

  Future<void> editUser(UserUpdateLocal data) async {
    final previousState = state;
    if (!state.hasValue || data.id == null) return;

    try {
      final userList = previousState.value!;
      final originalUser = userList.firstWhere((u) => u.id == data.id);
      final targetRole = data.roleName ?? originalUser.roleName;

      // 1. RBAC: VALIDACIÓN DE EDICIÓN
      final currentUser = ref.read(authProvider).value;
      if (currentUser == null ||
          !_canModifyTargetUserRole(currentUser.roleName, targetRole)) {
        throw Exception(
          'Permiso denegado: No puede modificar el usuario con rol "$targetRole".',
        );
      }

      // 2. Intentar ONLINE
      final isConnected = await _connectivityService.checkConnection();

      if (!isConnected) {
        // Si no hay conexión de red, vamos directo al offline
        await _handleOfflineUpdate(data, userList);
        return;
      }

      try {
        // ONLINE: LLAMAR DIRECTO AL API
        final userDataMap = data.toJson();
        final updatedUser = await _apiService.updateUser(data.id, userDataMap);
        await _isarService.saveUsers([updatedUser]);

        final finalUpdatedList = userList.map((user) {
          return user.id == data.id ? updatedUser : user;
        }).toList();
        state = AsyncValue.data(finalUpdatedList);
      } catch (e) {
        // 🚨 FALLBACK: Si falla la llamada al API
        await _handleOfflineUpdate(data, userList);
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
        try {
          await _apiService.deleteUser(userId);
          await _isarService.deleteUser(userId);
        } catch (e) {
          // 🚨 FALLBACK para DELETE: Marcar y encolar
          final userMarkedForDeletion = userToDelete.copyWith(isDeleted: true);
          await _isarService.saveUsers([userMarkedForDeletion]);

          final syncItem = SyncQueueItem.create(
            operation: SyncOperation.DELETE_USER,
            endpoint: '/api/v1/users/$userId',
            payload: '{}',
          );
          await _isarService.enqueueSyncItem(syncItem);
          print(
            'DEBUG OFFLINE: Fallback a modo offline (Eliminación encolada).',
          );
        }
      }
    } catch (e, st) {
      state = previousState;
      throw Exception('Fallo al eliminar usuario: ${e.toString()}');
    }
  }

  // Refresca la lista de usuarios desde el servidor
  Future<void> fetchOnlineUsers() async {
    state = await AsyncValue.guard(() async {
      // 🛑 PRIMERO PROCESAMOS LA COLA
      await _processSyncQueue();

      final onlineUsers = await _apiService.fetchAllUsers();
      await _syncLocalDatabase(onlineUsers);
      return onlineUsers;
    });
  }

  // --- LÓGICA DE AYUDA RBAC (Sin cambios) ---
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
}

final usersProvider = AsyncNotifierProvider<UsersNotifier, List<User>>(() {
  return UsersNotifier();
});

// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import 'users_screen.dart'; // 💡 IMPORTANTE: Importar la nueva pantalla de Usuarios

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  // Función para realizar la prueba del Refresh Token
  void _testRefreshToken(BuildContext context, WidgetRef ref) async {
    final apiService = ref.read(apiServiceProvider);

    // Usamos un ScaffoldMessenger para mostrar el estado.
    final messenger = ScaffoldMessenger.of(context);

    messenger.showSnackBar(
      const SnackBar(content: Text('⏳ Enviando solicitud de prueba...')),
    );

    try {
      final fetchedUser = await apiService.fetchMe();

      // Si llegamos aquí, la llamada fue exitosa (con o sin refresh)
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '✅ ÉXITO: Datos obtenidos para ${fetchedUser.username}!',
          ),
          backgroundColor: Colors.green,
        ),
      );

      // Imprimir en la consola para la verificación del log:
      print(
        'DEBUG TEST: Llamada a fetchMe() exitosa. Busque "DEBUG REFRESH" en el log.',
      );
    } catch (e) {
      // Si llega aquí, significa que el Refresh Token también falló.
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '❌ FALLO: El Refresh Token no funcionó o expiró. ${e.toString()}',
          ),
          backgroundColor: Colors.red,
        ),
      );
      print('DEBUG TEST: FALLO en fetchMe() o Refresh Token. Error: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('DCPOS - Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              // Llamada al método logout del Notifier
              ref.read(authProvider.notifier).logout();
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Bienvenido!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Usuario: ${user?.username ?? 'N/A'}'),
            Text('Rol: ${user?.roleName ?? 'N/A'}'),
            const SizedBox(height: 30),

            // 1. BOTÓN DE PRUEBA DE REFRESH TOKEN
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('PROBAR ACTUALIZACIÓN DE TOKEN (fetchMe)'),
              onPressed: () => _testRefreshToken(context, ref),
            ),
            const SizedBox(height: 20),

            // 2. BOTÓN PARA NAVEGAR A GESTIÓN DE USUARIOS
            ElevatedButton.icon(
              icon: const Icon(Icons.group),
              label: const Text('GESTIÓN DE USUARIOS'),
              onPressed: () {
                // 💡 NAVEGACIÓN A LA NUEVA PANTALLA
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const UsersScreen()),
                );
              },
            ),

            const SizedBox(height: 30),
            const Text(
              '¡Modo Offline-First Activado!',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}

// lib/screens/login_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();

    final authState = ref.watch(authProvider);

    void _submitLogin() {
      if (usernameController.text.isEmpty || passwordController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Por favor, ingresa usuario y contraseña.'),
          ),
        );
        return;
      }
      ref
          .read(authProvider.notifier)
          .login(usernameController.text, passwordController.text);
    }

    // Escucha los cambios de estado para mostrar errores
    ref.listen<AsyncValue>(authProvider, (_, next) {
      if (next.hasError && !next.isLoading) {
        final error = next.error;
        String displayMessage = 'Error inesperado.';

        // Lógica de visualización del mensaje
        if (error is Exception) {
          // Captura los mensajes limpios lanzados por ApiService (e.g., 'Credenciales inválidas.')
          displayMessage = error.toString().replaceFirst('Exception: ', '');
        } else if (error.toString().contains('DioException') ||
            error.toString().contains('SocketException')) {
          // Error de conexión/servidor
          displayMessage =
              'Error de conexión: Verifica que el backend esté activo.';
        }
        // 🚨 MEJORA CLAVE: Capturar y traducir los errores de tipo 'Null'
        else if (error.toString().contains(
          "type 'Null' is not a subtype of type",
        )) {
          displayMessage =
              'Fallo de datos de la API. Contacte al soporte. (El servidor envió datos incompletos).';
        } else {
          // Otros errores (Isar, JSON genérico, etc.)
          displayMessage =
              'Fallo de servicio: ${error.toString().split(':').last.trim()}';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(displayMessage), backgroundColor: Colors.red),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('DCPOS - Login')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Sistema POS Offline-First',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(
                  labelText: 'Usuario',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                keyboardType: TextInputType.text,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
                onSubmitted: (_) => _submitLogin(),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: authState.isLoading ? null : _submitLogin,
                  child: authState.isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Iniciar Sesión',
                          style: TextStyle(fontSize: 18),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// lib/screens/user_form_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user.dart';
import '../models/role.dart';
import '../providers/users_provider.dart';
import '../providers/roles_provider.dart'; // Importar el nuevo provider de roles
import 'package:uuid/uuid.dart'; // Necesario para generar localId en modo offline

// Proveedor para generar IDs (usamos Riverpod para consistency)
final uuidProvider = Provider((ref) => const Uuid());

// Definición del Widget
class UserFormScreen extends ConsumerStatefulWidget {
  final User? userToEdit;

  const UserFormScreen({super.key, this.userToEdit});

  @override
  ConsumerState<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends ConsumerState<UserFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  // 💡 ESTADOS CLAVE PARA EL MANEJO DEL ROL
  String? _selectedRoleId;
  String? _selectedRoleName;

  @override
  void initState() {
    super.initState();
    if (widget.userToEdit != null) {
      final user = widget.userToEdit!;
      _usernameController.text = user.username;

      // Si estamos editando, precargar los valores del rol existente
      _selectedRoleId = user.roleId;
      _selectedRoleName = user.roleName;

      // Nota: Nunca precargamos la contraseña por seguridad
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRoleId == null || _selectedRoleName == null) {
      // Validación extra si el dropdown no fue tocado
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecciona un rol.')),
      );
      return;
    }

    final usersNotifier = ref.read(usersProvider.notifier);

    try {
      // 💡 Lógica de Creación/Actualización envuelta en try-catch
      if (widget.userToEdit == null) {
        // --- CREACIÓN (Offline-First) ---
        final newUserId = ref.read(uuidProvider).v4(); // Generar un localId

        final newUser = UserCreateLocal(
          username: _usernameController.text,
          password: _passwordController.text,
          roleId: _selectedRoleId!,
          roleName: _selectedRoleName!, // Usamos el nombre REAL
          localId: newUserId,
          // Valores de empresa/sucursal deben venir de AuthProvider o un Provider de configuración
          companyId: "temp-company-uuid",
          branchId: "temp-branch-uuid",
          isActive: true,
        );

        await usersNotifier.createUser(newUser);
      } else {
        // --- EDICIÓN (Offline-First) ---
        final updatedUser = UserUpdateLocal(
          id: widget.userToEdit!.id,
          username: _usernameController.text,
          password: _passwordController.text.isNotEmpty
              ? _passwordController.text
              : null,
          roleId: _selectedRoleId,
          roleName: _selectedRoleName,
        );

        await usersNotifier.editUser(updatedUser);
      }

      // Si no hubo excepción, la operación fue exitosa
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // 🛑 CAPTURA DE ERROR: Muestra el SnackBar en rojo y NO cierra la pantalla
      if (mounted) {
        // Limpiamos el mensaje de la excepción de Dart si es necesario
        final errorMessage = e.toString().replaceAll('Exception: ', '');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error de Operación: $errorMessage',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 💡 Observar el proveedor de roles (clave para el Dropdown)
    final rolesAsyncValue = ref.watch(rolesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.userToEdit == null ? 'Crear Usuario' : 'Editar Usuario',
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre de Usuario',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Introduce un nombre de usuario';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Contraseña (mín 6 caracteres)',
                ),
                obscureText: true,
                validator: (value) {
                  if (widget.userToEdit == null &&
                      (value == null || value.isEmpty)) {
                    return 'Introduce una contraseña para el nuevo usuario';
                  }
                  if (value != null && value.isNotEmpty && value.length < 6) {
                    return 'La contraseña debe tener al menos 6 caracteres';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // ------------------------------------------
              // 💡 CAMPO DE SELECCIÓN DE ROL (Dropdown)
              // ------------------------------------------
              rolesAsyncValue.when(
                // Estado 1: Cargando (Muestra un indicador)
                loading: () => const Center(child: LinearProgressIndicator()),

                // Estado 2: Error (Muestra la causa del fallo)
                error: (err, stack) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '❌ Error al cargar roles:',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${err.toString().replaceAll('Exception: ', '')}',
                      style: const TextStyle(color: Colors.red),
                    ),
                    const Text(
                      'Revisa la conexión y el ApiService.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),

                // Estado 3: Data (Maneja la lista de roles)
                data: (roles) {
                  // 💡 DIAGNÓSTICO CLAVE: ¿La lista está vacía?
                  if (roles.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          '⚠️ No se encontraron roles. La lista devuelta por el API está vacía.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.orange,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    );
                  }

                  // Asegurarse de que el rol actual exista en la lista si estamos editando
                  // y que _selectedRoleId se inicialice si el userToEdit no lo hizo correctamente.
                  if (widget.userToEdit != null && _selectedRoleId == null) {
                    final existingRole = roles.firstWhere(
                      (r) => r.id == widget.userToEdit!.roleId,
                      orElse: () => roles
                          .first, // Fallback si el rol no se encuentra (debe ser raro)
                    );
                    // Solamente hacemos setState si el rol no estaba inicializado correctamente
                    // para evitar un 'setState' innecesario después del 'initState'.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_selectedRoleId == null) {
                        setState(() {
                          _selectedRoleId = existingRole.id;
                          _selectedRoleName = existingRole.name;
                        });
                      }
                    });
                  }

                  return DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Rol',
                      border: OutlineInputBorder(),
                    ),
                    value: _selectedRoleId, // Usamos el ID como valor
                    hint: const Text('Selecciona un Rol'),
                    items: roles.map((Role role) {
                      return DropdownMenuItem<String>(
                        value: role.id, // Valor real: el UUID del rol
                        child: Text(role.name), // Display: el nombre del rol
                      );
                    }).toList(),
                    onChanged: (String? newRoleId) {
                      if (newRoleId != null) {
                        final selectedRole = roles.firstWhere(
                          (r) => r.id == newRoleId,
                        );
                        setState(() {
                          // 💡 CLAVE: Guardamos tanto el ID como el Nombre REAL
                          _selectedRoleId = newRoleId;
                          _selectedRoleName = selectedRole.name;
                        });
                      }
                    },
                    validator: (value) {
                      if (value == null) {
                        return 'Debes seleccionar el rol del usuario.';
                      }
                      return null;
                    },
                  );
                },
              ),

              // ------------------------------------------
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _submitForm,
                child: Text(
                  widget.userToEdit == null
                      ? 'Crear Usuario'
                      : 'Guardar Cambios',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// lib/screens/users_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';
import '../providers/users_provider.dart';
import 'user_form_screen.dart';

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 💡 Observamos el estado del UsersProvider
    final usersAsyncValue = ref.watch(usersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Usuarios'),
        actions: [
          // Botón para recargar (fuerza la sincronización con la API)
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(usersProvider);
            },
          ),
        ],
      ),
      body: usersAsyncValue.when(
        // 1. ESTADO DE CARGA
        loading: () => const Center(child: CircularProgressIndicator()),

        // 2. ESTADO DE ERROR (Muestra el error, pero aún así puede mostrar datos si hay caché local)
        error: (e, st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              // Si el error es solo de conexión, el AsyncNotifier intenta usar datos locales.
              'Error al cargar usuarios: ${e.toString()}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),

        // 3. ESTADO DE DATOS
        data: (users) {
          if (users.isEmpty) {
            return const Center(child: Text('No hay usuarios registrados.'));
          }
          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              return UserListTile(user: user);
            },
          );
        },
      ),
      // Botón flotante para la creación
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const UserFormScreen(userToEdit: null),
          ),
        ),
        child: const Icon(Icons.person_add),
      ),
    );
  }
}

// Widget simple para mostrar la información de un usuario
class UserListTile extends ConsumerWidget {
  final User user;

  const UserListTile({required this.user, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(user.username),
      subtitle: Text(
        // Usamos roleName y roleId para mostrar la información relevante
        'Rol: ${user.roleName} | ID: ${user.id.substring(0, 8)}...',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Botón para Editar
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.blue),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  // Pasamos el usuario para editar
                  builder: (context) => UserFormScreen(userToEdit: user),
                ),
              );
            },
          ),
          // Botón para Eliminar
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => _confirmDelete(context, ref, user),
          ),
        ],
      ),
    );
  }

  // Diálogo de confirmación para eliminar
  void _confirmDelete(BuildContext context, WidgetRef ref, User user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Text(
          '¿Estás seguro de que quieres eliminar al usuario ${user.username}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              // Llama al método deleteUser del Notifier (usa el ID del servidor)
              ref.read(usersProvider.notifier).deleteUser(user.id);
              Navigator.of(ctx).pop();
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// lib/services/api_service.dart

import 'package:dcpos/models/role.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/token.dart';
import '../models/user.dart';
import '../models/company.dart'; // 💡 NUEVO
import '../models/branch.dart'; // 💡 NUEVO
import '../providers/auth_provider.dart';

// Proveedor de solo lectura para la URL base
final apiUrlProvider = Provider<String>(
  (ref) => 'http://127.0.0.1:8000/api/v1',
);

// Usamos un Provider separado para Dio para evitar bucles de dependencia
final dioInstanceProvider = Provider((ref) {
  // 1. Crear la instancia de Dio
  final dio = Dio(
    BaseOptions(
      baseUrl: ref.watch(apiUrlProvider),
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      contentType: 'application/json',
    ),
  );

  // LogInterceptor correctamente agregado
  dio.interceptors.add(
    LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (o) => print('DIO LOG: $o'),
    ),
  );

  // 2. Retornar la instancia configurada
  return dio;
});

// ---------------------------------------------
// CLASE INTERCEPTOR PARA EL MANEJO DE TOKEN
// ---------------------------------------------

class AuthInterceptor extends QueuedInterceptor {
  final Ref ref;
  final ApiService apiService;
  bool isRefreshing = false;

  AuthInterceptor(this.ref, this.apiService);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final authNotifier = ref.read(authProvider.notifier);
    final token = authNotifier.accessToken;

    if (token != null &&
        !options.path.contains('/auth/login') &&
        !options.path.contains('/auth/refresh')) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    return handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final authNotifier = ref.read(authProvider.notifier);
    final String? refresh = authNotifier.refreshToken;

    print('🧩 DEBUG onError PATH: ${err.requestOptions.path}');
    print('🧩 DEBUG onError STATUS: ${err.response?.statusCode}');

    // 🚨 MANEJO DE REDIRECCIÓN 307:
    // Si el error es una redirección 307, es probable que la próxima ruta (con slash)
    // funcione automáticamente con Dio. Si el error persiste, simplemente devolvemos
    // la excepción para que el DioException se resuelva en el .fetch del interceptor
    // o en el manejo del Notifier.
    if (err.response?.statusCode == 307) {
      print(
        'DEBUG INTERCEPTOR: Se detectó 307 Redirection. Dejando que Dio lo maneje.',
      );
      return handler.next(err);
    }

    if (err.response?.statusCode == 401 &&
        !err.requestOptions.path.contains('/auth/refresh') &&
        refresh != null) {
      print('🧩 DEBUG onError -> ENTRANDO A BLOQUE DE REFRESH');
      if (!isRefreshing) {
        isRefreshing = true;
        try {
          final newToken = await apiService.refreshToken(refresh);
          authNotifier.updateToken(newToken);
        } catch (e) {
          print('DEBUG INTERCEPTOR: FALLO al refrescar token. Error: $e');
          await authNotifier.logout();
          return handler.reject(err);
        } finally {
          isRefreshing = false;
        }
      }

      // Reintentar la solicitud original con el nuevo token
      final options = err.requestOptions;
      options.headers['Authorization'] = 'Bearer ${authNotifier.accessToken}';
      // Utilizamos .fetch para reintentar la llamada.
      final response = await apiService.dio.fetch(options);
      return handler.resolve(response);
    }

    return handler.next(err);
  }
}

// ---------------------------------------------
// CLASE API SERVICE
// ---------------------------------------------

class ApiService {
  final Dio dio;
  final Ref _ref;

  ApiService(this.dio, this._ref);

  // --- Auth Endpoints ---

  Future<Token> login(String username, String password) async {
    try {
      final response = await dio.post(
        '/auth/login',
        data: {'username': username, 'password': password},
      );
      if (response.statusCode == 200) {
        return Token.fromJson(response.data);
      }
      throw Exception('Login fallido con código: ${response.statusCode}');
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        final errorMessage =
            e.response?.data?['detail'] ?? 'Credenciales inválidas.';
        throw Exception(errorMessage);
      }
      rethrow;
    }
  }

  Future<User> fetchMe() async {
    try {
      final response = await dio.get('/auth/me');

      if (response.statusCode == 200) {
        return User.fromJson(response.data);
      }
      throw Exception(
        'Error al obtener datos del usuario: ${response.statusCode}',
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<Token> refreshToken(String refreshToken) async {
    final dioRefresh = Dio(dio.options);

    final response = await dioRefresh.post(
      '/auth/refresh',
      options: Options(headers: {'Authorization': 'Bearer $refreshToken'}),
    );
    return Token.fromJson(response.data);
  }

  // --- Endpoints de Roles ---
  Future<List<Role>> fetchAllRoles() async {
    final response = await dio.get('/roles');

    // 1. Aseguramos que la respuesta es un Map (el objeto JSON externo)
    final data = response.data as Map<String, dynamic>;

    // 2. Extraemos la lista del campo "roles"
    final rolesJsonList = data['roles'] as List;

    // 3. Mapeamos la lista extraída al modelo Role
    return rolesJsonList
        .map((json) => Role.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  // --- Endpoints de Usuarios (CRUD) ---
  Future<List<User>> fetchAllUsers() async {
    try {
      // 🚨 CORRECCIÓN: Añadir la barra final para evitar el 307 Redirect.
      final response = await dio.get('/users/');
      final List<dynamic> userList = response.data;
      return userList.map((json) => User.fromJson(json)).toList();
    } on DioException catch (e) {
      throw Exception('Error al obtener usuarios: ${e.message}');
    }
  }

  Future<User> createUser(Map<String, dynamic> userData) async {
    try {
      // 🚨 CORRECCIÓN: Añadir la barra final para evitar el 307 Redirect.
      final response = await dio.post('/users/', data: userData);
      return User.fromJson(response.data);
    } on DioException catch (e) {
      // Se mantiene el manejo de errores original.
      final errorMessage =
          e.response?.data?['detail'] ?? 'Error desconocido al crear usuario.';
      throw Exception(errorMessage);
    }
  }

  Future<User> updateUser(String userId, Map<String, dynamic> userData) async {
    try {
      // Se asume que el backend usa PATCH o PUT sin la barra al final
      final response = await dio.patch('/users/$userId', data: userData);
      return User.fromJson(response.data);
    } on DioException catch (e) {
      final errorMessage =
          e.response?.data?['detail'] ??
          'Error desconocido al actualizar usuario.';
      throw Exception(errorMessage);
    }
  }

  Future<void> deleteUser(String userId) async {
    try {
      // Se asume que el backend usa DELETE sin la barra al final
      await dio.delete('/users/$userId');
    } on DioException catch (e) {
      final errorMessage =
          e.response?.data?['detail'] ??
          'Error desconocido al eliminar usuario.';
      throw Exception(errorMessage);
    }
  }

  // ----------------------------------------------------------------------
  // 💡 NUEVOS MÉTODOS PARA COMPANY
  // ----------------------------------------------------------------------
  Future<List<Company>> fetchCompanies() async {
    final response = await dio.get('/platform/companies'); //
    final List<dynamic> jsonList = response.data;
    return jsonList.map((json) => Company.fromJson(json)).toList();
  }

  Future<Company> createCompany(Map<String, dynamic> data) async {
    final response = await dio.post(
      '/platform/companies', //
      data: data,
    );
    return Company.fromJson(response.data);
  }

  Future<Company> updateCompany(
    String companyId,
    Map<String, dynamic> data,
  ) async {
    final response = await dio.patch(
      '/platform/companies/$companyId', //
      data: data,
    );
    return Company.fromJson(response.data);
  }

  Future<void> deleteCompany(String companyId) async {
    await dio.delete('/platform/companies/$companyId'); //
  }

  // ----------------------------------------------------------------------
  // 💡 NUEVOS MÉTODOS PARA BRANCH
  // ----------------------------------------------------------------------

  // Nota: El API solo permite listar branches por company_id
  Future<List<Branch>> fetchBranches(String companyId) async {
    final response = await dio.get(
      '/platform/companies/$companyId/branches', //
    );
    final List<dynamic> jsonList = response.data;
    return jsonList.map((json) => Branch.fromJson(json)).toList();
  }

  Future<Branch> createBranch(
    String companyId,
    Map<String, dynamic> data,
  ) async {
    final response = await dio.post(
      '/platform/companies/$companyId/branches', //
      data: data,
    );
    return Branch.fromJson(response.data);
  }

  Future<Branch> updateBranch(
    String branchId,
    Map<String, dynamic> data,
  ) async {
    final response = await dio.patch(
      '/platform/branches/$branchId', //
      data: data,
    );
    return Branch.fromJson(response.data);
  }

  // Nota: El API requiere ambos IDs para eliminar
  Future<void> deleteBranch(String companyId, String branchId) async {
    await dio.delete(
      '/platform/companies/$companyId/branches/$branchId', //
    );
  }
}

// ---------------------------------------------
// PROVEEDOR DE API SERVICE (CORRECTO)
// ---------------------------------------------

final apiServiceProvider = Provider((ref) {
  final dio = ref.watch(dioInstanceProvider);
  final apiService = ApiService(dio, ref);

  // CLAVE: Agregamos el Interceptor solo una vez
  if (dio.interceptors.whereType<AuthInterceptor>().isEmpty) {
    dio.interceptors.add(AuthInterceptor(ref, apiService));
  }

  return apiService;
});

// lib/services/connectivity_service.dart (CORREGIDO)

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 1. 💡 CORRECCIÓN: El StreamProvider ahora recibe List<ConnectivityResult>
final connectivityStreamProvider = StreamProvider<List<ConnectivityResult>>((
  ref,
) {
  // El método onConnectivityChanged ahora devuelve un stream de List<ConnectivityResult>
  return Connectivity().onConnectivityChanged;
});

// 2. 💡 CORRECCIÓN: El StateProvider ahora debe verificar si alguna conexión es válida
final isConnectedProvider = StateProvider<bool>((ref) {
  // Observa el stream de la lista de resultados
  final connectivityResultList = ref.watch(connectivityStreamProvider);

  return connectivityResultList.when(
    // Cuando hay datos (una lista de resultados)
    data: (results) {
      // Retorna true si CUALQUIERA de los resultados NO es ConnectivityResult.none
      return results.any((result) => result != ConnectivityResult.none);
    },
    loading: () => false, // Asumimos false mientras carga
    error: (_, __) => false, // Asumimos false si hay error
  );
});

// CLASE UTILIZADA POR TU AUTH_PROVIDER (Para chequeos directos)
class ConnectivityService {
  // Función para chequeo directo, debe esperar una lista
  Future<bool> checkConnection() async {
    // 💡 CORRECCIÓN: checkConnectivity() también devuelve Future<List<ConnectivityResult>>
    final connectivityResultList = await (Connectivity().checkConnectivity());

    // Retorna true si CUALQUIERA de los resultados NO es ConnectivityResult.none
    return connectivityResultList.any(
      (result) => result != ConnectivityResult.none,
    );
  }
}

// Proveedor de la instancia del servicio
final connectivityServiceProvider = Provider((ref) => ConnectivityService());


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
        [UserSchema, RoleSchema, SyncQueueItemSchema],
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

  // 🚨 CORRECCIÓN CLAVE PARA LA ELIMINACIÓN 🚨
  Future<void> deleteUser(String userId) async {
    final isar = await db;
    await isar.writeTxn(() async {
      // En lugar de usar fastHash(userId) y .delete(isarId),
      // usamos una consulta filter() sobre el campo 'id' de tipo String.
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
    if (isar == null) return;
    await isar!.writeTxn(() async {
      await isar!.roles.putAll(roles); // putAll usa el id único para put/update
    });
  }

  // Obtiene todos los roles para el modo offline
  Future<List<Role>> getAllRoles() async {
    final isar = await db;
    if (isar == null) return [];
    return isar!.roles.where().findAll();
  }

  // 🚨 NUEVO MÉTODO CRÍTICO para la sincronización de CREACIÓN
  Future<void> updateLocalUserWithRealId(String localId, User newUser) async {
    final isar = await db;
    await isar.writeTxn(() async {
      // 1. Encontrar el usuario temporal por su ID temporal (que está en el campo 'id')
      final localUserIsarId = await isar.users
          .filter()
          .idEqualTo(localId)
          .isarIdProperty()
          .findFirst();

      if (localUserIsarId != null) {
        // 2. Eliminar el registro temporal (que tiene el localId)
        await isar.users.delete(localUserIsarId);
      }

      // 3. Guardar el nuevo registro (con el ID real/UUID devuelto por el API)
      // El método put manejará la inserción del nuevo User.
      await isar.users.put(newUser);
    });
    print(
      'DEBUG ISAR SYNC: Usuario con ID temporal $localId actualizado a ID real ${newUser.id}.',
    );
  }

  // ----------------------------------------------------------------------
  // 💡 NUEVOS MÉTODOS PARA COMPANY
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

  Future<void> deleteCompany(String companyId) async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.companys.filter().idEqualTo(companyId).deleteAll();
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

// lib/services/sync_service.dart

import 'dart:convert';
import 'package:dcpos/providers/auth_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sync_queue_item.dart';
import '../models/user.dart'; // 💡 NECESARIO para User.fromJson
import '../providers/users_provider.dart'; // 💡 NECESARIO para invalidar
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

        final payloadMap = jsonDecode(item.payload);
        print('-> Procesando [${item.operation.name}] a ${item.endpoint}');

        try {
          dynamic response;

          switch (item.operation) {
            case SyncOperation.CREATE_USER:
              response = await apiService.dio.post(
                item.endpoint, // '/users/'
                data: payloadMap,
              );

              // 🚨 CORRECCIÓN CRÍTICA: Reemplazar el usuario temporal con el real
              final createdUser = User.fromJson(response.data);

              if (item.localId != null) {
                // 1. Eliminar el usuario temporal (usando el ID local)
                await isarService.deleteUser(item.localId!);

                // 2. Guardar el usuario final con el ID real del servidor
                await isarService.saveUsers([createdUser]);

                // 3. Forzar el refresco de la UI
                _ref.invalidate(usersProvider);

                print(
                  '✅ SYNC: Usuario local ${item.localId} actualizado a ServerID ${createdUser.id}',
                );
              }
              break;

            case SyncOperation.UPDATE_USER:
              // 🚨 CORRECCIÓN: Usar item.endpoint directamente (ya debe contener el ID)
              response = await apiService.dio.patch(
                item.endpoint, // Ejemplo: '/users/uuid-real-del-servidor'
                data: payloadMap,
              );
              _ref.invalidate(usersProvider);
              break;

            case SyncOperation.DELETE_USER:
              response = await apiService.dio.delete(
                item.endpoint, // Ejemplo: '/users/uuid-real-del-servidor'
              );
              // La eliminación física ya se maneja en el Notifier si la red está ON.
              // Aquí solo debemos desencolar. La invalidación es opcional ya que DELETE
              // solo borra un registro.
              // _ref.invalidate(usersProvider);
              break;

            default:
              print('Operación no implementada: ${item.operation}');
              break;
          }

          // Si la llamada es exitosa, desencolar
          await isarService.dequeueSyncItem(item.id);
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

// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/auth_provider.dart';
import 'screens/home_screen.dart'; // Asegúrate de que este archivo existe
import 'screens/login_screen.dart';
// Importa las pantallas necesarias (o una pantalla de espera inicial)

void main() {
  // ⚠️ Importante: Riverpod requiere que la aplicación esté envuelta
  // en un ProviderScope para que los proveedores funcionen.
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. Observa el estado del proveedor de autenticación
    final authState = ref.watch(authProvider);
    return MaterialApp(
      title: 'DCPOS Offline-First',
      theme: ThemeData(primarySwatch: Colors.blue),
      // 2. Lógica de navegación condicional
      home: authState.when(
        // Muestra un loader mientras se carga el estado inicial (chequeo en Isar)
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        // Si hay un error, volvemos a mostrar el Login (y el SnackBar mostrará el error)
        error: (e, st) => const LoginScreen(),
        // Cuando los datos están disponibles (user puede ser null o el objeto User)
        data: (user) {
          if (user != null) {
            // USUARIO LOGUEADO: Navega a Home
            return const HomeScreen(); // <--- ¡Esta es la redirección!
          } else {
            // Usuario NO logueado o después de Logout
            return const LoginScreen();
          }
        },
      ),
    );
  }
}

name: dcpos
description: "A new Flutter project."
# The following line prevents the package from being accidentally published to
# pub.dev using `flutter pub publish`. This is preferred for private packages.
publish_to: 'none' # Remove this line if you wish to publish to pub.dev

# The following defines the version and build number for your application.
# A version number is three numbers separated by dots, like 1.2.43
# followed by an optional build number separated by a +.
# Both the version and the builder number may be overridden in flutter
# build by specifying --build-name and --build-number, respectively.
# In Android, build-name is used as versionName while build-number used as versionCode.
# Read more about Android versioning at https://developer.android.com/studio/publish/versioning
# In iOS, build-name is used as CFBundleShortVersionString while build-number is used as CFBundleVersion.
# Read more about iOS versioning at
# https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html
# In Windows, build-name is used as the major, minor, and patch parts
# of the product and file versions while build-number is used as the build suffix.
version: 1.0.0+1

environment:
  sdk: ^3.9.2

# Dependencies specify other packages that your package needs in order to work.
# To automatically upgrade your package dependencies to the latest versions
# consider running `flutter pub upgrade --major-versions`. Alternatively,
# dependencies can be manually updated by changing the version numbers below to
# the latest version available on pub.dev. To see which dependencies have newer
# versions available, run `flutter pub outdated`.
dependencies:
  flutter:
    sdk: flutter

  # The following adds the Cupertino Icons font to your application.
  # Use with the CupertinoIcons class for iOS style icons.
  cupertino_icons: ^1.0.8

  # Estado (riverpod es ideal para apps grandes y complejas)
  flutter_riverpod: ^2.5.1
  
  # HTTP y modelos de datos (JSON)
  dio: ^5.4.3
  json_annotation: ^4.8.1
  
  # Base de Datos Local (Isar)
  isar: ^3.1.0+1
  isar_flutter_libs: ^3.1.0+1
  # NECESARIO PARA ENCONTRAR LA RUTA DE ISAR (path_provider)
  path_provider: ^2.1.3 # Añade esta línea
  copy_with_extension: ^5.0.0
  connectivity_plus: ^7.0.0
  uuid: ^4.5.1

dev_dependencies:
  flutter_test:
    sdk: flutter

  # The "flutter_lints" package below contains a set of recommended lints to
  # encourage good coding practices. The lint set provided by the package is
  # activated in the `analysis_options.yaml` file located at the root of your
  # package. See that file for information about deactivating specific lint
  # rules and activating additional ones.
  flutter_lints: ^5.0.0

  # Generadores de código para Isar y JSON
  build_runner: ^2.4.9
  json_serializable: ^6.7.1
  isar_generator: ^3.1.0+1
  copy_with_extension_gen: ^5.0.0

# For information on the generic Dart part of this file, see the
# following page: https://dart.dev/tools/pub/pubspec

# The following section is specific to Flutter packages.
flutter:

  # The following line ensures that the Material Icons font is
  # included with your application, so that you can use the icons in
  # the material Icons class.
  uses-material-design: true

  # To add assets to your application, add an assets section, like this:
  # assets:
  #   - images/a_dot_burr.jpeg
  #   - images/a_dot_ham.jpeg

  # An image asset can refer to one or more resolution-specific "variants", see
  # https://flutter.dev/to/resolution-aware-images

  # For details regarding adding assets from package dependencies, see
  # https://flutter.dev/to/asset-from-package

  # To add custom fonts to your application, add a fonts section here,
  # in this "flutter" section. Each entry in this list should have a
  # "family" key with the font family name, and a "fonts" key with a
  # list giving the asset and other descriptors for the font. For
  # example:
  # fonts:
  #   - family: Schyler
  #     fonts:
  #       - asset: fonts/Schyler-Regular.ttf
  #       - asset: fonts/Schyler-Italic.ttf
  #         style: italic
  #   - family: Trajan Pro
  #     fonts:
  #       - asset: fonts/TrajanPro.ttf
  #       - asset: fonts/TrajanPro_Bold.ttf
  #         weight: 700
  #
  # For details regarding fonts from package dependencies,
  # see https://flutter.dev/to/font-from-package

