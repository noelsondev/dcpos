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

@JsonSerializable(fieldRename: FieldRename.snake) // Usar snake_case para JSON
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

  @JsonKey(required: true)
  @Index()
  final String roleId;

  @JsonKey(required: true)
  final String roleName;

  final bool isActive;

  // 💡 Campo para Borrado Lógico (para Offline-First)
  final bool isDeleted;

  // 🚨 CORRECCIÓN CLAVE: AÑADIDO el campo faltante
  final bool isPendingSync;

  // Campos relacionados con la jerarquía (pueden ser nulos)
  final String? companyId;

  final String? branchId;

  // Tokens (NO VIENEN EN /auth/me, pero se guardan para persistencia)
  final String? accessToken;
  final String? refreshToken;

  // Metadatos
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
    // 🚨 CORRECCIÓN CLAVE: Inicializar el campo en el constructor
    this.isPendingSync = false,
  });

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);
}

// ----------------------------------------------------------------------
// 🚨 MODELO PARA LA COLA DE SINCRONIZACIÓN (CREACIÓN)
// ----------------------------------------------------------------------

// Este es el modelo que el Admin crea en la app.
@JsonSerializable(fieldRename: FieldRename.snake)
class UserCreateLocal {
  @JsonKey(required: true)
  final String username;

  @JsonKey(required: true)
  final String password;

  @JsonKey(required: true)
  final String roleId;

  @JsonKey(required: true)
  final String roleName;

  final bool isActive;

  final String? companyId;

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
@JsonSerializable(
  includeIfNull: false,
  fieldRename: FieldRename.snake,
) // No incluye campos nulos en el JSON
class UserUpdateLocal {
  // ✅ CORREGIDO: Usamos 'id' para ser consistentes.
  final String id;

  // ✅ CORREGIDO: Añadido roleId que es esencial para la edición.
  final String? roleId;

  final String? username;
  final String? password;

  //CLAVE: Añadido 'roleName'.
  // 'includeToJson: false' evita que se serialice al enviarlo a la API,
  // pero permite acceder a él en el Notifier para la lógica.
  @JsonKey(includeToJson: false)
  final String? roleName;

  final bool? isActive;

  final String? companyId;

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
