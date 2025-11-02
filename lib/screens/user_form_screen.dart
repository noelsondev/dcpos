// lib/screens/user_form_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user.dart';
import '../models/role.dart';
import '../providers/users_provider.dart';
import '../providers/roles_provider.dart'; // Importar el nuevo provider de roles
import 'package:uuid/uuid.dart'; // Necesario para generar localId en modo offline

// Proveedor para generar IDs (usamos Riverpod para consistency)
final uuidProvider = Provider((ref) => const Uuid());

// Definición del Widget
class UserFormScreen extends ConsumerStatefulWidget {
  final User? userToEdit;

  const UserFormScreen({super.key, this.userToEdit});

  @override
  ConsumerState<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends ConsumerState<UserFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  // 💡 ESTADOS CLAVE PARA EL MANEJO DEL ROL
  String? _selectedRoleId;
  String? _selectedRoleName;

  @override
  void initState() {
    super.initState();
    if (widget.userToEdit != null) {
      final user = widget.userToEdit!;
      _usernameController.text = user.username;

      // Si estamos editando, precargar los valores del rol existente
      _selectedRoleId = user.roleId;
      _selectedRoleName = user.roleName;

      // Nota: Nunca precargamos la contraseña por seguridad
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
      // Validación extra si el dropdown no fue tocado
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecciona un rol.')),
      );
      return;
    }

    final usersNotifier = ref.read(usersProvider.notifier);

    try {
      // 💡 Lógica de Creación/Actualización envuelta en try-catch
      if (widget.userToEdit == null) {
        // --- CREACIÓN (Offline-First) ---
        final newUserId = ref.read(uuidProvider).v4(); // Generar un localId

        final newUser = UserCreateLocal(
          username: _usernameController.text,
          password: _passwordController.text,
          roleId: _selectedRoleId!,
          roleName: _selectedRoleName!, // Usamos el nombre REAL
          localId: newUserId,
          // Valores de empresa/sucursal deben venir de AuthProvider o un Provider de configuración
          companyId: "temp-company-uuid",
          branchId: "temp-branch-uuid",
          isActive: true,
        );

        await usersNotifier.createUser(newUser);
      } else {
        // --- EDICIÓN (Offline-First) ---
        final updatedUser = UserUpdateLocal(
          id: widget.userToEdit!.id,
          username: _usernameController.text,
          password: _passwordController.text.isNotEmpty
              ? _passwordController.text
              : null,
          roleId: _selectedRoleId,
          roleName: _selectedRoleName,
        );

        await usersNotifier.editUser(updatedUser);
      }

      // Si no hubo excepción, la operación fue exitosa
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // 🛑 CAPTURA DE ERROR: Muestra el SnackBar en rojo y NO cierra la pantalla
      if (mounted) {
        // Limpiamos el mensaje de la excepción de Dart si es necesario
        final errorMessage = e.toString().replaceAll('Exception: ', '');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error de Operación: $errorMessage',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 💡 Observar el proveedor de roles (clave para el Dropdown)
    final rolesAsyncValue = ref.watch(rolesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.userToEdit == null ? 'Crear Usuario' : 'Editar Usuario',
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre de Usuario',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Introduce un nombre de usuario';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Contraseña (mín 6 caracteres)',
                ),
                obscureText: true,
                validator: (value) {
                  if (widget.userToEdit == null &&
                      (value == null || value.isEmpty)) {
                    return 'Introduce una contraseña para el nuevo usuario';
                  }
                  if (value != null && value.isNotEmpty && value.length < 6) {
                    return 'La contraseña debe tener al menos 6 caracteres';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // ------------------------------------------
              // 💡 CAMPO DE SELECCIÓN DE ROL (Dropdown)
              // ------------------------------------------
              rolesAsyncValue.when(
                // Estado 1: Cargando (Muestra un indicador)
                loading: () => const Center(child: LinearProgressIndicator()),

                // Estado 2: Error (Muestra la causa del fallo)
                error: (err, stack) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '❌ Error al cargar roles:',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${err.toString().replaceAll('Exception: ', '')}',
                      style: const TextStyle(color: Colors.red),
                    ),
                    const Text(
                      'Revisa la conexión y el ApiService.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),

                // Estado 3: Data (Maneja la lista de roles)
                data: (roles) {
                  // 💡 DIAGNÓSTICO CLAVE: ¿La lista está vacía?
                  if (roles.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          '⚠️ No se encontraron roles. La lista devuelta por el API está vacía.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.orange,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    );
                  }

                  // Asegurarse de que el rol actual exista en la lista si estamos editando
                  // y que _selectedRoleId se inicialice si el userToEdit no lo hizo correctamente.
                  if (widget.userToEdit != null && _selectedRoleId == null) {
                    final existingRole = roles.firstWhere(
                      (r) => r.id == widget.userToEdit!.roleId,
                      orElse: () => roles
                          .first, // Fallback si el rol no se encuentra (debe ser raro)
                    );
                    // Solamente hacemos setState si el rol no estaba inicializado correctamente
                    // para evitar un 'setState' innecesario después del 'initState'.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_selectedRoleId == null) {
                        setState(() {
                          _selectedRoleId = existingRole.id;
                          _selectedRoleName = existingRole.name;
                        });
                      }
                    });
                  }

                  return DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Rol',
                      border: OutlineInputBorder(),
                    ),
                    value: _selectedRoleId, // Usamos el ID como valor
                    hint: const Text('Selecciona un Rol'),
                    items: roles.map((Role role) {
                      return DropdownMenuItem<String>(
                        value: role.id, // Valor real: el UUID del rol
                        child: Text(role.name), // Display: el nombre del rol
                      );
                    }).toList(),
                    onChanged: (String? newRoleId) {
                      if (newRoleId != null) {
                        final selectedRole = roles.firstWhere(
                          (r) => r.id == newRoleId,
                        );
                        setState(() {
                          // 💡 CLAVE: Guardamos tanto el ID como el Nombre REAL
                          _selectedRoleId = newRoleId;
                          _selectedRoleName = selectedRole.name;
                        });
                      }
                    },
                    validator: (value) {
                      if (value == null) {
                        return 'Debes seleccionar el rol del usuario.';
                      }
                      return null;
                    },
                  );
                },
              ),

              // ------------------------------------------
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _submitForm,
                child: Text(
                  widget.userToEdit == null
                      ? 'Crear Usuario'
                      : 'Guardar Cambios',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
