import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_budget/app.dart';
import 'package:my_little_budget/data/database.dart';
import 'package:my_little_budget/data/local_sync_store.dart';
import 'package:my_little_budget/data/providers.dart';
import 'package:my_little_budget/data/supabase_backup_settings.dart';
import 'package:my_little_budget/data/supabase_incremental_sync_service.dart';
import 'package:my_little_budget/data/supabase_sync_coordinator.dart';
import 'package:my_little_budget/data/supabase_operation_status.dart';
import 'package:my_little_budget/data/sync_metadata.dart';
import 'package:my_little_budget/data/sync_models.dart';

const _settings = SupabaseBackupSettings(
  url: 'https://unit-test.supabase.co',
  anonKey: 'anon-key',
  bucket: '',
  authEmail: 'user@example.com',
);

void main() {
  test(
    'a committed local edit starts uploading before immediate app disposal',
    () async {
      final db = await _openDatabase();
      addTearDown(db.close);
      await _markAllSyncedAndClearOutbox(db);
      final remote = _SharedMemoryGateway();
      final coordinator = _coordinator(db, remote);

      coordinator.start();
      await db.tagsDao.createTag('close-immediately', '#123456');
      await Future<void>.delayed(Duration.zero);
      await coordinator.dispose();

      await expectLater(
        remote.firstUpsert.timeout(const Duration(milliseconds: 100)),
        completes,
      );
    },
  );

  test(
    'a local edit on one device is loaded when another device starts',
    () async {
      final mobileDb = await _openDatabase();
      await _markAllSyncedAndClearOutbox(mobileDb);
      final remote = _SharedMemoryGateway();
      final mobile = _coordinator(mobileDb, remote);
      try {
        mobile.start();
        await mobileDb.tagsDao.createTag('mobile-only', '#123456');
        await remote.firstUpsert.timeout(const Duration(seconds: 1));
        final uploaded = await mobile.pushNow();
        expect(uploaded.isOk, isTrue, reason: uploaded.error);
      } finally {
        await mobile.dispose();
        await mobileDb.close();
      }

      final windowsDb = await _openDatabase();
      final windows = _coordinator(windowsDb, remote);
      try {
        await _markAllSyncedAndClearOutbox(windowsDb);
        final result = await windows.synchronizeNow();
        final loaded = await windowsDb
            .customSelect(
              'SELECT name, color FROM tags WHERE name = ?',
              variables: const [Variable<String>('mobile-only')],
            )
            .getSingleOrNull();

        expect(result.isOk, isTrue, reason: result.error);
        expect(loaded?.read<String>('color'), '#123456');
      } finally {
        await windows.dispose();
        await windowsDb.close();
      }
    },
  );

  test('a successful push does not cancel a pending full-sync retry', () async {
    final db = await _openDatabase();
    addTearDown(db.close);
    await _markAllSyncedAndClearOutbox(db);
    final remote = _FailFirstFetchGateway();
    final coordinator = _coordinator(db, remote);
    addTearDown(coordinator.dispose);

    final failedPull = await coordinator.synchronizeNow();
    final successfulPush = await coordinator.pushNow();

    expect(failedPull.isOk, isFalse);
    expect(successfulPush.isOk, isTrue);
    await expectLater(
      remote.secondFetch.timeout(const Duration(seconds: 1)),
      completes,
    );
    expect(remote.fetchCount, greaterThan(1));
  });

  test(
    'records full sync and automatic upload results independently',
    () async {
      final db = await _openDatabase();
      addTearDown(db.close);
      await _markAllSyncedAndClearOutbox(db);
      final recorder = _MemoryStatusRecorder();
      final coordinator = _coordinator(
        db,
        _FailFirstFetchGateway(),
        statusRecorder: recorder,
        retryDelays: const [Duration(days: 1)],
      );
      addTearDown(coordinator.dispose);

      final failedFullSync = await coordinator.synchronizeNow();
      final successfulUpload = await coordinator.pushNow();

      expect(failedFullSync.isOk, isFalse);
      expect(successfulUpload.isOk, isTrue);
      expect(recorder.fullResult?.isOk, isFalse);
      expect(recorder.fullResult?.errorStage, 'download');
      expect(recorder.autoResult?.isOk, isTrue);
    },
  );

  testWidgets(
    'actual initial route does not backfill before a successful startup pull',
    (tester) async {
      final db = await _openDatabase();
      addTearDown(db.close);
      final coordinator = _FailedStartupCoordinator(db);
      var backfillRuns = 0;

      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            supabaseSyncCoordinatorProvider.overrideWithValue(coordinator),
            recurringBackfillProvider.overrideWith((ref) async {
              backfillRuns++;
              return 0;
            }),
          ],
          child: const MyLittleBudgetApp(),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());

      expect(backfillRuns, 0);
      expect(coordinator.pushCount, 0);
    },
  );

  testWidgets(
    'actual initial route backfills once after startup pull and once per resume',
    (tester) async {
      final db = await _openDatabase();
      addTearDown(db.close);
      final coordinator = _SuccessfulLifecycleCoordinator(db);
      var backfillRuns = 0;

      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            supabaseSyncCoordinatorProvider.overrideWithValue(coordinator),
            recurringBackfillProvider.overrideWith((ref) async {
              backfillRuns++;
              return 0;
            }),
          ],
          child: const MyLittleBudgetApp(),
        ),
      );
      await tester.pump();

      expect(backfillRuns, 0);
      expect(coordinator.syncCount, 1);

      coordinator.completeStartupPull();
      await tester.pump();
      await tester.pump();

      expect(backfillRuns, 1);
      expect(coordinator.pushCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();

      expect(coordinator.syncCount, 2);
      expect(backfillRuns, 2);
      expect(coordinator.pushCount, 2);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _FailedStartupCoordinator extends SupabaseSyncCoordinator {
  _FailedStartupCoordinator(AppDatabase db)
    : super(
        database: db,
        service: SupabaseIncrementalSyncService(
          local: LocalSyncStore(db),
          remote: _FailFirstFetchGateway(),
        ),
        loadSettings: () async => _settings,
      );

  var pushCount = 0;

  @override
  void start({SyncResultListener? onResult}) {}

  @override
  Future<SyncRunResult> synchronizeNow() async {
    return const SyncRunResult(error: 'pull failed');
  }

  @override
  Future<SyncRunResult> pushNow() async {
    pushCount++;
    return const SyncRunResult();
  }
}

class _SuccessfulLifecycleCoordinator extends SupabaseSyncCoordinator {
  _SuccessfulLifecycleCoordinator(AppDatabase db)
    : super(
        database: db,
        service: SupabaseIncrementalSyncService(
          local: LocalSyncStore(db),
          remote: _FailFirstFetchGateway(),
        ),
        loadSettings: () async => _settings,
      );

  final _startupPull = Completer<SyncRunResult>();
  var syncCount = 0;
  var pushCount = 0;

  void completeStartupPull() {
    if (!_startupPull.isCompleted) {
      _startupPull.complete(const SyncRunResult());
    }
  }

  @override
  void start({SyncResultListener? onResult}) {}

  @override
  Future<SyncRunResult> synchronizeNow() {
    syncCount++;
    if (syncCount == 1) return _startupPull.future;
    return Future.value(const SyncRunResult());
  }

  @override
  Future<SyncRunResult> pushNow() async {
    pushCount++;
    return const SyncRunResult();
  }
}

SupabaseSyncCoordinator _coordinator(
  AppDatabase db,
  SupabaseSyncGateway remote, {
  List<Duration> retryDelays = const [Duration(milliseconds: 10)],
  SupabaseSyncStatusRecorder? statusRecorder,
}) {
  return SupabaseSyncCoordinator(
    database: db,
    service: SupabaseIncrementalSyncService(
      local: LocalSyncStore(db),
      remote: remote,
    ),
    loadSettings: () async => _settings,
    retryDelays: retryDelays,
    statusRecorder: statusRecorder,
  );
}

class _MemoryStatusRecorder implements SupabaseSyncStatusRecorder {
  SyncRunResult? fullResult;
  SyncRunResult? autoResult;

  @override
  Future<void> recordAutoUploadResult(
    SyncRunResult result, {
    int? pendingUploadCount,
    DateTime? now,
  }) async {
    autoResult = result;
  }

  @override
  Future<void> recordAutoUploadStarted({DateTime? now}) async {}

  @override
  Future<void> recordFullSyncResult(
    SyncRunResult result, {
    int? pendingUploadCount,
    DateTime? now,
  }) async {
    fullResult = result;
  }

  @override
  Future<void> recordFullSyncStarted({DateTime? now}) async {}
}

Future<AppDatabase> _openDatabase() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await db.customSelect('SELECT 1').get();
  return db;
}

Future<void> _markAllSyncedAndClearOutbox(AppDatabase db) async {
  for (final table in localSyncTableNames) {
    await db.customStatement("UPDATE $table SET sync_status = 'synced'");
  }
  await db.customStatement('DELETE FROM sync_outbox');
}

class _FailFirstFetchGateway implements SupabaseSyncGateway {
  final _firstFetch = Completer<void>();
  final _secondFetch = Completer<void>();
  var fetchCount = 0;
  var upsertCount = 0;
  var _revision = 1;

  Future<void> get firstFetch => _firstFetch.future;
  Future<void> get secondFetch => _secondFetch.future;

  @override
  Future<List<RemoteSyncRow>> fetchChanges({
    required SupabaseBackupSettings settings,
    required String entity,
    required int afterRevision,
    required int limit,
  }) async {
    fetchCount++;
    if (!_firstFetch.isCompleted) {
      _firstFetch.complete();
      throw StateError('pull failed');
    }
    if (!_secondFetch.isCompleted) _secondFetch.complete();
    return const [];
  }

  @override
  Future<RemoteSyncRow> upsert({
    required SupabaseBackupSettings settings,
    required String entity,
    required String uuid,
    required Map<String, Object?> payload,
    required String? deletedAt,
  }) async {
    upsertCount++;
    final revision = _revision++;
    return RemoteSyncRow(
      uuid: uuid,
      payload: payload,
      updatedAt: DateTime.utc(
        2026,
        7,
        13,
      ).add(Duration(seconds: revision)).toIso8601String(),
      deletedAt: deletedAt,
      revision: revision,
    );
  }
}

class _SharedMemoryGateway implements SupabaseSyncGateway {
  final _rows = <String, Map<String, RemoteSyncRow>>{};
  final _firstUpsert = Completer<void>();
  var _revision = 1;

  Future<void> get firstUpsert => _firstUpsert.future;

  @override
  Future<List<RemoteSyncRow>> fetchChanges({
    required SupabaseBackupSettings settings,
    required String entity,
    required int afterRevision,
    required int limit,
  }) async {
    final rows =
        (_rows[entity]?.values ?? const <RemoteSyncRow>[])
            .where((row) => row.revision > afterRevision)
            .toList()
          ..sort((a, b) => a.revision.compareTo(b.revision));
    return rows.take(limit).toList(growable: false);
  }

  @override
  Future<RemoteSyncRow> upsert({
    required SupabaseBackupSettings settings,
    required String entity,
    required String uuid,
    required Map<String, Object?> payload,
    required String? deletedAt,
  }) async {
    final revision = _revision++;
    final row = RemoteSyncRow(
      uuid: uuid,
      payload: Map<String, Object?>.from(payload),
      updatedAt: DateTime.utc(
        2026,
        7,
        20,
      ).add(Duration(seconds: revision)).toIso8601String(),
      deletedAt: deletedAt,
      revision: revision,
    );
    (_rows[entity] ??= {})[uuid] = row;
    if (!_firstUpsert.isCompleted) _firstUpsert.complete();
    return row;
  }
}
