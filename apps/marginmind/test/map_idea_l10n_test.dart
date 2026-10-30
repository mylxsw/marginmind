import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/l10n/generated/app_localizations.dart';
import 'package:marginmind/l10n/generated/app_localizations_en.dart';
import 'package:marginmind/l10n/generated/app_localizations_zh.dart';

/// Every string of the AI idea expansion UI (docs/mindmap-ai-expand-ui.md §10).
Map<String, String> _ideaStrings(AppLocalizations l) => {
  'menu': l.mapIdeaMenu,
  'expand': l.mapIdeaExpand,
  'expandEach': l.mapIdeaExpandEach(3),
  'expandMap': l.mapIdeaExpandMap,
  'wholeMap': l.mapIdeaWholeMap,
  'branchesOnly': l.mapIdeaBranchesOnly,
  'group': l.mapIdeaGroup,
  'fillSiblings': l.mapIdeaFillSiblings,
  'direction': l.mapIdeaDirection,
  'auto': l.mapIdeaDirectionAuto,
  'why': l.mapIdeaDirectionWhy,
  'example': l.mapIdeaDirectionExample,
  'counter': l.mapIdeaDirectionCounter,
  'question': l.mapIdeaDirectionQuestion,
  'action': l.mapIdeaDirectionAction,
  'depth': l.mapIdeaDepth,
  'depthLevels': l.mapIdeaDepthLevels(2),
  'amount': l.mapIdeaAmount,
  'few': l.mapIdeaAmountFew,
  'some': l.mapIdeaAmountSome,
  'many': l.mapIdeaAmountMany,
  'hint': l.mapIdeaHint,
  'grounded': l.mapIdeaGrounded,
  'expanding': l.mapIdeaExpanding('Spacing'),
  'expandingCount': l.mapIdeaExpandingCount(2),
  'stopped': l.mapIdeaStopped,
  'incompleteDepth': l.mapIdeaIncompleteDepth,
  'draftCount': l.mapIdeaDraftCount(4),
  'keptCount': l.mapIdeaKeptCount(3, 5),
  'regenerate': l.mapIdeaRegenerate,
  'adjust': l.mapIdeaAdjust,
  'regenerateAdjusted': l.mapIdeaRegenerateAdjusted,
  'discard': l.mapIdeaDiscard,
  'keep': l.mapIdeaKeep(3),
  'draftKeep': l.mapIdeaDraftKeep,
  'draftSkip': l.mapIdeaDraftSkip,
  'draftEdit': l.mapIdeaDraftEdit,
  'draftMore': l.mapIdeaDraftMore,
  'draftSemantics': l.mapIdeaDraftSemantics('Spacing', l.mapIdeaDraftKept),
  'draftKept': l.mapIdeaDraftKept,
  'draftSkipped': l.mapIdeaDraftSkipped,
  'newBranches': l.mapIdeaNewBranches,
  'addCount': l.mapIdeaAddCount(4),
  'fewer': l.mapIdeaFewer,
  'more': l.mapIdeaMore,
  'start': l.mapIdeaStart,
  'generate': l.mapIdeaGenerate,
  'added': l.mapIdeaAdded(5),
  'blocked': l.mapIdeaBlocked,
  'nothing': l.mapIdeaNothing,
  'stoppedEmpty': l.mapIdeaStoppedEmpty,
  'busy': l.mapIdeaBusy,
};

void main() {
  final en = AppLocalizationsEn();
  final zh = AppLocalizationsZh();

  test('every idea expansion string exists in both languages and differs where words do', () {
    final english = _ideaStrings(en), chinese = _ideaStrings(zh);
    expect(chinese.keys, english.keys);
    for (final key in english.keys) {
      expect(english[key], isNotEmpty, reason: key);
      expect(chinese[key], isNotEmpty, reason: key);
      expect(english[key], isNot(contains('{')), reason: '$key leaves a placeholder');
      expect(chinese[key], isNot(contains('{')), reason: '$key leaves a placeholder');
      if (key != 'addCount') expect(chinese[key], isNot(english[key]), reason: '$key is untranslated');
    }
  });

  test('placeholders and plurals read naturally', () {
    expect(en.mapIdeaExpandEach(1), 'Expand 1 Topic');
    expect(en.mapIdeaExpandEach(3), 'Expand 3 Topics');
    expect(zh.mapIdeaExpandEach(3), '分别扩展 3 个主题');
    expect(en.mapIdeaDepthLevels(1), '1 Level');
    expect(zh.mapIdeaDepthLevels(3), '3 层');
    expect(en.mapIdeaExpanding('Spacing'), 'Expanding “Spacing”');
    expect(zh.mapIdeaExpanding('间隔重复'), '扩展「间隔重复」');
    expect(en.mapIdeaExpandingCount(1), 'Expanding 1 Topic');
    expect(en.mapIdeaDraftCount(1), '1 idea');
    expect(zh.mapIdeaDraftCount(4), '4 条');
    expect(en.mapIdeaKeptCount(3, 5), '3 of 5 kept');
    expect(zh.mapIdeaKeptCount(3, 5), '保留 3 / 5');
    expect(en.mapIdeaKeep(1), 'Keep 1');
    expect(zh.mapIdeaKeep(4), '保留 4 条');
    expect(en.mapIdeaAdded(1), 'Added 1 topic');
    expect(zh.mapIdeaAdded(5), '已添加 5 个主题');
    expect(en.mapIdeaAddCount(4), '+4');
    expect(zh.mapIdeaDraftSemantics('提取练习', zh.mapIdeaDraftSkipped), 'AI 草稿，提取练习，未保留');
  });
}
