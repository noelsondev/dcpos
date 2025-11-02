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
