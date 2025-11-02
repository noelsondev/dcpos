// lib/screens/users_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';
import '../providers/users_provider.dart';
import 'user_form_screen.dart';

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 💡 Observamos el estado del UsersProvider
    final usersAsyncValue = ref.watch(usersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Usuarios'),
        actions: [
          // Botón para recargar (fuerza la sincronización con la API)
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(usersProvider);
            },
          ),
        ],
      ),
      body: usersAsyncValue.when(
        // 1. ESTADO DE CARGA
        loading: () => const Center(child: CircularProgressIndicator()),

        // 2. ESTADO DE ERROR (Muestra el error, pero aún así puede mostrar datos si hay caché local)
        error: (e, st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              // Si el error es solo de conexión, el AsyncNotifier intenta usar datos locales.
              'Error al cargar usuarios: ${e.toString()}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),

        // 3. ESTADO DE DATOS
        data: (users) {
          if (users.isEmpty) {
            return const Center(child: Text('No hay usuarios registrados.'));
          }
          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              return UserListTile(user: user);
            },
          );
        },
      ),
      // Botón flotante para la creación
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const UserFormScreen(userToEdit: null),
          ),
        ),
        child: const Icon(Icons.person_add),
      ),
    );
  }
}

// Widget simple para mostrar la información de un usuario
class UserListTile extends ConsumerWidget {
  final User user;

  const UserListTile({required this.user, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(user.username),
      subtitle: Text(
        // Usamos roleName y roleId para mostrar la información relevante
        'Rol: ${user.roleName} | ID: ${user.id.substring(0, 8)}...',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Botón para Editar
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.blue),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  // Pasamos el usuario para editar
                  builder: (context) => UserFormScreen(userToEdit: user),
                ),
              );
            },
          ),
          // Botón para Eliminar
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => _confirmDelete(context, ref, user),
          ),
        ],
      ),
    );
  }

  // Diálogo de confirmación para eliminar
  void _confirmDelete(BuildContext context, WidgetRef ref, User user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Text(
          '¿Estás seguro de que quieres eliminar al usuario ${user.username}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              // Llama al método deleteUser del Notifier (usa el ID del servidor)
              ref.read(usersProvider.notifier).deleteUser(user.id);
              Navigator.of(ctx).pop();
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
