//lib/screens/companies_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/companies_provider.dart';
import 'company_form_screen.dart';
import 'branches_screen.dart'; // 💡 Importación necesaria

class CompaniesScreen extends ConsumerWidget {
  const CompaniesScreen({super.key});

  // Función para forzar la recarga de datos
  void _reloadCompanies(WidgetRef ref) {
    // 🚀 Llamada para invalidar y reconstruir el AsyncNotifier
    ref.invalidate(companiesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companiesAsyncValue = ref.watch(companiesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Compañías'),
        actions: [
          // 🚀 BOTÓN DE RECARGA AGREGADO A LA APPBAR
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _reloadCompanies(ref),
            tooltip: 'Recargar datos y sincronizar',
          ),
        ],
      ),
      // El botón FAB solo debe aparecer si la lógica del Notifier/API permite crear (Global Admin)
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const CompanyFormScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
      body: companiesAsyncValue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Text(
            // Muestra el error de forma limpia
            'Error al cargar: ${err.toString().replaceAll('Exception: ', '')}',
            style: const TextStyle(color: Colors.red),
          ),
        ),
        data: (companies) {
          if (companies.isEmpty) {
            // Mensaje más contextualizado si no hay compañías
            return const Center(
              child: Text('No hay compañías disponibles para su perfil.'),
            );
          }

          // --- Listado de Compañías ---
          return ListView.builder(
            itemCount: companies.length,
            itemBuilder: (context, index) {
              final company = companies[index];

              // 💡 Acción Principal: Navegar a la gestión de Sucursales
              return ListTile(
                title: Text(company.name),
                subtitle: Text('Slug: ${company.slug}'),
                onTap: () {
                  // Navegar a BranchesScreen
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) =>
                          BranchesScreen(selectedCompanyId: company.id),
                    ),
                  );
                },
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Botón de Edición
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) =>
                                CompanyFormScreen(companyToEdit: company),
                          ),
                        );
                      },
                    ),
                    // Botón de Eliminación (Lógica de borrado en el Notifier)
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        // Mostrar confirmación antes de eliminar
                        _showDeleteConfirmation(
                          context,
                          ref,
                          company.id,
                          company.name,
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // Función de utilidad para mostrar diálogo de confirmación (Mejora UX)
  void _showDeleteConfirmation(
    BuildContext context,
    WidgetRef ref,
    String companyId,
    String companyName,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Text(
          '¿Está seguro de que desea eliminar la compañía "$companyName"? Esta acción es irreversible y eliminará todos sus datos asociados (sucursales, usuarios, etc.).',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop(); // Cerrar diálogo
            },
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop(); // Cerrar diálogo

              try {
                await ref
                    .read(companiesProvider.notifier)
                    .deleteCompany(companyId);
              } catch (e) {
                // Mostrar un error si la eliminación falla (ej: error de permisos)
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Fallo al eliminar: ${e.toString().replaceAll('Exception: ', '')}',
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
