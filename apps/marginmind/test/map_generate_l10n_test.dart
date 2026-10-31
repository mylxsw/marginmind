import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:marginmind/l10n/generated/app_localizations_en.dart';
import 'package:marginmind/l10n/generated/app_localizations_zh.dart';

/// Every string of the mind map from document UI (docs/mindmap-from-document-ui.md §14).
Map<String, String> _generateStrings(AppLocalizations l) => {
  'generate': l.mapGenerate,
  'menu': l.mapGenerateMenu,
  'documentMenu': l.mapGenerateDocumentMenu,
  'update': l.mapGenerateUpdate,
  'running': l.mapGenerateRunning,
  'reviewing': l.mapGenerateReviewing,
  'hasUpdates': l.mapHasUpdates,
  'hasMap': l.mapHasMap,
  'from': l.mapGenerateFrom('Memory'),
  'settings': l.mapGenerateSettings,
  'start': l.mapGenerateStart,
  'blank': l.mapGenerateBlank,
  'suggestExam': l.mapGenerateSuggestExam,
  'suggestExplain': l.mapGenerateSuggestExplain,
  'suggestQuotes': l.mapGenerateSuggestQuotes,
  'suggestExamples': l.mapGenerateSuggestExamples,
  'documents': l.mapGenerateDocuments,
  'pages': l.mapGeneratePages(48),
  'segments': l.mapGenerateSegments(9),
  'needsOcr': l.mapGenerateNeedsOcr,
  'wholeDocument': l.mapGenerateWholeDocument,
  'chapterCount': l.mapGenerateChapterCount(5, 6),
  'organization': l.mapGenerateOrganization,
  'byChapter': l.mapGenerateByChapter,
  'byTopic': l.mapGenerateByTopic,
  'mergeByTopic': l.mapGenerateMergeByTopic,
  'byQuestion': l.mapGenerateByQuestion,
  'detail': l.mapGenerateDetail,
  'brief': l.mapGenerateDetailBrief,
  'medium': l.mapGenerateDetailMedium,
  'full': l.mapGenerateDetailFull,
  'estimate': l.mapGenerateEstimate(3, 40),
  'content': l.mapGenerateContent,
  'myMarks': l.mapGenerateMyMarks,
  'markCount': l.mapGenerateMarkCount(12),
  'quotes': l.mapGenerateQuotes,
  'target': l.mapGenerateTarget,
  'targetNew': l.mapGenerateTargetNew,
  'targetBranch': l.mapGenerateTargetBranch,
  'targetReplace': l.mapGenerateTargetReplace('Memory'),
  'instructions': l.mapGenerateInstructions,
  'reading': l.mapGenerateReading('Memory'),
  'building': l.mapGenerateBuilding,
  'topicCount': l.mapGenerateTopicCount(12),
  'queued': l.mapGenerateQueued,
  'chapterFailed': l.mapGenerateChapterFailed('6.6'),
  'blocked': l.mapGenerateBlocked,
  'created': l.mapGenerateCreated('Memory', 19),
  'nothing': l.mapGenerateNothing,
  'stoppedEmpty': l.mapGenerateStoppedEmpty,
  'draftSemantics': l.mapGenerateDraftSemantics('Encoding', 19, l.mapIdeaDraftKept),
  'readProgress': l.mapGenerateReadProgress(3, 6),
  'ready': l.mapGenerateReady(19),
  'sourceSemantics': l.mapSourceSemantics('Memory', 20),
  'bannerNoMap': l.mapBannerNoMap('Forgetting'),
  'bannerGenerate': l.mapBannerGenerate,
  'bannerMerge': l.mapBannerMerge,
  'bannerNeedsOcr': l.mapBannerNeedsOcr,
  'followSwitched': l.mapFollowSwitched('Memory'),
  'updateTitle': l.mapUpdateTitle,
  'sources': l.mapUpdateSources,
  'addDocument': l.mapUpdateAddDocument,
  'since': l.mapUpdateSince,
  'newHighlights': l.mapUpdateNewHighlights,
  'newNotes': l.mapUpdateNewNotes,
  'readTo': l.mapUpdateReadTo,
  'readRange': l.mapUpdateReadRange(38, 46),
  'scope': l.mapUpdateScope,
  'scopeNew': l.mapUpdateScopeNew,
  'scopeAll': l.mapUpdateScopeAll,
  'protected': l.mapUpdateProtected(7),
  'preview': l.mapUpdatePreview,
  'updateNothing': l.mapUpdateNothing,
  'added': l.mapDiffAdded,
  'renamed': l.mapDiffRenamed,
  'moved': l.mapDiffMoved,
  'removed': l.mapDiffRemoved,
  'tagNew': l.mapDiffTagNew,
  'tagMovedFrom': l.mapDiffTagMovedFrom('Encoding'),
  'tagRemove': l.mapDiffTagRemove,
  'moveRoute': l.mapDiffMoveRoute('Encoding', 'Retrieval'),
  'excerpt': l.mapDiffExcerpt('Testing beats rereading'),
  'diffProtected': l.mapDiffProtected,
  'apply': l.mapUpdateApply(8),
  'applied': l.mapUpdateApplied(8),
  'updateBlocked': l.mapUpdateBlocked,
  'addSemantics': l.mapDiffAddSemantics('Retrieval'),
  'renameSemantics': l.mapDiffRenameSemantics('Encoding', 'Encoding: into memory'),
  'moveSemantics': l.mapDiffMoveSemantics('Generation', 'Encoding', 'Retrieval'),
  'removeSemantics': l.mapDiffRemoveSemantics('Buffer', 'Duplicate'),
  'followDocument': l.settingsMapFollowDocument,
  'clearCache': l.settingsMapClearCache,
};

/// Same text in both languages by design: page ranges.
const _shared = {'readRange'};

void main() {
  final en = AppLocalizationsEn();
  final zh = AppLocalizationsZh();

  test('every map generation string exists in both languages and is translated', () {
    final english = _generateStrings(en), chinese = _generateStrings(zh);
    expect(chinese.keys, english.keys);
    for (final key in english.keys) {
      expect(english[key], isNotEmpty, reason: key);
      expect(chinese[key], isNotEmpty, reason: key);
      expect(english[key], isNot(contains('{')), reason: '$key leaves a placeholder');
      expect(chinese[key], isNot(contains('{')), reason: '$key leaves a placeholder');
      if (!_shared.contains(key)) expect(chinese[key], isNot(english[key]), reason: '$key is untranslated');
    }
  });

  test('copy stays short: names and states, no explanations', () {
    // Docs §2.9 and the UI copy rules: controls carry a name, not a sentence.
    const labels = {
      'generate',
      'update',
      'running',
      'reviewing',
      'settings',
      'start',
      'blank',
      'documents',
      'organization',
      'byChapter',
      'byTopic',
      'mergeByTopic',
      'byQuestion',
      'detail',
      'brief',
      'medium',
      'full',
      'content',
      'myMarks',
      'quotes',
      'target',
      'targetNew',
      'targetBranch',
      'instructions',
      'bannerGenerate',
      'bannerMerge',
      'updateTitle',
      'sources',
      'addDocument',
      'scope',
      'scopeNew',
      'scopeAll',
      'preview',
      'added',
      'renamed',
      'moved',
      'removed',
      'tagNew',
      'tagRemove',
      'diffProtected',
    };
    for (final l in <AppLocalizations>[en, zh]) {
      final strings = _generateStrings(l);
      for (final key in labels) {
        final text = strings[key]!;
        expect(text.length, lessThanOrEqualTo(26), reason: '$key: $text');
        expect(text, isNot(matches(RegExp(r'[。.!！?？]$'))), reason: '$key ends like a sentence');
      }
    }
  });

  test('placeholders and plurals read naturally', () {
    expect(zh.mapGenerateFrom('第6章 记忆'), '从「第6章 记忆」生成脑图');
    expect(en.mapGenerateFrom('Memory'), 'Generate a Map from “Memory”');
    expect(en.mapGeneratePages(1), '1 page');
    expect(en.mapGeneratePages(48), '48 pages');
    expect(zh.mapGeneratePages(48), '48 页');
    expect(zh.mapGenerateSegments(9), '分 9 段阅读');
    expect(zh.mapGenerateChapterCount(5, 6), '5 / 6 章');
    expect(en.mapGenerateChapterCount(5, 6), '5 of 6 chapters');
    expect(zh.mapGenerateEstimate(3, 40), '3 层 · 约 40 个主题');
    expect(zh.mapGenerateMarkCount(12), '12 条');
    expect(en.mapGenerateTopicCount(1), '1 topic');
    expect(zh.mapGenerateTopicCount(12), '12 个主题');
    expect(zh.mapGenerateReading('第6章 记忆'), '阅读「第6章 记忆」');
    expect(zh.mapGenerateChapterFailed('6.6 提取'), '「6.6 提取」未生成');
    expect(zh.mapGenerateCreated('第6章 记忆', 19), '已生成脑图「第6章 记忆」 · 19 个主题');
    expect(en.mapGenerateCreated('Memory', 1), 'Created “Memory” · 1 topic');
    expect(en.mapGenerateCreated('Memory', 19), 'Created “Memory” · 19 topics');
    expect(zh.mapGenerateDraftSemantics('编码', 19, zh.mapIdeaDraftKept), 'AI 草稿，编码，第 19 页，已保留');
    expect(
      en.mapGenerateDraftSemantics('Encoding', 19, en.mapIdeaDraftSkipped),
      'AI draft, Encoding, page 19, not kept',
    );
    expect(zh.mapBannerNoMap('第7章 遗忘'), '「第7章 遗忘」还没有脑图');
    expect(zh.mapFollowSwitched('第6章 记忆'), '已切换到「第6章 记忆」');
    expect(zh.mapUpdateReadRange(38, 46), 'p.38 → p.46');
    expect(zh.mapUpdateProtected(7), '你改过、添加的 7 个节点保持不变');
    expect(en.mapUpdateProtected(1), '1 edited topic stays as is');
    expect(zh.mapDiffTagMovedFrom('编码'), '移自 编码');
    expect(zh.mapDiffMoveRoute('编码', '提取与提取练习'), '从「编码」移到「提取与提取练习」');
    expect(zh.mapUpdateApply(8), '应用 8 项');
    expect(en.mapUpdateApply(1), 'Apply 1');
    expect(en.mapUpdateApplied(8), 'Updated 8 items');
    expect(zh.mapDiffRenameSemantics('编码', '编码：信息怎样进入长时记忆'), '建议改名，编码 改为 编码：信息怎样进入长时记忆');
    expect(zh.mapSourceSemantics('第6章 记忆', 20), '第6章 记忆，第 20 页');
  });
}
