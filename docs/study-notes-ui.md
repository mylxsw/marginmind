# 学习笔记：界面规格

> 建立日期：2026-10-30（GUL-587）。上位文档：[`study-notes.md`](study-notes.md)（第 14 节为已确认的决定）。数据模型与服务以上位文档第 12 节为准；本文只定界面。
> 交互原型：[`design/prototype/study-notes.html`](../design/prototype/study-notes.html)。单文件、无依赖；14 个场景与本文第 13 节对应，演示控制台可切换“未配置 AI / 深色 / 窄窗口”。
> 视觉以现有应用和 `mm_design` 令牌为准，原型的 CSS 数值只作参考。没有写到的细节沿用 [`design-system.md`](design-system.md)、[`phase-3-assistant-ui.md`](phase-3-assistant-ui.md) 和 [`phase-4-ui.md`](phase-4-ui.md)。

本文写给第 A–C 期的实现者：每个界面给出尺寸（pt）、令牌、状态、文案和平台差异，实现时不需要再看原型源码。

**界面原则（必须遵守）。** 不加多余的次级标签和说明文字，让布局表达含义；不加多余的辅助文字、描述性文案和重复的界面微文案。具体到本功能：

- 表单选项只写名称，不写选项说明；选项的差别由缩略图、预览或结果本身展示。
- 面板标题不带副标题；页脚只放按钮，唯一例外是会发送内容给 AI 时的一行发送说明（第 3.2 节）。
- 提示条（HUD）只写结果，不写解释（“已从笔记中移除”，而不是“……，划线仍在原文”）。
- 不可用的操作直接隐藏（如“我的批注”没有 AI 改写项）；因缺少配置而暂时不可用的，置灰并以 tooltip 给出原因（“未配置 AI”）。

---

## 0. 术语

| 术语 | 含义 |
| --- | --- |
| 笔记 | `StudyNote`，学习集里的一篇学习笔记，与脑图并列 |
| 三种声音 | 原文（书里的话）、我的（页边批注、脑图笔记）、AI（小结、要点、关联、补充说明、复习题） |
| 块 | `NoteBlock`：摘录、我的批注、AI 段落、要点、关联 |
| 整理 | 从划线生成笔记的整个流程：设置 → （提纲）→ 生成 |
| 更新 | 把整理之后新增的划线合并进已有笔记 |
| 尺寸类 | `MMSizeClass`：compact（< 600 宽）、medium、regular（≥ 1180 宽且横屏；桌面始终 regular） |

---

## 2026-11-01：笔记独立工作页

以下规则取代后文中“笔记占用脑图面板”的布局约定：

- 打开笔记后，默认只显示笔记，学习集侧栏保留；不自动带出先前打开的文档。
- 笔记是常驻的主内容。点击摘录、页边批注或脑图笔记的来源，在右侧打开对应文档或脑图；脑图来源可以跨图定位。
- 内容区达到 801pt 时左右分栏，两栏各至少 400pt。分隔线支持拖动，双击恢复笔记占 55%。笔记分栏比例与阅读工作区分开保存于当前会话。
- 窄窗口的补充内容覆盖笔记区域，提供关闭入口；关闭后回到原来的笔记位置。打开、切换和关闭补充内容不会重建笔记编辑器。
- 笔记顶部只有一个“更多”，包含版式、目录、整理、导出、分享和补充内容入口；宽屏保留常用操作的快捷按钮。
- 手机笔记页使用自己的标题栏，不显示阅读／脑图切换栏。来源页面提供标题和关闭按钮。
- 点击侧栏里的文档或脑图也会在补充区域打开。点击其他笔记会收起补充内容；通过返回按钮或阅读／脑图布局快捷键离开笔记页。

## 1. 通用约定

### 1.1 新增令牌（`mm_design`）

在 `metrics.dart` 新增 `MMNoteLayout`（笔记版面，屏幕 pt）：

| 常量 | 值 | 用途 |
| --- | --- | --- |
| `measure` | 600 | 正文最大宽度（不含左右留白） |
| `gutter` | 64 | 正文左侧留白，容纳段落操作按钮 |
| `gutterCompact` | 20 | compact 下左右留白（段落操作改为长按，第 5.6 节） |
| `trailing` | 56 | 正文右侧留白 |
| `topInset` / `bottomInset` | 30 / 120 | 正文上下留白；底部留白保证最后一段能滚到 HUD 上方 |
| `blockButton` | 22 | 段落操作按钮边长，圆角 6，距正文左缘 30 |
| `blockGap` | 12 | 块间距 |
| `sectionTop` / `sectionBottom` | 30 / 10 | 节标题上下间距 |
| `quoteBar` | 3 | 摘录左侧色条宽度（圆角 2） |
| `quoteIndent` | 16 | 摘录、我的批注相对正文的缩进 |
| `aiRule` | 2 | AI 块左侧细线宽度；细线在正文左缘外 12 |
| `tocWidth` | 224 | 右侧目录宽度 |
| `tocMinWidth` | 1000 | 笔记面板宽度达到此值才显示浮动目录 |
| `barHeight` | 44 | 笔记工具栏、标注列表标题栏高度 |
| `voiceTagHeight` | 16 | “AI”标签高度，圆角 4，左右内边距 4 |

在 `MMSizes` 新增（面板宽度在窗口不够时取 `min(值, 窗口宽 − 2 × MMSpacing.xxl)`）：

| 常量 | 值 | 用途 |
| --- | --- | --- |
| `noteSetupSheetWidth` | 640 | 整理设置 |
| `noteOutlineSheetWidth` | 680 | 确认提纲 |
| `noteProgressSheetWidth` | 820 | 生成中（左侧步骤 200 + 右侧预览） |
| `noteExportSheetWidth` | 900 | 导出 |
| `noteExportOptionsWidth` | 280 | 导出左侧选项列 |
| `noteExportBodyHeight` | 520 | 导出面板内容区高度 |
| `noteShareSheetWidth` | 860 | 分享长图 |
| `noteShareOptionsWidth` | 250 | 分享左侧选项列 |
| `noteShareCardWidth` | 330 | 长图宽度（导出时 2×，即 660 px） |
| `noteFormThumbHeight` | 56 | 整理设置中版式缩略图高度 |
| `noteCoverageWidth` | 340 | “未用上”弹层宽度 |

在 `typography.dart` 新增 `MMNoteTypography`：

| 常量 | 字体 | 字号 / 行高 | 用途 |
| --- | --- | --- | --- |
| `title` | 系统字体 700 | 24 / 31 | 笔记标题 |
| `heading` | 系统字体 700 | 17 / 22 | 节标题；序号用 `secondaryLabel` 600、等宽数字 |
| `body` | 系统字体 400 | 14 / 24.5 | AI 段落、我的批注、要点、行动清单 |
| `quote` | `readingBody` 字族（宋体） | 15 / 27.75 | 摘录 |
| `context` | 同上 | 14 / 26 | 摘录的前后句 |
| `gloss` | 系统字体 400 | 12.5 / 20 | AI 补充说明、关联 |

### 1.2 三种声音：颜色与字体

**不新增 AI 颜色**：AI 写的内容统一使用助手已有的 `MMColors.research` / `researchTint`（浅色 `#5E5CE6`，深色 `#7D7AFF`），与助手、研究笔记一致，并与选中色 `accent` 区分。只新增一个前景色 `MMColors.onResearch`（浅色 `#FFFFFF`，深色 `#1E1E1F`），用于实心 `research` 底上的文字。

标签用实心底而不是 `researchTint` 浅底，是因为小字标签需要 4.5:1：`research` 字在 `researchTint` 上只有 4.3:1（浅色）/ 3.7:1（深色），实心标签为 5.1:1 / 4.8:1。

| 声音 | 字体 | 颜色与标记 | 能否编辑 |
| --- | --- | --- | --- |
| 原文摘录 | `MMNoteTypography.quote`，`excerptText` 色 | 左侧 3pt 色条 = 划线颜色（`MMAnnotationColor.color`）；下方出处行 | 不能 |
| 原文前后句 | `MMNoteTypography.context`，`secondaryLabel` 色 | 展开时摘录本身加划线颜色 `highlight` 底（圆角 2） | 不能 |
| 我的批注 | `MMNoteTypography.body`，`label` 色 | `MMAnnotationColor.yellow.cardTint` 底（14%），圆角 8，内边距 7×11，缩进 `quoteIndent`；下方来源行（`footnote`，`secondaryLabel`） | 能；同步回原批注（决定 1） |
| AI 段落、要点、关联 | `MMNoteTypography.body` | 行首“AI”标签：实心 `research` 底 + `onResearch` 字，`MMIcons.ai` 10 + “AI”（10.5 / 600）；左侧 2pt `researchTint` 细线，悬停时变 `research` | 能 |
| AI 段落（改过） | 同上 | 标签文字变为“AI · 已改”，样式不变 | 能；改过即加锁 |
| AI 补充说明（残句） | `MMNoteTypography.gloss`，`secondaryLabel` | `researchTint` 底，圆角 7，内边距 5×9，位于摘录下方 6 | 能 |
| 一句话总结 | `MMNoteTypography.body` | `researchTint` 底，圆角 10，内边距 12×14，位于标题区下方 14 | 能 |

- 关闭 AI 标记（第 5.2 节）后：“AI”标签和左侧细线隐藏；总结与补充说明的底色改为 `quaternaryFill`。
- 不使用 AI 整理的笔记没有 AI 块，因此也不显示 AI 标记按钮。
- 不加图例：三种声音由字体与底色区分，不在笔记里解释。

### 1.3 状态色

| 用途 | 令牌 |
| --- | --- |
| “N 条划线全部引用 · 原文未改写” | `MMPill`，`positive` |
| “N 条划线未用上” | `MMPill`，`caution`，可点 |
| 更新横幅、待插入的块 | `positive` 12% 底；待插入块左侧 4pt `positive` 色条 |
| 新增划线标记（原文） | 划线外 1.5pt `positive` 虚线框，外扩 1 |
| 划线已删除 / 原文已移除 | 出处行文字 `critical`，前置 `MMIcons.warning` 11 |
| 未配置 AI | 文字 `caution`（`footnote`） |

### 1.4 图标（`MMIcons` 新增）

| 名称 | 图标 | 用途 |
| --- | --- | --- |
| `studyNote` | `LucideIcons.notebookText` | 侧栏笔记条目、笔记工具栏标题 |
| `context` | `LucideIcons.textQuote` | 展开 / 收起上下文 |
| `share` | `LucideIcons.share` | 分享长图 |
| `export` | `LucideIcons.download` | 导出笔记 |
| `regenerate` | `LucideIcons.refreshCw` | 重新整理、换一种说法 |
| `shorter` / `longer` | `LucideIcons.alignLeft` / `LucideIcons.textSelect` | 更简洁 / 展开说明 |
| `person` | `LucideIcons.user` | 改为我的话、我的批注来源行 |
| `grip` | `LucideIcons.gripVertical` | 提纲中拖动节 |

已有图标直接复用：`ai`（整理入口、AI 标签）、`more`（段落操作）、`revealSource`（出处、定位原文）、`mindMap`（加入脑图）、`review`（加入复习）、`lock`（加锁）、`warning`、`check`、`stop`、`copy`、`trash`、`add`、`close`、`outline`（目录）。

### 1.5 动效

| 动作 | 时长 / 曲线 |
| --- | --- |
| 面板出现 | 沿用 `showMMSheet`（compact 为 `MMBottomSheet`） |
| 弹层、菜单 | `MMMotion.quick` 淡入 + 3pt 位移 |
| 生成时逐块出现 | 每块 `MMMotion.standard` 淡入；流式文字末尾 7×14 `research` 光标，1s 两态闪烁（与助手相同） |
| 跳回原文 / 跳到摘录 | `MMMotion.flash` 高亮闪烁（与“回原文”一致） |
| 应用更新后新块 | `positive` 12% 底，`MMMotion.flash` 内淡出 |
| 拖动提纲 | 被拖项 40% 不透明；目标节 2pt `accent` 描边 |
| 减少动态效果 | 无位移、无闪烁，改为一次静态强调 |

---

## 2. 入口（场景 1）

| 位置 | 形态 | 行为 |
| --- | --- | --- |
| 菜单 文件 › 整理学习笔记… | ⌥⌘P（Windows / Linux / Web：Ctrl+Alt+P） | 打开整理设置；标注列表有选中项时范围默认“选中的划线”，否则“整个学习集” |
| 窗口工具栏 | `MMToolbarGroup` 内 `MMToolbarButton`，图标 `ai` + 文字“整理笔记”，tooltip“整理学习笔记 ⌥⌘P” | 同上 |
| 侧栏“笔记”分组标题右侧 **+** | 20×20 `MMIconButton`（`add` 12），tooltip 同上 | 同上 |
| 标注列表多选栏 | 主要按钮“整理成笔记”（第 2.2 节） | 范围固定为“选中的划线” |
| 脑图分支右键 | 菜单项“整理成笔记…” | 范围“分支「标题」”，组织方式默认“按脑图结构” |

- 命令在 `app_commands.dart` 定义：`organizeStudyNote`（⌥⌘P，`primaryShortcut(LogicalKeyboardKey.keyP, alt: true)`）、`exportStudyNote`、`shareStudyNote`（后两者无快捷键，只在当前打开的是笔记时可用）。
- 学习集里没有任何划线时，所有入口仍可点，打开后显示空范围状态（第 3.4 节）。

### 2.1 侧栏

- 分组顺序：文档 → 脑图 → **笔记** → 学习。分组标题 `sectionNotes`“笔记”。
- 条目：`MMSidebarItem`，图标 `studyNote`（`accent`），标签为笔记标题（单行省略）。按 `updatedAt` 倒序排列，数量不限（决定 3）。
- 有待合并的新划线时，尾部 `MMBadge` 显示数量；否则不显示数字。
- 正在生成的笔记：尾部 9pt 转圈（`research`）。
- 没有笔记时分组只显示标题和 **+**，不加占位行。
- 右键菜单：重命名…（`rename`）、导出笔记…、分享长图… ─ 删除（`critical`）。删除不弹确认，HUD“已删除”＋“撤销”。

### 2.2 标注列表多选

沿用页面侧栏“标注”（⌥⌘4）与右侧面板的标注列表，增加多选：

- 标题栏（高 `barHeight`）：“标注”（`headline`）→ 颜色筛选（6 个 14pt 圆点，间距 5；关闭的颜色 35% 不透明，tooltip“按颜色筛选”）→ 弹性空白 → 纯文本按钮“全选 / 取消全选”。不显示条数。
- 条目：左侧 16pt `MMCheckbox`（整行可点）→ 3pt 色条 → 引文（宋体 13.5 / 21）→ 我的批注（`body` 12，`yellow.cardTint` 底，圆角 6）→ 出处行：页码链接“↗ p.12”（`accent` 11，点击定位原文）、整理后新增的划线加 `MMPill`“新增”（`positive`）。选中行 `accentTint` 底。
- 按章节分组：组标题“书名 · 章节”（`subheadline`，前置 `ebook` 11）。
- 多选栏：浮在列表底部居中，距底 18，高 38，圆角 19，`glass` 底 + `glassShadow`。内容：“已选 N 条”（`callout`，`secondaryLabel`）+ 主要按钮“整理成笔记”（`ai` 图标，胶囊）。N = 0 时按钮禁用。

---

## 3. 整理设置（场景 2、3）

### 3.1 版面

`showMMSheet`，宽 `noteSetupSheetWidth`。标题行：`ai` 图标 + “整理学习笔记”（`title3`），无副标题。表单用 `MMFormRow`（标签列 96，右对齐，`callout` / `secondaryLabel`；行间 0.5pt `separator`，行内上下 9）。

| 行 | 控件 | 选项与规则 |
| --- | --- | --- |
| 范围 | 单选胶囊组（高 28，圆角 8，间距 6；选中 1.5pt `accent` 描边 + `accentTint` 底 + `accent` 字；数量为 `footnote` `secondaryLabel`，选中时 `accent`） | 选中的划线 N / 整个学习集 N / 《当前文档》N / 最近 7 天 N；从脑图分支进入时只多一项“分支「标题」”并默认选中 |
| 素材 | 多选胶囊组，选中时前置 `check` 12 | 划线 N（始终选中、不可点）/ 我的批注 N / 脑图笔记 N / 已存的 AI 笔记 N / 图片卡片 N；数量为 0 的项置灰 |
| 组织方式 | 三张卡片（等宽，间距 8，内边距 10，圆角 10；选中 2pt `accent` 描边 + `accentTint` 底） | 按主题归纳（右上角“AI”标签）/ 按原文顺序 / 按脑图结构。卡片只写名称 |
| AI 参与 | 单选胶囊组 | 只排版 / 补全与小结 / 深度整理 |
| 上下文 | 滑块（宽 160，0–3，步长 1）+ “前后 N 句”；下一行 `MMSwitch`“补全指代” | 默认 1 句、补全开 |
| 版式 | 三张卡片，上部缩略图（高 `noteFormThumbHeight`，`card` 底，0.5pt `hairline`；抽象线条：标题 `label`、AI `research`、摘录 `yellow`），下部名称 | 读书笔记 / 康奈尔笔记 / 复习提纲 |

**联动**

- 默认值：AI 参与“深度整理”；之后记住上次生成时的选择（决定 2，保存在应用设置，不按学习集）。组织方式默认“按主题归纳”；记住的档位为“只排版”时默认“按原文顺序”。
- 选“只排版”时，若组织方式为“按主题归纳”，自动改为“按原文顺序”；反之在“只排版”下点“按主题归纳”，AI 参与自动改回记住的 AI 档位（没有则“深度整理”）。
- “补全指代”在“只排版”或未配置 AI 时置灰并显示为关。
- 切换版式只改变初始版式，之后可随时切换（第 5.4 节）。

### 3.2 页脚

左侧：会调用 AI 且范围不为空时，一行发送说明：`shield` 12 + “将发送 9 条划线、3 条批注（约 5,400 字）给 Claude Sonnet”（`footnote`，`secondaryLabel`；批注数为 0 时省略该项；模型名取助手当前模型）。不会调用 AI 时左侧留空。

右侧按钮：取消（`MMButton.secondary`）→ 先看提纲（`secondary`；只在会调用 AI 且组织方式为“按主题归纳”时出现）→ 生成笔记（`primary`，`ai` 图标；AI 档位时 `color: research`）。

### 3.3 未配置 AI（场景 3）

- “按主题归纳”卡片、“补全与小结”“深度整理”置灰（40% 不透明），AI 参与固定为“只排版”，组织方式默认“按原文顺序”。
- 组织方式行下方一行：“未配置 AI”（`caution`，`footnote`）+ 纯文本按钮“去设置”（`accent`），打开 设置 › 助手。
- 页脚不显示发送说明；按钮只有“取消”“生成笔记”。

### 3.4 范围为空

页脚左侧“没有可整理的划线”（`critical`，`footnote`），“先看提纲”“生成笔记”禁用。

### 3.5 compact

全高 `MMBottomSheet`：顶部标题行左“取消”、中“整理学习笔记”、右“生成笔记”（`accent` 文字按钮）。表单改为上下排列（标签在上，`subheadline`，左对齐），胶囊组可换行，组织方式与版式卡片横向滚动。发送说明放在表单末尾；“先看提纲”为表单末尾的全宽次要按钮。

---

## 4. 确认提纲与生成（场景 4、5）

### 4.1 确认提纲

`showMMSheet`，宽 `noteOutlineSheetWidth`。标题“确认提纲”，无副标题。

| 元素 | 规格 |
| --- | --- |
| 节卡片 | `card` 底，圆角 12，0.5pt `hairline`，内边距 8/10/10，间距 8 |
| 节标题行 | `grip` 14（`secondaryLabel`，拖动排序，tooltip“拖动排序”）→ 序号（`headline`，`secondaryLabel`，宽 16）→ 标题 `MMInlineTextField`（`headline` 13.5）→ 分组理由（`footnote`，`secondaryLabel`，单行省略，来自 AI）→ 删除 `MMIconButton`（`close` 12，tooltip“删除这一节”） |
| 划线芯片 | 高 26，圆角 7，`quaternaryFill` 底，0.5pt `hairline`；7pt 颜色圆点 + 引文（宋体 12，单行省略，最大宽 250）；可拖动；tooltip 为完整引文 |
| 空节 | 芯片区保留 28 高的 1pt 虚线框（`separator`），不写字 |
| 未归入 | 最后一张卡片，`quaternaryFill` 底、无阴影；标题“未归入”（`callout`，`secondaryLabel`），无序号、无删除 |
| 添加一节 | 列表末尾纯文本按钮 `add` +“添加一节”；新节标题“新的一节”，自动聚焦并全选 |
| 页脚 | 返回（回到整理设置，保留设置）→ 生成笔记（`primary`，`research`） |

- 删除一节：其中的划线移到“未归入”。空节在生成时跳过。
- 键盘与触控：芯片和节都支持右键 / 长按菜单“移到 › 各节名称 / 未归入”与“上移 / 下移”（节）；⌥↑ / ⌥↓ 移动聚焦的节。拖动是捷径，不是唯一方式。
- compact：全高底部面板；芯片拖动改为长按后拖动，同时提供上述菜单。

### 4.2 生成中

2026-11-01 按已选设计稿 1 调整；设计稿和界面截图见 [`evidence/note-organization-progress/`](evidence/note-organization-progress/)。

`showMMSheet`，宽 `noteProgressSheetWidth`，不可点外部关闭，Esc 等同“停止”。标题：AI 时 `ai` +“正在整理笔记”，只排版时 `studyNote` +“正在排版笔记”。

| 区域 | 规格 |
| --- | --- |
| 左：步骤列（宽 200） | 完成为蓝色勾选圆，进行中为 `research` 转圈，待办为空心圆；当前步骤 600 字重。撰写步骤下显示“已完成 N / M 节”和细进度条，只表示已完成节数，不表示整个任务的百分比。未取得提纲前不显示节数 |
| 右：预览 | 与步骤同一表面，中间细分隔线；内边距 22×24，整个进度区最高 440。顶部固定当前任务，如“正在撰写第 4 节”；正文独立滚动，节标题 20pt，正文 16pt / 1.7，AI 块标记、原文引用色条及出处分开排版，无编辑按钮。引用保留原划线颜色 |
| 页脚 | 生成时只放右侧“停止”（`secondary`，`stop` 图标）；不显示禁用的“取消” |

步骤：AI —— 收集素材 → 补全上下文 → 归纳主题 → 撰写笔记 → 核对引用；只排版 —— 收集素材 → 补全上下文 → 分组排版。素材收集和上下文读取在设置阶段完成，进入此面板时对应步骤已经完成；归纳、撰写和最终核对由真实任务状态驱动。

- 正文以完整、已校验的节为单位出现，不模拟逐字输出。用户位于预览底部时跟随新增内容，往上阅读时保留滚动位置。错误信息固定在正文滚动区之外，避免被滚动位置遮住。
- 完成：面板关闭，打开笔记，HUD“已生成”；有未用上的划线时 HUD“已生成 · N 条划线未用上”。
- 停止：保留已写好的部分并打开笔记，HUD“已停止”＋“继续整理”（重新打开本面板，从断点继续）。
- 进度内容宽度小于 620pt 或启用大字号时，步骤列收为顶部当前任务、已完成节数和细进度条，下面是预览；compact 沿用底部面板。进度与正文各自滚动，底部操作始终保留。

### 4.3 失败

| 情况 | 呈现 |
| --- | --- |
| 模型输出不合格，重试一次仍失败 | 自动按原文顺序排版并打开笔记；HUD“AI 整理失败，已按原文排版” |
| 断网或模型报错 | 面板中当前步骤图标变 `warning`（`caution`），步骤名下一行原因（沿用助手的错误文案）；页脚换为“改为只排版”（`secondary`）+“继续整理”（`primary`）。已写好的部分保留在预览中 |
| 超出预算 | 沿用助手的预算提示；生成前的发送说明已写明字数 |

---

## 5. 笔记视图（场景 6–10）

笔记在右侧主面板打开（与脑图同一位置；分栏时左侧仍为原文）。

### 5.1 版面

- 背景 `windowBackground`；正文列水平居中，宽 ≤ `measure`，左 `gutter`、右 `trailing`、上 `topInset`、下 `bottomInset`。
- **标题区**：标题（`MMNoteTypography.title`，原地可编辑，`MMInlineTextField`，Enter 提交）→ 下方 8 一行元信息：整理时间（`footnote`，`secondaryLabel`，本地化日期时间）+ 引用状态 `MMPill`（第 5.3 节）→ AI 笔记再下方一句话总结（第 1.2 节）。不显示文档数、划线数、批注数，不加图例。
- **节**：节标题（`heading`，序号 + 标题，标题原地可编辑）→ 块。
- **结尾**：行动清单（有我的批注或深度整理时）→ 复习题（深度整理）→ 出处（`headline` 14，`secondaryLabel`；有序列表，`footnote`：“书名 · p.12、p.16”）。
- **章节目录**：笔记面板宽 ≥ `tocMinWidth` 时显示在右侧（距右 14、顶部与正文对齐，宽 `tocWidth`），正文预留目录空间。标题“目录”（`subheadline`）；条目左对齐，序号独立成列，标题最多两行，悬停显示完整标题。列表使用一条细分隔线，常态无按钮背景；当前节使用 `accent` 字与 2pt 竖线，随正文滚动同步。目录独立滚动，自动保持当前节可见。支持键盘焦点、回车跳转和选中状态朗读。宽度不够时目录收进工具栏“目录”菜单（第 5.2 节）。

### 5.2 笔记工具栏

高 `barHeight`，底部 0.5pt `separator`。从左到右：

| 位置 | 控件 |
| --- | --- |
| 标题 | `studyNote` 14 + 笔记标题（`headline`，单行省略，最大宽 260） |
| 目录 | 仅在浮动目录隐藏时：`MMDropdownButton` 文字“目录”+ `chevronDown`，菜单为各节与“行动清单”“复习题” |
| 版式 | `MMDropdownButton`，文字为当前版式名 + `chevronDown`；菜单三项（当前项前置 `check`），不写说明 |
| AI 标记 | 仅 AI 笔记：`MMToolbarButton` 图标 `ai`，tooltip“显示 AI 标记 / 隐藏 AI 标记”，开启为选中态（`accentTint`）。按笔记记住，默认开 |
| 重新整理 | `regenerate` +“重新整理”；未配置 AI 时禁用，tooltip“未配置 AI” |
| 导出 | `export` +“导出” |
| 分享 | `share` +“分享” |

compact：标题行只保留返回、标题和“更多”（`more`），“更多”菜单依次为：目录、版式（子菜单）、显示 / 隐藏 AI 标记、重新整理、导出…、分享长图…。

### 5.3 引用状态

- 全部用上：`MMPill`（`positive`）`check` 11 +“N 条划线全部引用 · 原文未改写”。
- 有未用上的：`MMPill`（`caution`）`warning` 11 +“N 条划线未用上”。
- 点击打开弹层（宽 `noteCoverageWidth`，`glassOpaque`，最多显示 8 行后滚动，无标题）：先列未用上的划线，0.5pt 分隔线后列已用上的。每行：3pt 色条 + 引文（宋体 12，最多 2 行）+ 右侧“第 N 节”（`footnote`）或“放回笔记”按钮（`MMButton.secondary` 小号，高 22）。
- 点行：笔记滚到对应摘录并闪烁，同时左侧原文定位。点“放回笔记”：放进最相关的一节（AI 提纲中原本所在的节；否则同章节摘录最多的节；否则第一节），HUD“已放入「节标题」”＋“撤销”。

### 5.4 版式

| 版式 | 版面 |
| --- | --- |
| 读书笔记（默认） | 第 5.1 节 |
| 康奈尔笔记 | 每节标题下为两栏网格：左栏线索 170 宽（右边 1pt `separator`，内边距 10/12/10/0；每条问题 `callout` 500，前缀 `research` 色“Q”）、右栏摘录与批注（左内边距 16）；底部通栏“总结”（`subheadline` 标签 + `body` 正文，上边 1pt `separator`）。不使用 AI 时线索栏与总结为空的可编辑区域，不放提示文字 |
| 复习提纲 | 每节下每条划线一张卡片（`card` 底，圆角 10，0.5pt `hairline`，内边距 10×12，间距 8）：问题（`headline` 13.5，AI 写的带“AI”标签）→ 答案（摘录原文，宋体 14，默认 5pt 模糊遮住，点一下显示）→ 出处链接 + 右侧“加入复习”（`MMButton.plain`，`review` 图标）。不使用 AI 时问题为“《书名》p.12 说了什么？” |

切换版式不改变内容；改过的段落在各版式中一致。更新预览（第 6 节）只在读书笔记版式下显示，在其他版式点“预览更新”时自动切到读书笔记。

### 5.5 块

| 块 | 规格 |
| --- | --- |
| 摘录 | 色条 + 引文；展开上下文时依次为前句（`context`）、引文（加 `highlight` 底）、后句。出处行（上 3）：`revealSource` 11 +“《书名》p.28”（`accent` 11，悬停 `accentTint` 底，tooltip 为章节标题）→ 上下文按钮（`context` 11，`secondaryLabel`，tooltip“展开上下文 / 收起上下文”）→ 整理后新增的加 `MMPill`“新增”。残句的 AI 补充说明在出处行下方 |
| 我的批注 | 挂在对应摘录下；正文可原地编辑；来源行“页边批注 · p.12”或“脑图笔记 · 节点标题”。不加“我的批注”标签 |
| AI 段落 | “AI”标签 + 正文（原地可编辑）；改过后尾部 `lock` 11（`secondaryLabel`，tooltip“更新时保留”） |
| 要点 | “AI”标签单独一行，下面无序列表（`body`，左缩进 20）。不写“要点”标题 |
| 关联 | `link` 11 +“AI”标签 +“与 [N. 节标题] ……”（`gloss`，节标题为 `accent` 链接，点击滚到该节） |
| 行动清单 | 复选框 15（完成为 `positive` 底 + 白色 `check`），完成项 `secondaryLabel` + 删除线；AI 提出的项带“AI”标签 |
| 复习题 | 节标题右侧“全部加入复习”（`MMButton.secondary`，`review` 图标）；每题一张卡片，问题带“AI”标签 |

- 编辑：点击可编辑文字直接进入编辑（`MMInlineTextField`，`multiline: true`）：Enter 或失焦提交，⇧Enter 换行，Esc 取消。AI 块提交时如文字有变化，`origin` 变为 `mixed`、`edited = true`，标签变“AI · 已改”。我的批注提交时写回 `MarginNote` / 卡片笔记本身（决定 1），原文页边批注同步更新。
- 链接联动：点出处 → 左侧原文切换文档、跳页并闪烁划线（原文栏收起时先展开）；点原文中的高亮 → 笔记滚到对应摘录并闪烁；高亮不在笔记中时 HUD“这条划线不在笔记里”。

### 5.6 段落操作

悬停块时，块左侧出现 `more` 按钮（`blockButton`，距正文 30）；菜单打开期间按钮保持显示。触控（含 compact）改为长按块弹出同一菜单。

| 块 | 菜单（─ 为分隔线） |
| --- | --- |
| 摘录 | 展开上下文 / 收起上下文 · 定位原文 ⌘L · 解释这句话 ─ 加入脑图 · 生成复习卡 ─ 从笔记中移除 |
| AI 段落 | 换一种说法 · 更简洁 · 展开说明 · 改为我的话 ─ 加入脑图 · 生成复习卡 ─ 删除这段 |
| 我的批注 | 加入脑图 ─ 删除这段 |

- 未配置 AI：“解释这句话”“换一种说法”“更简洁”“展开说明”“生成复习卡”（AI 段落上）置灰，tooltip“未配置 AI”。摘录上的“生成复习卡”不需要 AI（题面为“《书名》p.12 说了什么？”），保持可用。
- 我的批注没有任何 AI 改写项（隐藏而不是置灰）。
- HUD 与撤销：换一种说法 → “已换一种说法”＋撤销；更简洁 → “已精简”＋撤销；展开说明 → “已展开”＋撤销；改为我的话 → “已改为我的话”＋撤销；解释这句话 → “已添加 AI 解释”；加入脑图 → “已加入脑图”＋“查看”；生成复习卡 → “已生成 1 张复习卡”；从笔记中移除 → “已从笔记中移除”＋撤销（划线保留在原文，被移除的划线计入“未用上”）；删除这段 → “已删除”＋撤销。所有操作也进入全局 ⌘Z 栈。
- AI 改写进行中：块内文字 50% 不透明，末尾流式光标；Esc 取消。

---

## 6. 增量更新（场景 11）

| 元素 | 规格 |
| --- | --- |
| 横幅 | 位于笔记工具栏下方、标题区之上，最大宽 600 居中，上边距 12；`positive` 12% 底，圆角 12，内边距 8/8/8/12。内容：`add` 14（`positive`）+“又划了 **N** 条”（有新批注时“又划了 **N** 条、写了 **M** 条批注”）→ 弹性空白 → “预览更新”（`primary`）+“忽略”（`plain`） |
| 侧栏 | 笔记条目尾部 `MMBadge` N |
| 原文 | 新划线外加 `positive` 虚线框 |
| 预览栏 | 横幅换成吸顶栏（`glass` 底，底部 0.5pt `separator`，内边距 8×12）：`regenerate` 14 +“新增 N 处”（`headline`）→ 弹性空白 → “取消”（`plain`）+“应用更新”（`primary`） |
| 待插入块 | 插在目标节最后一条摘录之后：`positive` 12% 底，左侧 4pt `positive` 色条，内边距 6×8；顶部一行 `add` 11 + AI 给出的理由（`footnote`，`secondaryLabel`），下面是摘录与批注。不写“放入「节名」”：位置本身说明了去处 |
| 已删除的划线 | 预览中原摘录加删除线、出处行 `critical`“划线已删除”；应用后移除 |

- 应用：合并，横幅与角标消失，新块闪烁，HUD“已更新 · 新增 N 条”＋撤销。改过（`edited`）的块不变，保持锁。
- 忽略：横幅与角标消失，不提示；之后“重新整理”时这些划线进入范围。
- 不使用 AI 的笔记：没有理由行，按原文顺序插入对应章节。
- 重新整理：沿用当前提纲直接进入“生成中”（第 4.2 节），改过的块保持不变。

---

## 7. 导出（场景 12、13）

`showMMSheet`，宽 `noteExportSheetWidth`，内容区高 `noteExportBodyHeight`。标题“导出笔记”，无副标题。

| 区域 | 规格 |
| --- | --- |
| 左列（宽 280，可滚动） | 格式网格 3×2（间距 6）：每格圆角 10、内边距 8×6，上方 28pt 图标、下方名称（`footnote`）；选中 2pt `accent` 描边 + `accentTint` 底。格式：Markdown（`markdown`）、Obsidian、PDF（`document`）、Word、复制为富文本（`copy`）、分享长图（`image`）。图标单色（`icon`），不使用品牌色 |
| | 下面三组，组标题 `subheadline`（`secondaryLabel`，上 12 下 6）：**出处** 胶囊组：页码 / 脚注 / 不标；**包含** `MMSwitch` 列表：上下文、我的批注、AI 内容（未使用 AI 时置灰）、复习题（没有复习题时置灰）、出处列表；**AI 标记** 胶囊组：标出 / 不标（只在包含 AI 内容时出现） |
| 右侧预览 | `readerBackground` 底，圆角 12，0.5pt `hairline`。吸顶标签行：`document` 11 +“标题.md / .pdf / .docx”（`footnote`）。Markdown / Obsidian：等宽字（`mono` 11.5 / 19），标题 `accent`、引用 `caution` 系、AI 行 `research`、frontmatter `secondaryLabel`；PDF / Word / 富文本：白色 A4 缩略页（宽 420）。预览就是最终文件内容 |
| 页脚 | 取消 → 拷贝（Markdown / Obsidian，`secondary`，`copy` 图标）→ 导出…（`primary`）。富文本只有“取消”“拷贝”（`primary`） |

- 点“分享长图”格式直接切到分享面板（第 8 节），不在导出面板里显示说明。
- 默认：格式记住上次；出处“页码”；包含全开；AI 标记“标出”。
- 导出：桌面弹系统存储对话框（文件名 = 笔记标题，去掉 `/ : \` 与控制字符）；成功 HUD“已导出”。失败 HUD“导出失败”＋“重试”（沿用 `exportFailed` / `exportRetry`）。拷贝成功 HUD“已拷贝”。
- **Obsidian 页码链接（决定 5）**：链接目标为 `书名.md#p12`，写成 `[[书名#p12|《书名》p.12]]`，放在 `[!quote]` callout 的标题位置；书名为文档标题，Obsidian 不允许出现在链接里的字符（`\ / : * ? " < > | # ^ [ ]`）替换为空格并合并空格。出处列表中的书写成 `[[书名]]`。出处选“脚注”或“不标”时 callout 标题为空。
- compact：全高底部面板；格式改为横向滚动的一行，选项在下，预览在最后（高 300）；底部全宽主要按钮“导出…”（移动端为“分享…”，第 10 节）。

### 7.1 导出内容中的固定文字

导出文件中的标题与标签使用应用当前语言：

| 位置 | 中文 | English |
| --- | --- | --- |
| Markdown 页首说明 | {docs} 份文档 · {count} 条划线 · 整理于 {date} | {docs} documents · {count} highlights · organized {date} |
| 一句话总结 | 一句话总结 | Summary |
| AI 标注（Markdown） | （AI 整理） | (AI) |
| 页码出处 | —— 《{title}》p.{page} | — {title}, p. {page} |
| 我的批注 | 我的批注 | My Note |
| AI 补充 | 注 / AI 补充 | Note / AI Note |
| 关联 | 相关 | Related |
| 行动清单 / 复习题 / 出处 | 行动清单 / 复习题 / 出处 | Action Items / Review Questions / Sources |
| 脚注 | {title}，第 {page} 页，{chapter} | {title}, p. {page}, {chapter} |

Obsidian callout 类型固定为英文：原文 `quote`、我的批注 `note`、AI 小结 `abstract`、AI 总结 `summary`、AI 补充 `info`；callout 标题用上表文字。

---

## 8. 分享长图（场景 14）

`showMMSheet`，宽 `noteShareSheetWidth`。标题“分享长图”，无副标题。

| 区域 | 规格 |
| --- | --- |
| 左列（宽 250，控件间距 12，无组标题） | 内容胶囊组：一句金句 / 一节 / 整篇摘要 → 小节下拉（`MMDropdownButton` 全宽，“N. 节标题”；整篇摘要时隐藏）→ 主题胶囊组：纸张 / 简洁 / 夜读 → 开关：我的批注、AI 小结（AI 小结只在 AI 笔记中出现） |
| 右侧舞台 | `quaternaryFill` 底，圆角 12，内边距 20，长图水平居中、可纵向滚动 |
| 页脚 | 完成（`secondary`）→ 拷贝图片（`secondary`，`copy`）→ 存储图片…（`primary`） |

**长图**（宽 `noteShareCardWidth`，圆角 14，阴影 0/6/24 14%）：

| 主题 | 底 / 字 | 说明 |
| --- | --- | --- |
| 纸张 | `#FBF7EE` / `#2B2A27` | 固定色，不随系统外观变化 |
| 简洁 | `#FFFFFF` / `#1D1D1F` | 同上 |
| 夜读 | `#1C1C1E` / `#F2F2F7` | 同上 |

新增常量 `MMShareCardTheme { paper, plain, night }`（`background` / `foreground`），放在 `mm_design` tokens，只用于长图。

- 一节 / 整篇：顶部小字“读书笔记 · 书名 × 书名”（10，字距 0.08em，55%）→ 标题（18 / 700）→（AI 小结开时）小结（12 / 1.7，85%）→ 摘录（宋体 13.5 / 1.8，左侧 2.5pt 当前字色 25% 竖线）+ 出处（10，50%）+（我的批注开时）批注（12，`yellow` 16% 底，圆角 8）。整篇摘要每节最多 2 条摘录、节名 12 / 700；一节最多 4 条。
- 一句金句：大引号（宋体 44，25%）→ 引文（宋体 20 / 1.7）→ 出处“书名 · p.12”→（可选）批注。
- 页脚（决定 4）：上方 0.5pt 线（50% 灰 25%），18pt 应用图标 +“摘自我的 MarginMind 笔记”，右侧“N 条划线”（金句卡不显示数量）。**不放二维码或链接。**
- 渲染：`RepaintBoundary` → PNG，2× 倍率。拷贝成功 HUD“已拷贝”；存储成功 HUD“已存储”。
- 所选小节没有摘录时，舞台显示“没有摘录”（`secondaryLabel`）。
- compact：全高底部面板，长图预览在上（可滚动），控件在下，底部全宽主要按钮“分享…”。

---

## 9. 状态

| 场景 | 呈现 | 文案 |
| --- | --- | --- |
| 学习集没有笔记 | 侧栏分组只有标题和 + | — |
| 范围内没有划线 | 设置页脚红字，生成按钮禁用（3.4） | 没有可整理的划线 |
| 未配置 AI | 设置中 AI 项置灰 + 去设置（3.3）；笔记里 AI 操作置灰；“重新整理”禁用 | 未配置 AI；去设置 |
| 生成中 | 生成面板（4.2）；侧栏条目转圈 | 正在整理 / 正在排版 |
| 生成失败 / 中断 | 4.3 | AI 整理失败，已按原文排版；继续整理；改为只排版 |
| 已停止 | HUD | 已停止；继续整理 |
| 笔记没有摘录（全部移除） | 正文位置一行 `secondaryLabel` | 没有摘录 |
| 原文被移除 | 摘录保留文字；出处行 `critical` 不可点 | 原文已移除 |
| 划线被删除 | 摘录保留文字；出处行 `critical`；下次更新预览中移除（6） | 划线已删除 |
| 扫描版 PDF 无文本 | 摘录无上下文按钮；出处行后 `footnote` | 无原文文本 |
| 划线很多（> 200） | 生成步骤“归纳主题”副文字 | 第 k / n 批 |
| 窄窗口 | 浮动目录收进“目录”菜单；原文栏可收起（工具栏 `sidebar` 按钮，tooltip“显示 / 隐藏原文”） | — |
| 深色模式 | 全部使用语义色；A4 预览页与长图主题固定色 | — |

---

## 10. 平台差异

| 项目 | macOS | Windows | Linux | Web | iPadOS | iOS | Android |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 笔记、整理、编辑、更新 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| AI 整理 | 跟随助手 | 跟随助手 | 跟随助手 | 跟随助手 | 跟随助手 | 跟随助手 | 跟随助手 |
| 菜单栏命令 | 系统菜单栏 | 应用内菜单 / 快捷键 | 同 Windows | 快捷键 | 外接键盘快捷键 | — | — |
| 快捷键修饰 | ⌥⌘P、⌘L | Ctrl+Alt+P、Ctrl+L | 同 Windows | 同 Windows | ⌥⌘P（外接键盘） | — | — |
| 布局 | regular | regular | regular | regular | 横屏 regular，竖屏 / 分屏 medium | compact | compact |
| 笔记位置 | 右侧主面板，左侧原文 | 同左 | 同左 | 同左 | 横屏同左；竖屏原文在上、笔记在下 | “脑图”Tab 内切换到笔记；原文在“原文”Tab | 同 iOS |
| 段落操作 | 悬停 ⋯ | 悬停 ⋯ | 悬停 ⋯ | 悬停 ⋯ | 长按 | 长按 | 长按 |
| 提纲拖动 | 拖动 + 右键菜单 | 同左 | 同左 | 同左 | 长按拖动 + 菜单 | 同 iPadOS | 同 iPadOS |
| Markdown / Obsidian / Word | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| PDF | ✓ | — | — | — | — | — | — |
| 复制为富文本 | ✓ | 拷贝为 Markdown | 同 Windows | 同 Windows | 拷贝为 Markdown | 同 iPadOS | 同 iPadOS |
| 分享长图 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 拷贝图片 | ✓ | — | — | — | — | — | — |
| 保存文件 | 存储对话框 | 存储对话框 | 存储对话框 | 浏览器下载 | 系统分享面板 | 系统分享面板 | 系统分享面板 |

- 能力判断沿用 `MMPlatformCapabilities`：PDF 复用原生 PDF 生成，与 `mapExport` 相同（目前只有 macOS）；结构化剪贴板（富文本、图片）与 `nativeMapClipboard` 相同；保存文件沿用脑图导出的分支（`shareFile` → `MobileFileShare`，Web → 浏览器下载，其余 → 存储对话框）。不可用的格式在导出网格中隐藏，不置灰。
- “复制为富文本”在不支持结构化剪贴板的平台上名称改为“拷贝为 Markdown”，内容为 Markdown 文本。
- 移动端导出、存储图片的主要按钮文字为“分享…”，打开系统分享面板。
- AI 是否可用由助手的现有配置决定：助手可用即可整理；否则按“未配置 AI”处理（第 3.3 节）。
- Android 系统返回键依次：关闭菜单 / 弹层 → 关闭面板（生成中等同“停止”）→ 退出编辑 → 现有页面返回（`MMBackHandler`）。

---

## 11. 文案（ARB 键建议）

已有键直接复用：`cancel`、`done`、`back`、`rename`、`delete`、`undo`、`copyAction`、`copiedHud`、`exportAction`、`exportedHud`、`exportFailed`、`exportRetry`、`addToMapAction`、`revealSource`、`readerOutline`、`viewAction`、`assistantStop`。

| 键 | 中文 | English |
| --- | --- | --- |
| `sectionNotes` | 笔记 | Notes |
| `studyNoteOrganize` | 整理学习笔记… | Organize Study Note… |
| `studyNoteOrganizeShort` | 整理笔记 | Organize |
| `studyNoteFromSelection` | 整理成笔记 | Organize into Note |
| `studyNoteFromBranch` | 整理成笔记… | Organize into Note… |
| `studyNoteExportMenu` | 导出笔记… | Export Note… |
| `studyNoteShareMenu` | 分享长图… | Share as Image… |
| `annotationsSelected` | 已选 {count} 条 | {count} selected |
| `selectAll` | 全选 | Select All |
| `deselectAll` | 取消全选 | Deselect All |
| `filterByColor` | 按颜色筛选 | Filter by Color |
| `studyNoteNewTag` | 新增 | New |
| `studyNoteSetupTitle` | 整理学习笔记 | Organize Study Note |
| `studyNoteScope` | 范围 | Scope |
| `studyNoteScopeSelection` | 选中的划线 | Selected Highlights |
| `studyNoteScopeSet` | 整个学习集 | Whole Study Set |
| `studyNoteScopeDocument` | 《{title}》 | {title} |
| `studyNoteScopeRecent` | 最近 7 天 | Last 7 Days |
| `studyNoteScopeBranch` | 分支「{title}」 | Branch “{title}” |
| `studyNoteMaterials` | 素材 | Include |
| `studyNoteMatHighlights` | 划线 | Highlights |
| `studyNoteMatOwn` | 我的批注 | My Notes |
| `studyNoteMatCards` | 脑图笔记 | Map Notes |
| `studyNoteMatAiNotes` | 已存的 AI 笔记 | Saved AI Notes |
| `studyNoteMatImages` | 图片卡片 | Image Cards |
| `studyNoteOrganizeBy` | 组织方式 | Organize By |
| `studyNoteOrgTheme` | 按主题归纳 | By Topic |
| `studyNoteOrgSource` | 按原文顺序 | Source Order |
| `studyNoteOrgMap` | 按脑图结构 | Mind Map |
| `studyNoteDepth` | AI 参与 | AI |
| `studyNoteDepthNone` | 只排版 | Layout Only |
| `studyNoteDepthLight` | 补全与小结 | Context & Summaries |
| `studyNoteDepthDeep` | 深度整理 | Full |
| `studyNoteContext` | 上下文 | Context |
| `studyNoteContextSentences` | 前后 {count} 句 | {count, plural, =0{None} =1{1 sentence each side} other{{count} sentences each side}} |
| `studyNoteResolveReferences` | 补全指代 | Resolve References |
| `studyNoteTemplate` | 版式 | Layout |
| `studyNoteTplReading` | 读书笔记 | Reading Notes |
| `studyNoteTplCornell` | 康奈尔笔记 | Cornell Notes |
| `studyNoteTplReview` | 复习提纲 | Review Outline |
| `studyNoteNoAi` | 未配置 AI | AI isn’t set up |
| `studyNoteOpenSettings` | 去设置 | Set Up |
| `studyNoteSendNotice` | 将发送 {highlights} 条划线{notes, plural, =0{} other{、{notes} 条批注}}（约 {chars} 字）给 {model} | Sends {highlights} highlights{notes, plural, =0{} other{ and {notes} notes}} (about {chars} characters) to {model} |
| `studyNoteNothingToOrganize` | 没有可整理的划线 | No highlights to organize |
| `studyNoteOutlineAction` | 先看提纲 | Outline First |
| `studyNoteCreate` | 生成笔记 | Create Note |
| `studyNoteOutlineTitle` | 确认提纲 | Outline |
| `studyNoteUnassigned` | 未归入 | Unassigned |
| `studyNoteAddSection` | 添加一节 | Add Section |
| `studyNoteNewSection` | 新的一节 | New Section |
| `studyNoteDeleteSection` | 删除这一节 | Delete Section |
| `studyNoteDragToReorder` | 拖动排序 | Drag to Reorder |
| `studyNoteMoveTo` | 移到 | Move To |
| `studyNoteMoveUp` | 上移 | Move Up |
| `studyNoteMoveDown` | 下移 | Move Down |
| `studyNoteOrganizing` | 正在整理 | Organizing |
| `studyNoteLayingOut` | 正在排版 | Laying Out |
| `studyNoteStepCollect` | 收集素材 | Collect |
| `studyNoteStepContext` | 补全上下文 | Add Context |
| `studyNoteStepTopics` | 归纳主题 | Find Topics |
| `studyNoteStepOutline` | 按提纲分节 | Apply Outline |
| `studyNoteStepWrite` | 撰写 | Write |
| `studyNoteStepVerify` | 核对引用 | Check Quotes |
| `studyNoteStepGroup` | 分组排版 | Lay Out |
| `studyNoteHighlightCount` | {count} 条划线 | {count, plural, =1{1 highlight} other{{count} highlights}} |
| `studyNoteSectionCount` | {count} 节 | {count, plural, =1{1 section} other{{count} sections}} |
| `studyNoteBatch` | 第 {index} / {total} 批 | Batch {index} of {total} |
| `studyNoteCreated` | 已生成 | Note Created |
| `studyNoteCreatedUnused` | 已生成 · {count} 条划线未用上 | Created · {count, plural, =1{1 highlight} other{{count} highlights}} unused |
| `studyNoteStopped` | 已停止 | Stopped |
| `studyNoteContinue` | 继续整理 | Continue |
| `studyNoteLayoutOnlyAction` | 改为只排版 | Layout Only |
| `studyNoteFallback` | AI 整理失败，已按原文排版 | AI couldn’t organize; laid out in source order |
| `studyNoteCoverageAll` | {count} 条划线全部引用 · 原文未改写 | {count, plural, =1{1 highlight quoted verbatim} other{All {count} highlights quoted verbatim}} |
| `studyNoteCoverageUnused` | {count} 条划线未用上 | {count, plural, =1{1 highlight unused} other{{count} highlights unused}} |
| `studyNoteSectionNumber` | 第 {index} 节 | Section {index} |
| `studyNotePutBack` | 放回笔记 | Put Back |
| `studyNotePutBackHud` | 已放入「{title}」 | Added to “{title}” |
| `studyNoteAiTag` | AI | AI |
| `studyNoteAiEditedTag` | AI · 已改 | AI · Edited |
| `studyNoteCitation` | 《{title}》p.{page} | {title}, p. {page} |
| `studyNoteFromMarginNote` | 页边批注 · p.{page} | Margin Note · p. {page} |
| `studyNoteFromMapNote` | 脑图笔记 · {title} | Map Note · {title} |
| `studyNoteShowContext` | 展开上下文 | Show Context |
| `studyNoteHideContext` | 收起上下文 | Hide Context |
| `studyNoteLocked` | 更新时保留 | Kept on Update |
| `studyNoteShowAiMarks` | 显示 AI 标记 | Show AI Labels |
| `studyNoteHideAiMarks` | 隐藏 AI 标记 | Hide AI Labels |
| `studyNoteRegenerate` | 重新整理 | Reorganize |
| `studyNoteExport` | 导出 | Export |
| `studyNoteShare` | 分享 | Share |
| `studyNoteActionItems` | 行动清单 | Action Items |
| `studyNoteQuestions` | 复习题 | Review Questions |
| `studyNoteSources` | 出处 | Sources |
| `studyNoteAddAllToReview` | 全部加入复习 | Add All to Review |
| `studyNoteAddToReview` | 加入复习 | Add to Review |
| `studyNoteAddedToReview` | 已加入复习 · {count} 张 | {count, plural, =1{Added 1 card to Review} other{Added {count} cards to Review}} |
| `studyNoteCornellSummary` | 总结 | Summary |
| `studyNoteDefaultQuestion` | 《{title}》p.{page} 说了什么？ | What does {title} say on p. {page}? |
| `studyNoteEmpty` | 没有摘录 | No Excerpts |
| `studyNoteNotInNote` | 这条划线不在笔记里 | This highlight isn’t in the note |
| `studyNoteBlockActions` | 段落操作 | Paragraph Actions |
| `studyNoteExplain` | 解释这句话 | Explain |
| `studyNoteRephrase` | 换一种说法 | Rephrase |
| `studyNoteShorter` | 更简洁 | Shorter |
| `studyNoteLonger` | 展开说明 | Expand |
| `studyNoteMakeMine` | 改为我的话 | Mark as Mine |
| `studyNoteMakeCard` | 生成复习卡 | Make Review Card |
| `studyNoteRemoveQuote` | 从笔记中移除 | Remove from Note |
| `studyNoteDeleteBlock` | 删除这段 | Delete Paragraph |
| `studyNoteExplained` | 已添加 AI 解释 | Explanation Added |
| `studyNoteRephrased` | 已换一种说法 | Rephrased |
| `studyNoteShortened` | 已精简 | Shortened |
| `studyNoteExpanded` | 已展开 | Expanded |
| `studyNoteMadeMine` | 已改为我的话 | Marked as Mine |
| `studyNoteAddedToMap` | 已加入脑图 | Added to Map |
| `studyNoteCardsMade` | 已生成 {count} 张复习卡 | {count, plural, =1{1 review card made} other{{count} review cards made}} |
| `studyNoteRemoved` | 已从笔记中移除 | Removed from Note |
| `studyNoteDeleted` | 已删除 | Deleted |
| `studyNoteNewSince` | 又划了 {count} 条 | {count, plural, =1{1 new highlight} other{{count} new highlights}} |
| `studyNoteNewSinceWithNotes` | 又划了 {count} 条、写了 {notes} 条批注 | {count, plural, =1{1 new highlight} other{{count} new highlights}}, {notes, plural, =1{1 new note} other{{notes} new notes}} |
| `studyNotePreviewUpdate` | 预览更新 | Preview Update |
| `studyNoteIgnore` | 忽略 | Ignore |
| `studyNotePendingCount` | 新增 {count} 处 | {count, plural, =1{1 addition} other{{count} additions}} |
| `studyNoteApplyUpdate` | 应用更新 | Apply |
| `studyNoteUpdated` | 已更新 · 新增 {count} 条 | Updated · {count} added |
| `studyNoteSourceRemoved` | 原文已移除 | Source removed |
| `studyNoteHighlightDeleted` | 划线已删除 | Highlight deleted |
| `studyNoteNoSourceText` | 无原文文本 | No source text |
| `studyNoteToggleSource` | 显示 / 隐藏原文 | Show / Hide Source |
| `studyNoteExportTitle` | 导出笔记 | Export Note |
| `studyNoteFormatMarkdown` | Markdown | Markdown |
| `studyNoteFormatObsidian` | Obsidian | Obsidian |
| `studyNoteFormatPdf` | PDF | PDF |
| `studyNoteFormatWord` | Word | Word |
| `studyNoteFormatRich` | 复制为富文本 | Rich Text |
| `studyNoteFormatPlain` | 拷贝为 Markdown | Copy as Markdown |
| `studyNoteFormatImage` | 分享长图 | Image |
| `studyNoteCite` | 出处 | Citations |
| `studyNoteCitePage` | 页码 | Page |
| `studyNoteCiteFootnote` | 脚注 | Footnotes |
| `studyNoteCiteNone` | 不标 | None |
| `studyNoteInclude` | 包含 | Include |
| `studyNoteIncContext` | 上下文 | Context |
| `studyNoteIncAi` | AI 内容 | AI Content |
| `studyNoteIncSources` | 出处列表 | Source List |
| `studyNoteAiLabels` | AI 标记 | AI Labels |
| `studyNoteAiLabelsOn` | 标出 | Show |
| `studyNoteAiLabelsOff` | 不标 | Hide |
| `studyNoteShareTitle` | 分享长图 | Share as Image |
| `studyNoteShareQuote` | 一句金句 | Quote |
| `studyNoteShareSection` | 一节 | Section |
| `studyNoteShareWhole` | 整篇摘要 | Summary |
| `studyNoteThemePaper` | 纸张 | Paper |
| `studyNoteThemePlain` | 简洁 | Plain |
| `studyNoteThemeNight` | 夜读 | Night |
| `studyNoteShareAi` | AI 小结 | AI Summary |
| `studyNoteCopyImage` | 拷贝图片 | Copy Image |
| `studyNoteSaveImage` | 存储图片… | Save Image… |
| `studyNoteShareAction` | 分享… | Share… |
| `studyNoteSavedImage` | 已存储 | Saved |
| `studyNoteCardKicker` | 读书笔记 · {titles} | Reading Notes · {titles} |
| `studyNoteCardFooter` | 摘自我的 MarginMind 笔记 | From my MarginMind notes |

- `studyNoteMatOwn` 同时用于导出“包含”与分享开关；`studyNoteQuestions` 同时用于导出“包含”。
- `studyNoteCardKicker` 的 `{titles}` 用“ × ”连接书名简称。日期使用现有本地化日期格式。
- 第 7.1 节导出内容中的固定文字另建 `studyNoteMd*` 键，按上表中英文填写。

---

## 12. 无障碍与键盘

- 所有图标按钮都有 tooltip 与辅助功能名称（使用上表文案）；“AI”标签的辅助功能名称为“AI 写的”，“AI · 已改”为“AI 写的，已修改”。
- 摘录朗读顺序：引文 → 出处 → 我的批注；色条不朗读颜色名以外的信息（“黄色划线”）。
- 键盘：笔记中 Tab 在可编辑块、链接、按钮间移动；聚焦块时 ⇧F10 / 菜单键打开段落操作；⌘L 定位当前摘录的原文；⌘Z / ⇧⌘Z 撤销重做；Esc 关闭菜单、面板或退出编辑。
- 对比度：“AI”标签 `onResearch` on `research` 为 5.1:1（浅色）/ 4.8:1（深色）；正文 `label` 在 `researchTint`、`yellow.cardTint` 上沿用现有检查。不要把 `research` 文字放在 `researchTint` 上（4.3:1 / 3.7:1）。实现时在 `tokens_test.dart` 增加 `onResearch` on `research` 的检查。长图三套主题正文对比度为 13.4:1 / 16.8:1 / 15.2:1。
- 减少动态效果：见第 1.5 节。

---

## 13. 原型场景对照

| # | 场景 | 本文 |
| --- | --- | --- |
| 1 | 入口：标注列表多选 | 2、2.1、2.2 |
| 2 | 整理设置 | 3.1、3.2 |
| 3 | 整理设置 · 未配置 AI | 3.3 |
| 4 | 确认提纲：拖动调整 | 4.1 |
| 5 | 生成中 | 4.2 |
| 6 | 笔记：三种声音 | 1.2、5.1–5.3 |
| 7 | 上下文与出处 | 5.5 |
| 8 | 段落操作 | 5.6 |
| 9 | 版式：康奈尔笔记 | 5.4 |
| 10 | 版式：复习提纲 | 5.4 |
| 11 | 新划线：增量更新 | 6 |
| 12 | 导出：Markdown / Obsidian | 7、7.1 |
| 13 | 导出：PDF / Word | 7 |
| 14 | 分享长图 | 8 |

原型限制：只模拟 macOS 窗口；compact / 移动端形态以本文第 3.5、4、5.2、7、8、10 节为准。AI 输出为固定演示数据；侧栏中较早的那篇笔记只演示排序，点开为占位提示。PDF / Word 预览为示意，导出 Markdown / Obsidian 会真实下载。

## 14. 分期对照

| 期 | 本文涉及的界面 |
| --- | --- |
| A：不用 AI 的笔记 | 2、3（只排版路径与 3.3）、4.2（只排版步骤）、5.1–5.3、5.5（无 AI 块）、5.6（非 AI 项）、7（Markdown / Obsidian）、9、10、11 |
| B：AI 整理 | 1.2 中 AI 声音、3（AI 档位、发送说明）、4.1、4.2–4.3（AI 步骤与失败）、5.2（AI 标记、重新整理）、5.4（复习题、复习提纲的 AI 问题）、5.6（AI 项） |
| C：持续更新与更多格式 | 5.4（康奈尔、复习提纲）、6、7（PDF / Word / 富文本）、8 |
