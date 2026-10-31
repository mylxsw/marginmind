# 基于文档生成与更新脑图：界面规格

> 建立日期：2026-10-31（GUL-623，父任务 GUL-600）。上位文档：[`mindmap-from-document.md`](mindmap-from-document.md)（§8 的决定均按建议执行）；数据模型、模型契约与写入链路以上位文档 §4 和 `docs/mindmap-from-document-arch.md`（子任务「技术架构」产出）为准，本文只定界面。
> 交互原型：[`design/prototype/mindmap-from-document.html`](../design/prototype/mindmap-from-document.html)，14 个场景与本文 §16 对应（`?scene=N`）。
> 视觉以 [layout-density.md §扁平化视觉规格](layout-density.md) 和 `mm_design` 令牌为准，原型的 CSS 数值只作参考。草稿、审阅、底部条、调整菜单沿用 [mindmap-ai-expand-ui.md](mindmap-ai-expand-ui.md)（下称 **扩展规格**），本文只写差异。

本文写给上位文档 §7 A–D 批次的实现者：每个界面给出尺寸（pt）、令牌、状态、文案键、键盘与无障碍语义，以及实现位置。

**界面原则（必须遵守）。** 不加多余的次级标签和说明文字，让布局表达含义；不加多余的辅助文字、描述性文案和重复的界面微文案。具体到本功能：

- 空状态只有标题、输入框、按钮和建议；不写页数、高亮条数或“需要先连接模型”之类的副标题。
- 生成设置的选项只写名称：组织方式不附说明，“摘录原文关键句”不附“在原文上用虚线标出”，页脚只写总页数。
- 差异列表只在必要处写第二行：改名写旧名，移动写去向，建议删除写理由；新增项不写“在「X」下”（画布已经表达位置）。
- 输入框占位只写名称（`mapIdeaHint`“补充要求”），不写“可选”和示例。
- 按钮只写动作，快捷键用右侧浅色键帽；不可用的原因放 tooltip。

---

## 0. 术语

| 术语 | 含义 |
| --- | --- |
| 依据 | 一张脑图生成时读过的文档（`MindMap.generation.sources`） |
| 关联 | 文档是某张脑图的依据 |
| 骨架 | 通读阶段由文档目录画出的一级主题占位，不是草稿 |
| 草稿 | 生成结果中的一个节点，画成扩展规格的 `MapGhostNode`；只在内存中 |
| 出处 | 生成主题的 `CardSource`（文档 + 页码），显示为页码标签 |
| 差异 | 更新结果：新增、改名、移动、建议删除四类改动 |
| 受保护 | 用户改过、添加、移动过的节点，以及摘录卡片、笔记、图片卡（上位文档 §3） |
| 有更新 | 依据的指纹或阅读进度与生成时不同（上位文档 §4.1） |

---

## 1. 通用约定

### 1.1 新增令牌（`mm_design`，已在本任务落地）

**尺寸**（`MMSizes`）：

| 常量 | 值 | 用途 |
| --- | --- | --- |
| `mapGenerateSheetWidth` | 640 | 生成设置 sheet 宽度（与 `noteSetupSheetWidth` 一致） |
| `mapGenerateLabelWidth` | 96 | 设置表单的标签列 |
| `mapGenerateDocumentRow` | 40 | 设置里的文档行高（触屏 `touchTarget`） |
| `mapGenerateChapterRow` | 30 | 设置里的章节行高（触屏 `touchTarget`） |
| `mapEmptyStateWidth` | 440 | 空状态内容宽度 |
| `mapEmptyGlyph` | 56 | 空状态图标块 |
| `mapDocumentBanner` | 44 | 文档提示条高度 |
| `mapUpdatePopoverWidth` | 360 | 更新弹层宽度 |
| `mapDiffPanelWidth` | 340 | 差异面板宽度 |
| `mapSourceChip` | 18 | 出处标签高度 |
| `mapSourceDot` | 6 | 出处前的文档色点、图例色点 |
| `mapUpdateBadge` / `mapUpdateBadgeRing` | 7 / 1.5 | 表头“有更新”紫点与它的窗口底色描边 |
| `mapProtectedBadge` | 18 | 受保护标记（锁）圆形徽标 |
| `mapReadingStep` | 16 × 4 | 通读进度的一格 |

**圆角**（`MMRadii`）：`mapEmptyGlyph` 16、`mapSourceChip` 9（标签高度一半）。差异标签与扩展规格的方向标签相同：高 `MMSizes.mapDraftTag`（16）、圆角 `MMRadii.mapDraftTag`（4）。提示条 12（`MMRadii.card`）；更新弹层 14（`MMRadii.dropdown`）；设置 sheet 22（`MMRadii.sheet`）。

**动效**（`MMMotion`）：新增 `breathe` 1200ms（当前章节骨架的呼吸：不透明度 1 → 0.4 → 1）。其余沿用：中心主题脉冲 `pulse`；草稿出现 `layout`；面板进出 `layout` + `layoutCurve`；状态切换 `quick`；跳页后段落闪烁 `flash`；HUD 和提示 `hud`。

**图标**（`MMIcons`）：

| 名称 | 来源 | 用途 |
| --- | --- | --- |
| `generateMap` | Lucide `wand-sparkles` | 表头按钮、空状态、设置与更新弹层标题、菜单项、提示条（与助手 `ai` sparkles、整理笔记 `organizeNote` notebook-pen 区分） |
| `mergeIntoMap` | Lucide `merge` | 提示条“并入当前脑图” |

沿用：`lock`（受保护）、`adjust`（设置、调整）、`history`（换一批、重试）、`stop`、`offline`、`warning`、`document` / `ebook`（文档行）、`highlight`（新增高亮）、`pen`（新增批注）、`mindMap`（文档行的关联标记）、`add`（添加文档）、`check`、`close`。

**文档色点**（新 `MMSourceColors`，`source_colors.dart`）：按依据顺序取色、循环使用。浅色：蓝 `#007AFF`、橙 `#FF9500`、绿 `#34C759`、粉 `#FF2D55`、青 `#30B0C7`、灰 `#8E8E93`；深色取对应的系统深色值。`MMSourceColors.of(brightness, index)`。色点只是辅助：语义标签里读文档名（§13），图例写文档名。

### 1.2 颜色用法

AI 产出一律用 `research` 系，选中仍是 `accent`（与扩展规格 §1.2 相同）。新增部分：

| 元素 | 颜色 |
| --- | --- |
| 表头按钮 | `research` 文字和图标；悬停、按下、打开弹层、生成中、审阅中为 `researchTint` 底 |
| 骨架主题 | `quaternaryFill` 底，`secondaryLabel` 文字，无描边 |
| 出处标签 | `quaternaryFill` 底 + `secondaryLabel` 字；悬停 `fill` 底 + `label` 字。草稿上相同（`research` 字在 `researchTint` 上只有 4.0:1 / 3.2:1，见扩展规格 §1.1） |
| 差异标签“新 / 改名 / 移自…” | 实心 `research` 底 + `onResearch` 字（同扩展规格的方向标签） |
| 差异标签“建议删除”、取消勾选的差异标签 | `fill` 底 + `secondaryLabel` 字 |
| 旧名（改名） | `secondaryLabel`，删除线 |
| 移动后的连线 | `research` 80% 实线 1.5pt（同扩展规格“归纳”） |
| 建议删除的节点 | 未勾选：普通主题底 + 1pt `secondaryLabel` 虚线；勾选：无底色、标题删除线 + `secondaryLabel`；连线 `fill` 虚线 |
| 受保护标记 | `surface` 底 + 0.5pt `border`，锁 `secondaryLabel` |
| 空状态图标块 | `researchTint` 底 + `research` 图标 |
| 输入框聚焦 | 1pt `research` 描边 + 3pt `researchTint` 外环（不发光） |
| 主按钮（生成、保留、应用、预览更改、生成新脑图） | 实心 `research` + `onResearch` |
| 通读进度格 | 已读 `research`；当前 `research` 45% 并 `breathe`；未读 `fill`；失败 `critical` |

### 1.3 减少动态效果

`MMAppearance.reduceMotionOf(context)` 为真时：当前章节骨架不呼吸，保持不透明度 1；当前进度格为静止的 45%；中心主题外圈静止（扩展规格 §1.3）；画布自动适配直接跳到结果；面板、弹层只淡入不位移；跳页后的段落闪烁改为静止的 `researchTint` 底，持续 `flash` 后去掉。

### 1.4 组件与实现位置

| 组件 | 位置 | 基于 |
| --- | --- | --- |
| `GenerateMapButton`（表头按钮） | `apps/marginmind/lib/features/workspace/widgets/map_header.dart` 的脑图工具组之后 | `MMToolbarButton`（带文字） |
| `MapEmptyState` | 新文件 `features/map_generation/widgets/map_empty_state.dart`；`map_pane.dart` 在脑图只有中心主题时替代画布 | `MMTextField`（多行）、`MMButton`、`MMPill` 式建议 chip、`ModelSetupCard` |
| `GenerateMapSheet` | 新文件 `features/map_generation/widgets/generate_map_sheet.dart`；`showMMSheet(width: MMSizes.mapGenerateSheetWidth)` | `MMSheet`、`MMCheckbox`、`MMSegmentedControl`、`MMSwitch`、`MMDropdownButton`、`MMTextField` |
| `MapSkeletonNode`（骨架主题） | `features/workspace/widgets/map_ghost_node.dart`（与草稿同文件） | 一级主题的测量 |
| `MapGenerationBar`（生成 / 审阅底部条） | 复用扩展规格的 `ExpansionBar`，增加通读进度和图例槽位 | `ExpansionBar` |
| `MapSourceChip`（出处标签） | 新文件 `features/workspace/widgets/map_source_chip.dart`；草稿与生成主题共用 | `MMInteractive` |
| `DocumentMapBanner`（文档提示条） | 新文件 `features/map_generation/widgets/document_map_banner.dart`；`map_pane.dart` Stack 顶部 | `MMButton`、`MMIconButton` |
| `MapUpdatePopover` | 新文件 `features/map_generation/widgets/map_update_popover.dart`；锚在表头按钮 | `MMDropdown` 的弹层定位、`MMSegmentedControl`、`MMTextField` |
| `MapDiffMarks`（差异标签、旧名、受保护标记） | `map_ghost_node.dart` | — |
| `MapDiffPanel` | 新文件 `features/map_generation/widgets/map_diff_panel.dart`；`map_pane.dart` 右侧 | `MMCheckbox`、`MapSourceChip` |
| 切换提示 | `MMHud` 的顶部变体（§8.3） | `MMHud` |
| 菜单项 | `app_commands.dart`：`MindMapCommand.generateFromDocument`；侧栏文档行右键与“脑图”分组 + | `MMMenuItem` |

---

## 2. 表头按钮（场景 1、7、11）

`MMToolbarButton` 带文字（Mac 左右内边距 10、iPad 12，图标 16 / 18，与文字间距 6，`MMTypography.callout`），放在脑图栏表头视图 / 样式之后、窗口级控件之前。

| 状态 | 文字 | 外观 | 点击 |
| --- | --- | --- | --- |
| 脑图没有依据 | `mapGenerate` | `research` 字，透明底 | 打开生成设置（§4），文档预选当前打开的文档 |
| 有依据 | `mapGenerateUpdate` | 同上 | 打开更新弹层（§9）；再点关闭 |
| 有依据且有更新 | `mapGenerateUpdate` + 紫点 | 紫点 `mapUpdateBadge`，`research`，外加 `mapUpdateBadgeRing` 的 `windowBackground` 描边；圆心在按钮右上角内缩 (5, 3)+半径 | 同上 |
| 弹层打开 / 差异审阅中 | 同上 | `researchTint` 底（选中态） | 关闭弹层；差异审阅中不响应 |
| 生成中 | `mapGenerateRunning` | `researchTint` 底；图标换成 14pt 环形进度（减少动效时为静止图标） | 无动作（画布上的底部条负责停止） |
| 审阅中 | `mapGenerateReviewing` | `researchTint` 底 | 无动作 |
| 未配置 AI | `mapGenerate` / `mapGenerateUpdate` | 同上 | 打开设置或弹层，主体换成 `ModelSetupCard(inline: true)` |
| 只读学习集 | — | 隐藏 | — |

- tooltip：与文字相同，菜单栏有快捷键时右侧加键帽；生成中、审阅中 tooltip 为 `mapGenerateBlocked`。
- 栏宽不够时按 `MMAdaptiveToolbar` 规则先收起文字，只留图标（tooltip 同文字），最后才收进溢出菜单。
- 侧栏：脑图行在生成中显示 14pt 环形进度，有更新时显示 6pt `research` 点（语义 `mapHasUpdates`）；文档行有关联脑图时在行尾显示 12pt `MMIcons.mindMap`（`secondaryLabel`，语义 `mapHasMap`）。都不加文字。
- 其他入口：侧栏文档行右键 `mapGenerateDocumentMenu`（预选这份文档）；侧栏“脑图”分组 + 菜单 `newMap` / `mapGenerateMenu`；菜单栏 › 脑图 › `mapGenerateMenu`（同表头按钮）。

---

## 3. 空状态 `MapEmptyState`（场景 1、13、14）

只在脑图除中心主题外没有任何节点、且不在生成中时出现，替代画布居中显示；有内容的脑图不显示空状态。

```
           ┌────────┐
           │  ✦⚲   │  56 · 圆角 16 · researchTint
           └────────┘
      从「第6章 记忆」生成脑图                     title3（15/20 600）
 ┌──────────────────────────────────────────┐
 │ 补充要求                                   │  多行，2 行起
 │ [⚙ 设置]                       [生成 ⌘↩] │
 └──────────────────────────────────────────┘
 (侧重考试要点)(每个主题附一句解释)(保留原文关键句)(举例说明)
               新建空白主题
```

- 宽 `MMSizes.mapEmptyStateWidth`，水平垂直居中（垂直中心上移 `MMSizes.ideaBarBottomInset / 2`，避开底部 HUD）。窗口更窄时为面板宽 − 2 × `MMSpacing.l`。
- 图标块：`MMSizes.mapEmptyGlyph`，圆角 `MMRadii.mapEmptyGlyph`，`researchTint` 底，`MMIcons.generateMap` 24（`research`）；与标题间距 14。
- 标题：`mapGenerateFrom(documentTitle)`，`MMTypography.title3`，`label`，最多 2 行，文档名过长时中间截断；与输入框间距 18。依据的文档为当前打开的文档；没有打开文档时取学习集里最近打开的一份。
- 输入框：`surface` 底 + 1pt `separator`，圆角 14，内边距 10 / 10 / 8 / 12；聚焦时 §1.2 的描边和外环。文字区 `MMTypography.body`，行高 20，最少 2 行、最多 6 行后在框内滚动，占位 `mapIdeaHint`，最多 500 字（隐藏计数）。下方一行：左侧 `MMButton`（plain）`MMIcons.adjust` 14 + `mapGenerateSettings`；右侧主按钮 `mapGenerateStart` + 键帽 `⌘↩`（高 28，圆角 14）。
- 建议 chip：输入框下 12，`Wrap` 居中，间距 6；高 24，圆角 12，左右内边距 9，`callout`；底 `quaternaryFill`，悬停 `fill`；已选为实心 `research` 底 + `onResearch` 字（小字不放在 `researchTint` 上，§1.2），以 `toggled` 语义标出。四项：`mapGenerateSuggestExam`、`mapGenerateSuggestExplain`、`mapGenerateSuggestQuotes`、`mapGenerateSuggestExamples`。点一下把文字追加到输入框（中文用“；”、英文用“; ”连接），再点从输入框删去这一段。
- 新建空白主题：建议下 22，纯文字按钮 `mapGenerateBlank`（`callout`，`accent`），点击后进入现有的新建主题编辑。
- 打开时焦点在输入框（Mac / iPad 硬件键盘）；触屏不自动弹出键盘。

| 状态 | 表现 |
| --- | --- |
| 未配置 AI（场景 13 开关） | 输入框、建议换成 `ModelSetupCard(inline: true)`（宽 360），其余不变；不加副标题 |
| 配置读取中 | 输入框和按钮整体 0.45 不透明且不可点 |
| 当前文档是扫描版（场景 14） | 主按钮禁用，tooltip `mapBannerNeedsOcr`；顶部显示扫描提示条（§8.2） |
| 另一个 AI 任务占用本机模型 | 可以点“生成”，进入排队（§5.3） |

---

## 4. 生成设置 `GenerateMapSheet`（场景 2）

### 4.1 布局

`showMMSheet(width: MMSizes.mapGenerateSheetWidth)`：`windowBackground`、0.5pt `border`、圆角 `MMRadii.sheet`，内边距 20 / 22 / 18；背后 `scrim`。标题行：`MMIcons.generateMap` 16（`research`）+ `mapGenerate`（`title3`），与表单间距 16。

表单是两列网格：标签列 `MMSizes.mapGenerateLabelWidth`，右对齐，`body`，`secondaryLabel`，顶部内边距 6（与右侧第一行文字基线对齐）；列间距 14，行间距 14。

| 行 | 标签 | 控件 |
| --- | --- | --- |
| 文档 | `mapGenerateDocuments` | 文档列表（§4.2） |
| 组织方式 | `mapGenerateOrganization` | `MMSegmentedControl`：`mapGenerateByChapter` / `mapGenerateByTopic`（选了多份文档时换成 `mapGenerateMergeByTopic`）/ `mapGenerateByQuestion` |
| 详细程度 | `mapGenerateDetail` | `MMSegmentedControl`：`mapGenerateDetailBrief` / `Medium` / `Full`；右侧 12 处 `mapGenerateEstimate(levels, count)`（`callout`，`secondaryLabel`，等宽数字） |
| 内容 | `mapGenerateContent` | 两行开关，行高 26：`mapGenerateMyMarks` + 行尾计数 `mapGenerateMarkCount(n)`（`footnote`，`secondaryLabel`）+ `MMSwitch(color: research)`；`mapGenerateQuotes` + `MMSwitch`。计数为 0 时开关仍可用，计数显示 0 |
| 生成到 | `mapGenerateTarget` | `MMDropdownButton`：`mapGenerateTargetNew` / `mapGenerateTargetBranch`（当前脑图为空时隐藏）/ 每张已关联脑图一项 `mapGenerateTargetReplace(title)`。选“新脑图”时右侧出现名称 `MMTextField`（宽 220，默认文档名，多文档时为第一份文档名，可改） |
| 要求 | `mapGenerateInstructions` | 多行 `MMTextField`，高 60 起、最多 6 行，最多 500 字，无占位 |

页脚（距表单 18）：左侧 `MMIcons.document` 14 + `mapGeneratePages(total)`（`callout`，`secondaryLabel`）；右侧 `cancel`（secondary）和主按钮 `mapGenerateStart` + 键帽 `⌘↩`。

- 组织方式的默认值：单文档 `chapter`，多文档 `topic`；从单选切到多选时，如果用户没有改过组织方式，自动切到“按主题合并”，反之亦然。
- 预计规模 `count`：概要约 20、适中约 40、详细约 80（层数 2 / 3 / 4），只随详细程度变化，不承诺准确值。
- 设置按学习集记住（文档选择除外），关闭不保存；“要求”在空状态和 sheet 之间同步。

### 4.2 文档列表

- 容器：1pt `separator` 描边、圆角 10，行间 1pt `separator` 分隔；最多显示 5 行高（`5 × mapGenerateDocumentRow`），超出在框内滚动。
- 文档行：高 `MMSizes.mapGenerateDocumentRow`，左右内边距 10，间距 10：`MMCheckbox(color: research)` → 类型图标 14（`document` / `ebook` / 扫描版 `MMReaderIcons.area`，`icon` 色）→ 标题（`body`，单行省略）→ 行尾信息（`callout`，`secondaryLabel`）。
- 行尾信息，只写一项（按优先级）：扫描版 `MMIcons.warning` 12 + `mapGenerateNeedsOcr`（`caution` 色）；需要分段 `mapGenerateSegments(n)`；否则 `mapGeneratePages(n)`。已关联脑图的文档在页数前加 12pt `MMIcons.mindMap`（语义 `mapHasMap`），不写文字。
- 章节范围：只选了一份有目录的文档时，这一行标题右侧出现纯文字按钮（`callout`，`accent`）：全选时 `mapGenerateWholeDocument`，否则 `mapGenerateChapterCount(selected, total)`，后接 `MMIcons.chevronDown` 10。点击在下方展开章节行；再点收起。没有目录时展开为页码范围输入（两个 `MMTextField` 宽 64，起止页）。
- 章节行：高 `MMSizes.mapGenerateChapterRow`，左内边距 38，`quaternaryFill` 底，无分隔线；复选框 + 章节名（`body`）+ 起始页 `notePage(page)`（`footnote`，`secondaryLabel`）。部分选中时文档行复选框为混合态。
- 至少选中一份文档；最后一份不能取消（复选框禁用）。

### 4.3 状态

| 状态 | 表现 |
| --- | --- |
| 选中了扫描版 | 主按钮禁用，tooltip `mapBannerNeedsOcr`；页脚总页数不计扫描版 |
| 选中章节为 0 | 主按钮禁用（不加说明，复选框状态已表达） |
| 未配置 AI | 表单换成 `ModelSetupCard(inline: true)`，页脚只留 `cancel` |
| 从提示条“并入当前脑图”打开 | 文档预选“当前脑图的依据 + 这份文档”，组织方式“按主题合并”，生成到“当前脑图的新分支”；结果以差异呈现（§10） |
| 生成到“替换「X」” | 主按钮文字不变；结果以差异呈现（§10） |

---

## 5. 生成中（场景 3、4）

### 5.1 通读：骨架主题

- 中心主题：文档标题（去掉“第 N 章”前缀后的主题词，由应用层给出），外加扩展规格 §4.4 的目标外圈脉冲。
- 骨架主题：每个一级目录条目一个，按目录顺序挂在中心主题下；尺寸、字号与一级主题相同（14pt 半粗，内边距 8 × 14，圆角 `MMRadii.row`），`quaternaryFill` 底，`secondaryLabel` 文字，连线 `research` 70% 虚线（同草稿）。没有目录时按固定页数分段，骨架标题为该段的页码范围（`notePage(start)` + “–” + `notePage(end)`，如“p.1–p.12”），不新增文案。
- 当前章节：不透明度按 `MMMotion.breathe` 呼吸；读完的章节换成草稿样式（扩展规格 §4.1），标题换成模型给出的章节标题。
- 画布在通读开始时适配到“中心主题 + 全部骨架”，之后不再自动缩放，直到成图阶段。
- 骨架不可点、不可聚焦，排除语义（进度由底部条播报）。

### 5.2 成图

- 骨架淡出（`quick`），草稿按到达顺序逐个出现（扩展规格 §4.2“出现”），画布按扩展规格 §4.4 自动缩放。
- 草稿右侧附出处标签（§6.1）。用户高亮作为摘录卡片草稿挂在对应主题下：摘录卡片原样（宋体摘录、左侧色条），外框换成草稿的 1pt `research` 虚线，底色不变（保留高亮色块的可读性）。

### 5.3 底部条

复用扩展规格 §5 的 `ExpansionBar`（高 `ideaBar` 40，下沿距面板底 `ideaBarBottomInset` + `chrome.bottom`，`surface` + 0.5pt `border`，圆角 20）。

| 阶段 | 标题区 | 按钮 |
| --- | --- | --- |
| 排队 | 14pt 环形进度 + `mapGenerateQueued` | `assistantStop` 键帽 `Esc` |
| 通读 | 14pt 环形进度 + `mapGenerateReading(document)`（标题最大宽 200）+ 进度格 + 当前章节名（`callout` 400，`secondaryLabel`，最大宽 160，单行省略） | `MMIcons.stop` `assistantStop` 键帽 `Esc` |
| 成图 | 14pt 环形进度 + `mapGenerateBuilding` + `mapGenerateTopicCount(n)`（0 时不显示） | 同上 |
| 审阅 | `MMIcons.generateMap`（`research`）+ 脑图名 + `mapIdeaKeptCount(kept, total)`；多文档时加 0.5pt 竖线和图例（§8.4） | `MMIcons.history` `mapIdeaRegenerate` · `MMIcons.adjust` `mapIdeaAdjust` · `mapIdeaDiscard` 键帽 `Esc` · 主按钮 `MMIcons.check` `mapIdeaDraftKeep` 键帽 `↩` |
| 审阅（已停止） | 标题换成 `mapIdeaStopped` | 同审阅 |
| 审阅（部分章节失败，场景 13） | 标题区前加 `MMIcons.warning` 14 + `mapGenerateChapterFailed(chapter)`（`critical`，多章失败时只列第一章 + “+N”）+ `assistantRetry` 纯文字按钮 + 竖线 | 同审阅；重试只重新生成失败的章节，完成后合并进当前草稿 |
| 失败且没有草稿 | `MMIcons.offline`（网络）或 `MMIcons.warning` + `assistantErrorNetwork` / `assistantError*`，`critical` | `assistantRetry` · `assistantUseLocal`（仅云端模型且本机模型可用）· `closePanel` |

- 进度格：每章一格 `MMSizes.mapReadingStep`，间距 3，圆角 2，颜色见 §1.2；章节超过 12 个时换成一条 120 × 4 的连续进度（`MMProgressBar`，`research`）。
- 审阅时“保留”按钮用不带数字的 `mapIdeaDraftKeep`，数量已经在标题区；保留数为 0 时禁用。
- 生成在后台进行：切换到其他脑图时底部条随脑图隐藏，侧栏脑图行显示进度；切回来恢复。

### 5.4 结束

| 结果 | 表现 |
| --- | --- |
| 保留 | 创建脑图，新节点 `flash`；HUD `mapGenerateCreated(title, count)` 带动作 `undo`（与 ⌘Z 同效）；表头按钮变为“更新” |
| 放弃 / Esc | 草稿全部消失；新建的空脑图不创建，回到空状态；无 HUD |
| 停止时没有任何草稿 | HUD `mapGenerateStoppedEmpty` |
| 正常结束但没有有效内容 | 不进入审阅，HUD `mapGenerateNothing` |
| 生成中关闭学习集 | 取消，草稿丢弃，无提示 |

---

## 6. 审阅（场景 5、6）

草稿样式、保留 / 不要、悬停控件、编辑、级联取消全部沿用扩展规格 §4。差异如下：

### 6.1 出处标签 `MapSourceChip`

- 高 `MMSizes.mapSourceChip`，圆角 `MMRadii.mapSourceChip`，左右内边距 6，`footnote` 500（11 / 中等）；文字 `notePage(page)`（`p.N`）。多文档时前置 `MMSizes.mapSourceDot` 色点（`MMSourceColors.of`，与文字间距 4）。
- 位置：节点内标题右侧，间距 6，参与节点宽度测量（保留后节点不跳动）。
- 草稿上常显；保留之后的生成主题平时隐藏，悬停或选中时显示（显示不改变节点尺寸：宽度始终按带标签测量，隐藏时只是透明）。
- 点击：原文栏跳到该页，`flash` 闪烁对应段落；多文档时先切换文档；原文栏收起时先恢复分栏。悬停 `fill` 底 + `label` 字，按下 `pressed`。
- 没有出处（模型给出的页码不在读过的页内，上位文档 §3）时不显示，节点保留。
- 摘录卡片沿用现有页脚的页码和定位按钮，不加出处标签。

### 6.2 调整菜单

扩展规格 §6 的 `ExpansionAdjustMenu` 换一组选项：`mapGenerateOrganization`、`mapGenerateDetail` 两行 `MMSegmentedControl`（组织方式的三项同 §4.1，标签用短名），下面多行 `MMTextField`（占位 `mapIdeaHint`）；底部右对齐主按钮 `MMIcons.history` `mapIdeaRegenerateAdjusted`。宽 `MMSizes.ideaAdjustWidth`；英文三段放不下时宽度增长到内容宽（上限 `mapUpdatePopoverWidth`）。没有“取消”按钮：Esc 或点外部关闭，草稿不变。改过字的草稿作为约束保留（上位文档 §2.4）。

### 6.3 保留之后（场景 7）

- 侧栏“脑图”分组出现新脑图（名称为设置里的名称），文档行出现关联标记；表头按钮变为“更新”。
- 生成主题的出处按 §6.1 隐藏 / 显示；⌘L 回到原文（`AppShortcuts.revealSource`，与摘录卡片一致）。
- 用户高亮写成普通摘录卡片，外观与手动摘录完全相同。

---

## 7. 生成期间的编辑限制

正在生成和审阅的脑图不可编辑，规则与扩展规格 §8.2 相同，HUD 文案换成 `mapGenerateBlocked`（差异审阅中为 `mapUpdateBlocked`）。原文栏、其他脑图、侧栏和切换文档不受影响；切换到其他脑图时生成继续（§5.3）。

---

## 8. 多文档（场景 8、9、10）

### 8.1 文档提示条 `DocumentMapBanner`

- 位置：脑图栏顶部浮动，上沿距表头下沿 8，左右各 `MMSpacing.m`；高 `MMSizes.mapDocumentBanner`；`surface` + 0.5pt `border`，圆角 `MMRadii.card`；左内边距 12、右内边距 6，项间距 10。
- 内容：`MMIcons.generateMap` 16（`research`）→ `mapBannerNoMap(document)`（`body`，文档名部分 600，单行省略，占满剩余宽度）→ 主按钮 `mapBannerGenerate`（高 28）→ 次按钮 `MMIcons.mergeIntoMap` 14 + `mapBannerMerge`（`quaternaryFill` 底，当前脑图为空时隐藏）→ `MMIconButton` `MMIcons.close`（语义 `closePanel`）。
- 每份文档只出现一次（✕、任一按钮、或切走都算出现过），记录按学习集保存。
- 出现 / 消失：`quick` 淡入并下移 4pt；不遮挡画布交互（只占自身区域）。
- “生成新脑图”：按记住的设置直接开始，新建脑图并切换过去。“并入当前脑图”：打开 §4.3 预选的设置。

### 8.2 扫描版提示条（场景 14）

同一组件：`MMReaderIcons.area` 16（`icon` 色）→ `mapBannerNeedsOcr` → 主按钮 `ocrTitle`（打开现有识别流程）→ ✕。识别完成后提示条消失，若用户已点过“生成”则自动继续。不写文档名和“是扫描版”。

### 8.3 随文档切换的提示（场景 9）

- 切换到有关联脑图的文档时，脑图栏切换（`layout` 交叉淡入），并在脑图栏右上角显示提示：`MMIcons.mindMap` 14（`research`）+ `mapFollowSwitched(title)`。
- 提示：`surface` + 0.5pt `border`，圆角 18（全圆），高 34，左右内边距 14，`callout`；上沿距表头下沿 12，右距 `MMSpacing.l`；显示 `MMMotion.hud` 后淡出；同时被提示条占用顶部时排在提示条下方 8。
- 设置 › 脑图 › `settingsMapFollowDocument`（`MMSwitch`，默认开）关闭后不切换、不提示。

### 8.4 多文档合成（场景 10）

- 出处标签前加色点（§6.1）。
- 底部条审阅阶段在计数后加图例：每份文档一项，色点 + 文档短名（`callout`，`secondaryLabel`，最大宽 96 省略），项间距 10；超过 3 份时只显示前 3 份 + “+N”。
- 点出处先切换文档再跳页。

---

## 9. 更新弹层 `MapUpdatePopover`（场景 11）

### 9.1 布局

- 锚在表头按钮下方 8，右缘对齐按钮右缘（放不下时向左平移，保持在窗口内 8）；宽 `MMSizes.mapUpdatePopoverWidth`；`surface` + 0.5pt `border`，圆角 `MMRadii.dropdown`，内边距 14；`quick` 淡入。
- 标题行：`MMIcons.generateMap` 16（`research`）+ `mapUpdateTitle`（`headline`）。
- 分组标签（`subheadline` 11 / 600，`secondaryLabel`，上 12 下 6，第一组上 0）依次：

| 分组 | 内容 |
| --- | --- |
| `mapUpdateSources` | 依据文档 chip（高 24，圆角 12，`quaternaryFill` 底 + `label` 字，`MMIcons.document` 12（`research`）+ 文档名，最大宽 160）；末尾 `MMIcons.add` 12 + `mapUpdateAddDocument`（`quaternaryFill` 底），点了在弹层内展开学习集文档列表（§4.2 行样式，只列未关联的文档）。依据有多份时 chip 换行 |
| `mapUpdateSince` | 键值行，高 28：`MMIcons.highlight` 14 + `mapUpdateNewHighlights` … 数字；`MMIcons.pen` 14 + `mapUpdateNewNotes` … 数字；`MMIcons.document` 14 + `mapUpdateReadTo` … `mapUpdateReadRange(from, to)`。数字右对齐，`secondaryLabel`，等宽。为 0 的行不显示；三行都为 0 时整组不显示 |
| `mapUpdateScope` | `MMSegmentedControl`：`mapUpdateScopeNew`（默认）/ `mapUpdateScopeAll`。没有新内容时默认仍是“只处理新内容”，配合要求使用 |
| — | 多行 `MMTextField`（占位 `mapIdeaHint`），2 行起、最多 4 行，最多 500 字。没有分组标签（占位已说明） |

- 受保护一行（输入框下 12）：`quaternaryFill` 底，圆角 10，内边距 10，`MMIcons.lock` 12（`secondaryLabel`）+ `mapUpdateProtected(n)`（`footnote`，`secondaryLabel`）；`n` 为 0 时不显示。
- 页脚（上 14）：右对齐主按钮 `mapUpdatePreview` + 键帽 `⌘↩`。没有“取消”：Esc、点外部或再点表头按钮关闭。
- 没有新内容、范围为“只处理新内容”、要求为空时，主按钮禁用（tooltip `mapUpdateNothing`）。

### 9.2 状态

| 状态 | 表现 |
| --- | --- |
| 预览更改 | 关闭弹层，脑图栏切到全宽（§10），底部条以“成图”阶段显示进度；差异逐条出现在画布和面板 |
| 没有得到任何改动 | 不进入差异审阅，HUD `mapUpdateNothing` |
| 失败 | 同 §5.3“失败且没有草稿” |
| 未配置 AI | 弹层主体换成 `ModelSetupCard(inline: true)` |

---

## 10. 差异审阅（场景 12）

### 10.1 进入与退出

- 进入：记住当前布局（原文 / 分栏 / 脑图），切到“脑图”单栏，右侧 `MapDiffPanel` 以 `layout` 从右滑入；画布可视区排除面板宽度，适配到“全部改动 + 其父节点”。
- 退出（应用、放弃）：面板滑出，恢复进入前的布局；应用后 HUD `mapUpdateApplied(n)` 带 `undo`；放弃无 HUD。
- 审阅期间表头按钮为选中态且不响应，底部条不显示（面板承担操作）。

### 10.2 画布上的差异标记 `MapDiffMarks`

| 类型 | 勾选（会应用） | 取消勾选 |
| --- | --- | --- |
| 新增 | 草稿样式 + 标签 `mapDiffTagNew` | 扩展规格的“不要”草稿样式，标签中性色 |
| 改名 | 节点显示新名，节点上方显示旧名（11pt `footnote`，`secondaryLabel`，删除线，左缘距节点左缘 10，下缘距节点上缘 3）+ 标签 `mapDiffRenamed` | 显示原名，不显示旧名行，标签中性色 |
| 移动 | 节点在新位置，外框草稿虚线，连线 `research` 80% 实线 + 标签 `mapDiffTagMovedFrom(oldParent)` | 节点回到原位置，普通样式 + 中性色标签 `mapDiffMoved` |
| 建议删除（默认不勾选） | 无底色、标题删除线 + `secondaryLabel`，1pt `secondaryLabel` 虚线，连线 `fill` 虚线 | 普通主题底 + 1pt `secondaryLabel` 虚线 + 中性色标签 `mapDiffTagRemove` |

- 标签：高 `MMSizes.mapDraftTag`，圆角 `MMRadii.mapDraftTag`，左右内边距 5，10pt 半粗（`MMTypography.subheadline` 改 10pt），在节点内标题之后、出处标签之前，间距 6。
- 改名节点在布局中上方多占 14pt（旧名一行），避免压到上一个兄弟节点。
- 受保护标记：只在差异审阅时显示，压在受保护节点（不含摘录卡片、笔记、图片卡，它们不会被改动）左上角，圆心在节点角外 (−8, −8) + 半径；`MMSizes.mapProtectedBadge` 圆形，`surface` + 0.5pt `border`，`MMIcons.lock` 12（`secondaryLabel`）；tooltip `mapDiffProtected`。不参与布局和命中。
- 点击画布上的改动节点：切换勾选（同列表复选框），并聚焦，面板滚动到对应行；点击未改动的节点无反应。
- 焦点：2pt `research` 环（扩展规格 §1.2）。

### 10.3 差异面板 `MapDiffPanel`

- 宽 `MMSizes.mapDiffPanelWidth`，贴脑图栏右缘，上接表头下沿，下到栏底；`windowBackground`，左侧 1pt `separator`。
- 标题行：高 44，左内边距 16，`MMIcons.generateMap` 16（`research`）+ `mapUpdateTitle`（`headline`）。不加关闭按钮（页脚“放弃”承担）。
- 列表（内边距 4 / 10 / 10，滚动）按类型分组，顺序：`mapDiffAdded`、`mapDiffRenamed`、`mapDiffMoved`、`mapDiffRemoved`；空组不显示。组标题：`subheadline`，`secondaryLabel`，左右缩进 6，上 10 下 4，行尾数量（`footnote`，`secondaryLabel`，等宽数字）。
- 行：内边距 7 × 8，圆角 `MMRadii.row`，项间距 9，上对齐；悬停 `hover`，聚焦 `selectedRow`。从左到右：`MMCheckbox(color: research)`（上移 1 对齐首行）→ 文本列 → 出处标签。
  - 标题（`body`，最多 2 行）：主题写标题；摘录卡片写 `mapDiffExcerpt(前 16 字…)`。
  - 第二行（`footnote`，`secondaryLabel`，上 2）只在三种情况出现：改名写旧名（删除线）；移动写 `mapDiffMoveRoute(from, to)`；建议删除写模型给出的理由。
- 列表最后（上 12）：受保护一行，样式同 §9.1，文案 `mapUpdateProtected(n)`。
- 页脚：上 1pt `separator`，内边距 10 × 12，项间距 8：左侧 `MMIcons.history` `mapIdeaRegenerate`；右侧 `mapIdeaDiscard` 键帽 `Esc`（secondary）、主按钮 `mapUpdateApply(n)` 键帽 `↩`；`n` 为 0 时主按钮禁用。
- 联动：点行聚焦对应节点（画布平移使其可见，不改缩放）；点节点滚动列表使行可见。取消勾选父级新增时，挂在它下面的新增一起取消（同级联取消）。
- 换一批：同样的要求重新生成，替换全部改动（改过字的新增 / 改名作为约束保留）。

---

## 11. 提示与退路汇总（场景 13、14）

| 情况 | 位置 | 文案 |
| --- | --- | --- |
| 未配置 AI | 空状态、设置、更新弹层 | `ModelSetupCard(inline: true)`，无额外文字 |
| 断网（云端模型） | 底部条 | `assistantErrorNetwork` · `assistantRetry` · `assistantUseLocal` · `closePanel` |
| 某章失败 | 底部条（审阅） | `mapGenerateChapterFailed(chapter)` · `assistantRetry` |
| 扫描版 | 提示条 | `mapBannerNeedsOcr` · `ocrTitle` |
| 超长文档 | 设置文档行 | `mapGenerateSegments(n)` |
| 没有有效内容 | HUD | `mapGenerateNothing` / `mapUpdateNothing` |
| 本机模型被占用 | 底部条 | `mapGenerateQueued` |
| 停止且无内容 | HUD | `mapGenerateStoppedEmpty` |
| 审阅中尝试编辑 | HUD | `mapGenerateBlocked` / `mapUpdateBlocked` |
| 保留 / 应用 | HUD + `undo` | `mapGenerateCreated(title, n)` / `mapUpdateApplied(n)` |
| 随文档切换 | 右上提示 | `mapFollowSwitched(title)` |

---

## 12. 键盘

快捷键用 `primaryShortcut`（macOS ⌘，Windows / Linux Ctrl），菜单显示随平台。

| 键 | 空状态 / 设置 / 更新弹层 / 调整菜单 | 生成中 | 审阅（焦点在草稿） | 差异审阅（焦点在改动） | 编辑草稿标题 |
| --- | --- | --- | --- | --- | --- |
| ⌘↩ | 生成 / 预览更改 / 重新生成（输入框内外都有效） | — | 保留 | 应用 | 确认编辑 |
| ↩ | 输入框内换行；焦点在主按钮时触发 | — | 保留勾选的草稿 | 应用勾选的改动 | 确认编辑 |
| Esc | 关闭 sheet / 弹层（输入法组合中先交给输入法） | 停止，已有草稿进入审阅 | 放弃 | 放弃 | 取消编辑 |
| 空格 | 输入 | — | 切换保留 / 不要 | 切换勾选 | 输入空格 |
| ↑ / ↓ | 输入框内移动光标；焦点在列表时移动行 | — | 按到达顺序移动焦点（循环） | 按面板列表顺序移动焦点（循环），列表与画布同步 | 交给输入框 |
| F2 | — | — | 编辑焦点草稿 | 编辑焦点新增 / 改名的标题（移动、删除不可编辑） | — |
| ⌘L | 选中生成主题时回到原文（空闲时） | 焦点草稿有出处时跳页（不改变审阅） | 同左 | 同左 | — |
| ⌘Z | 输入框自身撤销 | HUD `mapGenerateBlocked` | HUD `mapGenerateBlocked` | HUD `mapUpdateBlocked` | 输入框自身撤销 |
| 平移、缩放 | — | 允许 | 允许 | 允许 | 允许 |

- 生成中、审阅中的编辑命令拦截方式同扩展规格 §8.2（`Shortcuts` + `Actions` 覆盖 `mindMapShortcuts`）。
- 菜单栏 `MindMapCommand.generateFromDocument`：不设默认快捷键；大纲视图下可用（生成后切回脑图视图）；预览存在时禁用。
- 设置 sheet 内 Tab 顺序：文档列表 → 组织方式 → 详细程度 → 两个开关 → 生成到（→ 名称）→ 要求 → 取消 → 生成。打开时焦点在“要求”。

---

## 13. 无障碍

| 元素 | 语义 |
| --- | --- |
| 表头按钮 | `button`，标签为按钮文字；有更新时 `value` 为 `mapHasUpdates`；生成中 / 审阅中 `enabled: false` |
| 空状态 | 标题为 `header`；输入框 `textField` 标签 `mapIdeaHint`；建议 chip 为 `button` + `toggled` |
| 设置表单 | 每行用标签列作为控件的 `label`（`MMFormRow` 已有）；文档行复选框标签为文档名，`hint` 为行尾信息；章节按钮 `button` + `expanded` |
| 骨架主题 | `ExcludeSemantics` |
| 草稿节点 | 扩展规格 §9 的草稿语义；标签换成 `mapGenerateDraftSemantics(title, page, state)`（无出处时用 `mapIdeaDraftSemantics`） |
| 出处标签 | `button`，标签 `pageNumber(page)`；多文档 `mapSourceSemantics(document, page)` |
| 差异节点 / 面板行 | 可聚焦，`checked` 表示会应用；标签：新增 `mapDiffAddSemantics(title)`；改名 `mapDiffRenameSemantics(old, title)`；移动 `mapDiffMoveSemantics(title, from, to)`；建议删除 `mapDiffRemoveSemantics(title, reason)` |
| 受保护节点 | 节点自身语义追加 `hint` `mapDiffProtected`；徽标排除语义 |
| 底部条 | 标题区 `liveRegion`；按钮标签不含键帽 |
| 进度播报 | 每读完一章 `SemanticsService.announce(mapGenerateReadProgress(done, total))`；进入审阅时 `mapGenerateReady(n)`；章节失败时播报 `mapGenerateChapterFailed(chapter)`；不逐个播报草稿 |
| 提示条、切换提示、HUD | `liveRegion`；提示条按钮完整标签（并入按钮在 iPhone 只显示图标时仍读 `mapBannerMerge`） |
| 差异面板 | `Semantics(scopesRoute)` 标签 `mapUpdateTitle`，组标题 `header` |

焦点：开始生成时焦点留在画布；进入审阅时移到第一条草稿；进入差异审阅时移到面板第一行；保留、应用或放弃后回到中心主题（新脑图）或原选择（更新）。sheet、弹层关闭后焦点回到打开它的按钮。

---

## 14. 文案（ARB，已在本任务落地）

全部在 `apps/marginmind/lib/l10n/app_zh.arb` / `app_en.arb`，紧接 `mapIdea*` 之后；英文菜单项、按钮、分组标签用标题大小写，HUD 和语义用句子大小写。`test/map_generate_l10n_test.dart` 检查每个键两种语言都存在、已翻译、占位符已替换，并检查控件名称不超过 26 字符、不以句号或问号结尾。

### 14.1 入口与空状态

| 键 | 中文 | English | 用于 |
| --- | --- | --- | --- |
| `mapGenerate` | 生成脑图 | Generate Map | 表头按钮、设置标题 |
| `mapGenerateMenu` | 从文档生成… | Generate from Document… | 菜单栏、侧栏 + 菜单 |
| `mapGenerateDocumentMenu` | 生成脑图… | Generate Map… | 文档行右键 |
| `mapGenerateUpdate` | 更新 | Update | 表头按钮 |
| `mapGenerateRunning` / `Reviewing` | 生成中 / 审阅中 | Generating / Reviewing | 表头按钮 |
| `mapHasUpdates` | 有新内容 | New material | 紫点、侧栏点的语义 |
| `mapHasMap` | 已有脑图 | Has a map | 文档行关联标记的语义 |
| `mapGenerateFrom` | 从「{document}」生成脑图 | Generate a Map from “{document}” | 空状态标题 |
| `mapGenerateSettings` | 设置 | Settings | 空状态 |
| `mapGenerateStart` | 生成 | Generate | 主按钮 |
| `mapGenerateBlank` | 新建空白主题 | Start Blank | 空状态 |
| `mapGenerateSuggestExam` / `Explain` / `Quotes` / `Examples` | 侧重考试要点 / 每个主题附一句解释 / 保留原文关键句 / 举例说明 | Focus on Exam Points / Explain Each Topic / Keep Key Quotes / Add Examples | 建议 chip |

### 14.2 生成设置

| 键 | 中文 | English |
| --- | --- | --- |
| `mapGenerateDocuments` | 文档 | Documents |
| `mapGeneratePages` | {count} 页 | {count} pages（复数） |
| `mapGenerateSegments` | 分 {count} 段阅读 | {count} parts（复数） |
| `mapGenerateNeedsOcr` | 需先识别文字 | Needs text recognition |
| `mapGenerateWholeDocument` | 全文 | Entire Document |
| `mapGenerateChapterCount` | {selected} / {total} 章 | {selected} of {total} chapters |
| `mapGenerateOrganization` | 组织方式 | Organization |
| `mapGenerateByChapter` / `ByTopic` / `MergeByTopic` / `ByQuestion` | 按原文章节 / 按主题重组 / 按主题合并 / 按问题组织 | By Chapter / By Concept / Merge by Concept / By Question |
| `mapGenerateDetail` | 详细程度 | Detail |
| `mapGenerateDetailBrief` / `Medium` / `Full` | 概要 / 适中 / 详细 | Brief / Medium / Detailed |
| `mapGenerateEstimate` | {levels} 层 · 约 {count} 个主题 | {levels} levels · about {count} topics |
| `mapGenerateContent` | 内容 | Content |
| `mapGenerateMyMarks` | 放入我的高亮和批注 | My Highlights and Notes |
| `mapGenerateMarkCount` | {count} 条 | {count} |
| `mapGenerateQuotes` | 摘录原文关键句 | Key Quotes |
| `mapGenerateTarget` | 生成到 | Generate To |
| `mapGenerateTargetNew` / `Branch` | 新脑图 / 当前脑图的新分支 | New Map / New Branch of This Map |
| `mapGenerateTargetReplace` | 替换「{title}」 | Replace “{title}” |
| `mapGenerateInstructions` | 要求 | Instructions |

### 14.3 生成、审阅与结果

| 键 | 中文 | English |
| --- | --- | --- |
| `mapGenerateReading` | 阅读「{document}」 | Reading “{document}” |
| `mapGenerateBuilding` | 生成脑图 | Building Map |
| `mapGenerateTopicCount` | {count} 个主题 | {count} topics（复数） |
| `mapGenerateQueued` | 等待中 | Waiting |
| `mapGenerateChapterFailed` | 「{chapter}」未生成 | “{chapter}” failed |
| `mapGenerateBlocked` | 先保留（↩）或放弃（Esc）这次生成 | Keep (↩) or discard (Esc) the generated map first |
| `mapGenerateCreated` | 已生成脑图「{title}」 · {count} 个主题 | Created “{title}” · {count} topics（复数） |
| `mapGenerateNothing` | 没有得到可用的结构，换个组织方式试试 | No usable structure. Try another organization. |
| `mapGenerateStoppedEmpty` | 已停止，没有生成内容 | Stopped before any topics |
| `mapGenerateDraftSemantics` | AI 草稿，{title}，第 {page} 页，{state} | AI draft, {title}, page {page}, {state} |
| `mapGenerateReadProgress` | 已读 {done} / {total} 章 | Read {done} of {total} chapters |
| `mapGenerateReady` | 可以审阅，{count} 个主题 | Ready to review, {count} topics（复数） |
| `mapSourceSemantics` | {document}，第 {page} 页 | {document}, page {page} |

### 14.4 多文档

| 键 | 中文 | English |
| --- | --- | --- |
| `mapBannerNoMap` | 「{document}」还没有脑图 | “{document}” has no map |
| `mapBannerGenerate` | 生成新脑图 | New Map |
| `mapBannerMerge` | 并入当前脑图 | Add to This Map |
| `mapBannerNeedsOcr` | 先识别文字才能生成 | Recognize text to generate a map |
| `mapFollowSwitched` | 已切换到「{title}」 | Switched to “{title}” |
| `settingsMapFollowDocument` | 随文档切换脑图 | Switch Maps with Documents |
| `settingsMapClearCache` | 清除生成缓存 | Clear Generation Cache |

### 14.5 更新与差异

| 键 | 中文 | English |
| --- | --- | --- |
| `mapUpdateTitle` | 更新脑图 | Update Map |
| `mapUpdateSources` | 依据 | Sources |
| `mapUpdateAddDocument` | 添加文档 | Add Document |
| `mapUpdateSince` | 上次生成之后 | Since Last Generated |
| `mapUpdateNewHighlights` / `NewNotes` / `ReadTo` | 新增高亮 / 新增批注 / 读到 | New highlights / New notes / Read to |
| `mapUpdateReadRange` | p.{from} → p.{to} | p.{from} → p.{to} |
| `mapUpdateScope` | 范围 | Scope |
| `mapUpdateScopeNew` / `ScopeAll` | 只处理新内容 / 全文重新梳理 | New Material Only / Rework Everything |
| `mapUpdateProtected` | 你改过、添加的 {count} 个节点保持不变 | {count} edited topics stay as they are（复数） |
| `mapUpdatePreview` | 预览更改 | Preview Changes |
| `mapUpdateNothing` | 没有需要更新的内容 | Nothing to update |
| `mapDiffAdded` / `Renamed` / `Moved` / `Removed` | 新增 / 改名 / 移动 / 建议删除 | Added / Renamed / Moved / Suggested Removals |
| `mapDiffTagNew` | 新 | New |
| `mapDiffTagMovedFrom` | 移自 {from} | From {from} |
| `mapDiffTagRemove` | 建议删除 | Remove |
| `mapDiffMoveRoute` | 从「{from}」移到「{to}」 | {from} → {to} |
| `mapDiffExcerpt` | 摘录：{text} | Excerpt: {text} |
| `mapDiffProtected` | 受保护 | Protected |
| `mapUpdateApply` | 应用 {count} 项 | Apply {count}（复数） |
| `mapUpdateApplied` | 已更新 {count} 处 | Updated {count} items（复数） |
| `mapUpdateBlocked` | 先应用（↩）或放弃（Esc）这次更新 | Apply (↩) or discard (Esc) the update first |
| `mapDiffAddSemantics` | 建议新增，{title} | Suggested addition, {title} |
| `mapDiffRenameSemantics` | 建议改名，{old} 改为 {title} | Suggested rename, {old} to {title} |
| `mapDiffMoveSemantics` | 建议移动，{title}，从{from}移到{to} | Suggested move, {title}, from {from} to {to} |
| `mapDiffRemoveSemantics` | 建议删除，{title}，{reason} | Suggested removal, {title}, {reason} |

复用（不新增）：`mapIdeaHint`、`mapIdeaKeptCount`、`mapIdeaRegenerate`、`mapIdeaAdjust`、`mapIdeaRegenerateAdjusted`、`mapIdeaDiscard`、`mapIdeaDraftKeep`、`mapIdeaStopped`、`mapIdeaDraftSemantics`、`mapIdeaDraftKept` / `Skipped`、`assistantStop`、`assistantRetry`、`assistantUseLocal`、`assistantError*`、`ocrTitle`、`notePage`、`pageNumber`、`newMap`、`cancel`、`closePanel`、`undo`。

---

## 15. 设备布局

### 15.1 Mac

如上文。窗口最小宽 960：侧栏展开时脑图栏可能只有 `mapMinWidth`（360），差异审阅切到“脑图”单栏后可用宽度 ≥ 724，足够放下 340 的面板和 360 的画布（`tokens_test` 覆盖）。

### 15.2 iPad（regular 宽度，触控）

| 组件 | 差异 |
| --- | --- |
| 表头按钮 | 视觉高 `tabletControlVisual`（32），热区 `touchTarget`；图标 `tabletToolbarIcon`（18）；文字保留 |
| 空状态 | 同 Mac；硬件键盘时 ⌘↩ 有效；软键盘弹出时内容上移到键盘之上 |
| 生成设置 | `showMMSheet` 居中，宽 640；文档行、章节行高 `touchTarget`；开关行高 44 |
| 更新弹层 | 同 Mac，锚在表头按钮；键值行高 36 |
| 草稿 | 扩展规格 §11 的触控规则：点按切换，长按 Action Sheet（保留或不要 / 修改 / 回到原文） |
| 差异面板 | 脑图单栏宽度 ≥ `mapDiffPanelWidth + mapMinWidth`（700）时为右侧面板（横屏、竖屏全屏都满足）；否则（分屏多任务的窄窗口）改为底部 sheet（同 iPhone）。面板行最小高 44，复选框热区 44 |
| 提示条 | 同 Mac；按钮高 36 |
| 竖屏分栏（上下排列） | 提示条、切换提示在脑图栏内；进入差异审阅时切到脑图全屏 |

### 15.3 iPhone（compact）

| 组件 | 差异 |
| --- | --- |
| 入口 | 脑图视图的拇指工具条加一个按钮（`thumbDockButton` 46 × 44，图标 20 `generateMap`，`research`），位于样式之后；紫点贴图标右上角；生成中换成环形进度。只用图标，语义标签同表头按钮文字。“更多”菜单不重复 |
| 空状态 | 宽为屏幕宽 − 2 × `MMSpacing.l`；建议 chip 换行；底部让出拇指工具条与安全区；键盘弹出时滚动到输入框可见 |
| 生成设置 | **全高 sheet**：`showMMSheet` 在 compact 下走 `showMMBottomSheet`，`MMBottomSheet(expand: true)`。标题行左侧 `cancel`、中间 `mapGenerate`、右侧主按钮 `mapGenerateStart`；表单改为单列，标签在上（`subheadline`，`secondaryLabel`，下 6），控件全宽；组织方式三段放不下时换成 `MMDropdownButton`；页脚总页数移到文档列表下方 |
| 更新弹层 | 底部 sheet（随内容高度），内容同 §9.1，主按钮全宽固定在底部 |
| 调整菜单 | 底部 sheet（扩展规格 §11） |
| 底部条 | 扩展规格 §11 的 compact 规则：左右贴边 `MMSpacing.m`，标题区最大宽 140，按钮只留图标 + tooltip（保留按钮保留文字）；通读时隐藏当前章节名，只留进度格 |
| 差异审阅 | **差异面板改为底部 sheet**：两档高度，默认中档（`MMSizes.bottomSheetMedium` 比例，画布在上方可见并适配），上拉为大档；下拉到底只收起到最低档（标题行 + 页脚），不放弃。sheet 页脚固定：换一批（图标）· 放弃 · 应用 N 项。点画布节点时 sheet 保持当前档并滚动到对应行 |
| 提示条 | 左右 `MMSpacing.s`，在顶栏下方 8；“并入当前脑图”只显示 `mergeIntoMap` 图标（语义仍是完整文字）；文字区单行省略 |
| 切换提示 | 顶栏下方居中，最大宽为屏幕宽 − 32 |
| 键盘 | 硬件键盘时与 iPad 相同 |

---

## 16. 场景对照

| 原型场景 | 本文 |
| --- | --- |
| 1 空脑图：一句话生成 | §2、§3 |
| 2 生成设置 | §4 |
| 3 生成中 · 通读全文 | §5.1、§5.3 |
| 4 生成中 · 结构流式成图 | §5.2、§5.3 |
| 5 审阅新脑图 | §6.1、§12、扩展规格 §4 |
| 6 调整要求后重新生成 | §6.2 |
| 7 保留完成 | §5.4、§6.3 |
| 8 切换到没有脑图的文档 | §8.1 |
| 9 切换到已有脑图的文档 | §8.3 |
| 10 多份文档合成一张脑图 | §4.2、§8.4 |
| 11 文档有新内容 | §2、§9 |
| 12 审阅更新（差异） | §10 |
| 13 部分章节失败（含断网、未配置 AI 开关） | §3、§5.3、§11 |
| 14 扫描版文档 | §3、§8.2 |

三种设备的差异见 §15。

---

## 17. 本任务对原型的修改

为与本文一致，`design/prototype/mindmap-from-document.html` 做了以下修改：

1. 空状态去掉副标题（“全文 48 页 · 你的 12 条高亮会放进对应主题”“需要先连接一个模型”）、连接卡里的说明，以及“新建空白主题”前的“或”；输入框占位改为“补充要求”；建议“用英文”改为“举例说明”。
2. 生成设置：组织方式的说明文字去掉，改为分段控件；“摘录原文关键句”去掉“在原文上用虚线标出”；文档行的“全文 · 选择章节”改为行内的章节按钮；页脚只写总页数；“要求”去掉示例占位。
3. 更新弹层：去掉“取消”（Esc / 点外部关闭）和“要求”分组标签。
4. 调整菜单：去掉“取消”；要求输入框改为空白占位“补充要求”。
5. 差异面板：去掉标题栏 ✕；新增项去掉“在「X」下”，新高亮摘录去掉“你的新高亮”；保护说明改为“你改过、添加的 7 个节点保持不变”。
6. 草稿上的出处标签、更新弹层的依据 chip 不再用 `research` 字 + `researchTint` 底；差异标签和已选的建议 chip 改为实心 `research` 底 + `onResearch` 字（对比度，§1.2）。
7. 建议删除：未勾选时标题不划删除线，勾选后才划（表示“将删除”）。
8. 底部条高 40、下沿上移到 64（与扩展规格的 `ExpansionBar` 一致），审阅的“保留”不带数字；断网文案改为“网络不可用”；章节失败改为“「6.6 提取」未生成”。
9. 扫描版提示条改为“先识别文字才能生成 · 识别文字”。
