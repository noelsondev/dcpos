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
@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
@Collection()
class Company {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  final String id;

  final String name;
  final String slug;

  final bool isDeleted;

  Company({
    required this.id,
    required this.name,
    required this.slug,
    this.isDeleted = false,
  });

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

  // 💡 Usado para la solicitud al API (solo datos)
  Map<String, dynamic> toApiJson() {
    return {'name': name, 'slug': slug};
  }

  // 💡 Usado para guardar en SyncQueueItem.payload (datos completos)
  Map<String, dynamic> toJson() => _$CompanyCreateLocalToJson(this);

  factory CompanyCreateLocal.fromJson(Map<String, dynamic> json) =>
      _$CompanyCreateLocalFromJson(json);
}

// ----------------------------------------------------------------------
// 3. MODELO DE ACTUALIZACIÓN (Offline-First) - CORREGIDO
// ----------------------------------------------------------------------
@JsonSerializable(
  includeIfNull: false,
  explicitToJson: true,
  createFactory: false,
)
class CompanyUpdateLocal {
  @JsonKey(ignore: true)
  final String id; // Backend ID

  final String? name;
  final String? slug;

  CompanyUpdateLocal({required this.id, this.name, this.slug});

  // 💡 ESTE ES EL MÉTODO QUE DEBEMOS LLAMAR AHORA
  Map<String, dynamic> toApiJson() => _$CompanyUpdateLocalToJson(this);
}
