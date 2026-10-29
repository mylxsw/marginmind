# 四期文档：流式阅读界面规格

> 建立日期：2026-10-29（GUL-571）。上位文档：[`phase-4-documents.md`](phase-4-documents.md)（第 0、6 节为已定决定）。技术架构以 `docs/phase-4-architecture.md` 为准；本文只定界面。
> 交互原型：[`design/prototype/phase-4-documents.html`](../design/prototype/phase-4-documents.html)。单文件、无依赖；演示控制台可切换 8 种设备，27 个场景与本文第 10 节对应。
> 视觉以现有应用和 `mm_design` 令牌为准，原型的 CSS 数值只作参考。没有写到的细节沿用 [`design-system.md`](design-system.md)、[`phase-3-reading-ui.md`](phase-3-reading-ui.md) 和现有 PDF 阅读器。

本文写给实现者：每个界面给出尺寸（pt）、令牌、状态、文案和平台差异，实现时不需要再做界面决定。

**界面原则（必须遵守）。** 不新增界面区域，只在现有位置按格式替换或置灰。不加二级标签、说明文字和冗余微文案，让布局本身表达含义：菜单项、按钮、错误只写名称或一句原因；能用图标、预览、位置说明的，不写字。

---

## 0. 术语

| 术语 | 含义 |
| --- | --- |
| 流式文档 | EPUB（可重排）、MOBI、AZW3、Markdown、网页阅读模式。共用一个排版引擎，随窗口和设置重排 |
| 书籍 / 文章 | 阅读设置的两组默认值：书籍 = EPUB、MOBI、AZW3；文章 = Markdown、网页阅读模式 |
| 页面文档 | PDF、网页存成的 PDF、固定版式 EPUB。沿用现有 PDF 阅读器 |
| 位置 | 原文位置（章节 + 字符偏移），与版式无关。进度、书签、标注、跳转都基于位置 |
| 尺寸类 | `MMSizeClass`：compact（< 600 宽）、medium、regular（≥ 1180 宽且横屏；桌面始终为 regular） |

---

## 1. 通用约定

### 1.1 新增令牌（`mm_design`）

在 `metrics.dart` 新增 `MMReaderLayout`（流式版面，屏幕 pt）：

| 常量 | 值 | 用途 |
| --- | --- | --- |
| `measure` | 680 | 单栏正文最大宽度（不含左右边距） |
| `spreadMeasure` | 600 | 对页时每栏最大宽度 |
| `spreadMinWidth` | 1000 | 正文区（去掉左右边距）至少这么宽才排对页 |
| `spreadGap` | 64 | 对页两栏间距 |
| `margin` / `marginCompact` | 48 / 24 | 左右边距；compact 用后者 |
| `topInset` / `topInsetCompact` | 40 / 28 | 翻页模式顶部留白 |
| `scrollTopInset` / `scrollTopInsetCompact` | 36 / 24 | 滚动模式首屏顶部留白 |
| `turnZone` | 0.25 | 翻页模式正文左右各 25% 为翻页热区 |
| `marginColumn` | 220 | 页边批注列宽 |
| `chapterTopSpace` | 2.4 em | 章节标题上方留白（随字号） |

在 `typography.dart` 新增 `MMReaderTypography`：

| 常量 | 值 |
| --- | --- |
| `fontSizes` | `[13, 14.5, 15.5, 16.5, 18, 20, 22, 25]`（8 档） |
| `defaultSize` / `defaultSizePhone` | 索引 3（16.5，等于 `readingBody`）/ 索引 4（18） |
| `lineHeights` | 紧凑 1.6、适中 1.9、宽松 2.2（默认适中，接近 `readingBody` 的 32/16.5） |
| `serif` | `readingBody` 的字族与回退（Songti SC → Noto Serif CJK SC → …） |
| `sans` | `MMTypography` 的无衬线回退（系统字体 → PingFang SC → Noto Sans CJK SC → Microsoft YaHei） |
| `paragraphSpacing` | 0.8 em |
| `firstLineIndent` | 2 em（只用于书籍且书内样式未指定缩进时） |

`MMReaderStyle` 不新增颜色：流式文档整块阅读区填 `paperColor`，文字用 `inkColor`；次要文字（署名、表格线、引用）用 `inkColor` 60%；链接用 `accent`；高亮、下划线、页边批注颜色沿用 `MMAnnotationColor` 与 `reader_style.dart` 已有成员。

新增令牌后同步 `design/canvas/` 规范稿与 [`design-system.md`](design-system.md)。

### 1.2 尺寸与触控

- 桌面（macOS、Windows、Linux、Web）始终按 regular 布局，工具按钮 `MMSizes.readerToolbarButton`。
- iPad 横屏全屏 = regular + 触控尺寸；iPad 竖屏、分屏 = medium；手机 = compact + 底部 Tab（`showsPhoneTabs`）。
- 触控下所有可点控件热区至少 `MMSizes.touchTarget`（44）。

### 1.3 动效

| 动作 | 时长 / 曲线 |
| --- | --- |
| 翻页（水平位移） | `MMMotion.standard` + `layoutCurve`；“减少动态效果”时直接切换 |
| 设置变化后重排 | 无过渡，保持当前位置（第 3.3 节） |
| 弹层、气泡出现 | `MMMotion.quick` 淡入 + 4pt 位移 |
| 底部面板 | 沿用 `MMBottomSheet` |
| 跳转后高亮闪烁 | `MMMotion.flash`（与现有“回原文”一致） |
| 就绪后“转换为文档…”按钮 | 主色，外圈脉动 2 次，每次 1.4s |

### 1.4 图标（`MMIcons` 新增）

| 名称 | 图标 | 用途 |
| --- | --- | --- |
| `ebook` | `CupertinoIcons.book` | EPUB / MOBI / AZW3（含固定版式） |
| `markdown` | `LucideIcons.hash` | Markdown |
| `web`（已有） | `CupertinoIcons.globe` | 网页来源的文档（无论存成哪种格式）、添加网页、浏览器 |
| `readingSettings` | `LucideIcons.aLargeSmall` | 阅读设置 |
| `pagedMode` | `LucideIcons.bookOpenText` | 翻页 |
| `scrollMode` | `LucideIcons.scrollText` | 滚动 |
| `lineSpacingTight` / `Normal` / `Loose` | 三条横线、行距递增（自绘 `CustomPaint`，1.5pt 线宽，14pt 见方） | 行距 |

PDF 继续用 `document`。

---

## 2. 入口与导入（场景 1–3、10）

### 2.1 入口

| 位置 | 有内置浏览器（macOS、Windows、iOS、iPadOS、Android） | 无内置浏览器（Linux、Web） |
| --- | --- | --- |
| 侧栏“文档”标题右侧 **+** | 下拉菜单（`MMDropdownButton`，宽 240，提示“添加”）：导入文档…（⌘O）、添加网页…（⇧⌘O） | 直接打开文件选择器，提示“导入文档…”加快捷键（Ctrl+O） |
| 原文工具栏右端“切换文档” | 文档列表 ─ 导入文档… ─ 添加网页… ─（网页来源时）打开原网页、重新抓取 ─ 关闭当前文档 | 同左，去掉“添加网页…”“重新抓取” |
| 文件菜单（`app_commands.dart`） | 导入文档…、添加网页… | 只有导入文档… |
| 拖入网址 | 等同“添加网页”，直接在浏览器打开 | 忽略 |

- 命令先在 `app_commands.dart` 定义：`importDocument`（沿用，⌘O，扩展文件类型）、`addWebPage`（⇧⌘O，由 `MMPlatformCapabilities.webBrowser` 控制可见）。快捷键用 `primaryShortcut()`。
- 手机：“切换文档”是底部 Action Sheet（`showMMMenu` 的 compact 形态），内容同上。

### 2.2 文件选择与拖入

- 选择器类型：`pdf`、`epub`、`mobi`、`azw3`、`azw`、`md`、`markdown`。可多选。
- 拖入：投放区（沿用现有 `pdf_drop.dart` 样式）只显示导入图标和“松开以导入”。不支持的文件松开后 HUD“不支持「名称」”，其余文件照常导入。
- 资料库“新建学习集”接受同样的格式。

### 2.3 导入过程

- 流式文档没有排版步骤：只解析、复制。侧栏“文档”末尾出现临时行：16pt 转圈 + 书名（取自元数据，没有则用文件名），文字 `secondaryLabel`，不可点；右键菜单“取消导入”。
- 完成后临时行变为正式条目并闪一次（`accentTint`，`MMMotion.flash`）。只导入一份时自动打开；多份时打开第一份，HUD 沿用 `importedHud`。
- 文档条目右侧数字：PDF 与固定版式 EPUB 显示页数；流式文档不显示（页数随设置变化）。

### 2.4 无法导入

- 使用 `showMMDialog`（compact 为底部面板）：左侧 40pt 圆角方块（`critical` 10% 底，图标 `critical`），右侧标题“无法导入「名称」”+ 一行原因；只有一个按钮“好”。不写入任何文件。
- 原因：DRM → “受 DRM 保护”（图标盾牌）；损坏 → “文件已损坏”；KFX → “不支持 KFX 格式”；没有可读章节 → “没有可读内容”（以上图标 `warning`）。
- 一批里多份失败：标题“{count} 份文档无法导入”，下面每行“名称 — 原因”（`callout` / `secondaryLabel`），最多 6 行后滚动。成功的照常导入。

---

## 3. 流式阅读器（场景 4–8、11、17–21、23–26）

### 3.1 版面

**翻页模式**

- 正文区 = 阅读区减去左右 `margin`、顶部 `topInset`、底部导航占位（`pagePillClearance` + 16；手机再加 Tab 栏高度与间距）。
- 正文区宽 ≥ `spreadMinWidth` 且尺寸类为 regular：对页两栏，每栏 ≤ `spreadMeasure`，间距 `spreadGap`；否则单栏，宽 ≤ `measure`。正文块水平居中。
- 一次翻页 = 前进一个视图（对页时两栏）。
- 每个章节（spine 项；Markdown、网页不分章）从新的一页开始，标题上方留 `chapterTopSpace`。
- 图片、表格、代码块、公式不跨页；图片最大高度 = 正文区高度，按比例缩小。段落按行断开，至少保留 2 行（孤行 / 寡行控制）。

**滚动模式**

- 单栏，正文宽 ≤ `measure`，水平居中；首屏顶部 `scrollTopInset`；章节之间无分页，标题上方留 `chapterTopSpace`。
- 底部留出导航和 Tab 栏的空间，最后一行可以滚到导航上方。

**排版**

- 字号、行距每次都覆盖书内样式；书内的相对字号（标题、注释）按比例缩放。
- “原书”字体保留书内的字族、缩进、对齐和标题样式；“宋体 / 黑体”只换正文字族，书内标题仍按比例放大加粗。
- 书籍默认两端对齐、首行缩进 2em（书内样式指定时以书为准）；文章左对齐、无缩进。
- 宽表格：在自身区域内横向滚动（翻页模式也一样，不缩字号）。代码块：等宽字体（`MMTypography.mono` 字族，字号为正文 0.82 倍），长行换行。
- 远程图片（Markdown、网页里未保存到本地的）默认不加载：占位块（`inkColor` 6% 底、1pt 虚线框、高 9em），中间“加载图片”文字按钮（`accent`）；点一下只加载这一张。
- 链接：外部链接用系统浏览器打开（`externalLink` 能力；Web 平台新标签页）；书内链接跳转后 HUD“返回”操作（5 秒），点它回到跳转前的位置。
- 书内脚注（`epub:type="noteref"`）：点击弹出注释内容。桌面为锚定弹层（`MMGlass`，宽 320，最大高 240，内部滚动）；compact 为底部面板。

### 3.2 原文工具栏

位置与顺序沿用 `reader_pane.dart` `_toolbar`，按格式替换：

| 位置 | PDF（现状） | 流式文档（电子书 / Markdown / 网页阅读模式） | 固定版式 EPUB |
| --- | --- | --- | --- |
| 1 页面侧栏 | 缩略图 / 目录 / 书签 / 标注 | 目录 / 书签 / 标注 | 同 PDF |
| 2 页面（缩放） | 缩放菜单 | **置灰**（提示仍为“页面”）；缩放快捷键改为字号增减 | 同 PDF |
| 3 裁掉白边 | 裁边 | **阅读设置**（`readingSettings`） | 置灰 |
| 4 阅读外观 | 四种纸色 | 同 PDF | 同 PDF |
| 5 工具组 + 同步 | 选择、高亮、下划线、框选、画笔 │ 摘录同步到脑图 | 同 PDF，全部可用 | 同 PDF |
| 6 页边批注 | 页边批注 | 同 PDF | 同 PDF |
| 7 对照阅读 | 对照阅读 | 同 PDF | 同 PDF |
| 右端 | 切换文档 | 同 PDF | 同 PDF |

- Markdown 不再有“仅阅读”标签，工具与电子书完全一致。
- medium / compact（`MMSizeClass != regular`）：沿用现有窄窗口行——页面侧栏、工具组、（medium：页边批注、对照阅读）、右端“更多”。**流式文档把“更多”换成“阅读设置”**，设置面板内含阅读外观（第 3.3 节）；页面文档保持“更多”。
- 用 `DocumentCapabilities` 决定每个位置的状态，工具栏不写 `if (format == …)`。

### 3.3 阅读设置

一个面板，四行（流式文档在 medium / compact 下多一行外观），没有标题、行标签和说明：

| 行 | 控件 | 取值 |
| --- | --- | --- |
| 1 字号 | 步进条：左“A”（13pt 宋体）按钮、中间 8 个圆点（5pt，间距 5，当前 `label`、其余 `separator` 色）、右“A”（20pt）按钮；高 36、圆角 10、`quaternaryFill` 底；两端按钮宽 64，到头时禁用 | 8 档 |
| 2 行距 | `MMSegmentedControl` 三段，只放行距图标（辅助功能名称：紧凑 / 适中 / 宽松） | 1.6 / 1.9 / 2.2 |
| 3 字体 | `MMSegmentedControl`，每段文字用自身字体渲染 | 书籍：原书 / 宋体 / 黑体；文章：宋体 / 黑体 |
| 4 模式 | `MMSegmentedControl`，图标 + 文字 | 翻页 / 滚动 |
| 5 外观（仅 medium / compact） | 四个 36pt 圆形色块（`paperColor`，0.5pt `separator` 描边），选中为 2pt `accent` 外圈 + 对勾 | 白色 / 黑暗 / 纸质 / 浅绿 |

- 形态：regular / medium 为锚定在按钮下的 `MMDropdownButton` 弹层（宽 280，内边距 12，行间距 10，`glassOpaque` 底）；compact 为底部面板（`MMBottomSheet`，随内容高度，**无遮罩**，正文在上方可见，点面板外关闭）。
- **即时生效**：每次点击立即重排，没有“应用”“重新排版”。重排后保持当前位置：以视图首个可见字符为锚点，重排后该字符所在的页 / 滚动位置成为新的视图起点。
- 作用范围：全局，按“书籍 / 文章”两组分别记住，保存在应用设置（`settingsProvider`），不按文档保存。
- 默认值：

| | 书籍 | 文章 |
| --- | --- | --- |
| 字号 | 16.5（手机 18） | 16.5（手机 18） |
| 行距 | 适中 | 适中 |
| 字体 | 原书（书内未指定时按宋体显示） | 宋体 |
| 模式 | 翻页 | 滚动 |

- 快捷键：现有阅读器“放大 / 缩小 / 实际大小”命令在流式文档上分别改为字号 +1 档、−1 档、恢复默认字号；菜单项文字不变。
- 阅读外观（四种纸色）对流式文档作用于整个阅读区背景和文字颜色；对页面文档仍只变换页面。

### 3.4 翻页与导航

| 输入 | 翻页模式 | 滚动模式 |
| --- | --- | --- |
| → / ← | 下一页 / 上一页 | 向下 / 向上一屏（减去一行） |
| Space / ⇧Space、PageDown / PageUp | 下一页 / 上一页 | 同上 |
| Home / End | 开头 / 结尾 | 同左 |
| 点击正文左右 `turnZone` | 上一页 / 下一页（点到链接、高亮、批注标记时不翻页） | 无 |
| 触控横向轻扫 | 翻页 | 无（纵向滚动） |
| 触控板横向两指滑动 | 翻页 | 无 |
| 选区拖到正文左右边缘停留 600ms | 自动翻页，选区延续 | 自动滚动 |
| 捏合 | 无 | 无 |

**底部导航**（沿用 `_PagePill`：上方徽标、下方 ‹ 进度线 ›，高 `readerNavigationHeight`，距底 16；指针下悬停或拖动时显示，触控始终显示）：

- 徽标文字：“{章节标题} · {百分比}%”。章节标题取当前视图起点所在的最深一级目录项；无目录时用文档标题。单行，最大宽度为阅读区 80%，超出省略。点击徽标打开页面侧栏的“目录”（compact 为目录底部面板）。
- 百分比按位置在全文字符中的比例计算，与版式无关，取整。
- ‹ › 只在翻页模式出现，分别翻一页；首页 / 末页时禁用。
- 进度线可拖动：拖动时徽标实时显示目标章节和百分比，松开跳转。
- 页面文档的徽标仍是“n / N”，可点开输入页码（现状）。

### 3.5 页面侧栏

- 流式文档：三个标签“目录 / 书签 / 标注”，**没有缩略图**；所有条目不显示页码。
- 目录：来自 EPUB nav / NCX、MOBI 的 NCX、Markdown 与网页的标题（h1–h3）。两级缩进（第二级左缩进 14）。当前章节为选中底色。点击跳转；compact 下点击后关闭面板。无目录时空状态“没有目录”。
- 书签：现有“添加书签”命令在流式文档上记录当前视图首个可见字符的位置。条目两行：章节标题（`callout`），下一行“开头 24 个字… · 百分比”（`footnote` / `tertiaryLabel`）。空状态沿用“没有书签”。
- 标注：条目左侧 3pt 色条，正文为引文（宋体 12.5，最多 3 行），下一行为章节标题（`footnote` / `tertiaryLabel`）。空状态沿用“没有标注”。
- **需要确认**（重新抓取或源文件变化后无法重新定位的标注）：列在最上方单独一组，组标题“需要确认 {count}”（`subheadline`，`caution` 色，前置 `warning` 图标），条目章节标题行改用 `caution` 色；下面一条 0.5pt 分隔线后是正常标注。点击跳到该章节开头并 HUD“找不到原文位置”；右键（触控长按）菜单只有“删除”。
- 形态：regular / medium 为现有可拖动侧栏（240，180–360）；compact 为中等高度底部面板（`bottomSheetMedium`），顶部为三个图标标签。

### 3.6 选区、标注与工具

- **选区工具条与 PDF 完全相同**（`selection_toolbar.dart`：最近颜色、更多颜色、下划线 │ 拷贝、页边批注、笔记、添加到脑图、翻译 │ 问助手），不按格式删减。
- compact 宽度放不下时，按“笔记 → 页边批注 → 下划线”的顺序收进“更多”（`MMIcons.more`）按钮，顺序为：颜色 │ 拷贝、添加到脑图、翻译、更多 │ 问助手。触控高度 48，按钮热区 ≥ 44。
- 位置：优先在选区上方；上方空间不足（会盖住原文工具栏）时放在选区下方（`placeFloatingToolbar`）。翻页或滚动时收起。
- 高亮、下划线、批注画在文字上，随重排移动；颜色、样式与 PDF 相同。
- 卡片出处：“{文档标题} · {章节标题}”，前置格式图标（第 1.4 节）；“回原文”跳到位置并闪烁高亮。
- 页边批注：regular 下批注列宽 `marginColumn`，贴在正文栏右侧；翻页模式打开页边批注时对页改为单栏，正文栏与批注列一起居中。medium / compact 下只在正文里显示批注标记，点击标记弹出批注（medium 锚定弹层、compact 底部面板），与 PDF 在该尺寸下的行为一致。
- 画笔：沿用画笔工具条；笔迹挂在段落上，重排后随段落移动和缩放。
- 框选：与 PDF 相同，截取屏幕区域作为卡片图片。
- 查找（⌘F）：沿用查找栏；结果高亮，上一个 / 下一个会翻页或滚动到结果。
- 对照阅读：左右两栏各自保持自己的阅读设置，翻页模式下各自只排单栏。同步按位置比例。AI 逐段对照在翻页文档上打开时，两栏临时切换为滚动模式（不改设置），关闭对照后恢复。

### 3.7 Markdown

- 与电子书同一套界面与工具，可划线、摘录、批注。
- 渲染：标题、段落、列表、任务列表（复选框只读）、引用、表格、代码块、图片、链接、分隔线。h2 下方 0.5pt `separator` 色线。代码高亮、数学公式不在本期。
- 导入时把相对路径图片复制进学习集；远程图片按第 3.1 节默认不加载。

### 3.8 网页文档

- 阅读模式（默认）是流式文档，见上文。存成 PDF 的网页走 PDF 阅读器；存成 Markdown 的网页走 Markdown。三者侧栏图标都是地球。
- 正文标题下一行署名：“{域名} · {抓取日期}”（`inkColor` 60%，正文字号 0.75 倍，系统字体）。域名是链接，点击用系统浏览器打开原网页。不另设来源栏。
- “切换文档”菜单在当前文档为网页来源时多两项：打开原网页、重新抓取（无内置浏览器的平台不显示“重新抓取”）。
- **重新抓取**：在内置浏览器打开原网址（复用会话，可先登录）。浏览器栏的“转换为文档…”换成“更新文档”，就绪气泡为“更新文档？”［稍后］［更新］。更新按原格式保存为同一文档的新版本，不弹转换面板。完成后回到文档；全部标注对齐时 HUD“已更新”；有对不上的标注时 HUD“{count} 处标注需要确认”＋操作“查看”（打开页面侧栏“标注”）。

---

## 4. 固定版式 EPUB（场景 9）

- 按书内页面尺寸逐页显示，复用 PDF 阅读器的视图、缩放、缩略图、页码导航与标注。
- 工具栏：裁边置灰，其余同 PDF；没有阅读设置。
- 对页：书内 `rendition:spread` 不为 `none`、尺寸类为 regular、阅读区能放下两页（每页至少 360 宽）时按对页显示，第一页单独成页（封面）；否则单页。
- 有文字层的页面可以选字、划线；纯图片页只能框选和画笔（高亮、下划线工具保持可用，选不到文字时无反应）。
- 手机：单页、适合宽度、纵向连续滚动，与 PDF 一致。

---

## 5. 内置浏览器与转换（场景 12–17、22、23）

### 5.1 添加网页

- `showMMSheet`（compact 为底部面板）：标题“添加网页”；一个输入框（`MMTextField`，前置地球图标，占位“网址”，自动聚焦并全选）；输入框下方一行错误（`critical`，`footnote`，无错误时留空占位）；按钮“取消”“打开”（compact 为标题行右侧“打开”）。
- 规范化：去掉首尾空白；没有协议时补 `https://`。错误：空 → “请输入网址”；不能解析或主机名无点（`localhost` 除外）→ “网址无效”；非 http(s) → “只支持 http 和 https”。

### 5.2 浏览器栏

网页在原文栏打开，原文工具栏整行换成浏览器栏：

| 尺寸类 | 从左到右 |
| --- | --- |
| regular / medium | 后退、前进、重新载入（载入中为停止）、地址栏（完整网址，可编辑，回车按 5.1 规则打开）、“转换为文档…”按钮、关闭网页、切换文档 |
| compact | 关闭网页、地址栏（只显示域名，点击后显示完整网址可编辑；右端重新载入 / 停止）、“转换”按钮 |

- 地址栏：高 30（触控 36），胶囊，`quaternaryFill` 底；前置锁形图标（加载失败时为 `warning`）；载入进度为底边 2pt `accent` 线。
- “转换为文档…”：主框架提交前禁用；之后为次要按钮；就绪后变为主要按钮并脉动 2 次。
- 后退：iOS 用 WebView 边缘手势；Android 系统返回先后退网页历史，历史开头时关闭浏览器（与点“关闭网页”相同）。
- 侧栏“文档”末尾出现临时条目：地球图标（载入中为转圈）+ 页面标题（未就绪时为域名），文字 `secondaryLabel`（表示未保存），可点回浏览器；关闭浏览器即移除。
- 浏览器内容区不随阅读外观变色。

### 5.3 就绪提示

- 判定：主框架加载完成，且网络请求与 DOM 变化静默 800ms。
- 气泡（非模态）：锚定在“转换为文档…”按钮下方，带指向按钮的 12pt 小三角；`glassOpaque` 底、圆角 14、内边距 12。内容一行：粗体问句 + 两个按钮。regular / medium 宽度随内容（最小 280）；compact 左右各留 12，铺满宽度。
  - 就绪：“转换为文档？”［稍后］［转换］。
  - 15 秒仍未静默：“部分内容仍在加载”［继续等待］［转换］。之后若静默，再显示就绪气泡一次。
  - 重新抓取时：“更新文档？”［稍后］［更新］。
- 点“稍后”、气泡外任意处或页面导航时收起；同一网址只自动弹一次；按钮常驻，随时可转换。

### 5.4 加载失败

内容区居中：56pt 圆角方块内地球图标、标题“无法打开页面”、一行原因、主要按钮“重试”。不提供“修改网址”（地址栏可直接改）。“转换为文档…”禁用。

| 错误 | 原因文案 |
| --- | --- |
| 超时 | 连接超时 |
| 域名无法解析 | 找不到服务器 |
| 证书错误 | 证书无效 |
| 离线 | 未连接网络 |

HTTP 4xx / 5xx 显示网站自己的页面，不视为失败。

### 5.5 转换为文档

- regular / medium：`showMMSheet`，宽 640。标题“转换为文档”。左侧预览（200 × 260，`quaternaryFill` 底、圆角 12，内为所选格式的缩略预览）；右侧：标题输入框（默认页面标题，占位“标题”）、三段 `MMSegmentedControl`：**阅读模式**（默认）/ PDF / Markdown。底部“取消”“保存”。
- compact：全高底部面板。标题行“转换为文档”；下面依次为标题输入框、三段控件、预览（高 300）；底部全宽主要按钮“保存”（高 44）。
- 不提供格式说明文字：差别由预览展示。快照总是保存，没有开关。
- 保存：面板关闭，HUD 带进度条“正在保存”。成功：关闭浏览器，打开新文档，侧栏条目闪一次，HUD“已保存「标题」”。失败：浏览器保留，HUD“保存失败”＋操作“重试”。

### 5.6 设置中的网站数据

“设置 › 通用”增加一组“内置浏览器”（无内置浏览器的平台不显示），一行“网站数据”，右侧 `critical` 色纯文本按钮“清除…”。确认对话框：“清除所有网站数据？”［取消］［清除］（`critical`）。清除后已登录网站需要重新登录。

---

## 6. 平台差异

| 项目 | macOS | Windows | Linux | Web | iPadOS | iOS | Android |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 流式阅读、Markdown、固定版式 | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 添加网页 / 重新抓取 / 网站数据设置 | ✓ | ✓ | — | — | ✓ | ✓ | ✓ |
| 侧栏 + | 菜单 | 菜单 | 直接导入 | 直接导入 | 菜单 | 菜单（切换文档） | 菜单（切换文档） |
| 拖入文件 / 网址 | ✓ / ✓ | ✓ / ✓ | ✓ / — | — | —（沿用移动端约定） | — | — |
| 快捷键修饰 | ⌘ | Ctrl | Ctrl | Ctrl | ⌘（外接键盘） | — | — |
| 布局 | regular | regular | regular | regular | 横屏 regular，竖屏 / 分屏 medium | compact + Tab | compact + Tab |
| 阅读设置 | 工具栏第 3 位弹层 | 同左 | 同左 | 同左 | 横屏同左；竖屏右端弹层（含外观） | 右端底部面板（含外观） | 同 iOS |
| 页面侧栏 | 侧栏 | 侧栏 | 侧栏 | 侧栏 | 侧栏 | 底部面板 | 底部面板 |
| 翻页输入 | 键盘、点击热区、触控板 | 键盘、点击、滚轮横向 | 同 Windows | 同 Windows | 轻扫、点击热区 | 轻扫、点击热区 | 轻扫、点击热区 |
| 浏览器后退 | 按钮 | 按钮 | — | — | 按钮 / 边缘手势 | 边缘手势 | 系统返回 |
| 外部链接 | 系统浏览器 | 系统浏览器 | 系统浏览器 | 新标签页 | 系统浏览器 | 系统浏览器 | 系统浏览器 |

- Web 平台字体沿用应用在 Web 上的加载方式，不另打包字体；“原书”使用书内嵌字体时以 `FontLoader` 从书内资源加载。
- Android 系统返回键依次：关闭弹层 / 面板 → 浏览器内后退 → 关闭浏览器 → 现有页面返回（`MMBackHandler`）。

---

## 7. 空状态与错误态

| 场景 | 呈现 | 文案 |
| --- | --- | --- |
| 学习集没有文档 | 现有 `MMEmptyState` | 沿用 `readerEmptyTitle`；`readerEmptyMessage` 改为“在侧栏选择文档，或导入文档。” |
| 导入中 | 侧栏临时行，转圈 | 书名 |
| 无法导入 | 对话框 / 底部面板（2.4） | 无法导入「名称」＋原因 |
| 拖入不支持的文件 | HUD | 不支持「名称」 |
| 目录 / 书签 / 标注为空 | 侧栏居中 `tertiaryLabel` 12 | 没有目录 / 没有书签 / 没有标注 |
| 某章无法显示 | 该章位置一个块：`warning` 图标 + 一行 `secondaryLabel`，其余章节照常 | 这一章无法显示 |
| 远程图片未加载 | 占位块 + 文字按钮（3.1） | 加载图片 |
| 标注无法重新定位 | 标注列表“需要确认”组；点击后 HUD | 需要确认 {count}；找不到原文位置 |
| 浏览器载入中 | 地址栏进度线；内容区为网页本身 | — |
| 浏览器加载失败 | 内容区居中状态（5.4） | 无法打开页面＋原因；重试 |
| 网址错误 | 输入框下方红字 | 见 5.1 |
| 转换 / 更新保存中 | HUD 进度 | 正在保存 |
| 转换 / 更新失败 | HUD＋重试 | 保存失败 |
| 更新后有对不上的标注 | HUD＋查看 | {count} 处标注需要确认 |
| 源文件丢失 | 沿用现有 PDF 文件丢失状态 | 沿用 |

---

## 8. 文案（ARB 键建议）

已有键直接复用：`importDocument`、`switchDocument`、`readerOutline`、`readerBookmarks`、`readerAnnotations`、`readerAppearance`、`readerZoom`、`cropMargins`、`moreTools`、`showReaderSidebar`、`hideReaderSidebar`、`readerStyle*`、`noBookmarks`、`noAnnotations`、`addBookmark`、`previousPage`、`nextPage`、`pageOf`、`importedHud`、`copyAction`、`cancel`、`save`、`open`。`importPdf` 与 `importFailed` 由下表的通用键替代后删除。

| 键 | 中文 | English |
| --- | --- | --- |
| `addWebPage` | 添加网页… | Add Web Page… |
| `addDocumentMenu` | 添加 | Add |
| `dropToImport` | 松开以导入 | Drop to Import |
| `unsupportedFile` | 不支持「{name}」 | “{name}” isn’t supported |
| `importFailedTitle` | 无法导入「{name}」 | Couldn’t Import “{name}” |
| `importFailedMany` | {count} 份文档无法导入 | {count, plural, =1{1 document couldn’t be imported} other{{count} documents couldn’t be imported}} |
| `importErrorDrm` | 受 DRM 保护 | Protected by DRM |
| `importErrorDamaged` | 文件已损坏 | The file is damaged |
| `importErrorKfx` | 不支持 KFX 格式 | KFX isn’t supported |
| `importErrorEmpty` | 没有可读内容 | No readable content |
| `cancelImport` | 取消导入 | Cancel Import |
| `okAction` | 好 | OK |
| `readingSettings` | 阅读设置 | Reading Settings |
| `readingTextSmaller` | 缩小字号 | Smaller Text |
| `readingTextLarger` | 放大字号 | Larger Text |
| `readingSpacingTight` | 紧凑 | Tight |
| `readingSpacingNormal` | 适中 | Normal |
| `readingSpacingLoose` | 宽松 | Loose |
| `readingFontBook` | 原书 | Original |
| `readingFontSerif` | 宋体 | Serif |
| `readingFontSans` | 黑体 | Sans Serif |
| `readingModePaged` | 翻页 | Pages |
| `readingModeScroll` | 滚动 | Scroll |
| `readerChapterProgress` | {chapter} · {percent}% | {chapter} · {percent}% |
| `readerOutlineEmpty` | 没有目录 | No Contents |
| `readerChapterUnavailable` | 这一章无法显示 | This chapter can’t be displayed |
| `readerLoadImage` | 加载图片 | Load Image |
| `readerLinkBack` | 返回 | Back |
| `annotationsNeedReview` | 需要确认 {count} | Needs Review ({count}) |
| `annotationNotFound` | 找不到原文位置 | Passage not found |
| `addWebTitle` | 添加网页 | Add Web Page |
| `webUrlPlaceholder` | 网址 | URL |
| `webUrlEmpty` | 请输入网址 | Enter a URL |
| `webUrlInvalid` | 网址无效 | Not a valid URL |
| `webUrlScheme` | 只支持 http 和 https | Only http and https are supported |
| `browserBack` | 后退 | Back |
| `browserForward` | 前进 | Forward |
| `browserReload` | 重新载入 | Reload |
| `browserStop` | 停止 | Stop |
| `browserClose` | 关闭网页 | Close Page |
| `browserUnsaved` | 未保存 | Not Saved |
| `browserConvert` | 转换为文档… | Convert to Document… |
| `browserConvertShort` | 转换 | Convert |
| `browserUpdate` | 更新文档 | Update Document |
| `webReadyPrompt` | 转换为文档？ | Convert to a document? |
| `webUpdatePrompt` | 更新文档？ | Update the document? |
| `webStillLoading` | 部分内容仍在加载 | Some content is still loading |
| `webLater` | 稍后 | Later |
| `webKeepWaiting` | 继续等待 | Keep Waiting |
| `webConvertAction` | 转换 | Convert |
| `webUpdateAction` | 更新 | Update |
| `webErrorTitle` | 无法打开页面 | Can’t Open Page |
| `webErrorTimeout` | 连接超时 | The connection timed out |
| `webErrorHost` | 找不到服务器 | Server not found |
| `webErrorCertificate` | 证书无效 | Invalid certificate |
| `webErrorOffline` | 未连接网络 | You’re offline |
| `webRetry` | 重试 | Try Again |
| `convertTitle` | 转换为文档 | Convert to Document |
| `convertTitlePlaceholder` | 标题 | Title |
| `convertReadable` | 阅读模式 | Reader |
| `convertPdf` | PDF | PDF |
| `convertMarkdown` | Markdown | Markdown |
| `docSaving` | 正在保存 | Saving |
| `docSaved` | 已保存「{title}」 | Saved “{title}” |
| `docSaveFailed` | 保存失败 | Couldn’t Save |
| `docUpdated` | 已更新 | Updated |
| `annotationsNeedReviewHud` | {count} 处标注需要确认 | {count, plural, =1{1 highlight needs review} other{{count} highlights need review}} |
| `viewAction` | 查看 | View |
| `openOriginalPage` | 打开原网页 | Open Original Page |
| `refetchPage` | 重新抓取 | Refetch Page |
| `settingsBrowserGroup` | 内置浏览器 | In-App Browser |
| `settingsWebsiteData` | 网站数据 | Website Data |
| `settingsClearWebsiteData` | 清除… | Clear… |
| `clearWebsiteDataConfirm` | 清除所有网站数据？ | Clear all website data? |
| `clearAction` | 清除 | Clear |
| `readerEmptyMessage`（改） | 在侧栏选择文档，或导入文档。 | Pick a document in the sidebar, or import one. |

`browserUnsaved` 只作为侧栏临时条目的提示文字与辅助功能名称，不显示为标签。日期使用现有本地化日期格式（中文“2026年10月29日”，英文“Oct 29, 2026”）。

---

## 9. 无障碍与键盘

- 所有图标按钮都有提示文字与辅助功能名称（使用上表文案）；分段控件每段有名称（行距用“紧凑 / 适中 / 宽松”）。
- 阅读设置弹层：Tab / 方向键在控件间移动，Esc 关闭；底部面板支持 VoiceOver / TalkBack 的“关闭”手势。
- 翻页模式对屏幕阅读器按段落朗读并自动翻页；底部徽标朗读为“{章节}，{百分比}%”。
- 对比度：正文 `inkColor` 与 `paperColor` 已满足 4.5:1；次要文字（60%）用于署名等非正文信息，在四种纸色上不低于 3:1（大字号标准）；实现时在 `tokens_test.dart` 增加检查。
- “减少动态效果”：翻页无位移动画，脉动与闪烁改为一次静态强调色。

---

## 10. 原型场景对照

| # | 场景 | 设备 | 本文 |
| --- | --- | --- | --- |
| 1 | 导入入口 | macOS | 2.1、2.3 |
| 2 | 拖入文件 | macOS | 2.2 |
| 3 | Linux / Web 没有“添加网页” | Linux | 2.1、6 |
| 4 | EPUB 翻页阅读与摘录 | macOS | 3.1、3.2、3.4、3.6 |
| 5 | 阅读设置 | macOS | 3.3 |
| 6 | 滚动模式 + 页边批注 | macOS | 3.1、3.6 |
| 7 | 页面侧栏 | macOS | 3.5 |
| 8 | MOBI / AZW3 | macOS | 2.3 |
| 9 | 固定版式 EPUB | macOS | 4 |
| 10 | 无法导入 | macOS | 2.4 |
| 11 | Markdown 阅读与划线 | macOS | 3.7 |
| 12 | 添加网页 | macOS | 5.1 |
| 13 | 内置浏览器 · 就绪 | macOS | 5.2、5.3 |
| 14 | 加载缓慢 | macOS | 5.3 |
| 15 | 加载失败 | macOS | 5.4 |
| 16 | 转换为文档 | macOS | 5.5 |
| 17 | 网页文档 · 重新抓取 | macOS | 3.8 |
| 18–22 | iPhone：翻页阅读、选区工具条、阅读设置、目录、内置浏览器 | iPhone | 3.2–3.6、5.2 |
| 23 | iPhone 转换面板 | iPhone | 5.5 |
| 24 | Android Markdown | Android | 3.7、6 |
| 25 | iPad 横屏 | iPad | 1.2、3.1 |
| 26 | iPad 竖屏 | iPad | 3.2、3.3 |
| 27 | PDF（现状） | macOS | 对照基准 |

原型限制：字体在未安装宋体的系统上会回退；翻页用 CSS 多栏模拟，分页位置与 Flutter 排版引擎不同；Windows / Linux / Web 只模拟窗口外框和快捷键写法；画笔、框选、对照阅读、查找只演示工具状态，交互以本文为准。
