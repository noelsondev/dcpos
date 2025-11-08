// lib/screens/branches_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/branch.dart';
import '../models/company.dart'; // Asegúrate de tener este modelo
import '../providers/branches_provider.dart';
import '../providers/companies_provider.dart';

// Generador de UUID para IDs locales temporales
const _uuid = Uuid();

class BranchesScreen extends ConsumerWidget {
  static const routeName = '/branches';

  // ID de la compañía que se quiere ver, pasado desde CompaniesScreen.
  final String? selectedCompanyId;

  const BranchesScreen({super.key, this.selectedCompanyId});

  // Función auxiliar para obtener el ID de la compañía seleccionada o la primera disponible.
  String? _getCompanyIdToFilter(List<Company>? companies) {
    if (companies == null || companies.isEmpty) return null;

    // Encuentra la compañía pasada por argumento o usa la primera.
    final selectedCompany = companies.firstWhere(
      (c) => c.id == selectedCompanyId,
      orElse: () => companies.first,
    );
    return selectedCompany.id;
  }

  // 🚀 FUNCIÓN PARA FORZAR LA RECARGA Y SINCRONIZACIÓN
  void _reloadBranches(WidgetRef ref) {
    // Invalida el proveedor, forzando la recarga de la base de datos local
    // y la sincronización con la API (según la implementación de branchesProvider).
    ref.invalidate(branchesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companiesAsync = ref.watch(companiesProvider);
    final branchesAsync = ref.watch(branchesProvider);

    // Calcular el ID fuera del bloque 'when' para que sea accesible al FAB
    final fabCompanyId = _getCompanyIdToFilter(companiesAsync.value);

    return Scaffold(
      appBar: AppBar(
        title: const Text('🏢 Gestión de Sucursales'),
        actions: [
          // 💡 BOTÓN DE REFRESH AGREGADO
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _reloadBranches(ref),
            tooltip: 'Recargar y sincronizar sucursales',
          ),
        ],
      ),
      body: companiesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) =>
            Center(child: Text('Error al cargar compañías: $err')),
        data: (companies) {
          if (companies.isEmpty) {
            return const Center(
              child: Text(
                'No hay compañías disponibles para gestionar sucursales.',
              ),
            );
          }

          final companyIdToFilter = fabCompanyId!;
          final selectedCompany = companies.firstWhere(
            (c) => c.id == companyIdToFilter,
          );

          return Column(
            children: [
              // Indicador de Compañía Seleccionada
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Sucursales de: ${selectedCompany.name}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Expanded(
                // Lista de Sucursales
                child: branchesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (err, stack) =>
                      Center(child: Text('Error al cargar sucursales: $err')),
                  data: (allBranches) {
                    // 💡 Filtra las sucursales por el ID de la compañía
                    final filteredBranches = allBranches
                        .where((b) => b.companyId == companyIdToFilter)
                        .toList();

                    if (filteredBranches.isEmpty) {
                      return const Center(
                        child: Text(
                          'No hay sucursales registradas para esta compañía.',
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: filteredBranches.length,
                      itemBuilder: (context, index) {
                        final branch = filteredBranches[index];
                        final isMarkedForDeletion = branch.isDeleted;

                        return ListTile(
                          tileColor: isMarkedForDeletion
                              ? Colors.red.shade50
                              : null,
                          title: Text(
                            branch.name,
                            style: TextStyle(
                              decoration: isMarkedForDeletion
                                  ? TextDecoration.lineThrough
                                  : null,
                              fontStyle: isMarkedForDeletion
                                  ? FontStyle.italic
                                  : null,
                            ),
                          ),
                          subtitle: Text(
                            'ID: ${branch.id.length > 8 ? '${branch.id.substring(0, 8)}...' : branch.id} | Dirección: ${branch.address ?? 'Sin dirección'}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Estado de sincronización (lógica de placeholder)
                              if (branch.id.length > 10 &&
                                  !branch.id.startsWith(RegExp(r'[a-f0-9]{8}')))
                                const Tooltip(
                                  message:
                                      'Pendiente de sincronización (ID Local)',
                                  child: Icon(
                                    Icons.cloud_off,
                                    color: Colors.orange,
                                    size: 20,
                                  ),
                                ),
                              const SizedBox(width: 8),

                              // Botón de Eliminación
                              IconButton(
                                icon: Icon(
                                  isMarkedForDeletion
                                      ? Icons.delete_forever_rounded
                                      : Icons.delete,
                                  color: isMarkedForDeletion
                                      ? Colors.red
                                      : null,
                                ),
                                onPressed: isMarkedForDeletion
                                    ? null
                                    : () => _confirmDelete(
                                        context,
                                        ref,
                                        companyIdToFilter,
                                        branch.id,
                                      ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      // El FAB usa fabCompanyId, que está disponible en este scope.
      floatingActionButton: fabCompanyId != null
          ? FloatingActionButton(
              onPressed: () => _showCreateDialog(context, ref, fabCompanyId),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  // Diálogo y funciones auxiliares
  void _showCreateDialog(
    BuildContext context,
    WidgetRef ref,
    String companyId,
  ) {
    final nameController = TextEditingController();
    final addressController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Crear Nueva Sucursal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Nombre *'),
            ),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: 'Dirección'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              if (nameController.text.isEmpty) return;
              final data = BranchCreateLocal(
                companyId: companyId,
                name: nameController.text,
                address: addressController.text.isEmpty
                    ? null
                    : addressController.text,
              );

              ref.read(branchesProvider.notifier).createBranch(data);
              Navigator.of(ctx).pop();
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String companyId,
    String branchId,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Sucursal'),
        content: const Text(
          '¿Está seguro de que desea eliminar esta sucursal? La operación se encolará si está offline.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(branchesProvider.notifier)
                  .deleteBranch(companyId, branchId);
              Navigator.of(ctx).pop();
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
