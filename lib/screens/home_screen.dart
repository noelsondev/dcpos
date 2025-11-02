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
