// lib/models/company.dart

import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:isar/isar.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';

part 'company.g.dart';

// ----------------------------------------------------------------------
// 1. MODELO PRINCIPAL (DB y API Fetch)
// ----------------------------------------------------------------------
@CopyWith()
@JsonSerializable(
  fieldRename: FieldRename.snake,
  explicitToJson: true,
  anyMap: true,
)
@Collection()
class Company {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  final String id;

  final String name;
  final String slug;

  @JsonKey(name: 'created_at', required: false)
  final String? createdAt;

  final bool isDeleted;

  // ✅ CAMPO CLAVE: Usado solo localmente para el estado de sincronización.
  @JsonKey(ignore: true)
  final bool isSyncPending;

  Company({
    this.isarId = Isar.autoIncrement,
    required this.id,
    required this.name,
    required this.slug,
    this.createdAt,
    this.isDeleted = false,
    this.isSyncPending = false, // Por defecto es false
  });

  static String generateLocalId() => const Uuid().v4();

  factory Company.fromJson(Map<String, dynamic> json) =>
      _$CompanyFromJson(json);
  Map<String, dynamic> toJson() => _$CompanyToJson(this);
}

// ----------------------------------------------------------------------
// 2. MODELO DE CREACIÓN (Offline-First)
// ----------------------------------------------------------------------
@JsonSerializable(explicitToJson: true)
class CompanyCreateLocal {
  final String? localId;
  final String name;
  final String slug;

  CompanyCreateLocal({String? localId, required this.name, required this.slug})
    : localId = localId ?? const Uuid().v4();

  Map<String, dynamic> toApiJson() {
    return {'name': name, 'slug': slug};
  }

  Map<String, dynamic> toJson() => _$CompanyCreateLocalToJson(this);

  factory CompanyCreateLocal.fromJson(Map<String, dynamic> json) =>
      _$CompanyCreateLocalFromJson(json);
}

// ----------------------------------------------------------------------
// 3. MODELO DE ACTUALIZACIÓN (Offline-First)
// ----------------------------------------------------------------------
@JsonSerializable(
  includeIfNull: false,
  explicitToJson: true,
  createFactory: false, // 🛑 Requiere fromJson y toJson manual
)
class CompanyUpdateLocal {
  @JsonKey(ignore: true)
  final String id; // Backend ID

  final String? name;
  final String? slug;

  CompanyUpdateLocal({required this.id, this.name, this.slug});

  // ✅ CORRECCIÓN 1: Constructor de fábrica manual para la deserialización
  // Es usado por SyncService para reconstruir el objeto desde el payload.
  factory CompanyUpdateLocal.fromJson(Map<String, dynamic> json) {
    return CompanyUpdateLocal(
      id: json['id'] as String,
      name: json['name'] as String?,
      slug: json['slug'] as String?,
    );
  }

  // Mantenemos toApiJson (para el request PATCH, con campos opcionales)
  // Nota: Si usaras _$CompanyUpdateLocalToJson(this) necesitarías ejecutar
  // el generador. Para evitar dependencia y asegurar que el ID no vaya en el body,
  // creamos la versión API manualmente:
  Map<String, dynamic> toApiJson() {
    return {if (name != null) 'name': name, if (slug != null) 'slug': slug};
  }

  // ✅ CORRECCIÓN 2: Método toJson manual (para la cola de sincronización)
  // Incluye el ID para que SyncService sepa qué registro actualizar.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (name != null) 'name': name,
      if (slug != null) 'slug': slug,
    };
  }
}
