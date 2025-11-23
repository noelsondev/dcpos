// lib/services/api_service.dart

import 'package:dcpos/models/branch.dart';
import 'package:dcpos/models/role.dart';
import 'package:dcpos/models/token.dart';
import 'package:dcpos/models/user.dart';
import 'package:dcpos/models/company.dart';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';

// URL base del backend
final apiUrlProvider = Provider<String>(
  (ref) => 'http://localhost:8000/api/v1',
);

///
/// ================================
///     AUTH INTERCEPTOR
/// ================================
///

class AuthInterceptor extends Interceptor {
  final Ref ref;
  final ApiService api;

  AuthInterceptor(this.ref, this.api);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = ref.read(authProvider.notifier).accessToken;

    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    super.onRequest(options, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // Solo intentamos refresh si hay 401
    if (err.response?.statusCode == 401) {
      final refreshToken = ref.read(authProvider.notifier).refreshToken;

      if (refreshToken == null) {
        handler.next(err);
        return;
      }

      try {
        // Refrescamos token
        final newToken = await api.refreshToken(refreshToken);

        // Lo guardamos en AuthNotifier + Isar
        ref.read(authProvider.notifier).updateToken(newToken);

        // Reintentamos la petición original
        final retryResponse = await api.dio.fetch(err.requestOptions);

        return handler.resolve(retryResponse);
      } catch (e) {
        handler.next(err);
        return;
      }
    }

    handler.next(err);
  }
}

///
/// ================================
///       API SERVICE
/// ================================
///

class ApiService {
  final Dio dio;
  final Ref _ref;

  String get _baseUrl => _ref.read(apiUrlProvider);

  ApiService(this.dio, this._ref) {
    dio.options.baseUrl = _baseUrl;

    // Evitar duplicar interceptores
    if (dio.interceptors.whereType<AuthInterceptor>().isEmpty) {
      dio.interceptors.add(AuthInterceptor(_ref, this));
    }
  }

  ///
  /// AUTH
  ///

  Future<Token> login(String username, String password) async {
    final response = await dio.post(
      '/auth/login',
      data: {'username': username, 'password': password},
    );

    return Token.fromJson(response.data);
  }

  Future<Token> refreshToken(String refreshToken) async {
    final response = await dio.post(
      '/auth/refresh',
      options: Options(headers: {'Authorization': 'Bearer $refreshToken'}),
    );

    return Token.fromJson(response.data);
  }

  Future<User> fetchMe() async {
    final response = await dio.get('/auth/me');
    return User.fromJson(response.data);
  }

  ///
  /// ROLES
  ///

  Future<List<Role>> fetchAllRoles() async {
    final response = await dio.get('/roles/');

    final responseMap = response.data as Map<String, dynamic>;
    final List<dynamic> items = responseMap['roles'] ?? [];

    return items.map((e) => Role.fromJson(e)).toList();
  }

  ///
  /// USERS
  ///

  Future<List<User>> fetchAllUsers() async {
    final response = await dio.get('/users/');

    final responseMap = response.data as Map<String, dynamic>;
    final List<dynamic> items = responseMap['data'] ?? [];

    return items.map((e) => User.fromJson(e)).toList();
  }

  Future<User> createUser(Map<String, dynamic> data) async {
    final response = await dio.post('/users/', data: data);
    return User.fromJson(response.data);
  }

  Future<User> updateUser(String userId, Map<String, dynamic> data) async {
    final response = await dio.patch('/users/$userId', data: data);
    return User.fromJson(response.data);
  }

  Future<void> deleteUser(String userId) async {
    await dio.delete('/users/$userId');
  }

  /// Verifica si existe el usuario en backend
  Future<bool> userExists(String userId) async {
    try {
      final response = await dio.get('/users/$userId');
      return response.statusCode == 200;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return false;
      rethrow;
    }
  }

  ///
  /// COMPANIES
  ///

  Future<List<Company>> fetchCompanies() async {
    final response = await dio.get('/platform/companies');

    final List<dynamic> items = response.data is List ? response.data : [];

    return items.map((e) => Company.fromJson(e)).toList();
  }

  Future<Company> createCompany(Map<String, dynamic> data) async {
    final response = await dio.post('/platform/companies', data: data);
    return Company.fromJson(response.data);
  }

  Future<Company> updateCompany(String id, Map<String, dynamic> data) async {
    final response = await dio.patch('/platform/companies/$id', data: data);
    return Company.fromJson(response.data);
  }

  Future<void> deleteCompany(String id) async {
    await dio.delete('/platform/companies/$id');
  }

  ///
  /// BRANCHES
  ///

  Future<List<Branch>> fetchBranches(String companyId) async {
    final response = await dio.get('/platform/companies/$companyId/branches');

    final List<dynamic> items = response.data is List ? response.data : [];

    return items.map((e) => Branch.fromJson(e)).toList();
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

///
/// ================================
///      PROVIDERS
/// ================================
///

final dioInstanceProvider = Provider((ref) => Dio());

final apiServiceProvider = Provider<ApiService>((ref) {
  final dio = ref.watch(dioInstanceProvider);
  return ApiService(dio, ref);
});
