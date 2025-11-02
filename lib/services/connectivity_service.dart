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
