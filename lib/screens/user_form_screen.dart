// lib/screens/user_form_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

// 🚨 Asegúrate de que estas rutas coincidan con tu proyecto
import '../models/user.dart'; // Contiene UserCreateLocal, UserUpdateLocal
import '../models/role.dart';
import '../models/company.dart';
import '../models/branch.dart';
import '../providers/users_provider.dart';
import '../providers/roles_provider.dart';
import '../providers/companies_provider.dart';
import '../providers/branches_provider.dart';
import '../providers/auth_provider.dart';

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

  bool _isLoading = false;

  // VARIABLE DE ESTADO PARA EL ERROR DE VALIDACIÓN DE COMPAÑÍA
  String? _companyIdValidationError;
  // VARIABLE DE ESTADO PARA EL ERROR DE SUCURSAL
  String? _branchIdValidationError;

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

  // Función auxiliar para determinar si un rol requiere compañía
  bool _roleRequiresCompany(String? roleName) {
    if (roleName == null) return false;
    return roleName == 'company_admin' ||
        roleName == 'cashier' ||
        roleName == 'accountant';
  }

  // Función auxiliar para determinar si un rol requiere sucursal
  bool _roleRequiresBranch(String? roleName) {
    if (roleName == null) return false;
    return roleName == 'cashier' || roleName == 'accountant';
  }

  // -----------------------------------------------------------
  // FUNCIÓN PRINCIPAL DE ENVÍO Y LÓGICA CONDICIONAL DE IDs
  // -----------------------------------------------------------
  void _submitForm() async {
    // 1. Validaciones de formulario (nativas)
    if (!_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = false;
        _companyIdValidationError = null;
        _branchIdValidationError = null;
      });
      return;
    }
    if (_selectedRoleId == null || _selectedRoleName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecciona un rol.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      // Limpiar errores personalizados antes de la validación
      _companyIdValidationError = null;
      _branchIdValidationError = null;
    });

    // OBTENER EL USUARIO ACTUAL
    final currentUserAsync = ref.read(authProvider);
    final currentUser = currentUserAsync.value;

    if (currentUser == null) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Error de autenticación: No se pudo obtener el usuario actual.',
          ),
        ),
      );
      return;
    }

    final usersNotifier = ref.read(usersProvider.notifier);

    final bool isCurrentUserCompanyAdmin =
        currentUser.roleName == 'company_admin';
    final bool isCompanyRequired = _roleRequiresCompany(_selectedRoleName);
    final bool isBranchRequired = _roleRequiresBranch(_selectedRoleName);

    // Lógica de Asignación de IDs Condicionales (Base de la validación)
    String? finalCompanyId = _selectedCompanyId;
    String? finalBranchId = _selectedBranchId;

    // ------------------------------------------------------
    // 🚨 VALIDACIÓN LOCAL PARA COMPANY_ADMIN (y otros roles requeridos)
    // ------------------------------------------------------
    if (isCompanyRequired) {
      // Si el usuario logueado es Company Admin
      if (isCurrentUserCompanyAdmin) {
        // 1. Validación de Compañía (Si intenta asignar una que NO es la suya)
        if (finalCompanyId != null && finalCompanyId != currentUser.companyId) {
          setState(() {
            _companyIdValidationError =
                'Acceso Denegado: Solo puedes asignar usuarios a tu propia compañía.';
            _isLoading = false;
          });
          return;
        }

        // Forzamos su Company ID para la operación
        finalCompanyId = currentUser.companyId;
      } else {
        // Si el usuario logueado NO es Company Admin (Global Admin)

        if (finalCompanyId == null) {
          setState(() {
            _companyIdValidationError =
                'La compañía es requerida para este rol.';
            _isLoading = false;
          });
          return;
        }
      }

      // 2. VALIDACIÓN MANUAL PARA SUCURSAL SI ES CAJERO O CONTADOR
      if (isBranchRequired) {
        if (finalBranchId == null || finalBranchId.isEmpty) {
          setState(() {
            _branchIdValidationError =
                'La sucursal es requerida para el rol ${_selectedRoleName?.toUpperCase()}.';
            _isLoading = false;
          });
          return;
        }
      }
    }
    // ------------------------------------------------------

    // A. Roles que NO requieren compañía/sucursal (limpiar IDs)
    if (!isCompanyRequired) {
      finalCompanyId = null;
      finalBranchId = null;
    }
    // B. Rol 'company_admin' requiere compañía, pero NO sucursal
    else if (_selectedRoleName == 'company_admin') {
      finalBranchId = null;
    }
    // C. Rol 'cashier' o 'accountant' requieren ambos (finalCompanyId y finalBranchId se mantienen y fueron validados)

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
          companyId: finalCompanyId,
          branchId: finalBranchId,
        );

        await usersNotifier.editUser(updatedUser);
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // Manejo de Errores de API/Riverpod (genéricos)
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
            // Este validador nativo se mantiene como fallback para Global Admin
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
    final companiesAsyncValue = ref.watch(companiesProvider);
    final branchesAsyncValue = ref.watch(branchesProvider);

    // OBTENER EL USUARIO ACTUAL
    final currentUserAsync = ref.watch(authProvider);
    final currentUser = currentUserAsync.value;

    final bool isCurrentUserCompanyAdmin =
        currentUser?.roleName == 'company_admin' ?? false;

    // Lógica de Visibilidad Condicional
    final bool isCompanyRequired = _roleRequiresCompany(_selectedRoleName);
    final bool isBranchRequired = _roleRequiresBranch(_selectedRoleName);

    // Solo mostrar el selector de compañía si el usuario no es Company Admin
    final bool showCompanyDropdown =
        isCompanyRequired && !isCurrentUserCompanyAdmin;

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

                          final bool newRoleRequiresCompany =
                              _roleRequiresCompany(_selectedRoleName);

                          if (!newRoleRequiresCompany) {
                            _selectedCompanyId = null;
                            _selectedBranchId = null;
                          } else if (isCurrentUserCompanyAdmin) {
                            // Si es Company Admin y el rol lo requiere, precarga su ID
                            _selectedCompanyId = currentUser!.companyId;
                          } else if (widget.userToEdit == null) {
                            // Si es Global Admin creando uno nuevo, limpia la selección de compañía
                            _selectedCompanyId = null;
                          }

                          _companyIdValidationError = null;
                          _branchIdValidationError = null;
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
              // CAMPOS DE COMPAÑÍA Y SUCURSAL (CONDICIONALES)
              // ------------------------------------------
              if (isCompanyRequired)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    // 1. Dropdown/Info de Compañía
                    if (showCompanyDropdown) // Global Admin ve esto (Dropdown)
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

                          // Dropdown de Compañía para Global Admin
                          return _buildCompanyDropdown(companies);
                        },
                      )
                    else
                    // Company Admin ve esto (Campo de solo lectura)
                    if (isCurrentUserCompanyAdmin && isCompanyRequired)
                      companiesAsyncValue.when(
                        loading: () =>
                            const Center(child: LinearProgressIndicator()),
                        error: (err, stack) => Text(
                          '❌ Error al cargar su compañía: ${err.toString().replaceAll('Exception: ', '')}',
                          style: const TextStyle(color: Colors.red),
                        ),
                        data: (companies) {
                          final String? currentCompanyId =
                              currentUser?.companyId;

                          // Buscar la compañía por ID. Usamos cast<Company?>() y orElse para seguridad.
                          final Company? userCompany = companies
                              .cast<Company?>()
                              .firstWhere(
                                (c) => c?.id == currentCompanyId,
                                orElse: () => null,
                              );

                          final String companyName =
                              userCompany?.name ?? 'Compañía No Encontrada';

                          // Mostrar el campo de solo lectura
                          return TextFormField(
                            initialValue: companyName,
                            readOnly: true,
                            enabled: false, // Deshabilitado para evitar cambios
                            decoration: const InputDecoration(
                              labelText: 'Compañía (Asignada)',
                              border: OutlineInputBorder(),
                            ),
                            style: const TextStyle(
                              color: Colors.black54,
                            ), // Estilo para indicar solo lectura
                          );
                        },
                      ),

                    // Mostrar error de validación manual de la compañía
                    if (_companyIdValidationError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          '⚠️ ${_companyIdValidationError!}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 13,
                          ),
                        ),
                      ),

                    // 2. Dropdown de Sucursal (Solo para 'cashier' y 'accountant')
                    if (isBranchRequired)
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
                          final companyIdToFilter = showCompanyDropdown
                              ? _selectedCompanyId
                              : currentUser?.companyId;

                          if (companyIdToFilter == null) {
                            // Muestra un mensaje si el ID de compañía es nulo (Global Admin debe seleccionar uno)
                            return const Padding(
                              padding: EdgeInsets.only(top: 20.0),
                              child: Text(
                                '⚠️ Selecciona primero una compañía.',
                                style: TextStyle(color: Colors.orange),
                              ),
                            );
                          }

                          // Filtrar sucursales por la compañía seleccionada
                          final availableBranches = allBranches
                              .where((b) => b.companyId == companyIdToFilter)
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

                    // Mostrar error de validación manual de la Sucursal
                    if (_branchIdValidationError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          '⚠️ ${_branchIdValidationError!}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 13,
                          ),
                        ),
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
