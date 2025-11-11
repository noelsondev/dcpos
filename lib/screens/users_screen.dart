// lib/screens/users_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';
import '../providers/users_provider.dart';
import '../utils/snackbar_utils.dart';
import 'user_form_screen.dart';

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  // Navegación al formulario para CREAR
  void _openCreateForm(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const UserFormScreen()));
  }

  // Navegación al formulario para EDITAR
  void _openEditForm(BuildContext context, User user) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => UserFormScreen(userToEdit: user)),
    );
  }

  // Función para ELIMINAR un usuario
  void _deleteUser(BuildContext context, WidgetRef ref, String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: const Text(
          '¿Está seguro de que desea eliminar este usuario? Esta acción se encolará y sincronizará.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(usersProvider.notifier).deleteUser(userId);
        SnackbarUtils.showSuccess(context, 'Usuario eliminado y encolado.');
      } catch (e) {
        // Llama a la función void para mostrar el Snackbar
        SnackbarUtils.showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsyncValue = ref.watch(usersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Usuarios'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Forzar recarga (y proceso de cola)
              ref.invalidate(usersProvider);
            },
          ),
        ],
      ),
      body: usersAsyncValue.when(
        data: (users) {
          if (users.isEmpty) {
            return const Center(child: Text('No hay usuarios registrados.'));
          }
          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];

              // Lógica para visualizar el estado pendiente
              final isPendingCreate = user.id.length > 30 && user.isPendingSync;
              final isPendingDelete = user.isDeleted && user.isPendingSync;
              final isPendingUpdate =
                  !isPendingCreate && !isPendingDelete && user.isPendingSync;

              return Dismissible(
                key: ValueKey(user.id),
                direction: DismissDirection.endToStart,
                onDismissed: (direction) {
                  // Llama a la función de eliminación
                  _deleteUser(context, ref, user.id);
                },
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                child: ListTile(
                  title: Text(
                    user.username,
                    style: TextStyle(
                      fontStyle: user.isPendingSync ? FontStyle.italic : null,
                      color: isPendingDelete ? Colors.grey : Colors.black,
                      decoration: isPendingDelete
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                  subtitle: Text(
                    'Rol: ${user.roleName} | ID: ${user.id.substring(0, 8)}...',
                  ),
                  trailing: Text(
                    isPendingCreate
                        ? 'CREANDO...'
                        : (isPendingDelete
                              ? 'BORRANDO...'
                              : (isPendingUpdate
                                    ? 'ACTUALIZANDO...'
                                    : 'Sincronizado')),
                    style: TextStyle(
                      color: user.isPendingSync ? Colors.orange : Colors.green,
                      fontWeight: user.isPendingSync
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  onTap: () => _openEditForm(context, user),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 50),
                const SizedBox(height: 10),
                Text(
                  // 🟢 CORRECCIÓN: Usar getErrorMessage para obtener el String
                  SnackbarUtils.getErrorMessage(e),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openCreateForm(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
