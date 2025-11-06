//lib/screens/company_form_screen.dart (Corregido) 🛠️
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/company.dart';
import '../providers/companies_provider.dart';

class CompanyFormScreen extends ConsumerStatefulWidget {
  final Company? companyToEdit;

  const CompanyFormScreen({super.key, this.companyToEdit});

  @override
  ConsumerState<CompanyFormScreen> createState() => _CompanyFormScreenState();
}

class _CompanyFormScreenState extends ConsumerState<CompanyFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _slugController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.companyToEdit != null) {
      final company = widget.companyToEdit!;
      _nameController.text = company.name;
      _slugController.text = company.slug;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    super.dispose();
  }

  void _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final companiesNotifier = ref.read(companiesProvider.notifier);

    try {
      if (widget.companyToEdit == null) {
        // --- CREACIÓN (Offline-First) ---
        final newCompany = CompanyCreateLocal(
          name: _nameController.text,
          slug: _slugController.text,
        );
        await companiesNotifier.createCompany(newCompany);
      } else {
        // --- EDICIÓN (Offline-First) ---
        final updatedCompany = CompanyUpdateLocal(
          id: widget.companyToEdit!.id,
          name: _nameController.text,
          slug: _slugController.text,
        );
        // 🚀 CORRECCIÓN APLICADA: Llamada a updateCompany
        await companiesNotifier.updateCompany(updatedCompany);
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $errorMessage'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.companyToEdit == null
              ? 'Crear Compañía'
              : 'Editar Compañía: ${widget.companyToEdit!.name}',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Campo Nombre ---
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la Compañía',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Introduce el nombre.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // --- Campo Slug ---
              TextFormField(
                controller: _slugController,
                decoration: const InputDecoration(
                  labelText: 'Slug (Identificador único, ej: miempresa)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Introduce un slug.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 30),

              // --- Botón de Guardar ---
              ElevatedButton(
                onPressed: _isLoading ? null : _submitForm,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        widget.companyToEdit == null
                            ? 'Crear Compañía'
                            : 'Guardar Cambios',
                        style: const TextStyle(fontSize: 18),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
