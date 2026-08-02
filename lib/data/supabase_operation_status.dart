import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sync_models.dart';

enum SyncOperationResult { none, running, success, failure, authRequired }

enum DbConnectionResult { unknown, success, failure }

enum StorageCheckResult { unknown, exists, missing, failure }

class SupabaseOperationStatus {
  const SupabaseOperationStatus({
    this.fullSyncResult = SyncOperationResult.none,
    this.fullSyncAttemptedAt,
    this.fullSyncSucceededAt,
    this.fullSyncUploaded = 0,
    this.fullSyncDownloaded = 0,
    this.fullSyncError,
    this.fullSyncErrorStage,
    this.fullSyncErrorTable,
    this.autoUploadResult = SyncOperationResult.none,
    this.autoUploadAttemptedAt,
    this.autoUploadSucceededAt,
    this.autoUploadCount = 0,
    this.autoUploadError,
    this.autoUploadErrorStage,
    this.autoUploadErrorTable,
    this.pendingUploadCount,
    this.dbConnectionResult = DbConnectionResult.unknown,
    this.dbConnectionCheckedAt,
    this.dbConnectionTableCount,
    this.dbConnectionError,
    this.storageCheckResult = StorageCheckResult.unknown,
    this.storageCheckedAt,
    this.storageRemoteUpdatedAt,
    this.storageError,
  });

  final SyncOperationResult fullSyncResult;
  final String? fullSyncAttemptedAt;
  final String? fullSyncSucceededAt;
  final int fullSyncUploaded;
  final int fullSyncDownloaded;
  final String? fullSyncError;
  final String? fullSyncErrorStage;
  final String? fullSyncErrorTable;

  final SyncOperationResult autoUploadResult;
  final String? autoUploadAttemptedAt;
  final String? autoUploadSucceededAt;
  final int autoUploadCount;
  final String? autoUploadError;
  final String? autoUploadErrorStage;
  final String? autoUploadErrorTable;
  final int? pendingUploadCount;

  final DbConnectionResult dbConnectionResult;
  final String? dbConnectionCheckedAt;
  final int? dbConnectionTableCount;
  final String? dbConnectionError;

  final StorageCheckResult storageCheckResult;
  final String? storageCheckedAt;
  final String? storageRemoteUpdatedAt;
  final String? storageError;

  Map<String, Object?> toJson() => {
    'fullSyncResult': fullSyncResult.name,
    'fullSyncAttemptedAt': fullSyncAttemptedAt,
    'fullSyncSucceededAt': fullSyncSucceededAt,
    'fullSyncUploaded': fullSyncUploaded,
    'fullSyncDownloaded': fullSyncDownloaded,
    'fullSyncError': fullSyncError,
    'fullSyncErrorStage': fullSyncErrorStage,
    'fullSyncErrorTable': fullSyncErrorTable,
    'autoUploadResult': autoUploadResult.name,
    'autoUploadAttemptedAt': autoUploadAttemptedAt,
    'autoUploadSucceededAt': autoUploadSucceededAt,
    'autoUploadCount': autoUploadCount,
    'autoUploadError': autoUploadError,
    'autoUploadErrorStage': autoUploadErrorStage,
    'autoUploadErrorTable': autoUploadErrorTable,
    'pendingUploadCount': pendingUploadCount,
    'dbConnectionResult': dbConnectionResult.name,
    'dbConnectionCheckedAt': dbConnectionCheckedAt,
    'dbConnectionTableCount': dbConnectionTableCount,
    'dbConnectionError': dbConnectionError,
    'storageCheckResult': storageCheckResult.name,
    'storageCheckedAt': storageCheckedAt,
    'storageRemoteUpdatedAt': storageRemoteUpdatedAt,
    'storageError': storageError,
  };

  factory SupabaseOperationStatus.fromJson(Map<String, Object?> json) {
    T enumValue<T extends Enum>(List<T> values, String key, T fallback) {
      final name = json[key];
      return values.where((value) => value.name == name).firstOrNull ??
          fallback;
    }

    return SupabaseOperationStatus(
      fullSyncResult: enumValue(
        SyncOperationResult.values,
        'fullSyncResult',
        SyncOperationResult.none,
      ),
      fullSyncAttemptedAt: json['fullSyncAttemptedAt'] as String?,
      fullSyncSucceededAt: json['fullSyncSucceededAt'] as String?,
      fullSyncUploaded: json['fullSyncUploaded'] as int? ?? 0,
      fullSyncDownloaded: json['fullSyncDownloaded'] as int? ?? 0,
      fullSyncError: json['fullSyncError'] as String?,
      fullSyncErrorStage: json['fullSyncErrorStage'] as String?,
      fullSyncErrorTable: json['fullSyncErrorTable'] as String?,
      autoUploadResult: enumValue(
        SyncOperationResult.values,
        'autoUploadResult',
        SyncOperationResult.none,
      ),
      autoUploadAttemptedAt: json['autoUploadAttemptedAt'] as String?,
      autoUploadSucceededAt: json['autoUploadSucceededAt'] as String?,
      autoUploadCount: json['autoUploadCount'] as int? ?? 0,
      autoUploadError: json['autoUploadError'] as String?,
      autoUploadErrorStage: json['autoUploadErrorStage'] as String?,
      autoUploadErrorTable: json['autoUploadErrorTable'] as String?,
      pendingUploadCount: json['pendingUploadCount'] as int?,
      dbConnectionResult: enumValue(
        DbConnectionResult.values,
        'dbConnectionResult',
        DbConnectionResult.unknown,
      ),
      dbConnectionCheckedAt: json['dbConnectionCheckedAt'] as String?,
      dbConnectionTableCount: json['dbConnectionTableCount'] as int?,
      dbConnectionError: json['dbConnectionError'] as String?,
      storageCheckResult: enumValue(
        StorageCheckResult.values,
        'storageCheckResult',
        StorageCheckResult.unknown,
      ),
      storageCheckedAt: json['storageCheckedAt'] as String?,
      storageRemoteUpdatedAt: json['storageRemoteUpdatedAt'] as String?,
      storageError: json['storageError'] as String?,
    );
  }
}

abstract interface class SupabaseSyncStatusRecorder {
  Future<void> recordFullSyncStarted({DateTime? now});

  Future<void> recordFullSyncResult(
    SyncRunResult result, {
    int? pendingUploadCount,
    DateTime? now,
  });

  Future<void> recordAutoUploadStarted({DateTime? now});

  Future<void> recordAutoUploadResult(
    SyncRunResult result, {
    int? pendingUploadCount,
    DateTime? now,
  });
}

class SupabaseOperationStatusNotifier extends Notifier<SupabaseOperationStatus>
    implements SupabaseSyncStatusRecorder {
  static const _storageKey = 'mlb-supabase-operation-status-v1';
  static const _keep = Object();

  bool _mutated = false;
  final _ready = Completer<void>();

  Future<void> get whenReady => _ready.future;

  @override
  SupabaseOperationStatus build() {
    unawaited(_load());
    return const SupabaseOperationStatus();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || _mutated) return;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic> && !_mutated) {
          state = SupabaseOperationStatus.fromJson(decoded);
        }
      } catch (_) {
        // Ignore corrupt diagnostic state. It must never block sync startup.
      }
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  Future<void> _set(SupabaseOperationStatus value) async {
    _mutated = true;
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(value.toJson()));
  }

  @override
  Future<void> recordFullSyncStarted({DateTime? now}) {
    final current = state;
    return _set(
      SupabaseOperationStatus(
        fullSyncResult: SyncOperationResult.running,
        fullSyncAttemptedAt: _iso(now),
        fullSyncSucceededAt: current.fullSyncSucceededAt,
        fullSyncUploaded: current.fullSyncUploaded,
        fullSyncDownloaded: current.fullSyncDownloaded,
        autoUploadResult: current.autoUploadResult,
        autoUploadAttemptedAt: current.autoUploadAttemptedAt,
        autoUploadSucceededAt: current.autoUploadSucceededAt,
        autoUploadCount: current.autoUploadCount,
        autoUploadError: current.autoUploadError,
        autoUploadErrorStage: current.autoUploadErrorStage,
        autoUploadErrorTable: current.autoUploadErrorTable,
        pendingUploadCount: current.pendingUploadCount,
        dbConnectionResult: current.dbConnectionResult,
        dbConnectionCheckedAt: current.dbConnectionCheckedAt,
        dbConnectionTableCount: current.dbConnectionTableCount,
        dbConnectionError: current.dbConnectionError,
        storageCheckResult: current.storageCheckResult,
        storageCheckedAt: current.storageCheckedAt,
        storageRemoteUpdatedAt: current.storageRemoteUpdatedAt,
        storageError: current.storageError,
      ),
    );
  }

  @override
  Future<void> recordFullSyncResult(
    SyncRunResult result, {
    int? pendingUploadCount,
    DateTime? now,
  }) {
    final current = state;
    final succeededAt = result.isOk ? _iso(now) : current.fullSyncSucceededAt;
    return _set(
      SupabaseOperationStatus(
        fullSyncResult: _resultOf(result),
        fullSyncAttemptedAt: current.fullSyncAttemptedAt ?? _iso(now),
        fullSyncSucceededAt: succeededAt,
        fullSyncUploaded: result.uploaded,
        fullSyncDownloaded: result.downloaded,
        fullSyncError: sanitizeSupabaseError(result.error),
        fullSyncErrorStage: result.errorStage,
        fullSyncErrorTable: result.errorEntity,
        autoUploadResult: current.autoUploadResult,
        autoUploadAttemptedAt: current.autoUploadAttemptedAt,
        autoUploadSucceededAt: current.autoUploadSucceededAt,
        autoUploadCount: current.autoUploadCount,
        autoUploadError: current.autoUploadError,
        autoUploadErrorStage: current.autoUploadErrorStage,
        autoUploadErrorTable: current.autoUploadErrorTable,
        pendingUploadCount: pendingUploadCount ?? current.pendingUploadCount,
        dbConnectionResult: current.dbConnectionResult,
        dbConnectionCheckedAt: current.dbConnectionCheckedAt,
        dbConnectionTableCount: current.dbConnectionTableCount,
        dbConnectionError: current.dbConnectionError,
        storageCheckResult: current.storageCheckResult,
        storageCheckedAt: current.storageCheckedAt,
        storageRemoteUpdatedAt: current.storageRemoteUpdatedAt,
        storageError: current.storageError,
      ),
    );
  }

  @override
  Future<void> recordAutoUploadStarted({DateTime? now}) {
    final current = state;
    return _set(
      _withAutoUpload(
        current,
        result: SyncOperationResult.running,
        attemptedAt: _iso(now),
      ),
    );
  }

  @override
  Future<void> recordAutoUploadResult(
    SyncRunResult result, {
    int? pendingUploadCount,
    DateTime? now,
  }) {
    final current = state;
    return _set(
      _withAutoUpload(
        current,
        result: _resultOf(result),
        attemptedAt: current.autoUploadAttemptedAt ?? _iso(now),
        succeededAt: result.isOk ? _iso(now) : current.autoUploadSucceededAt,
        count: result.uploaded,
        error: sanitizeSupabaseError(result.error),
        errorStage: result.errorStage,
        errorTable: result.errorEntity,
        pendingUploadCount: pendingUploadCount,
      ),
    );
  }

  Future<void> recordDbConnectionSuccess(int tableCount, {DateTime? now}) {
    final current = state;
    return _set(
      _copy(
        current,
        dbConnectionResult: DbConnectionResult.success,
        dbConnectionCheckedAt: _iso(now),
        dbConnectionTableCount: tableCount,
        dbConnectionError: null,
      ),
    );
  }

  Future<void> recordDbConnectionFailure(String error, {DateTime? now}) {
    final current = state;
    return _set(
      _copy(
        current,
        dbConnectionResult: DbConnectionResult.failure,
        dbConnectionCheckedAt: _iso(now),
        dbConnectionTableCount: null,
        dbConnectionError: sanitizeSupabaseError(error),
      ),
    );
  }

  Future<void> recordStorageCheck({
    required bool exists,
    DateTime? remoteUpdatedAt,
    DateTime? now,
  }) {
    final current = state;
    return _set(
      _copy(
        current,
        storageCheckResult: exists
            ? StorageCheckResult.exists
            : StorageCheckResult.missing,
        storageCheckedAt: _iso(now),
        storageRemoteUpdatedAt: remoteUpdatedAt?.toUtc().toIso8601String(),
        storageError: null,
      ),
    );
  }

  Future<void> recordStorageFailure(String error, {DateTime? now}) {
    final current = state;
    return _set(
      _copy(
        current,
        storageCheckResult: StorageCheckResult.failure,
        storageCheckedAt: _iso(now),
        storageRemoteUpdatedAt: null,
        storageError: sanitizeSupabaseError(error),
      ),
    );
  }

  Future<void> resetDbStatus() => _set(_copy(state, resetDb: true));

  Future<void> resetStorageStatus() => _set(_copy(state, resetStorage: true));

  Future<void> resetAll() => _set(const SupabaseOperationStatus());

  static SupabaseOperationStatus _withAutoUpload(
    SupabaseOperationStatus current, {
    required SyncOperationResult result,
    String? attemptedAt,
    String? succeededAt,
    int? count,
    String? error,
    String? errorStage,
    String? errorTable,
    int? pendingUploadCount,
  }) => SupabaseOperationStatus(
    fullSyncResult: current.fullSyncResult,
    fullSyncAttemptedAt: current.fullSyncAttemptedAt,
    fullSyncSucceededAt: current.fullSyncSucceededAt,
    fullSyncUploaded: current.fullSyncUploaded,
    fullSyncDownloaded: current.fullSyncDownloaded,
    fullSyncError: current.fullSyncError,
    fullSyncErrorStage: current.fullSyncErrorStage,
    fullSyncErrorTable: current.fullSyncErrorTable,
    autoUploadResult: result,
    autoUploadAttemptedAt: attemptedAt,
    autoUploadSucceededAt: succeededAt,
    autoUploadCount: count ?? current.autoUploadCount,
    autoUploadError: error,
    autoUploadErrorStage: errorStage,
    autoUploadErrorTable: errorTable,
    pendingUploadCount: pendingUploadCount ?? current.pendingUploadCount,
    dbConnectionResult: current.dbConnectionResult,
    dbConnectionCheckedAt: current.dbConnectionCheckedAt,
    dbConnectionTableCount: current.dbConnectionTableCount,
    dbConnectionError: current.dbConnectionError,
    storageCheckResult: current.storageCheckResult,
    storageCheckedAt: current.storageCheckedAt,
    storageRemoteUpdatedAt: current.storageRemoteUpdatedAt,
    storageError: current.storageError,
  );

  static SupabaseOperationStatus _copy(
    SupabaseOperationStatus current, {
    DbConnectionResult? dbConnectionResult,
    Object? dbConnectionCheckedAt = _keep,
    Object? dbConnectionTableCount = _keep,
    Object? dbConnectionError = _keep,
    StorageCheckResult? storageCheckResult,
    Object? storageCheckedAt = _keep,
    Object? storageRemoteUpdatedAt = _keep,
    Object? storageError = _keep,
    bool resetDb = false,
    bool resetStorage = false,
  }) => SupabaseOperationStatus(
    fullSyncResult: resetDb ? SyncOperationResult.none : current.fullSyncResult,
    fullSyncAttemptedAt: resetDb ? null : current.fullSyncAttemptedAt,
    fullSyncSucceededAt: resetDb ? null : current.fullSyncSucceededAt,
    fullSyncUploaded: resetDb ? 0 : current.fullSyncUploaded,
    fullSyncDownloaded: resetDb ? 0 : current.fullSyncDownloaded,
    fullSyncError: resetDb ? null : current.fullSyncError,
    fullSyncErrorStage: resetDb ? null : current.fullSyncErrorStage,
    fullSyncErrorTable: resetDb ? null : current.fullSyncErrorTable,
    autoUploadResult: resetDb
        ? SyncOperationResult.none
        : current.autoUploadResult,
    autoUploadAttemptedAt: resetDb ? null : current.autoUploadAttemptedAt,
    autoUploadSucceededAt: resetDb ? null : current.autoUploadSucceededAt,
    autoUploadCount: resetDb ? 0 : current.autoUploadCount,
    autoUploadError: resetDb ? null : current.autoUploadError,
    autoUploadErrorStage: resetDb ? null : current.autoUploadErrorStage,
    autoUploadErrorTable: resetDb ? null : current.autoUploadErrorTable,
    pendingUploadCount: resetDb ? null : current.pendingUploadCount,
    dbConnectionResult: resetDb
        ? DbConnectionResult.unknown
        : dbConnectionResult ?? current.dbConnectionResult,
    dbConnectionCheckedAt: resetDb
        ? null
        : identical(dbConnectionCheckedAt, _keep)
        ? current.dbConnectionCheckedAt
        : dbConnectionCheckedAt as String?,
    dbConnectionTableCount: resetDb
        ? null
        : identical(dbConnectionTableCount, _keep)
        ? current.dbConnectionTableCount
        : dbConnectionTableCount as int?,
    dbConnectionError: resetDb
        ? null
        : identical(dbConnectionError, _keep)
        ? current.dbConnectionError
        : dbConnectionError as String?,
    storageCheckResult: resetStorage
        ? StorageCheckResult.unknown
        : storageCheckResult ?? current.storageCheckResult,
    storageCheckedAt: resetStorage
        ? null
        : identical(storageCheckedAt, _keep)
        ? current.storageCheckedAt
        : storageCheckedAt as String?,
    storageRemoteUpdatedAt: resetStorage
        ? null
        : identical(storageRemoteUpdatedAt, _keep)
        ? current.storageRemoteUpdatedAt
        : storageRemoteUpdatedAt as String?,
    storageError: resetStorage
        ? null
        : identical(storageError, _keep)
        ? current.storageError
        : storageError as String?,
  );

  static SyncOperationResult _resultOf(SyncRunResult result) {
    if (result.isOk) return SyncOperationResult.success;
    return isSupabaseAuthError(result.error)
        ? SyncOperationResult.authRequired
        : SyncOperationResult.failure;
  }

  static String _iso(DateTime? now) =>
      (now ?? DateTime.now()).toUtc().toIso8601String();
}

final supabaseOperationStatusProvider =
    NotifierProvider<SupabaseOperationStatusNotifier, SupabaseOperationStatus>(
      SupabaseOperationStatusNotifier.new,
    );

bool isSupabaseAuthError(String? error) {
  final value = error?.toLowerCase() ?? '';
  return value.contains('401') ||
      value.contains('jwt') ||
      value.contains('auth') ||
      value.contains('session') ||
      value.contains('로그인') ||
      value.contains('인증');
}

String? sanitizeSupabaseError(String? error) {
  if (error == null || error.trim().isEmpty) return null;
  var value = error.trim();
  value = value.replaceAll(
    RegExp(r'[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}'),
    '[redacted-token]',
  );
  value = value.replaceAll(
    RegExp(r'sb_(?:secret|publishable)_[A-Za-z0-9_-]+'),
    '[redacted-key]',
  );
  value = value.replaceAll(
    RegExp(r'bearer\s+[A-Za-z0-9._-]+', caseSensitive: false),
    'Bearer [redacted-token]',
  );
  return value.length <= 500 ? value : '${value.substring(0, 500)}…';
}
