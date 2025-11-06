// lib/services/api_service.dart
import 'package:dcpos/models/branch.dart'; // 💡 NUEVO
import 'package:dcpos/models/role.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/token.dart';
import '../models/user.dart';
import '../models/company.dart';
import '../providers/auth_provider.dart'; // Para leer el token

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
      final List<dynamic> jsonList = response.data;
      return jsonList.map((json) => Role.fromJson(json)).toList();
    } on DioException catch (e) {
      throw Exception('Error al obtener roles: ${e.message}');
    }
  }

  // --- User Endpoints ---
  Future<List<User>> fetchAllUsers() async {
    try {
      final response = await dio.get('/users/');
      final List<dynamic> jsonList = response.data;
      return jsonList.map((json) => User.fromJson(json)).toList();
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
  // 💡 MÉTODOS PARA COMPANY
  // ----------------------------------------------------------------------
  Future<List<Company>> fetchCompanies() async {
    final response = await dio.get('/platform/companies');
    final List<dynamic> jsonList = response.data;
    return jsonList.map((json) => Company.fromJson(json)).toList();
  }

  Future<Company> createCompany(Map<String, dynamic> data) async {
    final response = await dio.post(
      '/platform/companies',
      data: data, // ✅ CORRECCIÓN: Asegurar que los datos se envían
    );
    return Company.fromJson(response.data);
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
    final response = await dio.get('/platform/companies/$companyId/branches');
    final List<dynamic> jsonList = response.data;
    return jsonList.map((json) => Branch.fromJson(json)).toList();
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
