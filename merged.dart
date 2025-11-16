// ----- FILE: lib\main.dart -----
// lib/main.dart

import 'package:dcpos/screens/branches_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/auth_provider.dart';
import 'screens/home_screen.dart'; // Pantalla principal
import 'screens/login_screen.dart'; // Pantalla de login
import 'screens/companies_screen.dart';
import 'screens/users_screen.dart'; // Asumiendo que existe

void main() {
  // Riverpod requiere que la aplicación esté envuelta en un ProviderScope
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

        // Si hay un error, volvemos a mostrar el Login (o manejar el error)
        error: (e, st) => const LoginScreen(),

        // Cuando los datos están disponibles
        data: (user) {
          if (user != null) {
            // USUARIO LOGUEADO: Navega a Home
            return const HomeScreen();
          } else {
            // Usuario NO logueado o después de Logout
            return const LoginScreen();
          }
        },
      ),

      // Opcional: Definición de rutas nombradas si las necesita
      routes: {
        '/companies': (context) => const CompaniesScreen(),
        '/users': (context) =>
            const UsersScreen(), // Asumiendo que esta ruta existe
        '/branches': (context) => const BranchesScreen(), // ⬅️ NUEVA RUTA
      },
    );
  }
}


// ----- FILE: lib\models\branch.dart -----
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
  // 💡 CORRECCIÓN CRÍTICA: Se añade @JsonKey(ignore: true) para evitar el error
  // 'type Null is not a subtype of type num' al deserializar desde el API.
  // Este campo es exclusivo de Isar y debe ser ignorado por JSON.
  @JsonKey(ignore: true)
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
// 3. MODELO DE ACTUALIZACIÓN (Offline-First)
// ----------------------------------------------------------------------
@JsonSerializable(
  includeIfNull: false,
  explicitToJson: true,
  createFactory: false, // Indica que debemos definir el factory manualmente
)
class BranchUpdateLocal {
  // Los campos ignorados no se incluirán en el código generado de toApiJson()
  @JsonKey(ignore: true)
  final String id;
  @JsonKey(ignore: true)
  final String companyId;

  final String? name;
  final String? address;

  BranchUpdateLocal({
    required this.id,
    required this.companyId,
    this.name,
    this.address,
  });

  // ✅ Factory manual para deserializar desde la cola local
  factory BranchUpdateLocal.fromJson(Map<String, dynamic> json) {
    return BranchUpdateLocal(
      id: json['id'] as String,
      companyId: json['companyId'] as String,
      name: json['name'] as String?,
      address: json['address'] as String?,
    );
  }

  // Mantenemos toApiJson para el request PATCH
  // Incluye solo name y address (excluyendo nulls por includeIfNull: false).
  Map<String, dynamic> toApiJson() {
    return _$BranchUpdateLocalToJson(this);
  }

  // ✅ Manual toJson para la cola (incluye id y companyId)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'companyId': companyId,
      if (name != null) 'name': name,
      if (address != null) 'address': address,
    };
  }
}


// ----- FILE: lib\models\company.dart -----
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
@JsonSerializable(
  fieldRename: FieldRename.snake,
  explicitToJson: true,
  anyMap: true,
)
@Collection()
class Company {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  final String id;

  final String name;
  final String slug;

  @JsonKey(name: 'created_at', required: false)
  final String? createdAt;

  final bool isDeleted;

  // ✅ CAMPO CLAVE: Usado solo localmente para el estado de sincronización.
  @JsonKey(ignore: true)
  final bool isSyncPending;

  Company({
    this.isarId = Isar.autoIncrement,
    required this.id,
    required this.name,
    required this.slug,
    this.createdAt,
    this.isDeleted = false,
    this.isSyncPending = false, // Por defecto es false
  });

  static String generateLocalId() => const Uuid().v4();

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

  Map<String, dynamic> toApiJson() {
    return {'name': name, 'slug': slug};
  }

  Map<String, dynamic> toJson() => _$CompanyCreateLocalToJson(this);

  factory CompanyCreateLocal.fromJson(Map<String, dynamic> json) =>
      _$CompanyCreateLocalFromJson(json);
}

// ----------------------------------------------------------------------
// 3. MODELO DE ACTUALIZACIÓN (Offline-First)
// ----------------------------------------------------------------------
@JsonSerializable(
  includeIfNull: false,
  explicitToJson: true,
  createFactory: false, // 🛑 Requiere fromJson y toJson manual
)
class CompanyUpdateLocal {
  @JsonKey(ignore: true)
  final String id; // Backend ID

  final String? name;
  final String? slug;

  CompanyUpdateLocal({required this.id, this.name, this.slug});

  // ✅ CORRECCIÓN 1: Constructor de fábrica manual para la deserialización
  // Es usado por SyncService para reconstruir el objeto desde el payload.
  factory CompanyUpdateLocal.fromJson(Map<String, dynamic> json) {
    return CompanyUpdateLocal(
      id: json['id'] as String,
      name: json['name'] as String?,
      slug: json['slug'] as String?,
    );
  }

  // Mantenemos toApiJson (para el request PATCH, con campos opcionales)
  // Nota: Si usaras _$CompanyUpdateLocalToJson(this) necesitarías ejecutar
  // el generador. Para evitar dependencia y asegurar que el ID no vaya en el body,
  // creamos la versión API manualmente:
  Map<String, dynamic> toApiJson() {
    return {if (name != null) 'name': name, if (slug != null) 'slug': slug};
  }

  // ✅ CORRECCIÓN 2: Método toJson manual (para la cola de sincronización)
  // Incluye el ID para que SyncService sepa qué registro actualizar.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (name != null) 'name': name,
      if (slug != null) 'slug': slug,
    };
  }
}


// ----- FILE: lib\models\role.dart -----
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


// ----- FILE: lib\models\sync_queue_item.dart -----
import 'package:isar/isar.dart';
import 'package:json_annotation/json_annotation.dart';

part 'sync_queue_item.g.dart';

// ----------------------------------------------------------------------
// 1. ENUM DE OPERACIONES DE SINCRONIZACIÓN
// ----------------------------------------------------------------------

/// Define las operaciones CRUD que pueden ser encoladas para sincronización
/// cuando el dispositivo está sin conexión.
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

// ----------------------------------------------------------------------
// 2. MODELO DE COLA DE SINCRONIZACIÓN (ISAR)
// ----------------------------------------------------------------------

@JsonSerializable()
@Collection()
class SyncQueueItem {
  Id id = Isar.autoIncrement;

  @Enumerated(EnumType.name)
  final SyncOperation operation; // 👈 Aquí se usa la enumeración

  /// El endpoint REST al que se debe enviar el payload (ej: /api/v1/users/)
  final String endpoint;

  /// El payload (cuerpo) de la solicitud API, guardado como JSON string.
  final String payload;

  /// UUID local generado si es un CREATE, usado para identificar el item local temporalmente.
  final String? localId;

  /// Fecha de creación del ítem en la cola. Se usa para procesar los ítems en orden (FIFO).
  final DateTime createdAt;

  /// Contador de reintentos.
  final int? retryCount;

  // Constructor principal simple (usado por Isar y json_serializable/manual)
  SyncQueueItem({
    required this.operation,
    required this.endpoint,
    required this.payload,
    this.localId,
    required this.createdAt,
    this.retryCount = 0,
  });

  /// Fábrica auxiliar para crear el ítem con la hora actual (`DateTime.now()`) automáticamente.
  factory SyncQueueItem.create({
    required SyncOperation operation,
    required String endpoint,
    required String payload,
    String? localId,
    int retryCount = 0,
  }) {
    return SyncQueueItem(
      operation: operation,
      endpoint: endpoint,
      payload: payload,
      localId: localId,
      createdAt: DateTime.now(),
      retryCount: retryCount,
    );
  }

  factory SyncQueueItem.fromJson(Map<String, dynamic> json) =>
      _$SyncQueueItemFromJson(json);

  Map<String, dynamic> toJson() => _$SyncQueueItemToJson(this);
}


// ----- FILE: lib\models\token.dart -----
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


// ----- FILE: lib\models\user.dart -----
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


// ----- FILE: lib\providers\auth_provider.dart -----
// lib/providers/auth_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/token.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/isar_service.dart';
import '../services/sync_service.dart';

// Proveedor del SyncService (Necesario para la sincronización post-login)
final syncServiceProvider = Provider((ref) => SyncService(ref));

// Estado de Autenticación (StateNotifier para manejar estados de carga/error)
class AuthNotifier extends StateNotifier<AsyncValue<User?>> {
  final Ref _ref;
  Token? _token;

  // 💡 NUEVO GETTER: Permite acceder al User? de forma limpia (para CompaniesNotifier)
  User? get user => state.value;

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

      if (user != null && user.accessToken != null) {
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
      } else {
        state = const AsyncValue.data(null);
        print(
          'DEBUG INIT: No se encontró sesión o usuario en Isar. Mostrando LoginScreen.',
        );
      }
    } catch (e, st) {
      state = AsyncValue.error(
        'Error al inicializar la base de datos local: $e',
        st,
      );
    }
  }

  // --- Lógica de Login ---

  Future<void> login(String username, String password) async {
    state = const AsyncValue.loading();
    final _apiService = _ref.read(apiServiceProvider);
    final _isarService = _ref.read(isarServiceProvider);
    final _syncService = _ref.read(syncServiceProvider);

    try {
      final tokenResult = await _apiService.login(username, password);
      _token = tokenResult;

      final userResponse = await _apiService.fetchMe();

      final userToSave = userResponse.copyWith(
        accessToken: tokenResult.accessToken,
        refreshToken: tokenResult.refreshToken,
      );
      print('DEBUG LOGIN: accessToken=${tokenResult.accessToken}');
      print('DEBUG LOGIN: refreshToken=${tokenResult.refreshToken}');
      await _isarService.saveUser(userToSave);

      state = AsyncValue.data(userToSave);

      _syncService.startSync();

      print(
        'DEBUG AUTH: Estado final actualizado a DATA. User: ${userToSave.username}',
      );
    } catch (e, st) {
      print('DEBUG AUTH: Fallo catastrófico en Login: $e');

      if (e.toString().contains('DioException') ||
          e.toString().contains('SocketException')) {
        final isarUser = await _isarService.getActiveUser();

        if (isarUser != null && isarUser.username == username) {
          print(
            'DEBUG AUTH: Fallo de red detectado. Autenticación exitosa en modo OFFLINE con Isar.',
          );

          state = AsyncValue.data(isarUser);
          return;
        }
      }

      state = AsyncValue.error(e, st);
    }
  }

  // ⚠️ Este método es llamado por el Interceptor cuando el token expira
  void updateToken(Token newToken) async {
    final _isarService = _ref.read(isarServiceProvider);
    final _syncService = _ref.read(syncServiceProvider);

    _token = newToken;
    final currentUser = state.value;

    if (currentUser != null) {
      final userWithNewToken = currentUser.copyWith(
        accessToken: newToken.accessToken,
        refreshToken: newToken.refreshToken,
      );

      await _isarService.saveUser(userWithNewToken);
    }

    _syncService.startSync();

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

    await _isarService.cleanDB();
    print('DEBUG LOGOUT: Usuario y sesión eliminados de Isar (Hard Logout).');

    state = const AsyncValue.data(null);
  }
}

// Proveedor global que se utiliza para leer el estado de autenticación
final authProvider = StateNotifierProvider<AuthNotifier, AsyncValue<User?>>(
  (ref) => AuthNotifier(ref),
);


// ----- FILE: lib\providers\branches_provider.dart -----
// lib/providers/branches_provider.dart

import 'dart:convert';
import 'package:dcpos/providers/companies_provider.dart';
// ❌ ELIMINADA la importación ambigua/duplicada
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../models/branch.dart';
import '../models/sync_queue_item.dart';
import '../services/api_service.dart';
import '../services/isar_service.dart';
import '../services/connectivity_service.dart';
import '../services/sync_service.dart'; // ✅ Única importación del servicio

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
      // ✅ CORRECCIÓN: Tipado explícito <Branch>
      final updatedList = newList.map<Branch>((b) {
        return b.id == localId ? newBranch : b;
      }).toList();
      state = AsyncValue.data(updatedList);
      print('✅ ONLINE: Sucursal creada y sincronizada exitosamente.');
    } on DioException catch (e) {
      // 5. Fallback Offline: Encolar la operación
      if (e.response?.statusCode == null || e.response!.statusCode! < 500) {
        // ✅ CORRECCIÓN: Uso de argumentos nombrados
        final syncItem = SyncQueueItem.create(
          operation: SyncOperation.CREATE_BRANCH,
          endpoint: '/api/v1/platform/companies/${data.companyId}/branches',
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
        // Uso de argumentos nombrados
        final syncItem = SyncQueueItem.create(
          operation: SyncOperation.UPDATE_BRANCH,
          endpoint:
              '/api/v1/platform/companies/${data.companyId}/branches/${data.id}',
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
      endpoint: '/api/v1/platform/companies/$companyId/branches/$branchId',
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


// ----- FILE: lib\providers\companies_provider.dart -----
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

    // ✅ CORRECCIÓN SOLICITADA: Usamos roleName directamente
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
            await _isarService.deleteCompany(targetId);
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
      await _processSyncQueue();
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

  // ... el resto de la clase updateCompany y deleteCompany es igual ...

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
    final previousState = state;
    if (!state.hasValue) return;

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
          await _apiService.deleteCompany(companyId);
          await _isarService.deleteCompany(companyId);
        } catch (e) {
          await _handleOfflineDelete(companyId, companyToDelete);
        }
      } else {
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


// ----- FILE: lib\providers\roles_provider.dart -----
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


// ----- FILE: lib\providers\users_provider.dart -----
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


// ----- FILE: lib\screens\branches_screen.dart -----
// lib/screens/branches_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/branch.dart';
import '../models/company.dart'; // Asegúrate de tener este modelo
import '../providers/branches_provider.dart';
import '../providers/companies_provider.dart';

// Generador de UUID para IDs locales temporales
const _uuid = Uuid();

class BranchesScreen extends ConsumerWidget {
  static const routeName = '/branches';

  // ID de la compañía que se quiere ver, pasado desde CompaniesScreen.
  final String? selectedCompanyId;

  const BranchesScreen({super.key, this.selectedCompanyId});

  // Función auxiliar para obtener el ID de la compañía seleccionada o la primera disponible.
  String? _getCompanyIdToFilter(List<Company>? companies) {
    if (companies == null || companies.isEmpty) return null;

    // Encuentra la compañía pasada por argumento o usa la primera.
    final selectedCompany = companies.firstWhere(
      (c) => c.id == selectedCompanyId,
      orElse: () => companies.first,
    );
    return selectedCompany.id;
  }

  // 🚀 FUNCIÓN PARA FORZAR LA RECARGA Y SINCRONIZACIÓN
  void _reloadBranches(WidgetRef ref) {
    // Invalida el proveedor, forzando la recarga de la base de datos local
    // y la sincronización con la API (según la implementación de branchesProvider).
    ref.invalidate(branchesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companiesAsync = ref.watch(companiesProvider);
    final branchesAsync = ref.watch(branchesProvider);

    // Calcular el ID fuera del bloque 'when' para que sea accesible al FAB
    final fabCompanyId = _getCompanyIdToFilter(companiesAsync.value);

    return Scaffold(
      appBar: AppBar(
        title: const Text('🏢 Gestión de Sucursales'),
        actions: [
          // 💡 BOTÓN DE REFRESH AGREGADO
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _reloadBranches(ref),
            tooltip: 'Recargar y sincronizar sucursales',
          ),
        ],
      ),
      body: companiesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) =>
            Center(child: Text('Error al cargar compañías: $err')),
        data: (companies) {
          if (companies.isEmpty) {
            return const Center(
              child: Text(
                'No hay compañías disponibles para gestionar sucursales.',
              ),
            );
          }

          final companyIdToFilter = fabCompanyId!;
          final selectedCompany = companies.firstWhere(
            (c) => c.id == companyIdToFilter,
          );

          return Column(
            children: [
              // Indicador de Compañía Seleccionada
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Sucursales de: ${selectedCompany.name}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Expanded(
                // Lista de Sucursales
                child: branchesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (err, stack) =>
                      Center(child: Text('Error al cargar sucursales: $err')),
                  data: (allBranches) {
                    // 💡 Filtra las sucursales por el ID de la compañía
                    final filteredBranches = allBranches
                        .where((b) => b.companyId == companyIdToFilter)
                        .toList();

                    if (filteredBranches.isEmpty) {
                      return const Center(
                        child: Text(
                          'No hay sucursales registradas para esta compañía.',
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: filteredBranches.length,
                      itemBuilder: (context, index) {
                        final branch = filteredBranches[index];
                        final isMarkedForDeletion = branch.isDeleted;

                        return ListTile(
                          tileColor: isMarkedForDeletion
                              ? Colors.red.shade50
                              : null,
                          title: Text(
                            branch.name,
                            style: TextStyle(
                              decoration: isMarkedForDeletion
                                  ? TextDecoration.lineThrough
                                  : null,
                              fontStyle: isMarkedForDeletion
                                  ? FontStyle.italic
                                  : null,
                            ),
                          ),
                          subtitle: Text(
                            'ID: ${branch.id.length > 8 ? '${branch.id.substring(0, 8)}...' : branch.id} | Dirección: ${branch.address ?? 'Sin dirección'}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Estado de sincronización (lógica de placeholder)
                              if (branch.id.length > 10 &&
                                  !branch.id.startsWith(RegExp(r'[a-f0-9]{8}')))
                                const Tooltip(
                                  message:
                                      'Pendiente de sincronización (ID Local)',
                                  child: Icon(
                                    Icons.cloud_off,
                                    color: Colors.orange,
                                    size: 20,
                                  ),
                                ),
                              const SizedBox(width: 8),

                              // Botón de Eliminación
                              IconButton(
                                icon: Icon(
                                  isMarkedForDeletion
                                      ? Icons.delete_forever_rounded
                                      : Icons.delete,
                                  color: isMarkedForDeletion
                                      ? Colors.red
                                      : null,
                                ),
                                onPressed: isMarkedForDeletion
                                    ? null
                                    : () => _confirmDelete(
                                        context,
                                        ref,
                                        companyIdToFilter,
                                        branch.id,
                                      ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      // El FAB usa fabCompanyId, que está disponible en este scope.
      floatingActionButton: fabCompanyId != null
          ? FloatingActionButton(
              onPressed: () => _showCreateDialog(context, ref, fabCompanyId),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  // Diálogo y funciones auxiliares
  void _showCreateDialog(
    BuildContext context,
    WidgetRef ref,
    String companyId,
  ) {
    final nameController = TextEditingController();
    final addressController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Crear Nueva Sucursal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Nombre *'),
            ),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: 'Dirección'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              if (nameController.text.isEmpty) return;
              final data = BranchCreateLocal(
                companyId: companyId,
                name: nameController.text,
                address: addressController.text.isEmpty
                    ? null
                    : addressController.text,
              );

              ref.read(branchesProvider.notifier).createBranch(data);
              Navigator.of(ctx).pop();
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String companyId,
    String branchId,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Sucursal'),
        content: const Text(
          '¿Está seguro de que desea eliminar esta sucursal? La operación se encolará si está offline.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(branchesProvider.notifier)
                  .deleteBranch(companyId, branchId);
              Navigator.of(ctx).pop();
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}


// ----- FILE: lib\screens\companies_screen.dart -----
//lib/screens/companies_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/companies_provider.dart';
import 'company_form_screen.dart';
import 'branches_screen.dart'; // 💡 CORREGIDO: Importación de BranchesScreen

class CompaniesScreen extends ConsumerWidget {
  const CompaniesScreen({super.key});

  // Función para forzar la recarga de datos
  void _reloadCompanies(WidgetRef ref) {
    // 🚀 Llamada para invalidar y reconstruir el AsyncNotifier
    ref.invalidate(companiesProvider);
    // Opcional: ref.read(companiesProvider.notifier).build();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companiesAsyncValue = ref.watch(companiesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Compañías'),
        actions: [
          // 🚀 BOTÓN DE RECARGA AGREGADO A LA APPBAR
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _reloadCompanies(ref),
            tooltip: 'Recargar datos y sincronizar',
          ),
        ],
      ),
      // --- Botón Flotante para Crear ---
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const CompanyFormScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
      body: companiesAsyncValue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Text(
            'Error al cargar: ${err.toString().replaceAll('Exception: ', '')}',
            style: const TextStyle(color: Colors.red),
          ),
        ),
        data: (companies) {
          if (companies.isEmpty) {
            return const Center(child: Text('Aún no hay compañías creadas.'));
          }

          // --- Listado de Compañías ---
          return ListView.builder(
            itemCount: companies.length,
            itemBuilder: (context, index) {
              final company = companies[index];

              // 💡 Acción Principal: Navegar a la gestión de Sucursales
              return ListTile(
                title: Text(company.name),
                subtitle: Text('Slug: ${company.slug}'),
                onTap: () {
                  // ✅ CORREGIDO: Navegar a BranchesScreen, pasando el company.id
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) =>
                          BranchesScreen(selectedCompanyId: company.id),
                    ),
                  );
                },
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Botón de Edición
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) =>
                                CompanyFormScreen(companyToEdit: company),
                          ),
                        );
                      },
                    ),
                    // Botón de Eliminación (Lógica de borrado en el Notifier)
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        ref
                            .read(companiesProvider.notifier)
                            .deleteCompany(company.id);
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}


// ----- FILE: lib\screens\company_form_screen.dart -----
//lib/screens/company_form_screen.dart (Corregido) 🛠️
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/company.dart';
import '../providers/companies_provider.dart';

class CompanyFormScreen extends ConsumerStatefulWidget {
  final Company? companyToEdit;

  const CompanyFormScreen({super.key, this.companyToEdit});

  @override
  ConsumerState<CompanyFormScreen> createState() => _CompanyFormScreenState();
}

class _CompanyFormScreenState extends ConsumerState<CompanyFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _slugController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.companyToEdit != null) {
      final company = widget.companyToEdit!;
      _nameController.text = company.name;
      _slugController.text = company.slug;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    super.dispose();
  }

  void _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final companiesNotifier = ref.read(companiesProvider.notifier);

    try {
      if (widget.companyToEdit == null) {
        // --- CREACIÓN (Offline-First) ---
        final newCompany = CompanyCreateLocal(
          name: _nameController.text,
          slug: _slugController.text,
        );
        await companiesNotifier.createCompany(newCompany);
      } else {
        // --- EDICIÓN (Offline-First) ---
        final updatedCompany = CompanyUpdateLocal(
          id: widget.companyToEdit!.id,
          name: _nameController.text,
          slug: _slugController.text,
        );
        // 🚀 CORRECCIÓN APLICADA: Llamada a updateCompany
        await companiesNotifier.updateCompany(updatedCompany);
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $errorMessage'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.companyToEdit == null
              ? 'Crear Compañía'
              : 'Editar Compañía: ${widget.companyToEdit!.name}',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Campo Nombre ---
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la Compañía',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Introduce el nombre.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // --- Campo Slug ---
              TextFormField(
                controller: _slugController,
                decoration: const InputDecoration(
                  labelText: 'Slug (Identificador único, ej: miempresa)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Introduce un slug.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 30),

              // --- Botón de Guardar ---
              ElevatedButton(
                onPressed: _isLoading ? null : _submitForm,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        widget.companyToEdit == null
                            ? 'Crear Compañía'
                            : 'Guardar Cambios',
                        style: const TextStyle(fontSize: 18),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ----- FILE: lib\screens\home_screen.dart -----
// lib/screens/home_screen.dart

import 'package:dcpos/screens/branches_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import 'users_screen.dart';
import 'companies_screen.dart';

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

            // 2. BOTÓN PARA NAVEGAR A GESTIÓN DE COMPAÑÍAS 🏢
            ElevatedButton.icon(
              icon: const Icon(Icons.business),
              label: const Text('GESTIÓN DE COMPAÑÍAS'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const CompaniesScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),

            // 3. BOTÓN PARA NAVEGAR A GESTIÓN DE SUCURSALES 🏛️ ⬅️ NUEVO
            ElevatedButton.icon(
              icon: const Icon(Icons.apartment),
              label: const Text('GESTIÓN DE SUCURSALES'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const BranchesScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),

            // 4. BOTÓN PARA NAVEGAR A GESTIÓN DE USUARIOS
            ElevatedButton.icon(
              icon: const Icon(Icons.group),
              label: const Text('GESTIÓN DE USUARIOS'),
              onPressed: () {
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


// ----- FILE: lib\screens\login_screen.dart -----
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


// ----- FILE: lib\screens\users_screen.dart -----
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


// ----- FILE: lib\screens\user_form_screen.dart -----
// lib/screens/user_form_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

// 🚨 Asegúrate de que estas rutas coincidan con tu proyecto
import '../models/user.dart'; // Contiene UserCreateLocal, UserUpdateLocal
import '../models/role.dart';
import '../models/company.dart';
import '../models/branch.dart';
import '../providers/users_provider.dart';
import '../providers/roles_provider.dart';
import '../providers/companies_provider.dart';
import '../providers/branches_provider.dart';
import '../providers/auth_provider.dart';

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

  // ESTADOS CLAVE PARA EL MANEJO DEL ROL
  String? _selectedRoleId;
  String? _selectedRoleName;

  // NUEVAS VARIABLES DE ESTADO PARA COMPANY Y BRANCH
  String? _selectedCompanyId;
  String? _selectedBranchId;

  bool _isLoading = false;

  // VARIABLE DE ESTADO PARA EL ERROR DE VALIDACIÓN DE COMPAÑÍA
  String? _companyIdValidationError;
  // VARIABLE DE ESTADO PARA EL ERROR DE SUCURSAL
  String? _branchIdValidationError;

  @override
  void initState() {
    super.initState();
    if (widget.userToEdit != null) {
      final user = widget.userToEdit!;
      _usernameController.text = user.username;

      // Si estamos editando, precargar los valores del rol y IDs
      _selectedRoleId = user.roleId;
      _selectedRoleName = user.roleName;

      _selectedCompanyId = user.companyId;
      _selectedBranchId = user.branchId;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Función auxiliar para determinar si un rol requiere compañía
  bool _roleRequiresCompany(String? roleName) {
    if (roleName == null) return false;
    return roleName == 'company_admin' ||
        roleName == 'cashier' ||
        roleName == 'accountant';
  }

  // Función auxiliar para determinar si un rol requiere sucursal
  bool _roleRequiresBranch(String? roleName) {
    if (roleName == null) return false;
    return roleName == 'cashier' || roleName == 'accountant';
  }

  // -----------------------------------------------------------
  // FUNCIÓN PRINCIPAL DE ENVÍO Y LÓGICA CONDICIONAL DE IDs
  // -----------------------------------------------------------
  void _submitForm() async {
    // 1. Validaciones de formulario (nativas)
    if (!_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = false;
        _companyIdValidationError = null;
        _branchIdValidationError = null;
      });
      return;
    }
    if (_selectedRoleId == null || _selectedRoleName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecciona un rol.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      // Limpiar errores personalizados antes de la validación
      _companyIdValidationError = null;
      _branchIdValidationError = null;
    });

    // OBTENER EL USUARIO ACTUAL
    final currentUserAsync = ref.read(authProvider);
    final currentUser = currentUserAsync.value;

    if (currentUser == null) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Error de autenticación: No se pudo obtener el usuario actual.',
          ),
        ),
      );
      return;
    }

    final usersNotifier = ref.read(usersProvider.notifier);

    final bool isCurrentUserCompanyAdmin =
        currentUser.roleName == 'company_admin';
    final bool isCompanyRequired = _roleRequiresCompany(_selectedRoleName);
    final bool isBranchRequired = _roleRequiresBranch(_selectedRoleName);

    // Lógica de Asignación de IDs Condicionales (Base de la validación)
    String? finalCompanyId = _selectedCompanyId;
    String? finalBranchId = _selectedBranchId;

    // ------------------------------------------------------
    // 🚨 VALIDACIÓN LOCAL PARA COMPANY_ADMIN (y otros roles requeridos)
    // ------------------------------------------------------
    if (isCompanyRequired) {
      // Si el usuario logueado es Company Admin
      if (isCurrentUserCompanyAdmin) {
        // 1. Validación de Compañía (Si intenta asignar una que NO es la suya)
        if (finalCompanyId != null && finalCompanyId != currentUser.companyId) {
          setState(() {
            _companyIdValidationError =
                'Acceso Denegado: Solo puedes asignar usuarios a tu propia compañía.';
            _isLoading = false;
          });
          return;
        }

        // Forzamos su Company ID para la operación
        finalCompanyId = currentUser.companyId;
      } else {
        // Si el usuario logueado NO es Company Admin (Global Admin)

        if (finalCompanyId == null) {
          setState(() {
            _companyIdValidationError =
                'La compañía es requerida para este rol.';
            _isLoading = false;
          });
          return;
        }
      }

      // 2. VALIDACIÓN MANUAL PARA SUCURSAL SI ES CAJERO O CONTADOR
      if (isBranchRequired) {
        if (finalBranchId == null || finalBranchId.isEmpty) {
          setState(() {
            _branchIdValidationError =
                'La sucursal es requerida para el rol ${_selectedRoleName?.toUpperCase()}.';
            _isLoading = false;
          });
          return;
        }
      }
    }
    // ------------------------------------------------------

    // A. Roles que NO requieren compañía/sucursal (limpiar IDs)
    if (!isCompanyRequired) {
      finalCompanyId = null;
      finalBranchId = null;
    }
    // B. Rol 'company_admin' requiere compañía, pero NO sucursal
    else if (_selectedRoleName == 'company_admin') {
      finalBranchId = null;
    }
    // C. Rol 'cashier' o 'accountant' requieren ambos (finalCompanyId y finalBranchId se mantienen y fueron validados)

    try {
      if (widget.userToEdit == null) {
        // --- CREACIÓN (Offline-First) ---
        final newUserId = ref.read(uuidProvider).v4();

        final newUser = UserCreateLocal(
          username: _usernameController.text,
          password: _passwordController.text,
          roleId: _selectedRoleId!,
          roleName: _selectedRoleName!,
          localId: newUserId,
          companyId: finalCompanyId,
          branchId: finalBranchId,
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
          companyId: finalCompanyId,
          branchId: finalBranchId,
        );

        await usersNotifier.editUser(updatedUser);
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // Manejo de Errores de API/Riverpod (genéricos)
      if (mounted) {
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
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // -----------------------------------------------------------
  // WIDGETS AUXILIARES PARA COMPAÑÍA Y SUCURSAL
  // -----------------------------------------------------------

  Widget _buildCompanyDropdown(List<Company> companies) {
    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(
        labelText: 'Compañía (Requerido)',
        border: OutlineInputBorder(),
      ),
      value: _selectedCompanyId,
      items: companies.map((c) {
        return DropdownMenuItem(value: c.id, child: Text(c.name));
      }).toList(),
      onChanged: (String? newValue) {
        setState(() {
          _selectedCompanyId = newValue;
          // Al cambiar la compañía, forzamos a nulo la sucursal
          _selectedBranchId = null;
        });
      },
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Debes seleccionar una compañía.';
        }
        return null;
      },
    );
  }

  Widget _buildBranchDropdown(List<Branch> availableBranches) {
    return Column(
      children: [
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(
            labelText: 'Sucursal (Requerido)',
            border: OutlineInputBorder(),
          ),
          value: _selectedBranchId,
          items: availableBranches.map((b) {
            return DropdownMenuItem(value: b.id, child: Text(b.name));
          }).toList(),
          onChanged: (String? newValue) {
            setState(() {
              _selectedBranchId = newValue;
            });
          },
          validator: (value) {
            // Este validador nativo se mantiene como fallback para Global Admin
            if (value == null || value.isEmpty) {
              return 'Debes seleccionar una sucursal.';
            }
            return null;
          },
        ),
      ],
    );
  }

  // -----------------------------------------------------------
  // BUILD METHOD
  // -----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    // Observar los proveedores de datos
    final rolesAsyncValue = ref.watch(rolesProvider);
    final companiesAsyncValue = ref.watch(companiesProvider);
    final branchesAsyncValue = ref.watch(branchesProvider);

    // OBTENER EL USUARIO ACTUAL
    final currentUserAsync = ref.watch(authProvider);
    final currentUser = currentUserAsync.value;

    final bool isCurrentUserCompanyAdmin =
        currentUser?.roleName == 'company_admin' ?? false;

    // Lógica de Visibilidad Condicional
    final bool isCompanyRequired = _roleRequiresCompany(_selectedRoleName);
    final bool isBranchRequired = _roleRequiresBranch(_selectedRoleName);

    // Solo mostrar el selector de compañía si el usuario no es Company Admin
    final bool showCompanyDropdown =
        isCompanyRequired && !isCurrentUserCompanyAdmin;

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
              // ------------------------------------------
              // CAMPO DE USERNAME
              // ------------------------------------------
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre de Usuario',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Introduce un nombre de usuario';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 15),

              // ------------------------------------------
              // CAMPO DE PASSWORD
              // ------------------------------------------
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: widget.userToEdit == null
                      ? 'Contraseña (mín 6 caracteres)'
                      : 'Contraseña (mín 6 caracteres - dejar vacío para no cambiar)',
                  border: const OutlineInputBorder(),
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
              // CAMPO DE SELECCIÓN DE ROL (Dropdown)
              // ------------------------------------------
              rolesAsyncValue.when(
                loading: () => const Center(child: LinearProgressIndicator()),
                error: (err, stack) => Text(
                  '❌ Error al cargar roles: ${err.toString().replaceAll('Exception: ', '')}',
                  style: const TextStyle(color: Colors.red),
                ),
                data: (roles) {
                  if (roles.isEmpty) {
                    return const Center(
                      child: Text('⚠️ No se encontraron roles.'),
                    );
                  }

                  return DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Rol',
                      border: OutlineInputBorder(),
                    ),
                    value: _selectedRoleId,
                    hint: const Text('Selecciona un Rol'),
                    items: roles.map((Role role) {
                      return DropdownMenuItem<String>(
                        value: role.id,
                        child: Text(role.name),
                      );
                    }).toList(),
                    onChanged: (String? newRoleId) {
                      if (newRoleId != null) {
                        final selectedRole = roles.firstWhere(
                          (r) => r.id == newRoleId,
                        );
                        setState(() {
                          _selectedRoleId = newRoleId;
                          _selectedRoleName = selectedRole.name;

                          final bool newRoleRequiresCompany =
                              _roleRequiresCompany(_selectedRoleName);

                          if (!newRoleRequiresCompany) {
                            _selectedCompanyId = null;
                            _selectedBranchId = null;
                          } else if (isCurrentUserCompanyAdmin) {
                            // Si es Company Admin y el rol lo requiere, precarga su ID
                            _selectedCompanyId = currentUser!.companyId;
                          } else if (widget.userToEdit == null) {
                            // Si es Global Admin creando uno nuevo, limpia la selección de compañía
                            _selectedCompanyId = null;
                          }

                          _companyIdValidationError = null;
                          _branchIdValidationError = null;
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
              // CAMPOS DE COMPAÑÍA Y SUCURSAL (CONDICIONALES)
              // ------------------------------------------
              if (isCompanyRequired)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    // 1. Dropdown/Info de Compañía
                    if (showCompanyDropdown) // Global Admin ve esto (Dropdown)
                      companiesAsyncValue.when(
                        loading: () =>
                            const Center(child: LinearProgressIndicator()),
                        error: (err, stack) => Text(
                          '❌ Error al cargar compañías: ${err.toString().replaceAll('Exception: ', '')}',
                          style: const TextStyle(color: Colors.red),
                        ),
                        data: (companies) {
                          if (companies.isEmpty) {
                            return const Center(
                              child: Text('⚠️ No hay compañías disponibles.'),
                            );
                          }

                          // Dropdown de Compañía para Global Admin
                          return _buildCompanyDropdown(companies);
                        },
                      )
                    else
                    // Company Admin ve esto (Campo de solo lectura)
                    if (isCurrentUserCompanyAdmin && isCompanyRequired)
                      companiesAsyncValue.when(
                        loading: () =>
                            const Center(child: LinearProgressIndicator()),
                        error: (err, stack) => Text(
                          '❌ Error al cargar su compañía: ${err.toString().replaceAll('Exception: ', '')}',
                          style: const TextStyle(color: Colors.red),
                        ),
                        data: (companies) {
                          final String? currentCompanyId =
                              currentUser?.companyId;

                          // Buscar la compañía por ID. Usamos cast<Company?>() y orElse para seguridad.
                          final Company? userCompany = companies
                              .cast<Company?>()
                              .firstWhere(
                                (c) => c?.id == currentCompanyId,
                                orElse: () => null,
                              );

                          final String companyName =
                              userCompany?.name ?? 'Compañía No Encontrada';

                          // Mostrar el campo de solo lectura
                          return TextFormField(
                            initialValue: companyName,
                            readOnly: true,
                            enabled: false, // Deshabilitado para evitar cambios
                            decoration: const InputDecoration(
                              labelText: 'Compañía (Asignada)',
                              border: OutlineInputBorder(),
                            ),
                            style: const TextStyle(
                              color: Colors.black54,
                            ), // Estilo para indicar solo lectura
                          );
                        },
                      ),

                    // Mostrar error de validación manual de la compañía
                    if (_companyIdValidationError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          '⚠️ ${_companyIdValidationError!}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 13,
                          ),
                        ),
                      ),

                    // 2. Dropdown de Sucursal (Solo para 'cashier' y 'accountant')
                    if (isBranchRequired)
                      branchesAsyncValue.when(
                        loading: () => const Padding(
                          padding: EdgeInsets.only(top: 20.0),
                          child: LinearProgressIndicator(),
                        ),
                        error: (err, stack) => Text(
                          '❌ Error al cargar sucursales: ${err.toString().replaceAll('Exception: ', '')}',
                          style: const TextStyle(color: Colors.red),
                        ),
                        data: (allBranches) {
                          final companyIdToFilter = showCompanyDropdown
                              ? _selectedCompanyId
                              : currentUser?.companyId;

                          if (companyIdToFilter == null) {
                            // Muestra un mensaje si el ID de compañía es nulo (Global Admin debe seleccionar uno)
                            return const Padding(
                              padding: EdgeInsets.only(top: 20.0),
                              child: Text(
                                '⚠️ Selecciona primero una compañía.',
                                style: TextStyle(color: Colors.orange),
                              ),
                            );
                          }

                          // Filtrar sucursales por la compañía seleccionada
                          final availableBranches = allBranches
                              .where((b) => b.companyId == companyIdToFilter)
                              .toList();

                          if (availableBranches.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 20.0),
                              child: Text(
                                '⚠️ La compañía seleccionada no tiene sucursales.',
                                style: TextStyle(color: Colors.orange),
                              ),
                            );
                          }

                          return _buildBranchDropdown(availableBranches);
                        },
                      ),

                    // Mostrar error de validación manual de la Sucursal
                    if (_branchIdValidationError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          '⚠️ ${_branchIdValidationError!}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),

              const SizedBox(height: 30),

              // ------------------------------------------
              // BOTÓN DE GUARDAR
              // ------------------------------------------
              ElevatedButton(
                onPressed: _isLoading ? null : _submitForm,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Text(
                        widget.userToEdit == null
                            ? 'Crear Usuario'
                            : 'Guardar Cambios',
                        style: const TextStyle(fontSize: 16),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ----- FILE: lib\services\api_service.dart -----
// lib/services/api_service.dart
import 'package:dcpos/models/branch.dart';
import 'package:dcpos/models/role.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/token.dart';
import '../models/user.dart';
import '../models/company.dart';
import '../providers/auth_provider.dart';

// Proveedor de solo lectura para la URL base
final apiUrlProvider = Provider<String>(
  (ref) => 'http://localhost:8000/api/v1', // ⚠️ CAMBIA ESTA URL POR TU URL REAL
);

// ---------------------------------------------
// INTERCEPTOR PARA AUTH Y REFRESH (COMPLETO)
// ---------------------------------------------

class AuthInterceptor extends Interceptor {
  final Ref _ref;
  final ApiService apiService;
  bool isRefreshing = false;

  AuthInterceptor(this._ref, this.apiService);

  // Sobreescribe el método onRequest para adjuntar el Access Token
  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // 💡 No añadir token si es la llamada de login o refresh
    if (options.path.contains('/auth/login') ||
        options.path.contains('/auth/refresh')) {
      return handler.next(options);
    }

    final authNotifier = _ref.read(authProvider.notifier);
    final token = authNotifier.accessToken;

    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    return handler.next(options);
  }

  // Sobreescribe el método onError para manejar el 401 Unauthorized
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final authNotifier = _ref.read(authProvider.notifier);
    final refresh = authNotifier.refreshToken;

    // Evitar loop infinito: si la petición fallida ya era la de refresh, o si es un 307
    if (err.requestOptions.path.contains('/auth/refresh') ||
        err.response?.statusCode == 307) {
      print(
        'DEBUG INTERCEPTOR: Se detectó 307 Redirection o fallo en /refresh. Dejando que Dio lo maneje.',
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
// CLASE API SERVICE (CORREGIDA)
// ---------------------------------------------

class ApiService {
  final Dio dio;
  final Ref _ref;
  String get _apiUrl => _ref.read(apiUrlProvider);

  ApiService(this.dio, this._ref) {
    // 💡 Asegúrate de que Dio use la URL base
    dio.options.baseUrl = _apiUrl;
  }

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

  Future<Token> refreshToken(String refreshToken) async {
    try {
      final response = await dio.post(
        '/auth/refresh',
        // El API requiere el Refresh Token en el header como Bearer
        options: Options(headers: {'Authorization': 'Bearer $refreshToken'}),
      );
      return Token.fromJson(response.data);
    } on DioException catch (e) {
      final errorMessage = e.response?.data?['detail'] ?? 'Fallo al refrescar.';
      throw Exception(errorMessage);
    }
  }

  Future<User> fetchMe() async {
    try {
      final response = await dio.get('/auth/me');
      return User.fromJson(response.data);
    } on DioException catch (e) {
      final errorMessage =
          e.response?.data?['detail'] ?? 'Error al obtener usuario.';
      throw Exception(errorMessage);
    }
  }

  // --- Role Endpoints ---
  Future<List<Role>> fetchAllRoles() async {
    try {
      final response = await dio.get('/roles/');

      final responseMap = response.data as Map<String, dynamic>;
      // Usa la clave 'roles' y maneja nulos.
      final List<dynamic> jsonList =
          (responseMap['roles'] as List<dynamic>?) ?? [];

      return jsonList.map((json) => Role.fromJson(json)).toList();
    } on DioException catch (e) {
      throw Exception('Error al obtener roles: ${e.message}');
    }
  }

  // --- User Endpoints ---
  Future<List<User>> fetchAllUsers() async {
    try {
      final response = await dio.get('/users/');

      final responseMap = response.data as Map<String, dynamic>;
      // Se asume la clave 'data' y maneja nulos.
      final List<dynamic> jsonList =
          (responseMap['data'] as List<dynamic>?) ?? [];

      return jsonList.map((json) => User.fromJson(json)).toList();
    } on DioException catch (e) {
      throw Exception('Error al obtener usuarios: ${e.message}');
    }
  }

  Future<User> createUser(Map<String, dynamic> userData) async {
    try {
      // Usa la barra final: /users/
      final response = await dio.post('/users/', data: userData);
      return User.fromJson(response.data);
    } on DioException catch (e) {
      final errorMessage =
          e.response?.data?['detail'] ?? 'Error desconocido al crear usuario.';
      throw Exception(errorMessage);
    }
  }

  Future<User> updateUser(String userId, Map<String, dynamic> userData) async {
    try {
      // Corrección para 404: Añadir la barra final.
      final response = await dio.patch('/users/$userId/', data: userData);
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
      // Se asume que DELETE usa /users/$userId sin barra final.
      await dio.delete('/users/$userId');
    } on DioException catch (e) {
      final errorMessage =
          e.response?.data?['detail'] ??
          'Error desconocido al eliminar usuario.';
      throw Exception(errorMessage);
    }
  }

  // ----------------------------------------------------------------------
  // 💡 MÉTODOS PARA COMPANY
  // ----------------------------------------------------------------------
  Future<List<Company>> fetchCompanies() async {
    try {
      final response = await dio.get('/platform/companies');

      // Se asume que la respuesta es DIRECTAMENTE una List<dynamic>.
      final List<dynamic> jsonList = (response.data as List<dynamic>?) ?? [];

      return jsonList.map((json) => Company.fromJson(json)).toList();
    } on DioException catch (e) {
      throw Exception('Error al obtener compañías: ${e.message}');
    }
  }

  Future<Company> createCompany(Map<String, dynamic> data) async {
    try {
      final response = await dio.post('/platform/companies', data: data);
      return Company.fromJson(response.data);
    } on DioException catch (e) {
      // 💡 CORRECCIÓN EN EL MANEJO DE ERRORES:
      if (e.response != null) {
        // Intentamos obtener el detalle del error del cuerpo de la respuesta
        final errorDetail = e.response?.data is Map
            ? e.response?.data['detail'] as String?
            : null;

        // Si es 403, lanzamos una excepción con el mensaje del backend o uno predefinido.
        if (e.response!.statusCode == 403) {
          throw Exception(
            errorDetail ??
                'Fallo de Autorización (403): Permiso denegado por el servidor.',
          );
        }

        // Para otros errores de respuesta (4xx, 5xx)
        throw Exception(
          errorDetail ?? 'Error HTTP ${e.response!.statusCode}: ${e.message}',
        );
      }
      // Si el error no es de respuesta (ej: error de conexión)
      throw Exception('Error de red al crear compañía: ${e.message}');
    }
  }

  Future<Company> updateCompany(
    String companyId,
    Map<String, dynamic> data,
  ) async {
    final response = await dio.patch(
      '/platform/companies/$companyId',
      data: data,
    );
    return Company.fromJson(response.data);
  }

  Future<void> deleteCompany(String companyId) async {
    await dio.delete('/platform/companies/$companyId');
  }

  // ----------------------------------------------------------------------
  // 💡 MÉTODOS PARA BRANCH (NUEVOS)
  // ----------------------------------------------------------------------
  Future<List<Branch>> fetchBranches(String companyId) async {
    try {
      final response = await dio.get('/platform/companies/$companyId/branches');

      final responseMap = response.data as Map<String, dynamic>;
      // Se asume la clave 'data' y maneja nulos.
      final List<dynamic> jsonList =
          (responseMap['data'] as List<dynamic>?) ?? [];

      return jsonList.map((json) => Branch.fromJson(json)).toList();
    } on DioException catch (e) {
      throw Exception('Error al obtener sucursales: ${e.message}');
    }
  }

  Future<Branch> createBranch(
    String companyId,
    Map<String, dynamic> data,
  ) async {
    final response = await dio.post(
      '/platform/companies/$companyId/branches',
      data: data,
    );
    return Branch.fromJson(response.data);
  }

  Future<Branch> updateBranch(
    String companyId,
    String branchId,
    Map<String, dynamic> data,
  ) async {
    final response = await dio.patch(
      '/platform/companies/$companyId/branches/$branchId',
      data: data,
    );
    return Branch.fromJson(response.data);
  }

  Future<void> deleteBranch(String companyId, String branchId) async {
    await dio.delete('/platform/companies/$companyId/branches/$branchId');
  }
}

// ---------------------------------------------
// PROVEEDOR DE API SERVICE (CORRECTO)
// ---------------------------------------------

final dioInstanceProvider = Provider((ref) => Dio());

final apiServiceProvider = Provider((ref) {
  final dio = ref.watch(dioInstanceProvider);
  final apiService = ApiService(dio, ref);

  // CLAVE: Agregamos el Interceptor solo una vez
  if (dio.interceptors.whereType<AuthInterceptor>().isEmpty) {
    dio.interceptors.add(AuthInterceptor(ref, apiService));
  }
  return apiService;
});


// ----- FILE: lib\services\connectivity_service.dart -----
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


// ----- FILE: lib\services\isar_service.dart -----
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


// ----- FILE: lib\services\sync_service.dart -----
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


