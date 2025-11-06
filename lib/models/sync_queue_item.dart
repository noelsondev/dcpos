import 'package:isar/isar.dart';
import 'package:json_annotation/json_annotation.dart';

part 'sync_queue_item.g.dart';

// ----------------------------------------------------------------------
// 1. ENUM DE OPERACIONES DE SINCRONIZACIÓN
// ----------------------------------------------------------------------

/// Define las operaciones CRUD que pueden ser encoladas para sincronización
/// cuando el dispositivo está sin conexión.
@JsonEnum(fieldRename: FieldRename.screamingSnake)
enum SyncOperation {
  // Operaciones de Usuario
  CREATE_USER,
  UPDATE_USER,
  DELETE_USER,

  // Operaciones de Compañía
  CREATE_COMPANY,
  UPDATE_COMPANY,
  DELETE_COMPANY,

  // Operaciones de Sucursal
  CREATE_BRANCH,
  UPDATE_BRANCH,
  DELETE_BRANCH,
}

// ----------------------------------------------------------------------
// 2. MODELO DE COLA DE SINCRONIZACIÓN (ISAR)
// ----------------------------------------------------------------------

@JsonSerializable()
@Collection()
class SyncQueueItem {
  Id id = Isar.autoIncrement;

  @Enumerated(EnumType.name)
  final SyncOperation operation; // 👈 Aquí se usa la enumeración

  /// El endpoint REST al que se debe enviar el payload (ej: /api/v1/users/)
  final String endpoint;

  /// El payload (cuerpo) de la solicitud API, guardado como JSON string.
  final String payload;

  /// UUID local generado si es un CREATE, usado para identificar el item local temporalmente.
  final String? localId;

  /// Fecha de creación del ítem en la cola. Se usa para procesar los ítems en orden (FIFO).
  final DateTime createdAt;

  /// Contador de reintentos.
  final int? retryCount;

  // Constructor principal simple (usado por Isar y json_serializable/manual)
  SyncQueueItem({
    required this.operation,
    required this.endpoint,
    required this.payload,
    this.localId,
    required this.createdAt,
    this.retryCount = 0,
  });

  /// Fábrica auxiliar para crear el ítem con la hora actual (`DateTime.now()`) automáticamente.
  factory SyncQueueItem.create({
    required SyncOperation operation,
    required String endpoint,
    required String payload,
    String? localId,
    int retryCount = 0,
  }) {
    return SyncQueueItem(
      operation: operation,
      endpoint: endpoint,
      payload: payload,
      localId: localId,
      createdAt: DateTime.now(),
      retryCount: retryCount,
    );
  }

  factory SyncQueueItem.fromJson(Map<String, dynamic> json) =>
      _$SyncQueueItemFromJson(json);

  Map<String, dynamic> toJson() => _$SyncQueueItemToJson(this);
}
