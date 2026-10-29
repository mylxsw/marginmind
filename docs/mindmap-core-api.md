# 脑图一期数据 API（GUL-564）

从 `package:mm_core/mm_core.dart` 导入。编辑操作是纯函数：对返回的 `content` 提交一次 repository update，即一个撤销步骤；`StudySetEditor.restore` 恢复结构，保留现有复习历史。编辑器通过构造参数 `mapId` 指定目标导图，默认 `MindMap.defaultId`。

## 数据类型

- `CardSegment({required String text, String? annotationId})`；`Card.segments: List<CardSegment>`。空数组代表旧版单段字段，使用 `content.segmentsOf(card)` 解析有效段落；摘录标题仍是复习问题，不另生成段落。合并结果的 `annotationId` 指向第一处原文；只有主题/笔记时，`title` 是多行内容。
- `MapSummary.cardId: String?`：新建或读入后的概要指向主题卡片；nullable 仅为兼容旧构造调用。概要主题**没有自己的 MapNode**，位置由概要范围决定；子主题为普通 `MapNode(parentId: summary.cardId)`。添加子主题沿用 `addTopic`，改名使用 `rename` / `relabelSummary`。
- `RelationArrow { end, both, none }`；`MapRelation.arrow` 默认 `end`、`solid` 默认 `false`；`control1/2: RelationControlPoint?`，`RelationControlPoint(double dx, double dy)` 为相对各自端点中心的偏移。清空控制点恢复自动布局。
- `MapStructure { mind, logic, brace, tree }`；`MapPalette { system, rainbow, fresh, warm, morandi, ink }`；`MindMap.structure/palette` 默认 `mind/system`。
- `MapEditResult<T>`：`content`、可空 `value`、可空 `reason`、`succeeded`、`removedRelationCount`、`removedSummaryCount`。失败返回原 content，不创建部分数据。
- `MapEditReason`：`tooFewCards, missingCard, centerTopic, imageCard, summaryTopic, unsupportedCard, notMerged, differentParents, overlappingSummary, missingSummary`。UI 将枚举映射到本地化悬停文案。

## 编辑接口

以下是 `StudySetEditor` 上的 `MindMapEditing` 扩展方法，均已公开导出：

```dart
MapEditReason? mergeReason(StudySetContent c, Iterable<String> cardIds);
MapEditResult<Card> mergeCards(StudySetContent c, Iterable<String> cardIds);
MapEditResult<List<Card>> splitCard(StudySetContent c, String cardId);
MapEditReason? summaryReason(StudySetContent c, Iterable<String> cardIds,
    {String? excludingSummaryId});
MapEditResult<MapSummary> createSummary(StudySetContent c, Iterable<String> cardIds,
    {String label = ''});
MapEditResult<MapSummary> adjustSummaryRange(StudySetContent c, String summaryId,
    Iterable<String> cardIds);
StudySetContent updateRelation(StudySetContent c, String id,
    {RelationArrow? arrow, bool? solid, RelationControlPoint? control1,
    RelationControlPoint? control2, bool resetControl1 = false,
    bool resetControl2 = false});
StudySetContent reverseRelation(StudySetContent c, String id);
StudySetContent setMapStructure(StudySetContent c, MapStructure structure);
StudySetContent setMapPalette(StudySetContent c, MapPalette palette);
```

现有 `addSummary(c, ids, {label})` 继续返回 `(StudySetContent, MapSummary?)`，复用新校验。`removeSummary(c, id)` 同时删除概要主题与细分子树。概要选区自动覆盖两端间未选中的节点，禁止与已有范围重叠；默认文案由 UI 通过 `label` 传入。

现有 `addRelation(c, fromId, toId, {label})` 返回 `(StudySetContent, MapRelation?)`；重复端点（含反向）返回已有线和原 content，UI 可直接选中。

## 查询与迁移

```dart
List<CardSegment> StudySetContent.segmentsOf(Card card);
List<AnnotationSegmentMatch> StudySetContent.segmentsForAnnotation(
    String annotationId, {String? mapId});
bool StudySetContent.isPlaced(String cardId, {String mapId = MindMap.defaultId});
```

`AnnotationSegmentMatch` 有 `card` 和 `segmentIndex`，支持高亮反查精确段落；可按导图过滤。旧 `cardForAnnotation` 也检查全部段落。`isPlaced`、`relationsOf`、`branch` 支持概要主题。

文件格式升为 9，打开旧文件时备份并把概要 `label` 迁移成主题标题，生成稳定且防冲突的 cardId。直接 `StudySetContent.fromJson` 同样兼容旧概要；新字段缺失时采用默认值。

跨导图共享沿用既有模型：合并只改变目标导图的布局；被合并卡片如仍在其他导图使用则保留内容并暂停排期，复习记录不删除。拆分修改共享内容，因此所有包含该卡片的导图都会补齐新段落节点，第一段保留原 ID、子节点及关联线，新段落使用新 ID/排期。删除跨文档合并卡片的一处原文时，仅解除该段出处，保留文字和其余出处。
