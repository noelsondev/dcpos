// lib/screens/home_screen.dart

import 'package:dcpos/screens/branches_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import 'users_screen.dart';
import 'companies_screen.dart';
import 'login_screen.dart'; // 💡 Asegúrate de importar LoginScreen

// 💡 CAMBIO: Volvemos a ConsumerWidget, eliminando el error de ref.listen en initState
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  // Función para realizar la prueba del Refresh Token
  void _testRefreshToken(BuildContext context, WidgetRef ref) async {
    final apiService = ref.read(apiServiceProvider);

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
            onPressed: () async {
              // 1. Llamar al método logout del Notifier (actualiza el estado)
              await ref.read(authProvider.notifier).logout();

              // 2. 🚀 CORRECCIÓN: Navegación explícita al LoginScreen, limpiando el stack
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (Route<dynamic> route) =>
                    false, // Elimina todas las rutas anteriores
              );
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

            // 3. BOTÓN PARA NAVEGAR A GESTIÓN DE SUCURSALES 🏛️
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
