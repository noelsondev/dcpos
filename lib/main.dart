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
