// lib/models/branch.dart

import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:isar/isar.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';

part 'branch.g.dart';

// ----------------------------------------------------------------------
// 1. MODELO PRINCIPAL (DB y API Fetch)
// ----------------------------------------------------------------------
@CopyWith()
@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
@Collection()
class Branch {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true)
  final String id;

  final String companyId;
  final String name;
  final String? address;

  final bool isDeleted;

  Branch({
    required this.id,
    required this.companyId,
    required this.name,
    this.address,
    this.isDeleted = false,
  });

  factory Branch.fromJson(Map<String, dynamic> json) => _$BranchFromJson(json);
  Map<String, dynamic> toJson() => _$BranchToJson(this);
}

// ----------------------------------------------------------------------
// 2. MODELO DE CREACIÓN (Offline-First) - Para la Cola de Sincronización
// ----------------------------------------------------------------------
@JsonSerializable(explicitToJson: true)
class BranchCreateLocal {
  final String? localId;
  final String name;
  final String? address;
  final String companyId;

  BranchCreateLocal({
    String? localId,
    required this.name,
    this.address,
    required this.companyId,
  }) : localId = localId ?? const Uuid().v4();

  // 💡 Usado para la solicitud al API (solo datos)
  Map<String, dynamic> toApiJson() {
    return {'name': name, if (address != null) 'address': address};
  }

  // 💡 Usado para guardar en SyncQueueItem.payload (datos completos)
  Map<String, dynamic> toJson() => _$BranchCreateLocalToJson(this);

  factory BranchCreateLocal.fromJson(Map<String, dynamic> json) =>
      _$BranchCreateLocalFromJson(json);
}

// ----------------------------------------------------------------------
// 3. MODELO DE ACTUALIZACIÓN (Offline-First) - CORREGIDO
// ----------------------------------------------------------------------
// 💡 CORRECCIÓN: createFactory: false
@JsonSerializable(
  includeIfNull: false,
  explicitToJson: true,
  createFactory: false,
)
class BranchUpdateLocal {
  @JsonKey(ignore: true)
  final String id;
  @JsonKey(ignore: true)
  final String companyId;

  final String? name;
  final String? address;

  BranchUpdateLocal({
    required this.id, // Ahora funciona correctamente
    required this.companyId,
    this.name,
    this.address,
  });

  // Usado para la solicitud PATCH al API
  Map<String, dynamic> toApiJson() => _$BranchUpdateLocalToJson(this);
}
