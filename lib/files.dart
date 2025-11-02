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
  CREATE_USER,
  UPDATE_USER,
  DELETE_USER,
  CREATE_PRODUCT,
  // ... otros casos de sincronización
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

  /// Fecha de creación del ítem en la cola.
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
import 'package:uuid/uuid.dart'; // Añadido para generar IDs temporales si fuera necesario

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

  // 💡 Campo para la correlación local-remota
  @JsonKey(includeFromJson: false, includeToJson: false)
  final String localId;

  UserCreateLocal({
    required this.username,
    required this.password,
    required this.roleId,
    required this.roleName,
    this.isActive = true,
    this.companyId,
    this.branchId,
  }) : localId = const Uuid().v4(); // Generar ID local temporal al crear

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
final isarServiceProvider = Provider((ref) => IsarService());

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

// lib/providers/roles_provider.dart

import 'package:dcpos/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/role.dart';
import '../services/api_service.dart';
import '../services/isar_service.dart';

// Asumimos que isarServiceProvider ya está definido e importado
// y que la clase IsarService existe.

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

// ⚠️ Se asume que apiServiceProvider, isarServiceProvider y connectivityServiceProvider están definidos.
// Estos proveedores se definen aquí para asegurar la funcionalidad del Notifier.
final isarServiceProvider = Provider((ref) => IsarService());
final connectivityServiceProvider = Provider((ref) => ConnectivityService());
// ASUMIMOS que apiServiceProvider proviene de api_service.dart

// --- JERARQUÍA DE ROLES DE EJEMPLO (Prioridad: menor número = más privilegio) ---
const Map<String, int> _ROLE_HIERARCHY = {
  "global_admin": 0,
  "company_admin": 1,
  "cashier": 2,
  "accountant": 3,
  'Guest': 99,
};

// --- NOTIFIER PRINCIPAL ---

class UsersNotifier extends AsyncNotifier<List<User>> {
  // Declarar los servicios necesarios como late final
  late final ApiService _apiService;
  late final IsarService _isarService;
  late final ConnectivityService _connectivityService;

  @override
  Future<List<User>> build() async {
    // Inicializar los servicios dentro de build()
    _apiService = ref.watch(apiServiceProvider);
    _isarService = ref.watch(isarServiceProvider);
    _connectivityService = ref.watch(connectivityServiceProvider);

    // Carga Rápida y Sincronización
    final localUsers = await _isarService.getAllUsers();

    // Filtramos los que están marcados para borrado lógico (isDeleted=false)
    final activeLocalUsers = localUsers
        .where((u) => u.isDeleted == false)
        .toList();

    if (activeLocalUsers.isNotEmpty) {
      state = AsyncValue.data(activeLocalUsers);
    }

    try {
      final onlineUsers = await _apiService.fetchAllUsers();
      await _isarService.saveUsers(onlineUsers);
      return onlineUsers;
    } catch (e) {
      if (activeLocalUsers.isNotEmpty) return activeLocalUsers;
      throw Exception(
        'Fallo al cargar usuarios online y no hay datos offline: $e',
      );
    }
  }

  // --- LÓGICA DE AYUDA RBAC (Corregido 'roleNameSafe' por 'roleName') ---

  int _getRolePriority(String? roleName) {
    return _ROLE_HIERARCHY[roleName] ?? _ROLE_HIERARCHY['Guest']!;
  }

  bool _canCreateUserWithRole(String creatingUserRole, String targetUserRole) {
    final creatorPriority = _getRolePriority(creatingUserRole);
    final targetPriority = _getRolePriority(targetUserRole);

    if (creatingUserRole == 'Global Admin')
      return targetUserRole != 'Global Admin';

    return creatorPriority < targetPriority;
  }

  bool _canModifyTargetUserRole(
    String modifyingUserRole,
    String targetUserRole,
  ) {
    final modifierPriority = _getRolePriority(modifyingUserRole);
    final targetPriority = _getRolePriority(targetUserRole);

    if (modifyingUserRole == 'Global Admin')
      return targetUserRole != 'Global Admin';

    return modifierPriority <= targetPriority;
  }

  // ----------------------------------------------------
  // --- MÉTODOS CRUD CON LÓGICA OFFLINE (Corregidos) ---
  // ----------------------------------------------------

  Future<void> createUser(UserCreateLocal data) async {
    final isConnected = await _connectivityService.checkConnection();
    final previousState = state;

    if (!state.hasValue) return;

    try {
      // 1. 🛑 RBAC: VALIDACIÓN DE CREACIÓN 🛑
      final currentUser = ref.read(authProvider).value;
      // ✅ CORREGIDO: Usar currentUser.roleName en lugar de roleNameSafe
      if (currentUser == null ||
          !_canCreateUserWithRole(currentUser.roleName, data.roleName)) {
        throw Exception(
          'Permiso denegado: No puede crear el rol "${data.roleName}".',
        );
      }

      // ... (Lógica de creación omitida para brevedad, ya estaba bien)
      if (!isConnected) {
        final syncItem = SyncQueueItem.create(
          operation: SyncOperation.CREATE_USER,
          endpoint: '/api/v1/users/',
          payload: jsonEncode(data.toJson()),
        );
        await _isarService.enqueueSyncItem(syncItem);
        print('DEBUG USER: Usuario encolado. ID local: ${data.localId}');

        // Actualización optimista: Simular la creación del usuario para mostrarlo inmediatamente
        final tempUser = User(
          id: data.localId, // Usamos el ID temporal
          username: data.username,
          roleId: data.roleId,
          roleName: data.roleName,
          createdAt: DateTime.now().toIso8601String(),
          isActive: data.isActive,
          companyId: data.companyId,
          branchId: data.branchId,
          isDeleted: false,
        );
        // Guardar el usuario temporal en Isar
        await _isarService.saveUsers([tempUser]);

        state = AsyncValue.data([...previousState.value!, tempUser]);
      } else {
        final newUser = await _apiService.createUser(data.toJson());
        await _isarService.saveUsers([newUser]);
        state = AsyncValue.data([...previousState.value!, newUser]);
      }
    } catch (e, st) {
      // Revertir a estado anterior solo si es error de creación.
      state = previousState;
      state = AsyncValue.error('Fallo al crear usuario: ${e.toString()}', st);
    }
  }

  Future<void> editUser(UserUpdateLocal data) async {
    final isConnected = await _connectivityService.checkConnection();
    final previousState = state;
    final userDataMap = data.toJson();

    // ✅ CORREGIDO: Usar data.id, no data.remoteId
    if (!state.hasValue || data.id == null) return;

    try {
      final userList = previousState.value!;
      // ✅ CORREGIDO: Usar data.id, no data.remoteId
      final originalUser = userList.firstWhere((u) => u.id == data.id);
      final targetRole = data.roleName ?? originalUser.roleName;

      // 1. 🛑 RBAC: VALIDACIÓN DE EDICIÓN 🛑
      final currentUser = ref.read(authProvider).value;
      // ✅ CORREGIDO: Usar currentUser.roleName en lugar de roleNameSafe
      if (currentUser == null ||
          !_canModifyTargetUserRole(currentUser.roleName, targetRole)) {
        throw Exception(
          'Permiso denegado: No puede modificar el usuario con rol "$targetRole".',
        );
      }

      if (!isConnected) {
        final syncItem = SyncQueueItem.create(
          operation: SyncOperation.UPDATE_USER,
          // ✅ CORREGIDO: Usar data.id para el endpoint
          endpoint: '/api/v1/users/${data.id}',
          payload: jsonEncode(userDataMap),
        );
        await _isarService.enqueueSyncItem(syncItem);
        print('DEBUG USER: Edición encolada.');

        // Actualización optimista del estado local
        final updatedList = userList.map((user) {
          // ✅ CORREGIDO: Usar data.id
          return user.id == data.id
              ? user.copyWith(
                  username: data.username ?? user.username,
                  roleName: data.roleName ?? user.roleName,
                  roleId:
                      data.roleId ??
                      user.roleId, // Asumo que roleId está en el DTO
                )
              : user;
        }).toList();

        // Guardar el usuario actualizado en Isar (update optimista)
        final updatedUser = updatedList.firstWhere((u) => u.id == data.id);
        await _isarService.saveUsers([updatedUser]);

        state = AsyncValue.data(updatedList);
      } else {
        // ... (Lógica online ya estaba bien)
        final updatedUser = await _apiService.updateUser(
          data.id, // ✅ CORREGIDO: Usar data.id
          userDataMap,
        );
        await _isarService.saveUsers([updatedUser]);

        final updatedList = userList.map((user) {
          return user.id == data.id
              ? updatedUser
              : user; // ✅ CORREGIDO: Usar data.id
        }).toList();
        state = AsyncValue.data(updatedList);
      }
    } catch (e, st) {
      // Revertir el estado si falla
      state = previousState;
      state = AsyncValue.error('Fallo al editar usuario: ${e.toString()}', st);
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

      // 1. 🛑 RBAC: VALIDACIÓN DE ELIMINACIÓN 🛑
      final currentUser = ref.read(authProvider).value;
      // ✅ CORREGIDO: Usar currentUser.roleName en lugar de roleNameSafe
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
        // --- OFFLINE: ENCOLAR OPERACIÓN y MARCAR EN ISAR ---

        // 1. Marcar el usuario como borrado lógicamente en Isar
        final userMarkedForDeletion = userToDelete.copyWith(isDeleted: true);
        await _isarService.saveUsers([userMarkedForDeletion]);

        final syncItem = SyncQueueItem.create(
          operation: SyncOperation.DELETE_USER,
          endpoint: '/api/v1/users/$userId',
          payload: '{}',
        );
        await _isarService.enqueueSyncItem(syncItem);
        print('DEBUG USER: Eliminación encolada.');
      } else {
        // --- ONLINE: LLAMAR DIRECTO AL API ---
        await _apiService.deleteUser(userId);

        // Eliminar físicamente el registro de Isar
        await _isarService.deleteUser(userId);
      }
    } catch (e, st) {
      // Revertir el estado si falla
      state = previousState;
      state = AsyncValue.error(
        'Fallo al eliminar usuario: ${e.toString()}',
        st,
      );
    }
  }

  // Refresca la lista de usuarios desde el servidor
  Future<void> fetchOnlineUsers() async {
    state = await AsyncValue.guard(() async {
      final onlineUsers = await _apiService.fetchAllUsers();
      await _isarService.saveUsers(onlineUsers);
      return onlineUsers;
    });
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/role.dart';
import '../models/user.dart';
import '../providers/roles_provider.dart';
import '../providers/users_provider.dart';

class UserFormScreen extends ConsumerStatefulWidget {
  final User? userToEdit; // null para crear, User para editar

  const UserFormScreen({this.userToEdit, super.key});

  @override
  ConsumerState<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends ConsumerState<UserFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  // Estado local para el rol seleccionado
  Role? _selectedRole;

  bool get isEditing => widget.userToEdit != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      _usernameController.text = widget.userToEdit!.username;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /**
   * Procesa el formulario, crea el DTO correcto (Create o Update) y llama al Notifier.
   */
  Future<void> _submitForm(BuildContext context) async {
    // Validación de formulario y selección de rol
    if (!_formKey.currentState!.validate() || _selectedRole == null) {
      return;
    }

    final usersNotifier = ref.read(usersProvider.notifier);

    try {
      if (isEditing) {
        // --- 1. EDICIÓN: Crear UserUpdateLocal DTO ---
        final updateData = UserUpdateLocal(
          id: widget.userToEdit!.id,
          username: _usernameController.text,
          password: _passwordController.text.isNotEmpty
              ? _passwordController.text
              : null,

          // ✅ CORREGIDO: roleId es String (UUID)
          roleId: _selectedRole!.id,

          // Incluir roleName para el cache optimista en el Notifier
          roleName: _selectedRole!.name,

          isActive: widget.userToEdit!.isActive,
          companyId: widget.userToEdit!.companyId,
          branchId: widget.userToEdit!.branchId,
        );

        await usersNotifier.editUser(updateData);
      } else {
        // --- 2. CREACIÓN: Crear UserCreateLocal DTO ---
        final createData = UserCreateLocal(
          username: _usernameController.text,
          password: _passwordController.text,

          // ✅ CORREGIDO: roleId es String (UUID)
          roleId: _selectedRole!.id,

          roleName: _selectedRole!.name,

          // Usar valores por defecto o de la jerarquía actual
          companyId: null,
          branchId: null,
          isActive: true,
        );

        await usersNotifier.createUser(createData);
      }

      // Éxito: Volver a la pantalla anterior
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      // Manejo de errores
      if (context.mounted) {
        // Mostrar mensaje de error más limpio
        final errorMessage = e.toString().contains('Exception:')
            ? e.toString().split('Exception:').last.trim()
            : 'Error de red, permisos o datos.';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar usuario: $errorMessage')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Observamos el proveedor de roles
    final rolesAsyncValue = ref.watch(rolesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar Usuario' : 'Crear Usuario'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // 1. Campo Nombre de Usuario
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre de Usuario',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor, ingrese un nombre de usuario.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 2. Campo Contraseña
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: isEditing
                      ? 'Nueva Contraseña (Dejar vacío para mantener la actual)'
                      : 'Contraseña',
                ),
                validator: (value) {
                  if (!isEditing && (value == null || value.isEmpty)) {
                    return 'La contraseña es requerida para un nuevo usuario.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // 3. Dropdown de Roles
              rolesAsyncValue.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Text('Error al cargar roles: $e'),
                data: (roles) {
                  if (roles.isEmpty) {
                    return const Text('No hay roles disponibles.');
                  }

                  // 💡 Inicialización del rol seleccionado al cargar
                  if (isEditing && _selectedRole == null) {
                    // ✅ CORREGIDO: roleId del user ya es String (UUID)
                    _selectedRole = roles.firstWhere(
                      (r) => r.id == widget.userToEdit!.roleId,
                      orElse: () => roles.first,
                    );
                  }
                  // Asignar el primer rol si estamos creando y no hay selección
                  if (!isEditing && _selectedRole == null) {
                    _selectedRole = roles.first;
                  }

                  return DropdownButtonFormField<Role>(
                    value: _selectedRole,
                    decoration: const InputDecoration(labelText: 'Rol'),
                    items: roles.map((role) {
                      return DropdownMenuItem(
                        value: role,
                        child: Text(role.name),
                      );
                    }).toList(),
                    onChanged: (Role? newValue) {
                      setState(() {
                        _selectedRole = newValue;
                      });
                    },
                    validator: (value) {
                      if (value == null) {
                        return 'Debe seleccionar un rol.';
                      }
                      return null;
                    },
                  );
                },
              ),
              const SizedBox(height: 32),

              // 4. Botón de Guardar
              ElevatedButton(
                onPressed: () => _submitForm(context),
                child: Text(isEditing ? 'Guardar Cambios' : 'Crear Usuario'),
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
    try {
      final response = await dio.get('/roles');
      final rolesJson = response.data['roles'];
      // 2. Asegúrate de que 'rolesJson' es una lista antes de mapear.
      if (rolesJson is List) {
        return rolesJson.map((json) => Role.fromJson(json)).toList();
      } else {
        // Si la clave 'roles' no es una lista o no existe, lanza un error claro.
        throw Exception('Formato de roles incorrecto recibido del servidor.');
      }
    } on DioException catch (e) {
      throw Exception('Error al obtener roles: ${e.message}');
    }
  }

  // --- Endpoints de Usuarios (CRUD) ---
  Future<List<User>> fetchAllUsers() async {
    try {
      final response = await dio.get('/users');
      final List<dynamic> userList = response.data;
      return userList.map((json) => User.fromJson(json)).toList();
    } on DioException catch (e) {
      throw Exception('Error al obtener usuarios: ${e.message}');
    }
  }

  Future<User> createUser(Map<String, dynamic> userData) async {
    try {
      final response = await dio.post('/users', data: userData);
      return User.fromJson(response.data);
    } on DioException catch (e) {
      final errorMessage =
          e.response?.data?['detail'] ?? 'Error desconocido al crear usuario.';
      throw Exception(errorMessage);
    }
  }

  Future<User> updateUser(String userId, Map<String, dynamic> userData) async {
    try {
      final response = await dio.put('/users/$userId', data: userData);
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
      await dio.delete('/users/$userId');
    } on DioException catch (e) {
      final errorMessage =
          e.response?.data?['detail'] ??
          'Error desconocido al eliminar usuario.';
      throw Exception(errorMessage);
    }
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

  // 🚀 CORRECCIÓN DE NOMBRE: Usado para guardar el único usuario de la SESIÓN ACTIVA (con tokens)
  Future<void> saveUser(User user) async {
    final isar = await db;
    await isar.writeTxn(() async {
      // CLAVE: Borrar *todos* los usuarios antes de guardar el nuevo.
      // Esto fuerza que la colección de Users funcione como un Singleton de Sesión.
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

  Future<void> deleteUser(String userId) async {
    final isar = await db;
    // ✅ CORREGIDO: Llamando a la función fastHash definida arriba
    final isarId = fastHash(userId);
    await isar.writeTxn(() async {
      // Isar utiliza el Id (isarId) de la colección, no el UUID (userId)
      await isar.users.delete(isarId);
    });
    print('DEBUG ISAR: Usuario con ID $userId eliminado localmente.');
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
      await isar.roles.putAll(roles);
    });
    print('DEBUG ISAR: ${roles.length} roles guardados/actualizados.');
  }

  Future<List<Role>> getAllRoles() async {
    final isar = await db;
    return await isar.roles.where().findAll();
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

// lib/services/sync_service.dart

import 'dart:convert';
import 'package:dcpos/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sync_queue_item.dart';
import 'api_service.dart';
import 'isar_service.dart';
import 'connectivity_service.dart'; // 💡 Importar el Connectivity Service

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

    // Leer el valor del StateProvider directamente (corregido previamente)
    if (!_ref.read(isConnectedProvider)) {
      print('🔄 SINCRONIZACIÓN CANCELADA: No hay conexión a Internet.');
      return;
    }

    _isSyncing = true;
    final isarService = _ref.read(isarServiceProvider);
    final apiService = _ref.read(apiServiceProvider);

    print('🔄 INICIANDO SINCRONIZACIÓN DE COLA...');

    try {
      // 💡 CORRECCIÓN: Usamos un bucle while(true) y break/return
      // Esto permite una clara asignación no nula dentro del bloque.
      while (true) {
        final item = await isarService.getNextSyncItem();

        if (item == null) {
          break; // La cola está vacía.
        }

        // ¡AQUÍ item ya NO es nullable! El análisis estático de Dart lo confirma.
        final payloadMap = jsonDecode(item.payload);
        print('-> Procesando [${item.operation.name}] a ${item.endpoint}');

        try {
          dynamic response;

          switch (item.operation) {
            case SyncOperation.CREATE_USER:
              // Llamada directa al API con Dio/ApiService
              response = await apiService.dio.post(
                item.endpoint,
                data: payloadMap,
              );
              // Manejo post-creación: el servidor devuelve el objeto final (UserInDB)
              // ... (Implementar lógica para actualizar Isar con el ID real)
              break;
            case SyncOperation.UPDATE_USER:
              // Ejemplo: DELETE user_id, UPDATE user_id, etc.
              response = await apiService.dio.patch(
                '${item.endpoint}/${item.localId}',
                data: payloadMap,
              );
              break;
            // Añadir casos para otros CRUDs (PRODUCTOS, BRANCHES, etc.)
            default:
              print('Operación no implementada: ${item.operation}');
              break;
          }

          // Si la llamada es exitosa, desencolar
          await isarService.dequeueSyncItem(item.id);
        } catch (e) {
          // 🚨 Si falla (ej: error 422 de validación o 401 de auth), detenemos la cola
          print('❌ FALLA Sincronización: ${e.toString()}');
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

