// lib/screens/user_form_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/user.dart';
import '../models/role.dart';
import '../providers/users_provider.dart';
import '../providers/roles_provider.dart';
import '../utils/snackbar_utils.dart';

// Proveedor de Uuid para IDs locales temporales
final uuidProvider = Provider((ref) => const Uuid());

class UserFormScreen extends ConsumerStatefulWidget {
  final User? userToEdit;
  const UserFormScreen({super.key, this.userToEdit});

  @override
  ConsumerState<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends ConsumerState<UserFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  String? _selectedRoleId;
  String? _selectedRoleName;
  String? _companyId;
  String? _branchId;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();

    if (widget.userToEdit != null) {
      final user = widget.userToEdit!;
      _usernameController.text = user.username;
      _companyId = user.companyId;
      _branchId = user.branchId;

      _selectedRoleId = user.roleId;
      _selectedRoleName = user.roleName;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRoleId == null || _selectedRoleName == null) {
      SnackbarUtils.showError(
        context,
        Exception('Por favor, selecciona un rol.'),
      );
      return;
    }

    FocusScope.of(context).unfocus();

    final usersNotifier = ref.read(usersProvider.notifier);
    try {
      if (widget.userToEdit == null) {
        // --- CREACIÓN ---
        final newUserId = ref.read(uuidProvider).v4();
        final newUser = UserCreateLocal(
          username: _usernameController.text,
          password: _passwordController.text,
          roleId: _selectedRoleId!,
          roleName: _selectedRoleName!,
          companyId: _companyId,
          branchId: _branchId,
          localId: newUserId,
        );
        await usersNotifier.createUser(newUser);
      } else {
        // --- ACTUALIZACIÓN ---
        final updatedUser = UserUpdateLocal(
          id: widget.userToEdit!.id,
          username: _usernameController.text,
          password: _passwordController.text.isEmpty
              ? null
              : _passwordController.text,
          roleId: _selectedRoleId,
          roleName: _selectedRoleName,
          companyId: _companyId,
          branchId: _branchId,
        );
        await usersNotifier.editUser(updatedUser);
      }

      Navigator.of(context).pop(true);
      SnackbarUtils.showSuccess(
        context,
        'Usuario ${widget.userToEdit == null ? 'creado' : 'actualizado'} exitosamente.',
      );
    } catch (e) {
      // ✅ Correcto: Llama a la función void para mostrar el Snackbar
      SnackbarUtils.showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rolesState = ref.watch(rolesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.userToEdit == null ? 'Crear Usuario' : 'Editar Usuario',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre de Usuario',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor, introduce un nombre de usuario';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: widget.userToEdit == null
                      ? 'Contraseña'
                      : 'Contraseña (Dejar vacío para no cambiar)',
                ),
                obscureText: true,
                validator: (value) {
                  if (widget.userToEdit == null &&
                      (value == null || value.isEmpty)) {
                    return 'Por favor, introduce una contraseña';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              // Selector de Rol
              rolesState.when(
                data: (roles) {
                  return DropdownButtonFormField<String>(
                    value: _selectedRoleId,
                    decoration: const InputDecoration(
                      labelText: 'Rol',
                      border: OutlineInputBorder(),
                    ),
                    hint: const Text('Selecciona un rol'),
                    items: roles.map((role) {
                      return DropdownMenuItem<String>(
                        value: role.id,
                        child: Text(role.name),
                      );
                    }).toList(),
                    onChanged: (roleId) {
                      setState(() {
                        _selectedRoleId = roleId;
                        _selectedRoleName = roles
                            .firstWhere((r) => r.id == roleId)
                            .name;
                      });
                    },
                    validator: (value) {
                      if (value == null) {
                        return 'El rol es obligatorio';
                      }
                      return null;
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Text(
                  'Error al cargar roles: ${SnackbarUtils.getErrorMessage(e)}',
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _submitForm,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    widget.userToEdit == null
                        ? 'CREAR USUARIO'
                        : 'GUARDAR CAMBIOS',
                    style: const TextStyle(fontSize: 18),
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
