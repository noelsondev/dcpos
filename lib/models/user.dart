// lib/models/user.dart

import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:isar/isar.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:uuid/uuid.dart';

part 'user.g.dart';

// Función hash simple para Isar (debe ser la misma en todos los archivos .dart)
int fastHash(String string) {
  var hash = 2166136261;
  for (var i = 0; i < string.length; i++) {
    hash ^= string.codeUnitAt(i);
    hash *= 16777619;
  }
  return hash;
}

// ----------------------------------------------------------------------
// 📝 MODELO DE BASE DE DATOS Y API
// ----------------------------------------------------------------------

@JsonSerializable()
@CopyWith()
@Collection()
class User {
  Id get isarId =>
      fastHash(id); // Generar IsarId a partir del UUID del servidor

  @JsonKey(required: true)
  @Index(unique: true)
  final String id; // UUID del servidor

  @JsonKey(required: true)
  @Index(unique: true)
  final String username;

  @JsonKey(name: 'role_id', required: true)
  @Index()
  final String roleId;

  @JsonKey(name: 'role_name', required: true)
  final String roleName;

  final bool isActive;

  // 💡 Campo para Borrado Lógico (para Offline-First)
  final bool isDeleted;

  // Campos relacionados con la jerarquía (pueden ser nulos)
  @JsonKey(name: 'company_id')
  final String? companyId; // ✅ Correcto en el modelo principal

  @JsonKey(name: 'branch_id')
  final String? branchId; // ✅ Correcto en el modelo principal

  // Tokens (NO VIENEN EN /auth/me, pero se guardan para persistencia)
  final String? accessToken;
  final String? refreshToken;

  // Metadatos
  @JsonKey(name: 'created_at')
  final String createdAt;

  User({
    required this.id,
    required this.username,
    required this.roleId,
    required this.roleName,
    required this.createdAt,
    this.isActive = true,
    this.isDeleted = false, // Valor por defecto añadido
    this.companyId,
    this.branchId,
    this.accessToken,
    this.refreshToken,
  });

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);
}

// ----------------------------------------------------------------------
// 🚨 MODELO PARA LA COLA DE SINCRONIZACIÓN (CREACIÓN)
// ----------------------------------------------------------------------

// Este es el modelo que el Admin crea en la app.
@JsonSerializable()
class UserCreateLocal {
  @JsonKey(required: true)
  final String username;

  @JsonKey(required: true)
  final String password;

  @JsonKey(name: 'role_id', required: true)
  final String roleId;

  @JsonKey(name: 'role_name', required: true)
  final String roleName;

  final bool isActive;

  // 💡 CORRECCIÓN CLAVE: Asegurar la serialización a 'company_id'
  @JsonKey(name: 'company_id')
  final String? companyId;

  // 💡 CORRECCIÓN CLAVE: Asegurar la serialización a 'branch_id'
  @JsonKey(name: 'branch_id')
  final String? branchId;

  // 💡 CAMBIO CRÍTICO 1: Hacer 'localId' nullable.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final String? localId;

  UserCreateLocal({
    required this.username,
    required this.password,
    required this.roleId,
    required this.roleName,
    this.isActive = true,
    this.companyId,
    this.branchId,
    // 💡 CAMBIO CRÍTICO 2: Quitar 'required' del constructor.
    this.localId,
  });

  factory UserCreateLocal.fromJson(Map<String, dynamic> json) =>
      _$UserCreateLocalFromJson(json);
  Map<String, dynamic> toJson() => _$UserCreateLocalToJson(this);
}

// 🚨 MODELO PARA LA ACTUALIZACIÓN (Necesitas esto para la edición)
@JsonSerializable(includeIfNull: false) // No incluye campos nulos en el JSON
class UserUpdateLocal {
  // ✅ CORREGIDO: Usamos 'id' para ser consistentes.
  final String id;

  // ✅ CORREGIDO: Añadido roleId que es esencial para la edición.
  @JsonKey(name: 'role_id')
  final String? roleId;

  final String? username;
  final String? password;

  //CLAVE: Añadido 'roleName'.
  // 'includeToJson: false' evita que se serialice al enviarlo a la API,
  // pero permite acceder a él en el Notifier para la lógica.
  @JsonKey(includeToJson: false)
  final String? roleName;

  final bool? isActive;

  // 💡 CORRECCIÓN CLAVE: Asegurar la serialización a 'company_id'
  @JsonKey(name: 'company_id')
  final String? companyId;

  // 💡 CORRECCIÓN CLAVE: Asegurar la serialización a 'branch_id'
  @JsonKey(name: 'branch_id')
  final String? branchId;

  UserUpdateLocal({
    required this.id, // ID del servidor
    this.username,
    this.password,
    this.roleName,
    this.roleId,
    this.isActive,
    this.companyId,
    this.branchId,
  });

  factory UserUpdateLocal.fromJson(Map<String, dynamic> json) =>
      _$UserUpdateLocalFromJson(json);

  Map<String, dynamic> toJson() => _$UserUpdateLocalToJson(this);
}
