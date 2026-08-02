import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase/supabase.dart';

import 'local_sync_store.dart';
import 'sync_models.dart';
import 'supabase_backup_settings.dart';
import 'supabase_sync_auth.dart';

const syncPullOrder = <String>[
  'accounts',
  'categories',
  'tags',
  'monthly_income',
  'budget_groups',
  'transactions',
  'investments',
  'recurring_transactions',
  'transaction_presets',
  'calendar_events',
];

final supabaseSyncGatewayProvider = Provider<SupabaseSyncGateway>((ref) {
  return SupabasePostgrestSyncGateway(
    authService: ref.watch(supabaseSyncAuthServiceProvider),
  );
});

abstract class SupabaseSyncGateway {
  Future<List<RemoteSyncRow>> fetchChanges({
    required SupabaseBackupSettings settings,
    required String entity,
    required int afterRevision,
    required int limit,
  });

  Future<RemoteSyncRow> upsert({
    required SupabaseBackupSettings settings,
    required String entity,
    required String uuid,
    required Map<String, Object?> payload,
    required String? deletedAt,
  });
}

class SupabasePostgrestSyncGateway implements SupabaseSyncGateway {
  SupabasePostgrestSyncGateway({required SupabaseSyncAuthService authService})
    : _authService = authService;

  final SupabaseSyncAuthService _authService;

  @override
  Future<List<RemoteSyncRow>> fetchChanges({
    required SupabaseBackupSettings settings,
    required String entity,
    required int afterRevision,
    required int limit,
  }) async {
    final client = await _authService.restoreClient(settings);
    final response = await client
        .from(_remoteTable(entity))
        .select('uuid,payload,updated_at,deleted_at,sync_revision')
        .gt('sync_revision', afterRevision)
        .order('sync_revision', ascending: true)
        .limit(limit);
    return (response as List)
        .map((row) => _parseRemoteRow(Map<String, Object?>.from(row as Map)))
        .toList(growable: false);
  }

  @override
  Future<RemoteSyncRow> upsert({
    required SupabaseBackupSettings settings,
    required String entity,
    required String uuid,
    required Map<String, Object?> payload,
    required String? deletedAt,
  }) async {
    final client = await _authService.restoreClient(settings);
    final response = await client
        .from(_remoteTable(entity))
        .upsert({
          'uuid': uuid,
          'payload': payload,
          'deleted_at': deletedAt,
        }, onConflict: 'uuid')
        .select('uuid,payload,updated_at,deleted_at,sync_revision')
        .single();
    return _parseRemoteRow(Map<String, Object?>.from(response));
  }

  static String _remoteTable(String entity) => 'mlb_$entity';

  static RemoteSyncRow _parseRemoteRow(Map<String, Object?> row) {
    final payload = row['payload'];
    return RemoteSyncRow(
      uuid: row['uuid']! as String,
      payload: payload is Map
          ? Map<String, Object?>.from(payload)
          : const <String, Object?>{},
      updatedAt: row['updated_at']! as String,
      deletedAt: row['deleted_at'] as String?,
      revision: (row['sync_revision']! as num).toInt(),
    );
  }
}

class SupabaseIncrementalSyncService {
  SupabaseIncrementalSyncService({
    required LocalSyncStore local,
    required SupabaseSyncGateway remote,
    this.pageSize = 200,
    this.uploadChunkSize = 10,
  }) : _local = local,
       _remote = remote,
       assert(uploadChunkSize > 0);

  final LocalSyncStore _local;
  final SupabaseSyncGateway _remote;
  final int pageSize;
  final int uploadChunkSize;

  Future<SyncRunResult> synchronize(
    SupabaseBackupSettings settings, {
    SyncProgressListener? onProgress,
  }) async {
    final validationError = validateSupabaseSyncSettings(settings);
    if (validationError != null) return SyncRunResult(error: validationError);

    onProgress?.call(const SyncProgress(percent: 0, label: '동기화를 준비하고 있습니다.'));
    var downloaded = 0;
    String? currentEntity;
    try {
      final bootstrap = await _local.prepareRemote(settings.normalized().url);
      onProgress?.call(
        const SyncProgress(percent: 5, label: '서버 데이터를 확인하고 있습니다.'),
      );
      final tombstonePages = <String, List<List<RemoteSyncRow>>>{};
      final finalCursors = <String, int>{};

      // Live rows need their referenced parents first. Parent tombstones stay
      // deferred so they cannot violate local foreign keys during this pass.
      for (
        var entityIndex = 0;
        entityIndex < syncPullOrder.length;
        entityIndex++
      ) {
        final entity = syncPullOrder[entityIndex];
        currentEntity = entity;
        var cursor = await _local.cursor(entity);
        while (true) {
          final rows = await _remote.fetchChanges(
            settings: settings.normalized(),
            entity: entity,
            afterRevision: cursor,
            limit: pageSize,
          );
          if (rows.isEmpty) {
            break;
          }
          final liveRows = rows
              .where((row) => !row.isDeleted)
              .toList(growable: false);
          final tombstones = rows
              .where((row) => row.isDeleted)
              .toList(growable: false);
          if (liveRows.isNotEmpty) {
            downloaded += await _local.applyRemotePage(
              entity: entity,
              rows: liveRows,
              bootstrap: bootstrap,
              updateCursor: false,
            );
          }
          if (tombstones.isNotEmpty) {
            (tombstonePages[entity] ??= []).add(tombstones);
          }
          cursor = rows.last.revision;
          if (rows.length < pageSize) break;
        }
        finalCursors[entity] = cursor;
        final completedTables = entityIndex + 1;
        onProgress?.call(
          SyncProgress(
            percent: 5 + (completedTables * 50 / syncPullOrder.length).round(),
            label: '서버 데이터 확인 중 ($completedTables/${syncPullOrder.length})',
          ),
        );
      }

      // Deletions follow the inverse dependency order: children, then parents.
      for (final entity in syncPullOrder.reversed) {
        for (final rows
            in tombstonePages[entity] ?? const <List<RemoteSyncRow>>[]) {
          downloaded += await _local.applyRemotePage(
            entity: entity,
            rows: rows,
            bootstrap: bootstrap,
            updateCursor: false,
          );
        }
      }
      // A failed tombstone application must not make a later run skip it.
      await _local.commitCursors(finalCursors);
      await _local.markBootstrapComplete();
      onProgress?.call(
        const SyncProgress(percent: 60, label: '서버 데이터를 반영했습니다.'),
      );
    } catch (error) {
      return SyncRunResult(
        downloaded: downloaded,
        error: _describeError(error),
        errorStage: 'download',
        errorEntity: currentEntity,
      );
    }

    final pushResult = await _pushPending(
      settings,
      onProgress: onProgress,
      startPercent: 60,
    );
    return SyncRunResult(
      uploaded: pushResult.uploaded,
      downloaded: downloaded,
      error: pushResult.error,
      errorStage: pushResult.errorStage,
      errorEntity: pushResult.errorEntity,
    );
  }

  Future<SyncRunResult> pushPending(
    SupabaseBackupSettings settings, {
    SyncProgressListener? onProgress,
  }) {
    return _pushPending(settings, onProgress: onProgress, startPercent: 0);
  }

  Future<SyncRunResult> _pushPending(
    SupabaseBackupSettings settings, {
    SyncProgressListener? onProgress,
    required int startPercent,
  }) async {
    final validationError = validateSupabaseSyncSettings(settings);
    if (validationError != null) return SyncRunResult(error: validationError);

    var uploaded = 0;
    String? currentEntity;
    try {
      var total = await _local.pendingEntryCount();
      var entries = await _local.pendingEntries(limit: uploadChunkSize);
      if (entries.isEmpty) {
        onProgress?.call(
          const SyncProgress(percent: 100, label: '동기화를 완료했습니다.'),
        );
        return const SyncRunResult();
      }
      if (total < entries.length) total = entries.length;

      var completed = 0;
      while (entries.isNotEmpty) {
        for (final entry in entries) {
          currentEntity = entry.entity;
          final current = await _local.currentEntry(entry.entity, entry.uuid);
          if (current == null || current.generation != entry.generation) {
            completed++;
            _reportUploadProgress(onProgress, startPercent, completed, total);
            continue;
          }

          final payload = entry.isDelete
              ? entry.tombstonePayload
              : await _local.buildPayload(entry.entity, entry.uuid);
          if (!entry.isDelete && payload == null) {
            throw StateError(
              '${entry.entity}/${entry.uuid} 업로드 대상 행을 찾을 수 없습니다.',
            );
          }

          final accepted = await _remote.upsert(
            settings: settings.normalized(),
            entity: entry.entity,
            uuid: entry.uuid,
            payload: payload!,
            deletedAt: entry.isDelete ? entry.changedAt : null,
          );
          if (accepted.uuid != entry.uuid ||
              accepted.isDeleted != entry.isDelete) {
            throw StateError(
              '${entry.entity}/${entry.uuid} 동기화 결과가 요청 상태와 다릅니다. '
              'Supabase 동기화 SQL을 최신 버전으로 다시 실행해주세요.',
            );
          }
          if (await _local.acknowledge(entry)) uploaded++;
          completed++;
          _reportUploadProgress(onProgress, startPercent, completed, total);
        }

        entries = await _local.pendingEntries(limit: uploadChunkSize);
      }
      return SyncRunResult(uploaded: uploaded);
    } catch (error) {
      return SyncRunResult(
        uploaded: uploaded,
        error: _describeError(error),
        errorStage: 'upload',
        errorEntity: currentEntity,
      );
    }
  }

  static void _reportUploadProgress(
    SyncProgressListener? onProgress,
    int startPercent,
    int completed,
    int total,
  ) {
    final boundedCompleted = completed.clamp(0, total);
    final percent =
        startPercent +
        (boundedCompleted * (100 - startPercent) / total).round();
    onProgress?.call(
      SyncProgress(
        percent: percent,
        label: completed >= total
            ? '동기화를 완료했습니다.'
            : '로컬 데이터 업로드 중 ($completed/$total)',
      ),
    );
  }

  static String _describeError(Object error) {
    if (error is PostgrestException) {
      final code = error.code == null ? '' : ' (${error.code})';
      return '${error.message}$code';
    }
    if (error is AuthException) return error.message;
    return error.toString();
  }
}
