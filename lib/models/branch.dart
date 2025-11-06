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
  // 💡 CORRECCIÓN CRÍTICA: Se añade @JsonKey(ignore: true) para evitar el error
  // 'type Null is not a subtype of type num' al deserializar desde el API.
  // Este campo es exclusivo de Isar y debe ser ignorado por JSON.
  @JsonKey(ignore: true)
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
// 3. MODELO DE ACTUALIZACIÓN (Offline-First)
// ----------------------------------------------------------------------
@JsonSerializable(
  includeIfNull: false,
  explicitToJson: true,
  createFactory: false, // Indica que debemos definir el factory manualmente
)
class BranchUpdateLocal {
  // Los campos ignorados no se incluirán en el código generado de toApiJson()
  @JsonKey(ignore: true)
  final String id;
  @JsonKey(ignore: true)
  final String companyId;

  final String? name;
  final String? address;

  BranchUpdateLocal({
    required this.id,
    required this.companyId,
    this.name,
    this.address,
  });

  // ✅ Factory manual para deserializar desde la cola local
  factory BranchUpdateLocal.fromJson(Map<String, dynamic> json) {
    return BranchUpdateLocal(
      id: json['id'] as String,
      companyId: json['companyId'] as String,
      name: json['name'] as String?,
      address: json['address'] as String?,
    );
  }

  // Mantenemos toApiJson para el request PATCH
  // Incluye solo name y address (excluyendo nulls por includeIfNull: false).
  Map<String, dynamic> toApiJson() {
    return _$BranchUpdateLocalToJson(this);
  }

  // ✅ Manual toJson para la cola (incluye id y companyId)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'companyId': companyId,
      if (name != null) 'name': name,
      if (address != null) 'address': address,
    };
  }
}
