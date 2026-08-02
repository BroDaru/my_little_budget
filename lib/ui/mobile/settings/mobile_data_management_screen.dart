import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/backup.dart';
import '../../../data/providers.dart';
import '../../../data/supabase_backup_service.dart';
import '../../../data/supabase_backup_settings.dart';
import '../../../data/supabase_operation_status.dart';
import '../../../data/supabase_sync_auth.dart';
import '../../../data/supabase_table_sync_service.dart';
import '../../../data/sync_models.dart';
import 'package:my_little_budget/features/notes/providers.dart';
import 'package:my_little_budget/features/accounts/providers.dart'
    as accounts_providers;
import 'package:my_little_budget/features/budget/providers.dart'
    as budget_providers;
import 'package:my_little_budget/features/investments/providers.dart'
    as investments_providers;
import 'package:my_little_budget/features/settings/providers.dart'
    as settings_providers;
import 'package:my_little_budget/features/budget/badges_providers.dart'
    as badges_providers;
import 'package:my_little_budget/features/stats/providers.dart'
    as stats_providers;
import 'package:my_little_budget/features/transactions/providers.dart'
    as transactions_providers;
import '../mobile_widgets.dart';

enum _SyncMode { local, auto, windows }

class MobileDataManagementScreen extends ConsumerStatefulWidget {
  const MobileDataManagementScreen({super.key});

  @override
  ConsumerState<MobileDataManagementScreen> createState() =>
      _MobileDataManagementScreenState();
}

class _MobileDataManagementScreenState
    extends ConsumerState<MobileDataManagementScreen> {
  bool _busy = false;
  SyncProgress? _syncProgress;
  _SyncMode _selectedMode = _SyncMode.local;
  late final _supabaseUrlCtrl = TextEditingController();
  late final _supabaseAnonKeyCtrl = TextEditingController();
  late final _supabaseEmailCtrl = TextEditingController();
  late final _supabasePasswordCtrl = TextEditingController();
  late final _supabaseBucketCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadSupabaseSettings);
  }

  @override
  void dispose() {
    _supabaseUrlCtrl.dispose();
    _supabaseAnonKeyCtrl.dispose();
    _supabaseEmailCtrl.dispose();
    _supabasePasswordCtrl.dispose();
    _supabaseBucketCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSupabaseSettings() async {
    final notifier = ref.read(supabaseBackupSettingsProvider.notifier);
    await notifier.whenReady;
    if (!mounted) return;
    final settings = ref.read(supabaseBackupSettingsProvider);
    _fillSupabaseControllers(settings);
    setState(() {
      _selectedMode = settings.isConfigured || settings.isTableSyncConfigured
          ? _SyncMode.auto
          : _SyncMode.local;
    });
  }

  void _fillSupabaseControllers(SupabaseBackupSettings settings) {
    _supabaseUrlCtrl.text = settings.url;
    _supabaseAnonKeyCtrl.text = settings.anonKey;
    _supabaseEmailCtrl.text = settings.authEmail;
    _supabasePasswordCtrl.clear();
    _supabaseBucketCtrl.text = settings.bucket;
  }

  Future<void> _refreshSupabaseRemoteStatus() async {
    final draft = _supabaseDraft();
    final error = validateSupabaseBackupSettings(draft);
    if (error != null) {
      await ref
          .read(supabaseOperationStatusProvider.notifier)
          .recordStorageFailure(error);
      return;
    }

    final result = await ref
        .read(supabaseBackupServiceProvider)
        .getRemoteStatus(draft);
    final statusNotifier = ref.read(supabaseOperationStatusProvider.notifier);
    if (result.isOk) {
      await statusNotifier.recordStorageCheck(
        exists: result.value!.exists,
        remoteUpdatedAt: result.value!.updatedAt,
      );
    } else {
      await statusNotifier.recordStorageFailure(result.error!);
    }
  }

  Future<void> _exportBackup() async {
    setState(() => _busy = true);
    try {
      final backup = await ref.read(backupDaoProvider).exportBackup();
      final filename = buildBackupFilename();
      final path = await FilePicker.saveFile(
        dialogTitle: '백업 파일 저장',
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: utf8.encode(backup.toJsonString()),
      );
      if (path == null || !mounted) return;
      _showSnack('백업 파일을 만들었습니다.');
    } catch (e) {
      debugPrint('exportBackup failed: $e');
      if (mounted) _showSnack('백업에 실패했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBackup() async {
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.pickFiles(
        dialogTitle: '복원할 백업 파일 선택',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        allowMultiple: false,
      );
      if (picked == null || picked.files.single.path == null) return;

      final content = await File(picked.files.single.path!).readAsString();
      final parsed = parseBackup(content);
      if (!parsed.isOk) {
        _showSnack(parsed.error ?? '백업 파일 형식이 올바르지 않습니다.');
        return;
      }

      if (!mounted) return;
      final confirmed = await _confirmRestore(context);
      if (confirmed != true) return;

      await ref.read(backupDaoProvider).importBackup(parsed.backup!);
      _invalidateAfterImport(ref);
      await rebuildNoteNotifications(ref);
      if (!mounted) return;
      _showSnack('백업을 복원했습니다.');
    } catch (e) {
      debugPrint('importBackup failed: $e');
      if (mounted) _showSnack('복원에 실패했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetAllData() async {
    final confirmed = await _confirmReset(context);
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(backupDaoProvider).resetAllData();
      _invalidateAfterImport(ref);
      await rebuildNoteNotifications(ref);
      if (!mounted) return;
      _showSnack('초기화했습니다.');
    } catch (e) {
      debugPrint('resetAllData failed: $e');
      if (mounted) _showSnack('초기화에 실패했습니다. 데이터를 다시 확인해주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  SupabaseBackupSettings _supabaseDraft() {
    return SupabaseBackupSettings(
      url: _supabaseUrlCtrl.text,
      anonKey: _supabaseAnonKeyCtrl.text,
      bucket: _supabaseBucketCtrl.text,
      authEmail: _supabaseEmailCtrl.text,
      pathPrefix: SupabaseBackupSettings.defaultPathPrefix,
    );
  }

  Future<void> _saveSupabaseSettings() async {
    final draft = _supabaseDraft();
    final error = validateSupabaseConnectionSettings(draft);
    if (error != null) {
      _showSnack(error);
      return;
    }
    final previous = ref.read(supabaseBackupSettingsProvider);
    final statusNotifier = ref.read(supabaseOperationStatusProvider.notifier);

    setState(() {
      _busy = true;
      _syncProgress = const SyncProgress(
        percent: 0,
        label: 'Supabase에 로그인하고 있습니다.',
      );
    });
    try {
      await statusNotifier.recordFullSyncStarted();
      await ref
          .read(supabaseSyncAuthServiceProvider)
          .signInWithPassword(
            draft,
            email: _supabaseEmailCtrl.text,
            password: _supabasePasswordCtrl.text,
          );
      await _resetStatusForChangedIdentity(previous, draft);
      await ref.read(supabaseBackupSettingsProvider.notifier).save(draft);
      _supabasePasswordCtrl.clear();
      final syncResult = await ref
          .read(supabaseSyncCoordinatorProvider)
          .synchronizeNowWithProgress(_updateSyncProgress);
      if (!mounted) return;
      _fillSupabaseControllers(ref.read(supabaseBackupSettingsProvider));
      setState(() => _selectedMode = _SyncMode.auto);
      _showSnack(
        syncResult.isOk
            ? 'Supabase 연결 설정을 저장하고 동기화했습니다.'
            : '설정은 저장했지만 동기화하지 못했습니다: ${sanitizeSupabaseError(syncResult.error)}',
      );
    } catch (e) {
      await statusNotifier.recordFullSyncResult(
        SyncRunResult(error: e.toString(), errorStage: 'auth'),
      );
      debugPrint('saveSupabaseSettings failed: ${sanitizeSupabaseError('$e')}');
      if (mounted) _showSnack('Supabase 설정 저장에 실패했습니다.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _syncProgress = null;
        });
      }
    }
  }

  void _updateSyncProgress(SyncProgress progress) {
    if (mounted) setState(() => _syncProgress = progress);
  }

  Future<void> _resetStatusForChangedIdentity(
    SupabaseBackupSettings previous,
    SupabaseBackupSettings next,
  ) async {
    final oldValue = previous.normalized();
    final newValue = next.normalized();
    final notifier = ref.read(supabaseOperationStatusProvider.notifier);
    if (oldValue.url != newValue.url ||
        oldValue.anonKey != newValue.anonKey ||
        oldValue.authEmail != newValue.authEmail) {
      await notifier.resetDbStatus();
    }
    if (oldValue.url != newValue.url ||
        oldValue.anonKey != newValue.anonKey ||
        oldValue.bucket != newValue.bucket) {
      await notifier.resetStorageStatus();
    }
  }

  Future<void> _syncNow() async {
    final draft = _supabaseDraft();
    final error = validateSupabaseSyncSettings(draft);
    if (error != null) {
      _showSnack(error);
      return;
    }
    setState(() {
      _busy = true;
      _syncProgress = const SyncProgress(percent: 0, label: '동기화를 준비하고 있습니다.');
    });
    try {
      final result = await ref
          .read(supabaseSyncCoordinatorProvider)
          .synchronizeNowWithProgress(_updateSyncProgress);
      if (!mounted) return;
      _showSnack(
        result.isOk
            ? '동기화했습니다. 업로드 ${result.uploaded}건, 다운로드 ${result.downloaded}건'
            : '동기화하지 못했습니다: ${sanitizeSupabaseError(result.error)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _syncProgress = null;
        });
      }
    }
  }

  Future<void> _testSupabaseSettings() async {
    final draft = _supabaseDraft();
    final error = validateSupabaseBackupSettings(draft);
    if (error != null) {
      _showSnack(error);
      return;
    }

    setState(() => _busy = true);
    try {
      final result = await ref
          .read(supabaseBackupServiceProvider)
          .testConnection(draft);
      if (!result.isOk) {
        await ref
            .read(supabaseOperationStatusProvider.notifier)
            .recordStorageFailure(result.error!);
      }
      if (!mounted) return;
      _showSnack(
        result.isOk
            ? 'Supabase Storage 연결을 확인했습니다.'
            : sanitizeSupabaseError(result.error)!,
      );
      if (result.isOk) await _refreshSupabaseRemoteStatus();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testSupabaseTables() async {
    final draft = _supabaseDraft();
    final error = validateSupabaseSyncSettings(draft);
    if (error != null) {
      _showSnack(error);
      return;
    }

    setState(() => _busy = true);
    try {
      final result = await ref
          .read(supabaseTableSyncServiceProvider)
          .testConnection(draft);
      final statusNotifier = ref.read(supabaseOperationStatusProvider.notifier);
      if (result.isOk) {
        await statusNotifier.recordDbConnectionSuccess(
          result.value!.tables.length,
        );
      } else {
        await statusNotifier.recordDbConnectionFailure(result.error!);
      }
      if (!mounted) return;
      _showSnack(
        result.isOk
            ? 'Supabase DB 엔티티 테이블 ${result.value!.tables.length}개를 확인했습니다.'
            : sanitizeSupabaseError(result.error)!,
      );
    } catch (error) {
      debugPrint('testSupabaseTables failed: $error');
      if (mounted) _showSnack('Supabase DB 테이블 확인에 실패했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearSupabaseSettings() async {
    setState(() => _busy = true);
    try {
      await ref.read(supabaseSyncAuthServiceProvider).disconnect();
      await ref.read(supabaseBackupSettingsProvider.notifier).clear();
      await ref.read(supabaseOperationStatusProvider.notifier).resetAll();
      if (!mounted) return;
      _fillSupabaseControllers(SupabaseBackupSettings.empty);
      setState(() {
        _selectedMode = _SyncMode.local;
      });
      _showSnack('Supabase 연결 설정을 삭제했습니다.');
    } catch (e) {
      debugPrint('clearSupabaseSettings failed: $e');
      if (mounted) _showSnack('Supabase 설정 삭제에 실패했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadSupabaseBackup() async {
    final draft = _supabaseDraft();
    final error = validateSupabaseBackupSettings(draft);
    if (error != null) {
      _showSnack(error);
      return;
    }

    setState(() => _busy = true);
    try {
      await _resetStatusForChangedIdentity(
        ref.read(supabaseBackupSettingsProvider),
        draft,
      );
      await ref.read(supabaseBackupSettingsProvider.notifier).save(draft);
      final backup = await ref.read(backupDaoProvider).exportBackup();
      final result = await ref
          .read(supabaseBackupServiceProvider)
          .uploadBackup(settings: draft, backup: backup);
      if (!mounted) return;
      if (!result.isOk) {
        await ref
            .read(supabaseOperationStatusProvider.notifier)
            .recordStorageFailure(result.error!);
        _showSnack(sanitizeSupabaseError(result.error)!);
        return;
      }
      await ref.read(supabaseBackupSettingsProvider.notifier).markBackupNow();
      await _refreshSupabaseRemoteStatus();
      _showSnack('Supabase에 백업했습니다.');
    } catch (e) {
      await ref
          .read(supabaseOperationStatusProvider.notifier)
          .recordStorageFailure(e.toString());
      debugPrint('uploadSupabaseBackup failed: ${sanitizeSupabaseError('$e')}');
      if (mounted) _showSnack('Supabase 백업에 실패했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreSupabaseBackup() async {
    final draft = _supabaseDraft();
    final error = validateSupabaseBackupSettings(draft);
    if (error != null) {
      _showSnack(error);
      return;
    }

    setState(() => _busy = true);
    try {
      final result = await ref
          .read(supabaseBackupServiceProvider)
          .downloadLatestBackup(draft);
      if (!result.isOk) {
        await ref
            .read(supabaseOperationStatusProvider.notifier)
            .recordStorageFailure(result.error!);
        if (mounted) _showSnack(sanitizeSupabaseError(result.error)!);
        return;
      }

      final parsed = parseBackup(result.value!);
      if (!parsed.isOk) {
        if (mounted) _showSnack(parsed.error ?? '백업 파일 형식이 올바르지 않습니다.');
        return;
      }

      if (!mounted) return;
      final confirmed = await _confirmRestore(context);
      if (confirmed != true) return;

      await ref.read(backupDaoProvider).importBackup(parsed.backup!);
      _invalidateAfterImport(ref);
      await rebuildNoteNotifications(ref);
      await ref.read(supabaseBackupSettingsProvider.notifier).markRestoreNow();
      if (!mounted) return;
      await _refreshSupabaseRemoteStatus();
      _showSnack('Supabase 백업을 복원했습니다.');
    } catch (e) {
      await ref
          .read(supabaseOperationStatusProvider.notifier)
          .recordStorageFailure(e.toString());
      debugPrint(
        'restoreSupabaseBackup failed: ${sanitizeSupabaseError('$e')}',
      );
      if (mounted) _showSnack('Supabase 복원에 실패했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final supabaseSettings = ref.watch(supabaseBackupSettingsProvider);
    final operationStatus = ref.watch(supabaseOperationStatusProvider);

    return MobilePage(
      title: '데이터 관리',
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : () => context.go('/settings'),
            icon: const Icon(Icons.chevron_left),
            label: const Text('설정'),
          ),
        ),
        Text(
          '현재 데이터를 JSON 백업 파일로 저장하거나, 선택한 백업 파일로 데이터를 복원할 수 있습니다.',
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(height: 12),
        _SyncModeSelector(
          selected: _selectedMode,
          onChanged: (mode) => setState(() => _selectedMode = mode),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: switch (_selectedMode) {
            _SyncMode.local => _LocalBackupPanel(
              key: const ValueKey('mobile-settings-local-sync-panel'),
              busy: _busy,
              onExport: _exportBackup,
              onImport: _importBackup,
            ),
            _SyncMode.auto => _SupabaseSettingsCard(
              key: const ValueKey('mobile-settings-auto-sync-panel'),
              urlController: _supabaseUrlCtrl,
              anonKeyController: _supabaseAnonKeyCtrl,
              emailController: _supabaseEmailCtrl,
              passwordController: _supabasePasswordCtrl,
              bucketController: _supabaseBucketCtrl,
              configured:
                  supabaseSettings.isConfigured ||
                  supabaseSettings.isTableSyncConfigured,
              settings: supabaseSettings,
              operationStatus: operationStatus,
              busy: _busy,
              onSave: _saveSupabaseSettings,
              onTest: _testSupabaseSettings,
              onTestTables: _testSupabaseTables,
              onClear: _clearSupabaseSettings,
              onUpload: _uploadSupabaseBackup,
              onRestore: _restoreSupabaseBackup,
              onRefresh: _refreshSupabaseRemoteStatus,
              onSyncNow: _syncNow,
            ),
            _SyncMode.windows => const _WindowsDownloadPanel(
              key: ValueKey('mobile-settings-windows-download-panel'),
            ),
          },
        ),
        if (_busy) ...[
          if (_syncProgress != null) ...[
            Text(
              '${_syncProgress!.label} ${_syncProgress!.percent}%',
              key: const ValueKey(
                'mobile-settings-supabase-sync-progress-label',
              ),
            ),
            const SizedBox(height: 8),
          ],
          LinearProgressIndicator(
            key: const ValueKey('mobile-settings-supabase-sync-progress'),
            minHeight: 3,
            value: _syncProgress?.fraction,
          ),
        ],
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.5),
        _ResetDeviceButton(
          key: const ValueKey('mobile-settings-data-reset-button'),
          busy: _busy,
          onPressed: _resetAllData,
        ),
      ],
    );
  }
}

class _SyncModeSelector extends StatelessWidget {
  const _SyncModeSelector({required this.selected, required this.onChanged});

  final _SyncMode selected;
  final ValueChanged<_SyncMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return MobileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SyncModeRow(
            mode: _SyncMode.local,
            selected: selected,
            label: '로컬',
            onChanged: onChanged,
          ),
          const SizedBox(height: 12),
          _SyncModeRow(
            mode: _SyncMode.auto,
            selected: selected,
            label: '자동 동기화',
            onChanged: onChanged,
          ),
          const SizedBox(height: 12),
          _SyncModeRow(
            mode: _SyncMode.windows,
            selected: selected,
            label: 'Windows 버전 설치',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SyncModeRow extends StatelessWidget {
  const _SyncModeRow({
    required this.mode,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final _SyncMode mode;
  final _SyncMode selected;
  final String label;
  final ValueChanged<_SyncMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = selected == mode;
    final color = context.appIncome;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(mode),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? color
                    : theme.colorScheme.onSurface.withValues(alpha: 0.38),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalBackupPanel extends StatelessWidget {
  const _LocalBackupPanel({
    super.key,
    required this.busy,
    required this.onExport,
    required this.onImport,
  });

  final bool busy;
  final VoidCallback onExport;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: key,
      children: [
        _ActionCard(
          icon: Icons.file_upload_outlined,
          title: 'JSON 백업 내보내기',
          description: '현재 데이터를 하나의 JSON 파일로 저장합니다.',
          buttonLabel: '백업 파일 만들기',
          onPressed: busy ? null : onExport,
        ),
        _ActionCard(
          icon: Icons.file_download_outlined,
          title: 'JSON 백업 불러오기',
          description: '백업 JSON 파일을 확인한 뒤 현재 데이터를 백업 데이터로 교체합니다.',
          buttonLabel: '백업 파일 선택',
          danger: true,
          onPressed: busy ? null : onImport,
        ),
      ],
    );
  }
}

class _WindowsDownloadPanel extends StatelessWidget {
  const _WindowsDownloadPanel({super.key});

  static const _releasesUrl =
      'https://github.com/Flynn-Kalar/my_little_budget/releases';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.75);

    return MobileCard(
      child: Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.desktop_windows_outlined, color: context.appIncome),
              const SizedBox(width: 12),
              Text(
                '다운로드',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Windows PC 버전은 GitHub Releases에서 받을 수 있습니다.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 12),
          SelectableText(
            'Windows 버전 다운로드\n$_releasesUrl',
            style: TextStyle(
              color: context.appIncome,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Android 버전은 현재 내부 테스트/직접 설치용으로 제공됩니다.',
            style: TextStyle(color: muted),
          ),
        ],
      ),
    );
  }
}

class _ResetDeviceButton extends StatelessWidget {
  const _ResetDeviceButton({
    super.key,
    required this.busy,
    required this.onPressed,
  });

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          foregroundColor: context.appExpense,
          backgroundColor: context.appExpense.withValues(alpha: 0.10),
        ),
        icon: const Icon(Icons.delete_forever_outlined),
        label: const Text('기기 초기화'),
      ),
    );
  }
}

class _SupabaseSettingsCard extends StatelessWidget {
  const _SupabaseSettingsCard({
    super.key,
    required this.urlController,
    required this.anonKeyController,
    required this.emailController,
    required this.passwordController,
    required this.bucketController,
    required this.configured,
    required this.settings,
    required this.operationStatus,
    required this.busy,
    required this.onSave,
    required this.onTest,
    required this.onTestTables,
    required this.onClear,
    required this.onUpload,
    required this.onRestore,
    required this.onRefresh,
    required this.onSyncNow,
  });

  final TextEditingController urlController;
  final TextEditingController anonKeyController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController bucketController;
  final bool configured;
  final SupabaseBackupSettings settings;
  final SupabaseOperationStatus operationStatus;
  final bool busy;
  final VoidCallback onSave;
  final VoidCallback onTest;
  final VoidCallback onTestTables;
  final VoidCallback onClear;
  final VoidCallback onUpload;
  final VoidCallback onRestore;
  final VoidCallback onRefresh;
  final VoidCallback onSyncNow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.75);

    return MobileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.cloud_sync_outlined, color: context.appIncome),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Supabase 자동 동기화 및 백업',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _AutoSyncSetupGuide(),
          const SizedBox(height: 12),
          Text(
            'DB 동기화는 사용자가 입력한 Supabase Auth 이메일 계정으로 보호됩니다. 비밀번호는 저장하지 않고 로그인 세션만 보안 저장소에 보관합니다. service_role/secret key는 입력하지 마세요.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 12),
          _AutoSyncStatusPanel(settings: settings, status: operationStatus),
          const SizedBox(height: 12),
          _JsonBackupStatusPanel(settings: settings, status: operationStatus),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('mobile-settings-supabase-url-field'),
            controller: urlController,
            enabled: !busy,
            decoration: const InputDecoration(
              labelText: 'Supabase URL',
              hintText: 'https://project-ref.supabase.co',
              prefixIcon: Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('mobile-settings-supabase-anon-key-field'),
            controller: anonKeyController,
            enabled: !busy,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'anon / publishable key',
              prefixIcon: Icon(Icons.key_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('mobile-settings-supabase-email-field'),
            controller: emailController,
            enabled: !busy,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Supabase Auth 이메일',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('mobile-settings-supabase-password-field'),
            controller: passwordController,
            enabled: !busy,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Supabase Auth 비밀번호',
              helperText: '비밀번호는 기기에 저장하지 않습니다.',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('mobile-settings-supabase-bucket-field'),
            controller: bucketController,
            enabled: !busy,
            decoration: const InputDecoration(
              labelText: 'Storage bucket',
              hintText: 'my-little-budget',
              helperText: 'JSON 백업/복원을 사용할 때만 입력합니다.',
              prefixIcon: Icon(Icons.inventory_2_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const ValueKey('mobile-settings-supabase-save-button'),
                onPressed: busy ? null : onSave,
                icon: const Icon(Icons.save_outlined),
                label: const Text('설정 저장'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('mobile-settings-supabase-test-button'),
                onPressed: busy ? null : onTest,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Storage 연결 테스트'),
              ),
              OutlinedButton.icon(
                key: const ValueKey(
                  'mobile-settings-supabase-table-test-button',
                ),
                onPressed: busy ? null : onTestTables,
                icon: const Icon(Icons.storage_outlined),
                label: const Text('DB 테이블 테스트'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('mobile-settings-supabase-refresh-button'),
                onPressed: busy ? null : onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('백업 상태 확인'),
              ),
              FilledButton.icon(
                key: const ValueKey('mobile-settings-supabase-sync-now-button'),
                onPressed: busy ? null : onSyncNow,
                icon: const Icon(Icons.sync),
                label: const Text('지금 동기화'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('mobile-settings-supabase-clear-button'),
                onPressed: busy || !configured ? null : onClear,
                icon: const Icon(Icons.delete_outline),
                label: const Text('설정 삭제'),
              ),
              FilledButton.icon(
                key: const ValueKey('mobile-settings-supabase-upload-button'),
                onPressed: busy ? null : onUpload,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('JSON 백업 업로드'),
              ),
              FilledButton.icon(
                key: const ValueKey('mobile-settings-supabase-restore-button'),
                onPressed: busy ? null : onRestore,
                icon: const Icon(Icons.cloud_download_outlined),
                label: const Text('JSON 백업 복원'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AutoSyncSetupGuide extends StatefulWidget {
  const _AutoSyncSetupGuide();

  @override
  State<_AutoSyncSetupGuide> createState() => _AutoSyncSetupGuideState();
}

class _AutoSyncSetupGuideState extends State<_AutoSyncSetupGuide> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: const ValueKey('mobile-settings-auto-sync-setup-guide'),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExpansionTile(
        initiallyExpanded: _expanded,
        onExpansionChanged: (value) => setState(() => _expanded = value),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        leading: Icon(Icons.help_outline, color: context.appIncome),
        title: const Text(
          '자동동기화 설정방법',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        children: const [_AutoSyncSetupSteps()],
      ),
    );
  }
}

class _AutoSyncSetupSteps extends StatelessWidget {
  const _AutoSyncSetupSteps();

  static const _supabaseUrl = 'https://supabase.com/';
  static final _tableSyncSql = rootBundle.loadString(
    'supabase/table_sync_v2_schema.sql',
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = TextStyle(
      color: theme.colorScheme.onSurface,
      height: 1.45,
      fontSize: 18,
      fontWeight: FontWeight.w800,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('1. ', style: style),
            InkWell(
              onTap: () => _openSupabase(context),
              child: Text(
                _supabaseUrl,
                style: style.copyWith(
                  color: context.appIncome,
                  fontWeight: FontWeight.w800,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            Text(
              '에서 GitHub 아이디가 있으면 GitHub 연동으로 로그인합니다. GitHub 아이디가 없으면 계정을 생성합니다.',
              style: style,
            ),
          ],
        ),
        const SizedBox(height: 10),
        const _GuideImage(assetName: 'assets/help/supabase-sign-up.png'),
        const SizedBox(height: 10),
        Text(
          '2. 조직 생성 화면에서 Type은 Personal, Plan은 Free 플랜으로 시작하면 됩니다.',
          style: style,
        ),
        const SizedBox(height: 10),
        const _GuideImage(
          assetName: 'assets/help/supabase-create-organization.png',
        ),
        const SizedBox(height: 10),
        Text('3. Supabase 프로젝트를 만듭니다.', style: style),
        const SizedBox(height: 10),
        const _GuideImage(assetName: 'assets/help/supabase-create-project.png'),
        const SizedBox(height: 10),
        Text(
          '지역은 Asia-Pacific처럼 아시아 지역으로 지정하는 것이 좋습니다. 비밀번호를 설정해야 Storage bucket 생성이 가능합니다.',
          style: style,
        ),
        const SizedBox(height: 10),
        Text('4. JSON 백업/복원도 사용할 경우에만 Storage bucket을 생성합니다.', style: style),
        const SizedBox(height: 10),
        const _GuideImage(
          assetName: 'assets/help/supabase-create-storage-bucket.png',
        ),
        const SizedBox(height: 10),
        Text(
          '5. 앱 접근용 이메일 사용자 생성: Authentication - Sign In / Providers에서 Email 공급자가 활성화되어 있는지 확인합니다. 이어서 Authentication - Users에서 Add user - Create new user를 눌러 이메일/비밀번호 사용자를 하나 만듭니다.',
          style: style,
        ),
        const SizedBox(height: 10),
        const _GuideImage(
          assetName: 'assets/help/supabase-auth-user-create.png',
        ),
        const SizedBox(height: 10),
        Text(
          '중요: 여기서 만드는 이메일과 비밀번호는 my_little_budget 앱이 데이터에 접근할 때 사용하는 Supabase Auth 사용자 로그인 정보입니다. Supabase 대시보드에 로그인하는 계정의 이메일/비밀번호와는 별개이므로, 대시보드 계정 정보를 입력하지 마세요.',
          style: style,
        ),
        const SizedBox(height: 10),
        Text('6. 프로젝트 메인페이지에서 프로젝트 URL을 복사 후 동기화 설정창에 입력합니다.', style: style),
        const SizedBox(height: 10),
        const _GuideImage(
          assetName: 'assets/help/supabase-project-url-copy.png',
        ),
        const SizedBox(height: 10),
        Text(
          '7. Settings - API Keys에서 publishable key(또는 legacy anon public)를 복사해 입력합니다. secret/service_role key는 사용하지 않습니다.',
          style: style,
        ),
        const SizedBox(height: 10),
        const _GuideImage(assetName: 'assets/help/supabase-anon-key-copy.png'),
        const SizedBox(height: 10),
        Text(
          '8. JSON 백업/복원을 사용할 경우에만 앞서 만든 bucket name을 입력합니다. DB 증분 동기화만 쓸 때는 비워둬도 됩니다.',
          style: style,
        ),
        const SizedBox(height: 10),
        const _GuideImage(
          assetName: 'assets/help/supabase-storage-bucket-create.png',
        ),
        const SizedBox(height: 10),
        const _GuideImage(
          assetName: 'assets/help/supabase-storage-bucket-name.png',
        ),
        const SizedBox(height: 10),
        Text(
          '9. URL, anon/publishable key, 5단계에서 만든 앱 접근용 Auth 이메일/비밀번호, bucket을 입력하고 설정 저장을 누릅니다. 로그인 성공 후 비밀번호는 저장하지 않고 세션만 보안 저장소에 보관합니다.',
          style: style,
        ),
        const SizedBox(height: 10),
        Text(
          '10. SQL 스키마 설치: 앱에서 설정 저장을 눌러 Auth 로그인을 완료한 뒤 Supabase 대시보드의 SQL Editor를 엽니다. 아래 SQL 명령어를 그대로 붙여넣고 Run 버튼을 누릅니다.',
          style: style,
        ),
        const SizedBox(height: 10),
        const _GuideImage(assetName: 'assets/help/supabase-sql-editor.png'),
        const SizedBox(height: 10),
        FutureBuilder<String>(
          future: _tableSyncSql,
          builder: (context, snapshot) =>
              _SqlCommandBlock(sql: snapshot.data ?? '-- SQL 명령어를 불러오는 중입니다.'),
        ),
        const SizedBox(height: 10),
        Text(
          '11. DB 테이블 테스트를 실행합니다. 이후 변경사항은 즉시 업로드되고 앱 시작 시 변경분만 내려옵니다.',
          style: style,
        ),
      ],
    );
  }

  Future<void> _openSupabase(BuildContext context) async {
    final opened = await launchUrl(
      Uri.parse(_supabaseUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Supabase 링크를 열 수 없습니다.')));
    }
  }
}

class _GuideImage extends StatelessWidget {
  const _GuideImage({required this.assetName});

  final String assetName;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showImagePreview(context),
          child: Image.asset(assetName, fit: BoxFit.contain),
        ),
      ),
    );
  }

  void _showImagePreview(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    boundaryMargin: const EdgeInsets.all(1000),
                    minScale: 0.8,
                    maxScale: 8,
                    child: Center(
                      child: Image.asset(assetName, fit: BoxFit.contain),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton.filled(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SqlCommandBlock extends StatefulWidget {
  const _SqlCommandBlock({required this.sql});

  final String sql;

  @override
  State<_SqlCommandBlock> createState() => _SqlCommandBlockState();
}

class _SqlCommandBlockState extends State<_SqlCommandBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final codeStyle = TextStyle(
      color: theme.colorScheme.onSurface,
      fontFamily: 'monospace',
      fontSize: 12,
      height: 1.35,
    );

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: _expanded ? '접기' : '펼치기',
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        _expanded ? 'SQL 명령어 접기' : 'SQL 명령어 펼쳐보기',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.75,
                          ),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: widget.sql));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('SQL 명령어를 복사했습니다.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('복사'),
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: SelectableText(widget.sql, style: codeStyle),
            ),
          ],
        ],
      ),
    );
  }
}

class _AutoSyncStatusPanel extends StatelessWidget {
  const _AutoSyncStatusPanel({required this.settings, required this.status});

  final SupabaseBackupSettings settings;
  final SupabaseOperationStatus status;

  @override
  Widget build(BuildContext context) {
    final badge = _syncBadge(settings, status);
    final lines = <String>[
      '설정: ${settings.isTableSyncConfigured ? '완료' : '미설정'}',
      '동작: 앱 시작·복귀 시 전체 동기화, 데이터 변경 시 자동 업로드',
      '최근 전체 동기화: ${_syncResultLabel(status.fullSyncResult)}',
      '실행 시각: ${_formatIso(status.fullSyncAttemptedAt)}',
      '최근 성공: ${_formatIso(status.fullSyncSucceededAt)}',
      '전송: 업로드 ${status.fullSyncUploaded}건 / 다운로드 ${status.fullSyncDownloaded}건',
      '최근 자동 업로드: ${_syncResultLabel(status.autoUploadResult)}',
      '자동 업로드 시각: ${_formatIso(status.autoUploadAttemptedAt)}',
      '자동 업로드: ${status.autoUploadCount}건',
      '업로드 대기: ${status.pendingUploadCount == null ? '집계되지 않음' : '${status.pendingUploadCount}건'}',
      'DB 연결 확인: ${_dbConnectionLabel(status)}',
    ];
    final stage = [
      status.fullSyncErrorTable,
      status.fullSyncErrorStage,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' / ');
    if (stage.isNotEmpty) lines.add('실패 단계: $stage');
    if (status.fullSyncError != null) lines.add('오류: ${status.fullSyncError}');
    if (status.autoUploadError != null) {
      lines.add('자동 업로드 오류: ${status.autoUploadError}');
    }
    return _StatusPanel(
      panelKey: const ValueKey('mobile-settings-supabase-status-panel'),
      title: '자동 동기화',
      badge: badge,
      lines: lines,
    );
  }
}

class _JsonBackupStatusPanel extends StatelessWidget {
  const _JsonBackupStatusPanel({required this.settings, required this.status});

  final SupabaseBackupSettings settings;
  final SupabaseOperationStatus status;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      'Storage 설정: ${settings.isConfigured ? '사용 가능' : '미설정'}',
      '파일: ${settings.normalized().pathPrefix}/latest.json',
      '원격 백업: ${_storageResultLabel(status.storageCheckResult)}',
      '상태 확인: ${_formatIso(status.storageCheckedAt)}',
      '원격 수정: ${_formatIso(status.storageRemoteUpdatedAt)}',
      '마지막 JSON 백업: ${_formatIso(settings.lastBackupAt)}',
      '마지막 JSON 복원: ${_formatIso(settings.lastRestoreAt)}',
    ];
    if (status.storageError != null) {
      lines.add('Storage 오류: ${status.storageError}');
    }
    return _StatusPanel(
      panelKey: const ValueKey('mobile-settings-json-backup-status-panel'),
      title: 'JSON 백업 / 복원',
      badge: _storageBadge(settings, status),
      lines: lines,
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.panelKey,
    required this.title,
    required this.badge,
    required this.lines,
  });

  final Key panelKey;
  final String title;
  final ({String label, _StatusTone tone}) badge;
  final List<String> lines;

  @override
  Widget build(BuildContext context) => Container(
    key: panelKey,
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            _StatusChip(label: badge.label, tone: badge.tone),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          lines.join('\n'),
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.75),
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}

String _formatIso(String? value) {
  if (value == null || value.isEmpty) return '없음';
  return _formatDate(DateTime.tryParse(value));
}

String _formatDate(DateTime? value) {
  if (value == null) return '';
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

enum _StatusTone { neutral, progress, success, warning, error }

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.tone});

  final String label;
  final _StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      _StatusTone.success => context.appIncome,
      _StatusTone.error => context.appExpense,
      _StatusTone.progress => context.appAccent,
      _StatusTone.warning => Theme.of(context).colorScheme.tertiary,
      _StatusTone.neutral => Theme.of(
        context,
      ).colorScheme.onSurface.withValues(alpha: 0.75),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

({String label, _StatusTone tone}) _syncBadge(
  SupabaseBackupSettings settings,
  SupabaseOperationStatus status,
) {
  if (!settings.isTableSyncConfigured) {
    return (label: '미설정', tone: _StatusTone.neutral);
  }
  return switch (status.fullSyncResult) {
    SyncOperationResult.none => (label: '확인 전', tone: _StatusTone.neutral),
    SyncOperationResult.running => (label: '동기화 중', tone: _StatusTone.progress),
    SyncOperationResult.success => (label: '정상', tone: _StatusTone.success),
    SyncOperationResult.authRequired => (
      label: '로그인 필요',
      tone: _StatusTone.warning,
    ),
    SyncOperationResult.failure => (label: '오류', tone: _StatusTone.error),
  };
}

({String label, _StatusTone tone}) _storageBadge(
  SupabaseBackupSettings settings,
  SupabaseOperationStatus status,
) {
  if (!settings.isConfigured) {
    return (label: '미설정', tone: _StatusTone.neutral);
  }
  return switch (status.storageCheckResult) {
    StorageCheckResult.unknown => (label: '확인 전', tone: _StatusTone.neutral),
    StorageCheckResult.exists => (label: '백업 있음', tone: _StatusTone.success),
    StorageCheckResult.missing => (label: '백업 없음', tone: _StatusTone.warning),
    StorageCheckResult.failure => (label: '연결 오류', tone: _StatusTone.error),
  };
}

String _syncResultLabel(SyncOperationResult result) => switch (result) {
  SyncOperationResult.none => '기록 없음',
  SyncOperationResult.running => '실행 중',
  SyncOperationResult.success => '성공',
  SyncOperationResult.failure => '실패',
  SyncOperationResult.authRequired => '로그인 필요',
};

String _dbConnectionLabel(
  SupabaseOperationStatus status,
) => switch (status.dbConnectionResult) {
  DbConnectionResult.unknown => '확인 전',
  DbConnectionResult.success =>
    '정상 (${status.dbConnectionTableCount ?? 0}개, ${_formatIso(status.dbConnectionCheckedAt)})',
  DbConnectionResult.failure => '오류 (${status.dbConnectionError ?? '원인 불명'})',
};

String _storageResultLabel(StorageCheckResult result) => switch (result) {
  StorageCheckResult.unknown => '확인 전',
  StorageCheckResult.exists => 'latest.json 있음',
  StorageCheckResult.missing => 'latest.json 없음',
  StorageCheckResult.failure => '확인 실패',
};

Future<bool?> _confirmReset(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('데이터 초기화'),
      content: const Text('현재 데이터를 초기 상태로 되돌립니다. 이 작업은 되돌릴 수 없습니다.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('초기화'),
        ),
      ],
    ),
  );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = danger ? context.appExpense : context.appIncome;

    return MobileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.75,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(danger ? Icons.restore_outlined : Icons.save_alt),
            label: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}

Future<bool?> _confirmRestore(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('백업 데이터 복원'),
      content: const Text('현재 데이터를 모두 지우고 백업 데이터를 복원합니다. 이 작업은 되돌릴 수 없습니다.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('복원'),
        ),
      ],
    ),
  );
}

void _invalidateAfterImport(WidgetRef ref) {
  ref.invalidate(notesProvider);
  ref.invalidate(pendingReminderCountProvider);
  ref.invalidate(accounts_providers.accountBalancesProvider);
  ref.invalidate(accounts_providers.archivedAccountsProvider);

  ref.invalidate(budget_providers.monthlyExpectedIncomeProvider);
  ref.invalidate(budget_providers.budgetRowsProvider);
  ref.invalidate(budget_providers.budgetExpenseCategoriesProvider);
  ref.invalidate(budget_providers.budgetActiveAccountsProvider);
  ref.invalidate(badges_providers.overBudgetCountProvider);

  ref.invalidate(transactions_providers.transactionsListProvider);
  ref.invalidate(transactions_providers.monthlySummaryProvider);
  ref.invalidate(transactions_providers.activeAccountsProvider);
  ref.invalidate(transactions_providers.activeCategoriesProvider);
  ref.invalidate(transactions_providers.allTagsProvider);
  ref.invalidate(transactions_providers.recentMemosProvider);

  ref.invalidate(investments_providers.investmentRowsProvider);
  ref.invalidate(investments_providers.investmentMonthlySummaryProvider);
  ref.invalidate(investments_providers.investmentAccountProvider);
  ref.invalidate(investments_providers.currentHoldingsProvider);
  ref.invalidate(investments_providers.realizedPnlProvider);

  ref.invalidate(stats_providers.statsExpenseBreakdownProvider);
  ref.invalidate(stats_providers.statsMonthlyTrendProvider);

  ref.invalidate(settings_providers.allCategoriesProvider);
  ref.invalidate(settings_providers.settingsActiveCategoriesProvider);
  ref.invalidate(settings_providers.settingsAccountsProvider);
  ref.invalidate(settings_providers.settingsTagsProvider);
  ref.invalidate(settings_providers.recurringItemsProvider);
  ref.invalidate(settings_providers.transactionPresetItemsProvider);
}
