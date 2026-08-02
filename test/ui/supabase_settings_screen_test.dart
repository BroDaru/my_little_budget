import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase/supabase.dart';

import 'package:my_little_budget/app.dart';
import 'package:my_little_budget/data/database.dart';
import 'package:my_little_budget/data/local_sync_store.dart';
import 'package:my_little_budget/data/providers.dart';
import 'package:my_little_budget/data/supabase_backup_settings.dart';
import 'package:my_little_budget/data/supabase_incremental_sync_service.dart';
import 'package:my_little_budget/data/supabase_sync_auth.dart';
import 'package:my_little_budget/data/supabase_sync_coordinator.dart';
import 'package:my_little_budget/data/supabase_operation_status.dart';
import 'package:my_little_budget/data/supabase_table_sync_service.dart';
import 'package:my_little_budget/data/sync_models.dart';
import 'package:my_little_budget/router/app_router.dart';

const _configuredSupabasePrefs = {
  'mlb-supabase-backup-url-v1': 'https://example.supabase.co',
  'mlb-supabase-backup-anon-key-v1': 'anon-key',
  'mlb-supabase-backup-bucket-v1': 'backups',
  'mlb-supabase-auth-email-v1': 'user@example.com',
};

void main() {
  testWidgets('Mobile data management renders Supabase settings controls', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(390, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MyLittleBudgetApp(),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MyLittleBudgetApp)),
    );
    container.read(appRouterProvider).go('/settings/backup');
    await tester.pumpAndSettle();
    await tester.tap(find.text('자동 동기화'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile-settings-supabase-url-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-settings-supabase-email-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-settings-supabase-password-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-settings-supabase-save-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-settings-supabase-test-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-settings-supabase-table-test-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-settings-supabase-upload-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-settings-supabase-restore-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-settings-supabase-status-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-settings-json-backup-status-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-settings-supabase-sync-now-button')),
      findsOneWidget,
    );
  });

  testWidgets(
    'Mobile data management defaults to local without Supabase setup',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(390, 860));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MyLittleBudgetApp(),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MyLittleBudgetApp)),
      );
      container.read(appRouterProvider).go('/settings/backup');
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('mobile-settings-local-sync-panel')),
        findsWidgets,
      );
      expect(
        find.byKey(const ValueKey('mobile-settings-auto-sync-panel')),
        findsNothing,
      );
    },
  );

  testWidgets('Mobile data management defaults to auto sync when configured', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(_configuredSupabasePrefs);
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MyLittleBudgetApp(),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MyLittleBudgetApp)),
    );
    container.read(appRouterProvider).go('/settings/backup');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile-settings-auto-sync-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-settings-local-sync-panel')),
      findsNothing,
    );
  });

  testWidgets('Desktop data management renders DB table test button', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MyLittleBudgetApp(),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MyLittleBudgetApp)),
    );
    container.read(appRouterProvider).go('/settings/backup');
    await tester.pumpAndSettle();
    await tester.tap(find.text('자동 동기화'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-supabase-table-test-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-json-backup-status-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-supabase-sync-now-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-supabase-email-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-supabase-password-field')),
      findsOneWidget,
    );

    final setupGuide = find.text('자동동기화 설정방법');
    await tester.ensureVisible(setupGuide);
    await tester.tap(setupGuide);
    await tester.pumpAndSettle();

    expect(find.textContaining('앱 접근용 이메일 사용자 생성'), findsOneWidget);
    expect(find.textContaining('Supabase 대시보드에 로그인하는 계정'), findsOneWidget);
    expect(find.textContaining('SQL 스키마 설치'), findsOneWidget);
    expect(
      find.image(const AssetImage('assets/help/supabase-auth-user-create.png')),
      findsOneWidget,
    );
  });

  testWidgets(
    'Desktop data management defaults to local without Supabase setup',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MyLittleBudgetApp(),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MyLittleBudgetApp)),
      );
      container.read(appRouterProvider).go('/settings/backup');
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('settings-local-sync-panel')),
        findsWidgets,
      );
      expect(
        find.byKey(const ValueKey('settings-auto-sync-panel')),
        findsNothing,
      );
    },
  );

  testWidgets('Desktop data management defaults to auto sync when configured', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(_configuredSupabasePrefs);
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MyLittleBudgetApp(),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MyLittleBudgetApp)),
    );
    container.read(appRouterProvider).go('/settings/backup');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-auto-sync-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-local-sync-panel')),
      findsNothing,
    );
  });

  testWidgets('Mobile disables actions while DB table test is running', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(390, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = _PendingTableSyncService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          supabaseTableSyncServiceProvider.overrideWithValue(service),
        ],
        child: const MyLittleBudgetApp(),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MyLittleBudgetApp)),
    );
    container.read(appRouterProvider).go('/settings/backup');
    await tester.pumpAndSettle();
    await tester.tap(find.text('자동 동기화'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('mobile-settings-supabase-url-field')),
      'https://example.supabase.co',
    );
    await tester.enterText(
      find.byKey(const ValueKey('mobile-settings-supabase-anon-key-field')),
      'anon-key',
    );
    await tester.enterText(
      find.byKey(const ValueKey('mobile-settings-supabase-email-field')),
      'user@example.com',
    );
    final tableButton = find.byKey(
      const ValueKey('mobile-settings-supabase-table-test-button'),
    );
    await tester.ensureVisible(tableButton);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -220));
    await tester.pumpAndSettle();
    await tester.tap(tableButton);
    await tester.pump();

    expect(tester.widget<OutlinedButton>(tableButton).onPressed, isNull);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('mobile-settings-supabase-save-button')),
          )
          .onPressed,
      isNull,
    );

    service.complete();
    await tester.pumpAndSettle();
    expect(
      find.textContaining('${supabaseSyncTableNames.length}개를 확인했습니다'),
      findsOneWidget,
    );
  });

  testWidgets('Desktop separates persisted sync and JSON backup status', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      ..._configuredSupabasePrefs,
      'mlb-supabase-operation-status-v1': jsonEncode(
        const SupabaseOperationStatus(
          fullSyncResult: SyncOperationResult.success,
          fullSyncAttemptedAt: '2026-08-02T08:42:00Z',
          fullSyncSucceededAt: '2026-08-02T08:42:01Z',
          fullSyncUploaded: 2,
          fullSyncDownloaded: 1,
          autoUploadResult: SyncOperationResult.failure,
          autoUploadAttemptedAt: '2026-08-02T08:45:00Z',
          autoUploadError: 'network unavailable',
          pendingUploadCount: 1,
          storageCheckResult: StorageCheckResult.exists,
          storageCheckedAt: '2026-08-02T08:46:00Z',
        ).toJson(),
      ),
    });
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final coordinator = _ProgressCoordinator(db)..complete();
    addTearDown(coordinator.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          supabaseSyncCoordinatorProvider.overrideWithValue(coordinator),
        ],
        child: const MyLittleBudgetApp(),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MyLittleBudgetApp)),
    );
    container.read(appRouterProvider).go('/settings/backup');
    await tester.pumpAndSettle();

    expect(find.text('자동 동기화'), findsWidgets);
    expect(find.text('정상'), findsOneWidget);
    expect(find.text('JSON 백업 / 복원'), findsOneWidget);
    expect(find.text('백업 있음'), findsOneWidget);
    expect(
      find.textContaining('자동 업로드 오류: network unavailable'),
      findsOneWidget,
    );
  });

  testWidgets('Desktop shows percentage while settings save performs sync', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(_configuredSupabasePrefs);
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final coordinator = _ProgressCoordinator(db);
    addTearDown(coordinator.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          supabaseSyncAuthServiceProvider.overrideWithValue(_FakeAuthService()),
          supabaseSyncCoordinatorProvider.overrideWithValue(coordinator),
        ],
        child: const MyLittleBudgetApp(),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MyLittleBudgetApp)),
    );
    container.read(appRouterProvider).go('/settings/backup');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('settings-supabase-password-field')),
      'password',
    );
    final saveButton = find.byKey(
      const ValueKey('settings-supabase-save-button'),
    );
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('settings-supabase-sync-progress')),
      findsOneWidget,
    );
    expect(find.textContaining('64%'), findsOneWidget);

    coordinator.complete();
    await tester.pumpAndSettle();
  });
}

class _PendingTableSyncService implements SupabaseTableSyncService {
  final _completer =
      Completer<SupabaseTableSyncResult<SupabaseTableConnectionStatus>>();

  void complete() {
    _completer.complete(
      const SupabaseTableSyncResult.ok(
        SupabaseTableConnectionStatus(tables: supabaseSyncTableNames),
      ),
    );
  }

  @override
  Future<SupabaseTableSyncResult<SupabaseTableConnectionStatus>> testConnection(
    SupabaseBackupSettings settings,
  ) {
    return _completer.future;
  }
}

class _ProgressCoordinator extends SupabaseSyncCoordinator {
  _ProgressCoordinator(AppDatabase db)
    : super(
        database: db,
        service: SupabaseIncrementalSyncService(
          local: LocalSyncStore(db),
          remote: _NoopSyncGateway(),
        ),
        loadSettings: () async => null,
      );

  final _completion = Completer<SyncRunResult>();

  void complete() => _completion.complete(const SyncRunResult());

  @override
  void start({SyncResultListener? onResult}) {}

  @override
  Future<SyncRunResult> synchronizeNow() async => const SyncRunResult();

  @override
  Future<SyncRunResult> synchronizeNowWithProgress(
    SyncProgressListener onProgress,
  ) {
    onProgress(const SyncProgress(percent: 64, label: '로컬 데이터 업로드 중'));
    return _completion.future;
  }
}

class _FakeAuthService extends SupabaseSyncAuthService {
  _FakeAuthService() : super(tokenStore: _MemoryTokenStore());

  @override
  Future<SupabaseClient> signInWithPassword(
    SupabaseBackupSettings settings, {
    required String email,
    required String password,
  }) async {
    return SupabaseClient(
      settings.url,
      settings.anonKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  }
}

class _MemoryTokenStore implements SupabaseSyncTokenStore {
  @override
  Future<void> clear() async {}

  @override
  Future<SupabaseStoredSession?> read() async => null;

  @override
  Future<void> write(SupabaseStoredSession session) async {}
}

class _NoopSyncGateway implements SupabaseSyncGateway {
  @override
  Future<List<RemoteSyncRow>> fetchChanges({
    required SupabaseBackupSettings settings,
    required String entity,
    required int afterRevision,
    required int limit,
  }) async => const [];

  @override
  Future<RemoteSyncRow> upsert({
    required SupabaseBackupSettings settings,
    required String entity,
    required String uuid,
    required Map<String, Object?> payload,
    required String? deletedAt,
  }) {
    throw UnimplementedError();
  }
}
