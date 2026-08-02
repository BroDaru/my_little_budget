import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_little_budget/data/supabase_operation_status.dart';
import 'package:my_little_budget/data/sync_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('persists full sync and auto upload results separately', () async {
    final first = ProviderContainer();
    final notifier = first.read(supabaseOperationStatusProvider.notifier);
    await notifier.whenReady;
    await notifier.recordFullSyncStarted(now: DateTime.utc(2026, 8, 2, 8));
    await notifier.recordFullSyncResult(
      const SyncRunResult(
        downloaded: 3,
        error: 'permission denied',
        errorStage: 'download',
        errorEntity: 'transactions',
      ),
      pendingUploadCount: 2,
      now: DateTime.utc(2026, 8, 2, 8, 1),
    );
    await notifier.recordAutoUploadStarted(now: DateTime.utc(2026, 8, 2, 8, 2));
    await notifier.recordAutoUploadResult(
      const SyncRunResult(uploaded: 1),
      pendingUploadCount: 1,
      now: DateTime.utc(2026, 8, 2, 8, 3),
    );
    first.dispose();

    final second = ProviderContainer();
    final restoredNotifier = second.read(
      supabaseOperationStatusProvider.notifier,
    );
    await restoredNotifier.whenReady;
    final restored = second.read(supabaseOperationStatusProvider);

    expect(restored.fullSyncResult, SyncOperationResult.failure);
    expect(restored.fullSyncDownloaded, 3);
    expect(restored.fullSyncErrorTable, 'transactions');
    expect(restored.autoUploadResult, SyncOperationResult.success);
    expect(restored.autoUploadCount, 1);
    expect(restored.pendingUploadCount, 1);
    second.dispose();
  });

  test('classifies authentication failures and redacts credentials', () async {
    final container = ProviderContainer();
    final notifier = container.read(supabaseOperationStatusProvider.notifier);
    await notifier.whenReady;
    await notifier.recordFullSyncStarted(now: DateTime.utc(2026, 8, 2));
    await notifier.recordFullSyncResult(
      const SyncRunResult(
        error:
            '401 JWT abcdefghij.abcdefghij.abcdefghij sb_secret_do_not_store',
      ),
      now: DateTime.utc(2026, 8, 2, 0, 1),
    );
    final status = container.read(supabaseOperationStatusProvider);

    expect(status.fullSyncResult, SyncOperationResult.authRequired);
    expect(status.fullSyncError, contains('[redacted-token]'));
    expect(status.fullSyncError, contains('[redacted-key]'));
    expect(status.fullSyncError, isNot(contains('sb_secret_do_not_store')));
    container.dispose();
  });

  test('DB and Storage resets do not overwrite each other', () async {
    final container = ProviderContainer();
    final notifier = container.read(supabaseOperationStatusProvider.notifier);
    await notifier.whenReady;
    await notifier.recordFullSyncStarted(now: DateTime.utc(2026, 8, 2));
    await notifier.recordFullSyncResult(
      const SyncRunResult(uploaded: 2, downloaded: 1),
      now: DateTime.utc(2026, 8, 2, 0, 1),
    );
    await notifier.recordStorageCheck(
      exists: true,
      remoteUpdatedAt: DateTime.utc(2026, 8, 1),
      now: DateTime.utc(2026, 8, 2, 0, 2),
    );

    await notifier.resetDbStatus();
    var status = container.read(supabaseOperationStatusProvider);
    expect(status.fullSyncResult, SyncOperationResult.none);
    expect(status.storageCheckResult, StorageCheckResult.exists);

    await notifier.resetStorageStatus();
    status = container.read(supabaseOperationStatusProvider);
    expect(status.storageCheckResult, StorageCheckResult.unknown);
    container.dispose();
  });
}
