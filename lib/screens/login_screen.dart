// lib/screens/login_screen.dart (COMPLETO Y CORREGIDO)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import 'home_screen.dart';
import '../utils/snackbar_utils.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final usernameController = TextEditingController(text: 'noelson');
  final passwordController = TextEditingController(text: '123456');
  bool _isLoading = false; // Estado de carga local

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void _submitLogin() async {
    final username = usernameController.text;
    final password = passwordController.text;

    FocusScope.of(context).unfocus();

    setState(() => _isLoading = true); // Iniciar carga

    // 💡 AHORA USAMOS EL VALOR DEVUELTO PARA SABER SI HUBO ERROR
    final errorMessage = await ref
        .read(authProvider.notifier)
        .login(username, password);

    setState(() => _isLoading = false); // Finalizar carga

    if (errorMessage != null) {
      // 🚨 Error: El AuthProvider devolvió un mensaje de error
      // Usamos 'Exception(errorMessage)' para que SnackbarUtils.showError lo formatee.
      SnackbarUtils.showError(context, Exception(errorMessage));
    } else {
      // ✅ Éxito: Ya fue manejado en el AuthProvider (state = AsyncValue.data).
      // El ref.listen se encargará de la navegación.
    }
  }

  @override
  Widget build(BuildContext context) {
    // 💡 ref.listen: Se mantiene solo para la NAVEGACIÓN EXITOSA.
    ref.listen<AsyncValue<User?>>(authProvider, (previous, next) {
      // La navegación solo debe ocurrir si el state se actualizó a DATA y hay un User.
      if (next.hasValue && next.value != null && !next.isReloading) {
        // Opcional: Deshabilita la navegación si el login fue en modo offline
        // if (previous?.value?.accessToken == null && next.value!.accessToken == null) return;

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
        SnackbarUtils.showSuccess(
          context,
          'Bienvenido, ${next.value!.username}!',
        );
      }
    });

    // Usamos el estado de carga local para el botón, ya que el AuthProvider ya no lo gestiona.
    // final authState = ref.watch(authProvider); // <-- Ya no es necesario si usamos _isLoading

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
                  // Usamos el estado de carga local
                  onPressed: _isLoading ? null : _submitLogin,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'INICIAR SESIÓN',
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
