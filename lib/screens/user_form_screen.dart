// lib/screens/user_form_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

// 🚨 Asegúrate de que estas rutas coincidan con tu proyecto
import '../models/user.dart';
import '../models/role.dart';
import '../models/company.dart'; // 💡 IMPORTACIÓN AÑADIDA
import '../models/branch.dart'; // 💡 IMPORTACIÓN AÑADIDA
import '../providers/users_provider.dart';
import '../providers/roles_provider.dart';
import '../providers/companies_provider.dart'; // 💡 IMPORTACIÓN AÑADIDA
import '../providers/branches_provider.dart'; // 💡 IMPORTACIÓN AÑADIDA

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

  // ESTADOS CLAVE PARA EL MANEJO DEL ROL
  String? _selectedRoleId;
  String? _selectedRoleName;

  // NUEVAS VARIABLES DE ESTADO PARA COMPANY Y BRANCH
  String? _selectedCompanyId;
  String? _selectedBranchId;

  bool _isLoading = false; // 💡 AÑADIDO estado de carga

  @override
  void initState() {
    super.initState();
    if (widget.userToEdit != null) {
      final user = widget.userToEdit!;
      _usernameController.text = user.username;

      // Si estamos editando, precargar los valores del rol y IDs
      _selectedRoleId = user.roleId;
      _selectedRoleName = user.roleName;

      _selectedCompanyId = user.companyId;
      _selectedBranchId = user.branchId;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // -----------------------------------------------------------
  // FUNCIÓN PRINCIPAL DE ENVÍO Y LÓGICA CONDICIONAL DE IDs
  // -----------------------------------------------------------
  void _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRoleId == null || _selectedRoleName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecciona un rol.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final usersNotifier = ref.read(usersProvider.notifier);

    // 💡 1. Lógica de Asignación de IDs Condicionales
    String? finalCompanyId = _selectedCompanyId;
    String? finalBranchId = _selectedBranchId;

    // A. Roles que NO requieren compañía/sucursal (limpiar IDs)
    if (_selectedRoleName != 'company_admin' &&
        _selectedRoleName != 'cashier') {
      finalCompanyId = null;
      finalBranchId = null;
    }
    // B. Rol 'company_admin' requiere compañía, pero NO sucursal
    else if (_selectedRoleName == 'company_admin') {
      finalBranchId = null;
    }
    // C. Rol 'cashier' requiere ambos (finalCompanyId y finalBranchId se mantienen y fueron validados por los Dropdowns)

    try {
      if (widget.userToEdit == null) {
        // --- CREACIÓN (Offline-First) ---
        final newUserId = ref.read(uuidProvider).v4();

        final newUser = UserCreateLocal(
          username: _usernameController.text,
          password: _passwordController.text,
          roleId: _selectedRoleId!,
          roleName: _selectedRoleName!,
          localId: newUserId,
          // 💡 Aplicar IDs condicionales
          companyId: finalCompanyId,
          branchId: finalBranchId,
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
          // 💡 Aplicar IDs condicionales
          companyId: finalCompanyId,
          branchId: finalBranchId,
        );

        await usersNotifier.editUser(updatedUser);
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
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
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // -----------------------------------------------------------
  // WIDGETS AUXILIARES PARA COMPAÑÍA Y SUCURSAL
  // -----------------------------------------------------------

  Widget _buildCompanyDropdown(List<Company> companies) {
    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(
        labelText: 'Compañía (Requerido)',
        border: OutlineInputBorder(),
      ),
      value: _selectedCompanyId,
      items: companies.map((c) {
        return DropdownMenuItem(value: c.id, child: Text(c.name));
      }).toList(),
      onChanged: (String? newValue) {
        setState(() {
          _selectedCompanyId = newValue;
          // Al cambiar la compañía, forzamos a nulo la sucursal
          _selectedBranchId = null;
        });
      },
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Debes seleccionar una compañía.';
        }
        return null;
      },
    );
  }

  Widget _buildBranchDropdown(List<Branch> availableBranches) {
    return Column(
      children: [
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(
            labelText: 'Sucursal (Requerido)',
            border: OutlineInputBorder(),
          ),
          value: _selectedBranchId,
          items: availableBranches.map((b) {
            return DropdownMenuItem(value: b.id, child: Text(b.name));
          }).toList(),
          onChanged: (String? newValue) {
            setState(() {
              _selectedBranchId = newValue;
            });
          },
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Debes seleccionar una sucursal.';
            }
            return null;
          },
        ),
      ],
    );
  }

  // -----------------------------------------------------------
  // BUILD METHOD
  // -----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    // Observar los proveedores de datos
    final rolesAsyncValue = ref.watch(rolesProvider);
    final companiesAsyncValue = ref.watch(companiesProvider); // 💡 Observado
    final branchesAsyncValue = ref.watch(branchesProvider); // 💡 Observado

    // Lógica de Visibilidad Condicional
    final bool isCompanyRequired =
        _selectedRoleName == 'company_admin' || _selectedRoleName == 'cashier';

    final bool isBranchRequired = _selectedRoleName == 'cashier';

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
              // ------------------------------------------
              // CAMPO DE USERNAME
              // ------------------------------------------
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre de Usuario',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Introduce un nombre de usuario';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 15),

              // ------------------------------------------
              // CAMPO DE PASSWORD
              // ------------------------------------------
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: widget.userToEdit == null
                      ? 'Contraseña (mín 6 caracteres)'
                      : 'Contraseña (mín 6 caracteres - dejar vacío para no cambiar)',
                  border: const OutlineInputBorder(),
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
              // CAMPO DE SELECCIÓN DE ROL (Dropdown)
              // ------------------------------------------
              rolesAsyncValue.when(
                loading: () => const Center(child: LinearProgressIndicator()),
                error: (err, stack) => Text(
                  '❌ Error al cargar roles: ${err.toString().replaceAll('Exception: ', '')}',
                  style: const TextStyle(color: Colors.red),
                ),
                data: (roles) {
                  if (roles.isEmpty) {
                    return const Center(
                      child: Text('⚠️ No se encontraron roles.'),
                    );
                  }

                  return DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Rol',
                      border: OutlineInputBorder(),
                    ),
                    value: _selectedRoleId,
                    hint: const Text('Selecciona un Rol'),
                    items: roles.map((Role role) {
                      return DropdownMenuItem<String>(
                        value: role.id,
                        child: Text(role.name),
                      );
                    }).toList(),
                    onChanged: (String? newRoleId) {
                      if (newRoleId != null) {
                        final selectedRole = roles.firstWhere(
                          (r) => r.id == newRoleId,
                        );
                        setState(() {
                          _selectedRoleId = newRoleId;
                          _selectedRoleName = selectedRole.name;

                          // Lógica para limpiar Company/Branch si el nuevo rol no los requiere
                          final bool newRoleRequiresCompany =
                              _selectedRoleName == 'company_admin' ||
                              _selectedRoleName == 'cashier';

                          if (!newRoleRequiresCompany) {
                            _selectedCompanyId = null;
                            _selectedBranchId = null;
                          }
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
              // 💡 CAMPOS DE COMPAÑÍA Y SUCURSAL (CONDICIONALES)
              // ------------------------------------------
              if (isCompanyRequired)
                Column(
                  children: [
                    const SizedBox(height: 20),
                    companiesAsyncValue.when(
                      loading: () =>
                          const Center(child: LinearProgressIndicator()),
                      error: (err, stack) => Text(
                        '❌ Error al cargar compañías: ${err.toString().replaceAll('Exception: ', '')}',
                        style: const TextStyle(color: Colors.red),
                      ),
                      data: (companies) {
                        if (companies.isEmpty) {
                          return const Center(
                            child: Text('⚠️ No hay compañías disponibles.'),
                          );
                        }

                        // 1. Dropdown de Compañía
                        return _buildCompanyDropdown(companies);
                      },
                    ),

                    // 2. Dropdown de Sucursal (Solo para 'cashier' y si ya seleccionó compañía)
                    if (isBranchRequired && _selectedCompanyId != null)
                      branchesAsyncValue.when(
                        loading: () => const Padding(
                          padding: EdgeInsets.only(top: 20.0),
                          child: LinearProgressIndicator(),
                        ),
                        error: (err, stack) => Text(
                          '❌ Error al cargar sucursales: ${err.toString().replaceAll('Exception: ', '')}',
                          style: const TextStyle(color: Colors.red),
                        ),
                        data: (allBranches) {
                          // Filtrar sucursales por la compañía seleccionada
                          final availableBranches = allBranches
                              .where((b) => b.companyId == _selectedCompanyId)
                              .toList();

                          if (availableBranches.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 20.0),
                              child: Text(
                                '⚠️ La compañía seleccionada no tiene sucursales.',
                                style: TextStyle(color: Colors.orange),
                              ),
                            );
                          }

                          return _buildBranchDropdown(availableBranches);
                        },
                      ),
                  ],
                ),

              const SizedBox(height: 30),

              // ------------------------------------------
              // BOTÓN DE GUARDAR
              // ------------------------------------------
              ElevatedButton(
                onPressed: _isLoading ? null : _submitForm,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Text(
                        widget.userToEdit == null
                            ? 'Crear Usuario'
                            : 'Guardar Cambios',
                        style: const TextStyle(fontSize: 16),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
