// lib/models/role.dart

import 'package:isar/isar.dart';

// Importante: Debes ejecutar 'dart run build_runner build' después de este cambio
part 'role.g.dart';

@Collection()
class Role {
  Id isarId = Isar.autoIncrement; // ID para Isar

  @Index(unique: true)
  final String id; // ID real del backend (para unicidad)
  final String name;

  Role({required this.id, required this.name});

  factory Role.fromJson(Map<String, dynamic> json) {
    return Role(id: json['id'] as String, name: json['name'] as String);
  }
}
