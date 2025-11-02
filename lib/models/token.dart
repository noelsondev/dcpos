// lib/models/token.dart (Modificado)

import 'package:json_annotation/json_annotation.dart';

part 'token.g.dart';

@JsonSerializable()
class Token {
  @JsonKey(name: 'access_token')
  final String accessToken;

  @JsonKey(name: 'token_type')
  final String tokenType;

  // ⚠️ Nuevo campo Refresh Token
  @JsonKey(name: 'refresh_token')
  final String? refreshToken;

  final String? role;

  Token({
    required this.accessToken,
    this.tokenType = 'bearer',
    this.refreshToken, // Añadir al constructor
    required this.role,
  });

  factory Token.fromJson(Map<String, dynamic> json) => _$TokenFromJson(json);
  Map<String, dynamic> toJson() => _$TokenToJson(this);
}
