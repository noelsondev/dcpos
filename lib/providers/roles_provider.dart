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
