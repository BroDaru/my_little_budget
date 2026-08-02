class RemoteSyncRow {
  const RemoteSyncRow({
    required this.uuid,
    required this.payload,
    required this.updatedAt,
    required this.deletedAt,
    required this.revision,
  });

  final String uuid;
  final Map<String, Object?> payload;
  final String updatedAt;
  final String? deletedAt;
  final int revision;

  bool get isDeleted => deletedAt != null;
}

class SyncOutboxEntry {
  const SyncOutboxEntry({
    required this.entity,
    required this.uuid,
    required this.operation,
    required this.generation,
    required this.changedAt,
    this.tombstonePayload = const <String, Object?>{},
  });

  final String entity;
  final String uuid;
  final String operation;
  final int generation;
  final String changedAt;
  final Map<String, Object?> tombstonePayload;

  bool get isDelete => operation == 'delete';
}

class SyncRunResult {
  const SyncRunResult({
    this.uploaded = 0,
    this.downloaded = 0,
    this.error,
    this.errorStage,
    this.errorEntity,
  });

  final int uploaded;
  final int downloaded;
  final String? error;
  final String? errorStage;
  final String? errorEntity;

  bool get isOk => error == null;
  bool get changedLocalData => downloaded > 0;
}

typedef SyncProgressListener = void Function(SyncProgress progress);

class SyncProgress {
  const SyncProgress({required this.percent, required this.label})
    : assert(percent >= 0 && percent <= 100);

  final int percent;
  final String label;

  double get fraction => percent / 100;
}
