//lib/screens/companies_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/companies_provider.dart';
import 'company_form_screen.dart';
import 'branches_screen.dart'; // 💡 CORREGIDO: Importación de BranchesScreen

class CompaniesScreen extends ConsumerWidget {
  const CompaniesScreen({super.key});

  // Función para forzar la recarga de datos
  void _reloadCompanies(WidgetRef ref) {
    // 🚀 Llamada para invalidar y reconstruir el AsyncNotifier
    ref.invalidate(companiesProvider);
    // Opcional: ref.read(companiesProvider.notifier).build();
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
      // --- Botón Flotante para Crear ---
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
            'Error al cargar: ${err.toString().replaceAll('Exception: ', '')}',
            style: const TextStyle(color: Colors.red),
          ),
        ),
        data: (companies) {
          if (companies.isEmpty) {
            return const Center(child: Text('Aún no hay compañías creadas.'));
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
                  // ✅ CORREGIDO: Navegar a BranchesScreen, pasando el company.id
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
                        ref
                            .read(companiesProvider.notifier)
                            .deleteCompany(company.id);
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
}
