# 脑图 AI 扩展想法：界面规格

> 建立日期：2026-10-30（GUL-606，父任务 GUL-581）。上位文档：[`mindmap-ai-expand.md`](mindmap-ai-expand.md)（§7 为已定决定）；数据结构、模型契约与写入链路以上位文档 §3–§4 为准，本文只定界面。
> 交互原型：[`design/prototype/mindmap-ai-expand.html`](../design/prototype/mindmap-ai-expand.html)，15 个场景与本文 §12 对应。
> 视觉以现有应用和 `mm_design` 令牌为准，原型的 CSS 数值只作参考。没有写到的细节沿用 [`design-system.md`](design-system.md) 和 [`phase-3-assistant-ui.md`](phase-3-assistant-ui.md)。

本文写给上位文档 §6 A–D 批次的实现者：每个界面给出尺寸（pt）、令牌、状态、文案、键盘与无障碍语义，以及对照现有组件的实现位置。

**界面原则（必须遵守）。** 不加多余的次级标签和说明文字，让布局表达含义；不加多余的辅助文字、描述性文案和重复的界面微文案。具体到本功能：

- 弹层不显示上下文路径；计划卡没有副标题，也不写分支现状（“还是空的”）；生成中不显示阶段文字；画布上没有操作提示。
- 按钮只写动作，快捷键用右侧的浅色键帽表示，不写成句子。
- 提示条（HUD）只写结果（“已添加 5 个主题”），不附带跳过数量或原因说明。
- 不可用的操作：与当前选择无关的直接隐藏（单选时没有“归纳上级主题”）；因选择不满足条件而不可用的，置灰并在 tooltip 给出原因（复用 `mapEditDifferentParents`）。

---

## 0. 术语

| 术语 | 含义 |
| --- | --- |
| 目标 | 本次扩展的主题：单选主题、多选主题、中心主题（`assistantRootId`） |
| 草稿 | 一条 `ExpansionDraft`，在画布上画成 `MapGhostNode`；只在内存中 |
| 预览 | `ExpansionPreview`：一次扩展的全部草稿与移动，阶段为 generating / review / error |
| 保留 / 不要 | 草稿的 `kept` 状态；保留的草稿在 ↩ 时写入脑图 |
| 归纳 | “归纳上级主题”：新上级是草稿，被移动的已有主题挂到它下面 |

---

## 1. 通用约定

### 1.1 新增令牌（`mm_design`，已在本任务落地）

**颜色**（`MMColors`，不随系统强调色变化，`tokens_test` 覆盖对比度）：

| 令牌 | 浅色 / 深色 | 用途 |
| --- | --- | --- |
| `researchWash` | `research` 6% / 10% | 草稿节点底色、弹层“扩展想法”区底色 |
| `onResearch` | `#FFFFFF` / `#1E1E1F` | 实心 `research` 上的文字和图标：主按钮、选中的方向、草稿方向标签、底部条“保留”按钮 |

为什么新增 `onResearch`：深色 `research`（`#7D7AFF`）上的白字只有 3.4:1；深色字为 4.8:1，浅色白字为 5.1:1。`research` 字放在 `researchTint` 上也只有 4.0:1 / 3.2:1，因此小字标签一律用实心底（与 [study-notes-ui.md](study-notes-ui.md) §1 的结论一致）。

**尺寸**（`MMSizes`）：

| 常量 | 值 | 用途 |
| --- | --- | --- |
| `ideaPrimaryButton` | 34 | 弹层“扩展想法”主按钮高度 |
| `ideaChip` | 22 | 方向 chip 高度（圆角为高度一半） |
| `ideaBar` | 40 | 生成 / 审阅底部条高度（圆角为高度一半） |
| `ideaBarBottomInset` | 64 | 底部条下沿到脑图面板底边（再加 `chrome.bottom`），避开视图控制（12 + 28）和窗口 HUD |
| `ideaAdjustWidth` | 330 | 调整菜单宽度 |
| `ideaPlanWidth` | 420 | 扩展计划卡宽度 |
| `ideaPlanTopInset` | 64 | 计划卡上沿到脑图面板顶边 |
| `ideaPlanRow` | 36 | 计划卡分支行高 |
| `ideaStepperButton` | 20 × 22 | 计划卡 −/+ 按钮 |
| `mapDraftBorder` | 1 | 草稿虚线描边宽度 |
| `mapDraftDash` / `mapDraftDashGap` | 4 / 3 | 草稿描边与草稿连线的虚线节奏 |
| `mapDraftTag` | 16 | 草稿上方向标签、页码 chip 的高度 |
| `mapDraftControls` | 24 | 草稿悬停控件胶囊高度 |
| `mapDraftControlButton` | 22 × 20 | 悬停控件里的单个按钮 |
| `mapDraftPlaceholder` | 120 × 30 | 第一条草稿到达前的占位草稿 |
| `mapWorkingRing` | 2 | 正在扩展的目标外圈 `research` 描边 |
| `mapWorkingHalo` / `mapWorkingHaloMax` | 6 / 10 | 外圈 `researchTint` 光晕的起止扩散半径（脉冲） |

**圆角**（`MMRadii`）：`ideaSection` 10（弹层“扩展想法”区）、`mapDraftTag` 4（方向标签与页码 chip）。草稿节点与普通主题同为 12（`MMRadii.card`）；计划卡 14（`MMRadii.dropdown`）；调整菜单 12（`MMRadii.card`）；弹层主按钮与次按钮 8（`MMRadii.row`）。

**动效**（`MMMotion`）：`pulse` 1400ms（目标外圈脉冲一拍）、`shimmer` 1100ms（占位草稿闪烁一遍）。其余沿用：草稿出现与布局展开 `layout` 320ms + `layoutCurve`；草稿切换保留 / 不要 `quick` 150ms；弹层、计划卡、调整菜单出现 `quick` 淡入；保留后新节点闪烁 `flash` 1600ms；HUD `hud`。

**图标**（`MMIcons`）：

| 名称 | 来源 | 用途 |
| --- | --- | --- |
| `expandIdeas` | Lucide `list-tree` | 扩展想法（弹层主按钮、右键菜单、菜单栏） |
| `groupParent` | Lucide `group` | 归纳上级主题 |
| `fillSiblings` | Lucide `list-plus` | 补全同级 |
| `adjust` | Lucide `sliders-horizontal` | 底部条“调整” |

沿用：`ai`（✦，助手入口、草稿“继续扩展”）、`network`（扩展整张脑图）、`history`（换一批、重试）、`check` / `close`（保留 / 不要）、`pen`（修改）、`stop`、`offline`、`document`（页码 chip）。

### 1.2 颜色用法

所有 AI 表面只用 `research` 系，从而与选中色 `accent` 区分：草稿不会被看成“选中”，选中环也不会被看成 AI。

| 元素 | 颜色 |
| --- | --- |
| 草稿底 / 描边 / 标题 | `researchWash` / `research` 1pt 虚线 / `label` |
| 不要的草稿 | 无底色；`line` 1pt 虚线；标题 `secondaryLabel` + 删除线 |
| 焦点草稿 | 在描边外加 2pt `research` 环（`BoxShadow(spreadRadius: 2)`，与选中环同法，换颜色） |
| 草稿连线 / 不要的草稿连线 | `research` 70% 虚线 / `research` 20% 虚线，线宽 1.5（同 `_EdgesPainter`） |
| 归纳预览中被移动主题的连线 | `research` 80% 实线 |
| 方向标签 | 实心 `research` 底 + `onResearch` 字；不要的草稿上为 `quaternaryFill` 底 + `secondaryLabel` 字 |
| 页码 chip | `quaternaryFill` 底 + `secondaryLabel` 字，前置 `MMIcons.document` 10pt |
| 目标外圈 | `research` 2pt 描边 + `researchTint` 光晕 |
| 范围外节点 | 内容透明度 0.45（与暂停卡片的 `_suspendedOpacity` 相同），祖先路径保持不透明 |
| 弹层“扩展想法”区 | `researchWash` 底 + 0.5pt `researchTint` 内描边 |
| 主按钮 / 选中 chip / “保留”按钮 | 实心 `research` + `onResearch` |

### 1.3 减少动态效果

`MMAppearance.reduceMotionOf(context)` 为真时：目标外圈只画静止的描边和 6pt 光晕，不脉冲；占位草稿不闪烁，显示为静止的 `researchTint` 底；草稿直接出现在最终位置，布局不做插值（`MMAppearance.duration` 返回 0）；保留后的闪烁沿用 `flashAssistantNodes`（本身是持续 `flash` 时长的静止选中环，无需另行处理）；底部条的进度用静止的 `MMIcons.ai`，不旋转。“降低透明度”时，底部条、调整菜单和计划卡跟随 `MMGlass` 改为不透明。

### 1.4 组件与实现位置

| 组件 | 位置 | 基于 |
| --- | --- | --- |
| `ExpandSection`（弹层“扩展想法”区） | 新文件 `apps/marginmind/lib/features/assistant/widgets/expand_section.dart`；插在 `AssistantQuickActions` 菜单模式中 `_ActionRow` 列表之前 | `MMButton`、`MMSegmentedControl`、`MMSwitch`、`MMTextField`、新的私有 `_DirectionChips`（`MMInteractive`） |
| `MapGhostNode`（草稿节点）、占位草稿 | 新文件 `apps/marginmind/lib/features/workspace/widgets/map_ghost_node.dart`；由 `MindMapCanvas` 在节点层绘制 | 与 `_NodeView` 的主题分支同尺寸；测量复用 `mind_map_cache.dart` 中主题的 `_measure`（`MMTypography.headline`，最大宽 220 − 28） |
| 草稿连线、移动连线 | `mind_map_canvas.dart` 的 `_EdgesPainter` 增加虚线样式 | `MapConnector` 增加 `draft` / `moved` 标记 |
| `ExpansionBar`（生成 / 审阅底部条） | 新文件 `apps/marginmind/lib/features/workspace/widgets/expansion_bar.dart`；`map_pane.dart` 的 Stack 中，与视图控制同层 | `MMGlass`、`MMButton` |
| `ExpansionAdjustMenu`（调整菜单） | 同上文件 | 与 `ExpandSection` 共用方向 / 层级 / 数量行（抽成 `ExpansionOptions` 组件） |
| `ExpansionPlanSheet`（扩展计划卡） | 新文件 `apps/marginmind/lib/features/workspace/widgets/expansion_plan_sheet.dart`；`map_pane.dart` Stack 顶部居中 | `MMGlass`、`MMCheckbox`、`MMIconButton` |
| 右键菜单项 | `map_pane.dart` 的 `_assistantEntries` | `MMMenuItem` |
| 菜单栏项与 ⌥⇥ | `app_commands.dart`：`MindMapCommand.expandIdeas`、`mindMapShortcuts`、`mapLabels` | 不走 `primaryShortcut`，见 §8.3 |
| 节点工具条 ✦ tooltip | `map_selection_bar.dart` 的 `_AssistantAction` | `_MapAction` |

---

## 2. 入口（场景 1、7、9）

| 入口 | 规格 |
| --- | --- |
| 节点工具条 ✦（`MapNodeBar`） | 按钮不变（`research` 着色）。tooltip 两行：`问助手  ⇧⌘E` / `扩展想法  ⌥⇥`（第二行用 `mapIdeaExpand` + `describeShortcut`）。点击打开 `AssistantQuickActions`，顶部为 `ExpandSection` |
| 选择工具条 ✦（`MapSelectionBar`） | 同上；弹层为多选形态（§3.2） |
| 右键菜单 | 在现有“问助手”分组（`MMMenuHeader(l.askAssistant)`）的**第一项**插入扩展项：单选 `mapIdeaExpand`、多选 `mapIdeaExpandEach(n)`、中心主题 `mapIdeaExpandMap`，快捷键列 `⌥⇥`；多选且同一上级时再加 `mapIdeaGroup`（不同上级时隐藏，不置灰——右键菜单不承载原因说明）。其余项不变 |
| 菜单栏 › 脑图 | 在“合并”“概要”一组之后新增 `mapIdeaMenu`（⌥⇥）。与 `MindMapCommand` 其他项一样，经焦点画布分发；大纲视图下禁用（加入 `mapOnly`）；预览存在时禁用，审阅中焦点在草稿上时可用（继续扩展） |
| ⌥⇥ | 见 §8 |

工具条、右键菜单和菜单栏只在 `editable`（非只读）且 AI 入口存在时出现扩展项；图片卡、笔记卡不提供扩展（只有主题和中心主题可以作为目标；概要主题是主题，可以扩展）。

---

## 3. 弹层“扩展想法”区（场景 1、7、9、11）

### 3.1 布局（单个主题）

`ExpandSection` 放在 `AssistantQuickActions` 的标题行（✦ `AI 助手` + 关闭）之下、快捷问答列表之上；弹层宽度和定位（`QuickActionsPlacement`）不变。

```
┌ researchWash · 圆角 ideaSection 10 · 内边距 10 ───────────────┐
│ [▤ 扩展想法                                         ⌥⇥]       │  ← 主按钮 34
│ 方向  (自动)(原因)(例子)(反方)(问题)(行动)                     │  ← chip 22，间距 4，可换行
│ 层级  [1 层|2 层|3 层]     数量  [少|适中|多]                  │  ← MMSegmentedControl
│ ┌ 补充要求 ───────────────────────── 参考原文 (●) ┐            │  ← MMTextField 28 + MMSwitch
└───────────────────────────────────────────────────────────────┘
  解释这个主题 / 总结要点 / 整理大纲 / 查证 / 出题 …（现有 _ActionRow）
  [或直接问一个问题…]（现有输入框）
```

- 区块：`researchWash` 底，0.5pt `researchTint` 内描边，圆角 `MMRadii.ideaSection`，内边距 `MMSpacing.s + MMSpacing.xxs`（10），区块与下方列表间距 `MMSpacing.s`。
- 主按钮：高 `MMSizes.ideaPrimaryButton`，整行宽，圆角 `MMRadii.row`；`research` 底、`onResearch` 字（`headline`）；左侧 `MMIcons.expandIdeas` 16，右侧键帽 `⌥⇥`（`footnote`，`onResearch` 75%）。悬停亮度 +8%，按下 `pressed` 叠加；键盘焦点为 2pt `research` 外环。弹层打开时**初始焦点在主按钮**，↩ 即开始。
- 行标签“方向 / 层级 / 数量”：`footnote`，`secondaryLabel`；三行的标签列宽取最宽标签（用 `Table` 的 `IntrinsicColumnWidth`，不写死宽度，英文 “Direction” 不换行）。行间距 `MMSpacing.s`。
- 方向 chip（`_DirectionChips`，单选，`Wrap` 间距 4）：高 `MMSizes.ideaChip`，水平内边距 8，`footnote`；未选为 0.5pt `line` 内描边 + `secondaryLabel` 字，悬停字色 `label`；选中为 `research` 底 + `onResearch` 字、无描边。键盘：Tab 进入整组，←/→ 在组内移动并选中（单选组语义，§9）。
- 层级、数量：现有 `MMSegmentedControl`（不自定义高度）。层级 `mapIdeaDepthLevels(1/2/3)`，数量 `mapIdeaAmountFew / Some / Many`。
- 补充要求：`MMTextField`（单行，高 `MMSizes.field`，不加前置图标），占位 `mapIdeaHint`，最多 200 字（`maxLength` 隐藏计数）；输入框内 ↩ 直接开始（组合输入期间交给输入法）。同一行右侧 `mapIdeaGrounded` 文字（`footnote`、`secondaryLabel`）+ `MMSwitch(color: research)`。
- 方向、层级、数量、参考原文按学习集记住（上位文档 §2.2）；补充要求不记住，每次打开为空。

### 3.2 多个主题

- 主按钮文案 `mapIdeaExpandEach(n)`。
- 主按钮下方一行两个等宽次按钮（间距 6，高 `MMSizes.field`，圆角 `MMRadii.row`，`card` 底 + 0.5pt `hairline`，深色为 `fill` 底）：`MMIcons.groupParent` + `mapIdeaGroup`、`MMIcons.fillSiblings` + `mapIdeaFillSiblings`。悬停为 1pt `research` 描边 + `research` 字。
- 选中主题不属于同一上级时，两个次按钮置灰（不透明度 0.45，与 `_MapAction` 一致），tooltip 为 `mapEditDifferentParents`，点击时用 `MMHud.show(reason, icon: MMIcons.info)`，与“合并”“概要”不可用时相同。
- 方向、层级、数量、补充要求、参考原文对三个动作都生效；“归纳上级主题”只生成 1 个上级，忽略层级和数量。

### 3.3 中心主题

- 主按钮：`MMIcons.network` + `mapIdeaExpandMap`（带省略号，表示会先打开计划卡），键帽 `⌥⇥`。点击关闭弹层并打开 §7 计划卡。
- 次按钮一个（整行宽）：`MMIcons.expandIdeas` + `mapIdeaBranchesOnly`，直接为中心主题生成一级分支，不经过计划卡。

### 3.4 状态

| 状态 | 表现 |
| --- | --- |
| 未配置 AI（场景 11） | 不显示 `ExpandSection`，弹层主体为现有 `ModelSetupCard(inline: true)`；快捷问答列表照旧隐藏 |
| 配置读取中 | 区块整体置灰（0.45）且不可点，不显示文字 |
| 另一个助手运行或扩展占用模型 | 区块置灰；沿用列表上方现有的 `assistantQuickBusy` 一行，不另加文案 |
| 已有预览（另一处正在扩展或审阅） | ✦ 弹层不会打开（审阅中节点工具条不显示，§5.3）；若从菜单栏触发，HUD `mapIdeaBlocked` |

---

## 4. 草稿节点 `MapGhostNode`（场景 2–6、8、10）

### 4.1 尺寸与结构

- 外框尺寸与**同标题的普通主题完全相同**（宽 = 文字宽 + 32，高 = 文字高 + 18，标题最大宽 220 − 28，`MMTypography.headline`，可换行），再加上可选的方向标签和页码 chip（各自前置 6pt 间距）。这样保留后节点不跳动。
- 描边 `MMSizes.mapDraftBorder` 虚线（`mapDraftDash` / `mapDraftDashGap`），画在外框内侧，不占布局尺寸；底色 `researchWash`；圆角 `MMRadii.card`。不随脑图配色（`MMMapPalette`）变化，一级草稿也不用分支色。
- 方向标签：高 `MMSizes.mapDraftTag`，圆角 `MMRadii.mapDraftTag`，水平内边距 4，文字 `footnote`（11 / 500）。`auto` 方向不显示标签。文案复用方向 chip 的 `mapIdeaDirection*`。
- 页码 chip：同高同圆角，`MMIcons.document` 10 + `p.N`（与助手引用 `assistant_markdown.dart` 的 `p.N` 写法一致）；“参考原文”关闭或草稿没有 `page` 时不显示。
- 归纳生成的上级草稿：与一级主题同字号（`MMTypography.headline`，不放大），子节点为被移动的已有主题（真实节点样式不变，只有连线变色）。

### 4.2 状态

| 状态 | 外观 | 触发 |
| --- | --- | --- |
| 出现 | 从左侧 10pt、0.96 缩放、透明淡入到位，`MMMotion.layout` | 每到达一条 |
| 保留（默认） | §1.2 草稿样式 | — |
| 不要 | 无底色，`line` 虚线，标题删除线 + `secondaryLabel`，标签换中性色；连线 20% | 点击 / 空格；父草稿取消时级联 |
| 焦点 | 外加 2pt `research` 环，并常显悬停控件 | ↑↓、点击、审阅开始时第一条 |
| 悬停 | 显示悬停控件 | 指针进入 |
| 编辑 | 标题换成 `MMInlineTextField`（单行），全选；↩ 确认、Esc 取消、失焦确认；空字符串视为取消 | 双击 / F2 / 控件 ✎ |
| 生成中（继续扩展的那条） | 与目标相同的外圈脉冲（§4.4） | 控件 ✦ / ⌥⇥ |

编辑确认后草稿自动设为保留，`edited = true`。生成阶段草稿不响应点击（避免与仍在到达的子草稿冲突），只能平移查看。

### 4.3 悬停控件

- 胶囊：高 `MMSizes.mapDraftControls`，`MMGlass`（`glass` + 0.5pt `hairline`），贴在草稿右上角外侧：右缘对齐草稿右缘 + 6，下缘在草稿上缘之上 2。
- 三个按钮（`MMSizes.mapDraftControlButton`，图标 14，`icon` 色，悬停 `research`）：保留 / 不要切换（当前保留时为 `MMIcons.close` + tooltip `mapIdeaDraftSkip  空格`，否则 `MMIcons.check` + `mapIdeaDraftKeep  空格`）、`MMIcons.pen` + `mapIdeaDraftEdit  F2`、`MMIcons.ai` + `mapIdeaDraftMore  ⌥⇥`。
- 胶囊不参与布局，不会挡住上方节点的命中（用 `Overlay` 层或画布最上层绘制）；画布缩放时胶囊保持屏幕尺寸，与新增子节点按钮的处理一致。
- 已达 3 层的草稿不显示 ✦（层级上限，上位文档 §3）。

### 4.4 生成中的画布

- **目标外圈**：`mapWorkingRing` 2pt `research` 描边 + `researchTint` 光晕，光晕扩散半径在 `mapWorkingHalo` 与 `mapWorkingHaloMax` 之间来回，周期 `MMMotion.pulse`。目标是中心主题时画在中心主题上。
- **占位草稿**：第一条草稿到达之前，在目标的子节点末尾放一个 `MMSizes.mapDraftPlaceholder` 的占位：1pt `research` 虚线、圆角 `MMRadii.card`、`researchWash → researchTint → researchWash` 横向扫光，周期 `MMMotion.shimmer`，整体不透明度 0.7。之后占位跟随“下一条草稿将挂的父节点”，最后一条到达后移除。
- **范围外变淡**：不在目标子树、也不是目标祖先的节点，内容透明度 0.45；连线不变淡。扩展整张脑图时不变淡。
- **自动缩放**：新草稿超出可视区域时，以 `MMMotion.layout` 平移 / 缩小到恰好容纳本次扩展的全部节点（目标 + 草稿），不放大；用户在生成中手动平移或缩放后不再自动调整。
- 生成和审阅期间隐藏节点工具条、选择工具条和新增子节点按钮；真实节点的选中环清除，结束后恢复原选择。

---

## 5. 生成 / 审阅底部条 `ExpansionBar`（场景 2–4、12、13）

### 5.1 布局

- 位置：脑图面板水平居中，下沿距面板底 `MMSizes.ideaBarBottomInset + chrome.bottom`；最大宽度为面板宽 − 2 × `MMSpacing.m`，放不下时横向滚动（按钮不换行、不省略）。
- 容器：高 `MMSizes.ideaBar`，`MMGlass`，圆角 20，左内边距 12、右内边距 5，项间距 4。
- 左侧标题区：图标 14 + 标题（`callout` 500，`label`，单行省略，最大宽 260）+ 计数（`callout` 400，`secondaryLabel`，等宽数字）。标题区与按钮组之间是 0.5pt × 18 的 `separator` 竖线。
- 按钮：高 30、圆角 `MMRadii.capsuleButton`、水平内边距 12，`callout` 500；默认透明底、悬停 `hover`；图标 14 在文字前；键帽在文字后（`footnote`，70% 不透明）。主按钮为 `research` 底 + `onResearch`。

### 5.2 状态

| 阶段 | 标题区 | 按钮 |
| --- | --- | --- |
| 生成中 | 14pt 环形进度（`research` / `researchTint`，减少动效时为静止 `MMIcons.ai`）+ 标题（§5.4）+ 已到达条数（0 时不显示） | `MMIcons.stop` `assistantStop` 键帽 `Esc` |
| 审阅 | `MMIcons.ai`（`research`）+ 标题 + `mapIdeaKeptCount(kept, total)` | `MMIcons.history` `mapIdeaRegenerate` · `MMIcons.adjust` `mapIdeaAdjust` · `mapIdeaDiscard` 键帽 `Esc` · 主按钮 `MMIcons.check` `mapIdeaKeep(kept)` 键帽 `↩` |
| 审阅（已停止 / 部分失败后） | 标题换成 `mapIdeaStopped`，其余同审阅 | 同审阅 |
| 失败且没有任何草稿（场景 12） | `MMIcons.offline`（网络）或 `MMIcons.warning`（其他）+ 错误文案，`critical` 色 | `MMIcons.history` `assistantRetry` · `assistantUseLocal`（仅云端模型且已有本机模型可用时）· `closePanel` |

- 错误文案复用助手的错误分类：`assistantErrorNetwork` / `assistantErrorKey` / `assistantErrorService` / `assistantErrorBudget` / `assistantErrorFailed`，不追加“没有生成内容”之类的解释（脑图本来就没变）。
- `kept` 为 0 时“保留”按钮禁用（0.45），↩ 无效。
- 换一批、调整在**继续扩展的子生成**进行中禁用。

### 5.3 进入与退出

- 进入：开始生成时以 `MMMotion.quick` 从下方 4pt 淡入；生成 → 审阅时原地换内容，不重新动画。
- 保留：底部条消失，新节点 `flash`，HUD `mapIdeaAdded(n)` 带动作 `undo`（点即撤销，与 ⌘Z 同效）。
- 放弃 / Esc：底部条和全部草稿立即消失，恢复原选择，无 HUD。
- 停止时一条草稿都没有：底部条消失，HUD `mapIdeaStoppedEmpty`。
- 正常结束但没有有效草稿（场景 14）：不进入审阅，HUD `mapIdeaNothing`。
- 模型被占用：不进入生成，HUD `mapIdeaBusy`。

### 5.4 标题

| 范围 | 标题 |
| --- | --- |
| 单个主题 | `mapIdeaExpanding(title)`，`title` 超过 12 个字符时截断加 “…” |
| 多个主题 | `mapIdeaExpandingCount(n)` |
| 补全同级 | `mapIdeaFillSiblings` |
| 归纳上级主题 | `mapIdeaGroup` |
| 只加新分支 | `mapIdeaBranchesOnly` |
| 扩展整张脑图 | `mapIdeaWholeMap` |

在草稿上继续扩展时标题不变，计数累加。

---

## 6. 调整菜单 `ExpansionAdjustMenu`（场景 4）

- 锚在底部条“调整”按钮上方 8pt，水平居中于底部条；宽 `MMSizes.ideaAdjustWidth`，`MMGlass`，圆角 `MMRadii.card`，内边距 10。
- 内容：与 §3.1 相同的“方向 / 层级 / 数量”三行（同一个 `ExpansionOptions` 组件），不含补充要求和参考原文；底部右对齐主按钮 `MMIcons.history` `mapIdeaRegenerateAdjusted`（`MMButton` primary，`color: research`，`foregroundColor: onResearch`）。
- 修改选项不会立即生成；点主按钮后关闭菜单，丢弃当前草稿并按新设置重新生成，`round + 1`。新的选项同样写回学习集的记忆值。
- Esc、点击外部或再次点“调整”关闭菜单，不改变草稿；菜单打开时，审阅键盘映射暂停（焦点在菜单内）。

---

## 7. 扩展计划卡 `ExpansionPlanSheet`（场景 9、10）

### 7.1 布局

- 位置：脑图面板顶部居中，上沿距面板顶 `MMSizes.ideaPlanTopInset`；宽 `MMSizes.ideaPlanWidth`（面板更窄时取面板宽 − 2 × `MMSpacing.l`）；最大高度为面板高 − 上沿 − `ideaBarBottomInset`，分支行超出时在卡内滚动。
- 容器：`MMGlass`，圆角 `MMRadii.dropdown`。
- 标题行：内边距 16 / 14 / 16 / 6；`MMIcons.network` 16（`research`）+ `mapIdeaWholeMap`（`headline`）。没有副标题。
- 分支行（左右外边距 8）：高 `MMSizes.ideaPlanRow`，内边距 8，圆角 `MMRadii.row`，悬停 `hover`。从左到右：`MMCheckbox(color: research)` → 分支标题（`body`，单行省略）→ 步进器。
- 新分支行：放在最后，标题为 `mapIdeaNewBranches`，前置 `MMIcons.add` 12（`research`），文字仍为 `label`。
- 步进器：0.5pt `line` 内描边、圆角 6、高 22；两侧 `MMSizes.ideaStepperButton` 的 − / + 按钮（`MMIcons.zoomOut` / `MMIcons.zoomIn` 12，悬停 `research`），中间 `mapIdeaAddCount(n)`（`footnote`，等宽数字，最小宽 22）。范围 1–8（每个父节点的上限，与“多”档一致）。行未勾选时步进器置灰。
- 页脚：0.5pt `separator` 上边线，内边距 12 / 16；左侧总数 `mapIdeaAddCount(total)`（`footnote`，`secondaryLabel`），右侧 `cancel`（secondary）与主按钮 `MMIcons.ai` `mapIdeaStart`（primary，`research` / `onResearch`）。总数为 0 时主按钮禁用。

### 7.2 状态

| 状态 | 表现 |
| --- | --- |
| 计划计算中 | 卡片立即出现；分支区显示 3 行占位（与分支行同高，`quaternaryFill` 圆角条，`shimmer` 闪烁），页脚主按钮禁用 |
| 计划完成 | 空的、较薄的分支排在前面并默认勾选；其余按原顺序、默认不勾选 |
| 计划失败 | 分支区换成一行：`MMIcons.warning` + 错误文案（§5.2 同一组）+ `assistantRetry` 纯文本按钮 |
| 开始扩展 | 关闭计划卡，进入生成；底部条标题 `mapIdeaWholeMap` |

Esc / 取消 / 点击计划卡外部：关闭，脑图不变。计划卡打开期间脑图可以平移缩放，不能编辑（同审阅期间）。未修改计划再次打开时复用上次结果，不重复请求（上位文档 §2.6）。

---

## 8. 键盘映射

### 8.1 空闲（脑图获得焦点）

| 键 | 选中 | 行为 |
| --- | --- | --- |
| ⌥⇥ | 一个或多个主题 | 按记住的设置直接开始“扩展子主题 / 分别扩展”，不打开弹层 |
| ⌥⇥ | 中心主题 | 打开计划卡 |
| ⌥⇥ | 未配置 AI | 打开 ✦ 弹层（显示连接卡） |
| ⌥⇥ | 只选了笔记 / 图片卡，或没有选择 | 无反应（菜单项禁用） |

### 8.2 生成中 / 审阅中

| 键 | 生成中 | 审阅中（焦点在草稿） | 编辑草稿中 |
| --- | --- | --- | --- |
| Esc | 停止，已有草稿进入审阅 | 放弃 | 取消编辑 |
| ↩ | — | 保留勾选的草稿 | 确认编辑 |
| 空格 | — | 切换焦点草稿保留 / 不要 | 输入空格 |
| ↑ / ↓ | — | 按草稿的到达顺序移动焦点（循环） | 交给输入框 |
| F2 | — | 编辑焦点草稿 | — |
| ⌥⇥ | — | 在焦点草稿下继续扩展 | — |
| ⌘Z | HUD `mapIdeaBlocked` | HUD `mapIdeaBlocked` | 输入框自身撤销 |
| 其他编辑键（Tab、⇧⇥、⌫、⌦、⌘X、⌘V、⌘↑ / ⌘↓ 等）和可见字符 | HUD `mapIdeaBlocked` | HUD `mapIdeaBlocked` | 输入 |
| 平移、缩放（⌘0、滚轮、触控板） | 允许 | 允许 | 允许 |

实现：预览存在时，`MindMapCanvas` 用一层 `Shortcuts` + `Actions` 覆盖 `mindMapShortcuts` 中的编辑命令（`child`、`siblingAfter`、`siblingBefore`、`promote`、`parent`、`edit`、`delete`、`cut`、`paste`、`up`、`down`、`relation`、`summary`、`merge`），映射到上表；`fit`、`center`、`copy`、`expand`、`fold` 保持原行为。菜单栏中被覆盖的命令同时禁用；“撤销 / 重做”在预览期间也禁用（⌘Z 由画布拦截并提示）。

### 8.3 快捷键定义

`MindMapCommand` 新增 `expandIdeas`，在 `mindMapShortcuts` 中登记 `SingleActivator(LogicalKeyboardKey.tab, alt: true)`，各平台相同（不走 `primaryShortcut`，⌘/Ctrl 不参与）。macOS 菜单显示 `⌥⇥`；Windows / Linux 显示 `Alt+Tab` 会被系统截获，因此这两个平台的菜单项不显示快捷键，命令仍可从菜单、右键和 ✦ 进入。现有 Tab（子主题）与 ⇧⇥（提升）不受影响（`map_keyboard_test` 回归）。

---

## 9. 无障碍语义

| 元素 | 语义 |
| --- | --- |
| 主按钮、次按钮 | `button`，标签为按钮文字；快捷键放在 `hint`（`⌥⇥`） |
| 方向 chip 组 | 单选组：每个 chip `inMutuallyExclusiveGroup: true`、`checked` 表示选中，标签为方向名；组标签 `mapIdeaDirection` |
| 层级、数量 | `MMSegmentedControl` 现有语义；组标签 `mapIdeaDepth` / `mapIdeaAmount` |
| 补充要求 | `textField`，标签 `mapIdeaHint` |
| 参考原文 | `MMSwitch(semanticLabel: mapIdeaGrounded)` |
| 草稿节点 | 可聚焦；`button` + `toggled: kept`，标签 `mapIdeaDraftSemantics(title, kept ? mapIdeaDraftKept : mapIdeaDraftSkipped)`，有方向时在 `hint` 读方向名，有页码时 `hint` 加 `pageNumber(page)`；`onTap` 切换；自定义动作 `mapIdeaDraftEdit`、`mapIdeaDraftMore` |
| 占位草稿 | 排除语义（`ExcludeSemantics`） |
| 底部条 | 标题区为 `liveRegion`：生成中读标题 + `mapIdeaDraftCount(n)`（每到达一条更新，系统会合并播报），审阅读标题 + `mapIdeaKeptCount`；各按钮标签为完整文字（不含键帽） |
| 计划卡 | 每行一个 `MMCheckbox`（标签为分支标题）；步进器 −/+ 的标签为 `mapIdeaFewer` / `mapIdeaMore`，数值读 `mapIdeaAddCount(n)` |
| HUD | 沿用 `MMHud` 的播报 |

焦点：开始生成时键盘焦点留在脑图画布；审阅开始时焦点移到第一条草稿（屏幕阅读器读出它）；保留或放弃后焦点回到原目标节点。调整菜单、计划卡打开时焦点进入卡内，关闭后回到打开前的位置。

---

## 10. 文案（ARB，已在本任务落地）

全部放在 `apps/marginmind/lib/l10n/app_zh.arb` / `app_en.arb`，前缀 `mapIdea`；英文菜单项与按钮用标题大小写，HUD 用句子大小写。

| 键 | 中文 | English | 用于 |
| --- | --- | --- | --- |
| `mapIdeaMenu` | AI 扩展想法 | Expand Ideas with AI | 菜单栏 |
| `mapIdeaExpand` | 扩展想法 | Expand Ideas | 主按钮、右键、tooltip |
| `mapIdeaExpandEach` | 分别扩展 {count} 个主题 | Expand {count} Topics | 多选主按钮、右键 |
| `mapIdeaExpandMap` | 扩展整张脑图… | Expand Whole Map… | 中心主题主按钮、右键 |
| `mapIdeaWholeMap` | 扩展整张脑图 | Expand Whole Map | 计划卡标题、底部条 |
| `mapIdeaBranchesOnly` | 只加新分支 | New Branches Only | 中心主题次按钮、底部条 |
| `mapIdeaGroup` | 归纳上级主题 | Group Under New Parent | 多选次按钮、右键、底部条 |
| `mapIdeaFillSiblings` | 补全同级 | Fill In Siblings | 多选次按钮、底部条 |
| `mapIdeaDirection` / `Depth` / `Amount` | 方向 / 层级 / 数量 | Direction / Depth / Amount | 选项行标签 |
| `mapIdeaDirectionAuto` … `Action` | 自动 / 原因 / 例子 / 反方 / 问题 / 行动 | Auto / Why / Examples / Counterpoints / Questions / Actions | chip、草稿标签 |
| `mapIdeaDepthLevels` | {count} 层 | {count} Levels | 层级分段 |
| `mapIdeaAmountFew` / `Some` / `Many` | 少 / 适中 / 多 | Few / Some / Many | 数量分段 |
| `mapIdeaHint` | 补充要求 | Instructions | 输入框占位 |
| `mapIdeaGrounded` | 参考原文 | Use Source | 开关 |
| `mapIdeaExpanding` | 扩展「{title}」 | Expanding “{title}” | 底部条 |
| `mapIdeaExpandingCount` | 扩展 {count} 个主题 | Expanding {count} Topics | 底部条 |
| `mapIdeaStopped` | 已停止 | Stopped | 底部条 |
| `mapIdeaDraftCount` | {count} 条 | {count} ideas | 底部条语义 |
| `mapIdeaKeptCount` | 保留 {kept} / {total} | {kept} of {total} kept | 底部条 |
| `mapIdeaRegenerate` | 换一批 | Try Others | 底部条 |
| `mapIdeaAdjust` | 调整 | Adjust | 底部条 |
| `mapIdeaRegenerateAdjusted` | 重新生成 | Regenerate | 调整菜单 |
| `mapIdeaDiscard` | 放弃 | Discard | 底部条 |
| `mapIdeaKeep` | 保留 {count} 条 | Keep {count} | 底部条主按钮 |
| `mapIdeaDraftKeep` / `Skip` / `Edit` / `More` | 保留 / 不要 / 修改 / 继续扩展 | Keep / Skip / Edit / Expand Further | 草稿控件 tooltip、语义动作 |
| `mapIdeaDraftSemantics` | AI 草稿，{title}，{state} | AI draft, {title}, {state} | 草稿语义 |
| `mapIdeaDraftKept` / `Skipped` | 已保留 / 未保留 | kept / not kept | 草稿语义 |
| `mapIdeaNewBranches` | 新分支 | New Branches | 计划卡 |
| `mapIdeaAddCount` | +{count} | +{count} | 计划卡步进器、总数 |
| `mapIdeaFewer` / `More` | 减少 / 增加 | Fewer / More | 步进器语义 |
| `mapIdeaStart` | 开始扩展 | Expand | 计划卡主按钮 |
| `mapIdeaAdded` | 已添加 {count} 个主题 | Added {count} topics | HUD |
| `mapIdeaBlocked` | 先保留（↩）或放弃（Esc）这次 AI 扩展 | Keep (↩) or discard (Esc) the AI drafts first | HUD |
| `mapIdeaNothing` | 这里暂时没有值得补充的方向，换个方向试试 | No new ideas here. Try another direction. | HUD |
| `mapIdeaStoppedEmpty` | 已停止，没有生成内容 | Stopped before any ideas | HUD |
| `mapIdeaBusy` | 模型正忙，请稍后再试 | The model is busy. Try again later. | HUD |

复用（不新增）：`askAssistant`、`assistantStop`、`assistantRetry`、`assistantUseLocal`、`assistantError*`、`assistantQuickBusy`、`mapEditDifferentParents`、`cancel`、`closePanel`、`undo`、`pageNumber`。英文复数在 ARB 中用 ICU `plural`；`test/map_idea_l10n_test.dart` 检查每个键两种语言都存在、已翻译、占位符已替换。

---

## 11. 平台与窗口尺寸

| 情况 | 差异 |
| --- | --- |
| 触控输入（`MMInput.touchInput`） | 草稿没有悬停：点按切换保留 / 不要，长按打开 Action Sheet（保留或不要 / 修改 / 继续扩展，复用 `showMMMenu` 在 compact 下的表现）；双击修改仍可用。底部条、计划卡的按钮高度至少 `MMSizes.touchTarget`（底部条随之增高为 44 + 2 × 4），步进器按钮热区扩到 44 |
| Compact 窗口（< 600 宽） | ✦ 弹层沿用 `AssistantQuickActions` 在 compact 下的呈现；计划卡改为 `showMMBottomSheet`（随内容高度），页脚固定在底部；底部条左右贴边（`MMSpacing.m`），标题区最大宽缩到 140，按钮只显示图标 + tooltip（保留按钮保留文字）；调整菜单改为底部 sheet |
| 手机 | 同 compact；底部条下沿再让出 `MMTabBar` 与安全区 |
| Windows / Linux | 快捷键见 §8.3；其余相同 |
| 大纲视图 | 扩展命令禁用；预览只在脑图视图中存在。预览期间“脑图 / 大纲”切换和切换脑图都视为编辑而被拦截（HUD `mapIdeaBlocked`）；阅读原文、切换文档不受影响 |

---

## 12. 场景对照

| 原型场景 | 本文 |
| --- | --- |
| 1 选中主题 → ✦ → 扩展想法 | §2、§3.1 |
| 2 一键扩展，边生成边出现 | §4.4、§5.2 生成中 |
| 3 审阅草稿 | §4.2、§4.3、§5.2 审阅、§8.2 |
| 4 换一批 / 调整 | §5.2、§6 |
| 5 指定方向 · 2 层 | §3.1、§4.1 方向标签、级联取消（上位文档 §2.4） |
| 6 在草稿上继续扩展 | §4.2、§4.3 |
| 7 多选 → 分别扩展 | §3.2 |
| 8 归纳上级主题 | §1.2 移动连线、§4.1 |
| 9 中心主题 → 扩展整张脑图 | §3.3 |
| 10 扩展计划 → 生成 → 审阅 | §7 |
| 11 未配置 AI | §3.4 |
| 12 断网 | §5.2 失败 |
| 13 中途停止 | §5.2 已停止、§5.3 |
| 14 没有可补充的内容 | §5.3 |
| 15 保留后撤销 | §5.3 保留 |

---

## 13. 本任务对原型的修改

为与本文一致，`design/prototype/mindmap-ai-expand.html` 做了以下修改：

1. 新增 `--onAi`（浅色白、深色 `#1E1E1F`），主按钮、选中 chip、草稿方向标签和“保留”按钮的文字改用它；方向标签改为实心 `research` 底（深色下白字不足 4.5:1）。
2. 补充要求的占位由“补充要求（可选）”改为“补充要求”；断网提示去掉“，没有生成内容”。
3. 底部条标题按 §5.4：补全同级、归纳上级不再拼接主题名和数量。
4. 保留后的 HUD 去掉“· 跳过 N 条”；撤销后的 HUD 用应用现有的“已撤销”。
6. 补充要求输入框去掉前置的 ✎ 图标（占位文字已说明用途）。
5. 底部条上移到距面板底 64，避开窗口 HUD。
