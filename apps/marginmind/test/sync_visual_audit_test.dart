/// Opt-in screenshots of production widgets with synthetic typed state.
/// MM_SCREENSHOTS=/absolute/output MM_FONT=/path/to/CJK.otf flutter test
/// test/sync_visual_audit_test.dart --concurrency=1
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/app/app.dart';
import 'package:marginmind/app/navigation.dart';
import 'package:marginmind/settings/app_settings.dart';
import 'package:marginmind/features/vocabulary/vocabulary_sync.dart';
import 'package:marginmind/features/library/library_screen.dart';
import 'package:marginmind/features/library/folder_sheet.dart';
import 'package:marginmind/features/library/recovery_sheet.dart';
import 'package:marginmind/features/workspace/widgets/content_sync_sheet.dart';
import 'package:marginmind/features/workspace/widgets/reading_continuations.dart';
import 'package:marginmind/settings/settings_window.dart';
import 'package:marginmind/settings/sync_settings_controller.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_sync/mm_sync.dart';

import 'content_sync_sheet_test.dart' show SyncRepository;
import 'helpers.dart';
import 'vocabulary_sync_test.dart' show SyncVocabulary;
import 'support/sync_visual_settings.dart';
import 'vocabulary_screenshots.dart';

const _capture = ValueKey('audit-capture');

void main() {
  setUpAll(loadVocabularyScreenshotFonts);
  for (final device in ['pc', 'ipad', 'phone']) {
    testWidgets('sync design audit $device', (tester) async {
      final phone = device == 'phone';
      tester.view.physicalSize = switch (device) {
        'phone' => const Size(393, 852),
        'ipad' => const Size(1024, 1366),
        _ => const Size(1440, 1000),
      };
      tester.view.devicePixelRatio = 1;
      if (phone) tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
      addTearDown(tester.view.reset);
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = true);
      final service = AuditSettings();
      final content = SyncRepository();
      await content.update('demo-1', (_) => demoContent());
      final vocabulary = SyncVocabulary();
      await vocabulary.save([
        VocabularyEntry(
          id: 'word',
          term: 'retrieval',
          language: 'en',
          kind: VocabularyKind.word,
          forms: ['retrieval'],
          createdAt: testNow,
          updatedAt: testNow,
          note: '通过主动回忆巩固记忆。',
        ),
      ]);
      vocabulary.status = VocabularySyncState(
        enabled: true,
        conflicts: [
          VocabularySyncConflict(
            entryId: 'word',
            term: 'retrieval',
            revision: 'r',
            field: VocabularySyncField.note,
            choices: const [VocabularySyncChoice('a', '通过主动回忆巩固记忆。'), VocabularySyncChoice('b', '检索练习：合上书，尝试用自己的话复述。')],
          ),
        ],
      );
      final base = await testOverrides(
        vocabulary: vocabulary,
        prefs: {'settings.language': 'zh', 'settings.appearance': 'light'},
        content: content,
      );
      final recovery = LibraryRecovery(
        enabled: true,
        entries: [
          LibraryRecoveryEntry(
            studySetId: 'demo-1',
            version: 'v',
            observedRevision: 'r',
            title: '认知科学入门',
            deleted: true,
            documents: ['学习的底层逻辑', '论文：检索练习效应'],
            cards: 18,
            hasUnresolvedChoices: true,
            preview: ['间隔重复不是机械重复，而是在即将遗忘时主动回忆。'],
          ),
        ],
      );
      final organization = LibraryOrganization(
        syncEnabled: true,
        queued: 2,
        entries: [
          FolderEntry(
            id: 'f1',
            revision: 'r',
            folder: const Folder(id: 'f1', name: '认知科学'),
            choices: [const FolderChoice(transaction: 't', name: '学习方法与认知科学', concurrentChoices: 2)],
          ),
          FolderEntry(
            id: 'f2',
            revision: 'r2',
            folder: const Folder(id: 'f2', name: '英语阅读'),
          ),
        ],
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: _capture,
          child: ProviderScope(
            overrides: [
              ...base,
              touchPlatformProvider.overrideWithValue(device != 'pc'),
              phoneProvider.overrideWithValue(phone),
              syncSettingsControllerProvider.overrideWithValue(service),
              libraryRecoveryProvider.overrideWith((ref) => Stream.value(recovery)),
              libraryOrganizationProvider.overrideWith((ref) => Stream.value(organization)),
              readingContinuationsProvider('demo-1').overrideWith(
                (ref) => Stream.value(
                  ReadingContinuations(
                    enabled: true,
                    items: [
                      for (final missing in [false, true])
                        ReadingContinuation(
                          deviceId: missing ? 'ipad' : 'mac',
                          deviceName: missing ? '书房 iPad' : '办公室 MacBook',
                          documentId: missing ? 'c2' : 'c1',
                          title: missing ? '论文：检索练习效应' : '学习的底层逻辑',
                          remoteRevision: 'r',
                          localToken: 'l',
                          position: PdfPosition(missing ? 3 : 24),
                          readAt: DateTime(2026, 11, 4, 9, 30),
                          availability: missing
                              ? ReadingContinuationAvailability.unavailable
                              : ReadingContinuationAvailability.ready,
                        ),
                    ],
                  ),
                ),
              ),
            ],
            child: const MarginMindApp(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> snap(String name) async {
        await tester.pumpAndSettle();
        final error = tester.takeException();
        expect(error, isNull);
        await saveVocabularyHintScreenshot(tester, '$device-$name', find.byKey(_capture));
      }

      BuildContext context() => tester.element(find.byType(LibraryScreen).first);
      Future<void> close() async {
        Navigator.of(tester.element(find.byType(SettingsWindow))).pop();
        await tester.pumpAndSettle();
      }

      Future<void> scrollTo(String key, {double alignment = 0}) async {
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(tester.element(find.byKey(ValueKey(key))), alignment: alignment);
        await tester.pumpAndSettle();
      }

      await snap('01-library-reference');
      showSettings(context());
      await tester.pumpAndSettle();
      if (phone) {
        // Open the existing General settings section from the phone hub.
        final general = find.text('通用');
        if (general.evaluate().isNotEmpty) await tester.tap(general.first);
      }
      await snap('02-settings-reference');
      await close();
      showSettings(context(), tab: SettingsTab.sync);
      await snap('03-sync-local');
      await close();
      service.libraryId = '7cfa8e26-98ac-4a92-a1d0-568fdd971704';
      service.setup = SyncSetup(libraryId: service.libraryId!, deviceId: 'local', deviceName: '我的设备', joining: false);
      service.devices = [
        const SyncDeviceInfo('local', '我的设备', 'v', local: true),
        const SyncDeviceInfo('ipad', '书房 iPad', 'v2', local: false),
      ];
      service.target = SyncTarget(
        service: 'webdav',
        account: 'reader@example.test',
        location: 'https://dav.example.test/Foliarc/',
        libraryId: service.libraryId!,
      );
      service.pending = 12;
      service.resources = [
        const SyncResourceStatus('demo-1', 'doc1', '学习的底层逻辑.pdf', 'v', SyncResourceAvailability.missing, 12582912),
        const SyncResourceStatus('demo-1', 'doc2', '论文：检索练习效应.pdf', 'v', SyncResourceAvailability.changed, 4194304),
      ];
      service.cacheUsage = const SyncCacheUsage(
        bytes: 104857600,
        chunks: 25,
        reclaimableBytes: 8388608,
        reclaimableChunks: 2,
        canReclaim: true,
      );
      showSettings(context(), tab: SettingsTab.sync);
      await snap('04-sync-connected');
      Future<void> tapKey(String key) async {
        await scrollTo(key);
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
      }

      await tapKey('sync-nav-files');
      await snap('05-resources-cache');
      await tapKey('sync-back');
      await tapKey('sync-nav-connection');
      await scrollTo('sync-connect');
      await snap('06-connect-form');
      await tester.enterText(find.byKey(const ValueKey('sync-password')), 'synthetic-test-password');
      service.nextFailure = SyncSettingsFailure.authentication;
      await tapKey('sync-connect');
      await snap('07-auth-error-location');
      expect(service.failure, SyncSettingsFailure.authentication);
      expect(find.text('认证失败，请检查账号和应用专用密码。').hitTestable(), findsOneWidget);
      await snap('08-auth-error-top');
      service.failure = null;
      service.nextFailure = null;
      await tapKey('sync-back');
      await tapKey('sync-nav-advanced');
      await service.previewHistoryCopy();
      await scrollTo('sync-copy-preview', alignment: .1);
      await snap('09-copy-preview');
      await scrollTo('sync-cache-inspect', alignment: .4);
      await snap('20-cache-management');
      await tapKey('sync-back');
      await tapKey('sync-nav-devices');
      await snap('21-devices');
      await close();
      content.publish(
        ContentSyncStatus(
          enabled: true,
          revision: 'r',
          queued: 3,
          conflicts: [
            ContentSyncConflict(
              id: 'choice',
              deviceName: '书房 iPad',
              canUseCandidate: true,
              concurrentChoices: 2,
              changes: const [
                ContentSyncDifference(
                  entity: ContentSyncEntity.card,
                  title: '间隔重复',
                  field: ContentSyncField.text,
                  current: '复习应安排在即将遗忘之前，主动回忆比重复阅读更有效。',
                  candidate: '先尝试回忆，再阅读原文。复习间隔随记忆稳定度逐步延长。',
                ),
              ],
            ),
          ],
        ),
      );
      showContentSyncSheet(context(), 'demo-1');
      await snap('10-content-conflict');
      if (phone) {
        expect(find.text('间隔重复').evaluate().isNotEmpty || find.textContaining('间隔重复').evaluate().isNotEmpty, isTrue);
      }
      await scrollTo('content-sync-use-choice', alignment: .7);
      await snap('11-conflict-actions');
      await scrollTo('reading-continue-ipad-c2');
      await snap('12-reading-continuation');
      Navigator.of(tester.element(find.byType(ContentSyncSheet))).pop();
      await tester.pumpAndSettle();
      showLibraryRecovery(context());
      await snap('13-deleted-content');
      await tester.tap(find.text('恢复为副本').first);
      await snap('14-recovery-confirm');
      Navigator.of(tester.element(find.byType(LibraryRecoverySheet))).pop();
      await tester.pumpAndSettle();
      showFolderSheet(context());
      await snap('15-folder-conflict');
      Navigator.of(tester.element(find.byType(FolderSheet))).pop();
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(context());
      container.read(navigationProvider.notifier).showVocabulary();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('vocabulary-sync-open')));
      await snap('16-vocabulary-conflict');
      Navigator.of(tester.element(find.byType(VocabularySyncSheet))).pop();
      await tester.pumpAndSettle();
      container.read(navigationProvider.notifier).showLibrary();
      await tester.pumpAndSettle();
      await container.read(settingsProvider.notifier).setAppearance(AppearancePreference.dark);
      await tester.pumpAndSettle();
      showSettings(context(), tab: SettingsTab.sync);
      await snap('17-sync-dark');
      await close();
      await container.read(settingsProvider.notifier).setAppearance(AppearancePreference.light);
      await tester.pumpAndSettle();
      if (phone) {
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        showContentSyncSheet(context(), 'demo-1');
        await snap('18-conflict-large-text');
        Navigator.of(tester.element(find.byType(ContentSyncSheet))).pop();
        await tester.pumpAndSettle();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        showLibraryRecovery(context());
        await tester.pumpAndSettle();
        await tester.tap(find.text('恢复为副本').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('recovery-title')));
        tester.view.viewInsets = const FakeViewPadding(bottom: 320);
        await snap('19-recovery-keyboard-inset');
        final confirm = find.byKey(const ValueKey('recovery-confirm'));
        expect(confirm.hitTestable(), findsOneWidget);
        expect(tester.getRect(confirm).bottom, lessThanOrEqualTo(852 - 320));
        tester.view.resetViewInsets();
      }
      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await content.changes.close();
      await vocabulary.events.close();
      service.dispose();
    }, skip: !vocabularyScreenshotsEnabled);
  }
}
