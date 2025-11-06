import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/auth_provider.dart';
import 'screens/home_screen.dart'; // Pantalla principal
import 'screens/login_screen.dart'; // Pantalla de login
import 'screens/companies_screen.dart'; // ⚠️ Importar la nueva pantalla

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
        // Agregue otras rutas como /branches, /users, etc.
      },
    );
  }
}
