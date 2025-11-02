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
