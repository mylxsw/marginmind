# 工作区布局：一行工具栏（GUL-609）

原型：`design/prototype/layout-density.html`（单文件，浏览器直接打开）。顶部切换“现状 / 新方案”、设备和外观；`?scheme=current&device=phone&theme=light&layout=map` 可直接定位。

“现状”是应用本身的截图：用 `flutter build web` 构建、打开示例学习集，在 Mac、iPad、iPhone 尺寸和浅色 / 深色下截取。“新方案”按下文的扁平化视觉规格，用 `mm_design` 的颜色、尺寸、字号、圆角，以及应用自带的 CupertinoIcons 与 Lucide 图标字体（子集，内嵌）绘制，各控件对应 `MMToolbarButton`、`MMToolbarGroup`、`MMSegmentedControl`、`MMDropdown`、`MapStylePopover`。

## 问题

工作区在正文上方叠了三层横条：窗口工具栏（文档标题 + 视图 + AI）、原文工具栏、脑图标题栏（“主脑图” + 脑图/大纲/样式）。底部还有“紧凑 / 完整”、摘录目标提示、缩放组和分割线上的 ‹ › 收起按钮。PDF 页面在 iPad 上从 129pt 开始，iPhone 是 154pt，再加上底部 86pt 的标签栏。

右上角“整理笔记”和“助手”都用 `MMIcons.ai`（sparkles），只靠颜色区分。

## 方案

1. **每栏一行，合成一条工具栏。** 原文栏和脑图栏各自的表头上移到窗口工具栏这一行，并按栏宽对齐，分割线贯穿到顶。窗口级控件（原文 / 分栏 / 脑图，整理笔记，助手）放在最后一栏的末端。“原文”或“脑图”单栏时，这一行只剩那一栏的工具。
2. **不显示文档标题和脑图标题。** 侧栏的选中行已经标出当前文档和脑图；侧栏收起时由“切换文档”菜单的勾选标出。窗口标题仍写给系统（窗口菜单、Mission Control、无障碍），不占工具栏。
3. **原文工具栏只留标注工具。** 选择 / 高亮 / 下划线 / 画笔 / 框选、摘录同步，加一个 `Aa` 阅读菜单：缩放与适配、阅读配色、页边批注、生词提示、对照阅读、裁边、阅读设置。栏宽不够时依次把框选、同步收进 `Aa`。
4. **脑图表头只留视图和样式。** “主脑图”标题去掉，脑图 / 大纲分段控件移到这一行最前面；“紧凑 / 完整”移入样式弹窗。底部只剩缩放组（适合窗口、−、比例、+），摘录目标缩成一个带同步图标的小标签，只在同步打开时出现。
5. **表头是纯色的一行。** 底色与所在栏相同，正文和画布从表头下方滚过；滚动后才出现 0.5pt 分隔线。
6. **去掉分割线上的 ‹ ›。** 收起某一栏用工具栏的原文 / 分栏 / 脑图，或拖动分割线。
7. **触屏阅读时隐藏工具栏。** iPad、iPhone 向下滚动时表头滑出，向上滚动或轻点正文时回来；Mac 不隐藏。
8. **两个 AI 入口用不同图标。** 整理笔记改用 `LucideIcons.notebookPen`（与侧栏“笔记”的 `notebookText` 同族，表示“生成一份笔记”）；助手保留 sparkles 和研究色，作为唯一的 AI 对话入口。

### iPhone

顶部一条 50pt 的纯色栏：侧栏、原文 / 脑图分段、助手、更多（整理笔记、复习、生词本）。工具放在拇指区的浮动工具条：原文时是标注工具和 `Aa`，脑图时是大纲切换、样式和缩放。学习集内不再显示底部标签栏：资料库和复习从侧栏进入。两条栏都随滚动隐藏。

### iPad 与 Mac

同一套结构；只有触控尺寸（按钮 36pt）、状态栏和滚动隐藏不同。竖屏分栏时上下排列，原文表头带窗口级控件，脑图表头只有脑图工具。

## 收益

| 设备 | 现状 | 新方案 | 滚动阅读时 |
| --- | --- | --- | --- |
| Mac 1280×800 | 133pt | 56pt | 56pt |
| iPad 11″ 横屏 | 129pt | 80pt | 24pt |
| iPad 11″ 竖屏 | 136pt | 80pt | 24pt |
| iPhone 393×852 | 154pt | 104pt | 54pt |

指 PDF 页面上边缘的 y 坐标。现状从应用截图量出，web 版没有状态栏，所以加上了状态栏高度（iPad 24pt，iPhone 54pt）；新方案由原型实测（`#metric`）。iPhone 底部另外让出 86pt（标签栏改为随滚动隐藏的浮动工具条）。

## 实现要点

- `MMToolbar` 不再接收 `title`；`WorkspaceScreen` 给原文栏和脑图栏各传一组 toolbar items，由布局按分割线位置排列。窗口标题继续通过平台通道设置。
- `ReaderPane._toolbar` 拆成“标注工具 + `Aa`”，现有 `reader-more` 菜单的内容并入 `Aa`；`MapHeader` 去掉标题槽位。
- “紧凑 / 完整”从地图底部移到 `MapStylePopover`；`MMSizes.mapViewControlsReservedWidth` 随之缩小。
- 删除分割线上的收起按钮，保留单栏时的恢复入口（工具栏的视图切换）。
- `PhoneTabBar` 只在资料库和复习页面显示；学习集内用浮动工具条。
- `workspace_screen.dart` 中 `toolbar-organize-note` 的图标改为 `MMIcons.studyNote` 的同族图标（新增 `MMIcons.organizeNote = LucideIcons.notebookPen`）。

## 扁平化视觉规格（GUL-610）

工作区不用毛玻璃、模糊、渐变和外投影。层级只靠三样东西：纯色填充、0.5pt 分隔线（悬浮物体的外框）、语义色。本节是实现的唯一视觉依据；颜色、尺寸都写 `mm_design` 令牌名，括号里是 pt 值，标 **新** 的令牌见本节末尾。

### 通用规则

- **填充**：表头与所在栏同色；工具组和分段控件的底用 `quaternaryFill`；浮在内容上的控件（菜单、弹窗、选择工具条、缩放组、翻页条、iPhone 工具条、提示）用 **新** `surface`。
- **描边**：浮动控件和侧栏 0.5pt **新** `border`（**新** `MMSizes.hairline`）；摘录卡片 1pt **新** `border`（**新** `MMSizes.nodeStroke`）；表头下沿、菜单分组、工具组内分隔 0.5 / 1pt `separator`。描边都画在框内，不改变外形尺寸。
- **不再使用**：`BackdropFilter`、`BoxShadow`（包括 `glassShadow`、`cardShadow`、`sidebarShadow`、`sheetShadow`）、`Gradient`、`MMLiquidGlass` 的光泽和边缘高光。
- **状态**：悬停叠加 `hover`，按下叠加 `pressed`，选中用 `accentTint` 底 + `accent` 图标 / 文字；“助手”这类研究入口用 `research` 文字、选中 `researchTint` 底；禁用整体 30% 不透明度；键盘焦点 2pt `accent` 描边环（外扩 2pt，不发光）。
- **文字**：只留控件名称和必要的状态。侧栏文档行不显示数量，弹窗标题与入口同名（“整理笔记”），说明性的副标题和提示一律不加，靠位置和分组表达。
- **动效**：状态变化 `MMMotion.quick`；表头随滚动隐藏、侧栏抽屉、面板进出 `MMMotion.layout` + `layoutCurve`。只做位移和透明度，不做模糊过渡。

### 组件

| 组件 | 填充 | 描边 | 圆角 | 尺寸（Mac / iPad / iPhone） | 状态 |
| --- | --- | --- | --- | --- | --- |
| 栏表头（原文栏、脑图栏） | 所在栏底色：`readerBackground` / `canvas`（都等于 `windowBackground`） | 下沿 0.5pt `separator`，内容滚动超过 2pt 才显示 | 0 | 高 **新** `MMSizes.paneHeaderHeight`（52）+ 状态栏；左右内边距 12 / 16 / 16，控件间距 10 / 8 / 8 | 触屏向下滚动整条上移隐藏，向上滚动或轻点正文回来 |
| iPhone 顶栏 | `windowBackground`，盖住状态栏区域 | 下沿 0.5pt `separator`，常显 | 0 | 高 50 + 状态栏 | 同上 |
| 工具按钮 `MMToolbarButton` | 透明 | 无 | `capsuleButton`（15）；iPad 16 | `toolbarButton`（34×30）；iPad 视觉 `tabletControlVisual`（32），热区 `touchTarget`（44）；图标 16 / `tabletToolbarIcon`（18） | 悬停 `hover`，按下 `pressed`，选中 `accentTint` + `accent`，研究入口 `research` / `researchTint` |
| 带文字的工具按钮（Mac“整理笔记”） | 同上 | 无 | 同上 | 左右内边距 10（iPad 12），图标与文字间距 6，`MMTypography.callout` | 同上 |
| 工具组 `MMToolbarGroup` | `quaternaryFill` | 无 | `capsule`（18） | 高 `toolbarGroupHeight`（36），内边距 3；iPad 视觉 `tabletToolbarVisual`（36）在 44 热区内，左右内边距 2，按钮间距 6 | 只有组内按钮有状态 |
| 组内分隔 | `separator` | — | — | 1×18，左右各 4 | — |
| 分段控件 `MMSegmentedControl`（脑图 / 大纲、原文 / 脑图、紧凑 / 完整） | 轨道 `quaternaryFill`；选中段 **新** `selectedSegment` | 选中段 0.5pt **新** `border` | 轨道 14，段 12；触屏 18 / 16 | 高 `segmented`（28），内边距 2，段左右 12，`callout`；触屏 `segmentedTouch`（36），段左右 16，14pt | 未选中段悬停 `hover` |
| 侧栏（Mac 内嵌） | `sidebar`（改为不透明，见末尾） | 0.5pt **新** `border` | `sidebar`（16） | 宽 `sidebarWidth`（236），四周留 `sidebarInset`（8） | 行悬停 `hover`，选中行 `selectedRow`；行高 `sidebarRow`（28），触屏 44，圆角 `row`（8） |
| 侧栏抽屉（iPad、iPhone） | `sidebar` | 0.5pt **新** `border` | 16 | 宽 `sidebarMaxWidth`（320），顶部让出状态栏 + 8 | 背后 `scrim`，点 `scrim` 关闭 |
| 菜单 `MMDropdown`（`Aa`、切换文档、更多） | **新** `surface` | 0.5pt **新** `border` | `dropdown`（14） | 宽 `readerZoomMenuWidth`（280），触屏 300；内边距 6；行高 `dropdownRowHeight`（30），触屏 44；图标 `dropdownIcon`（14），触屏 18 | 行悬停 `accentFill` 底 + `onAccent` 文字和图标；勾选 `accent`；快捷键、占位文字 `secondaryLabel`；分组线 1pt `separator`，左右缩进 8 |
| 菜单内开关 `MMSwitch` | 关 `fill`，开 `accent`；圆钮白色 | 无 | 全圆 | 28×16，钮 12；触屏只扩大热区 | 无投影 |
| 阅读配色色块 | 配色本身（`MMReaderStyle`） | 0.5pt 内描边 `border` | 全圆 | 16 | — |
| 样式弹窗 `MapStylePopover` | **新** `surface` | 0.5pt **新** `border` | 14 | 宽 `mapStylePopoverWidth`（300），内边距 12；结构缩略图高 `mapStructureThumbHeight`（52），配色缩略图高 `mapPaletteThumbHeight`（44） | 缩略图底 `quaternaryFill` + 1pt `separator` 内描边，圆角 8；选中 2pt `accent` 内描边，标签 `accent` 半粗；标签 `footnote` / `secondaryLabel` |
| 选择工具条 `MMFloatingToolbar` | **新** `surface` | 0.5pt **新** `border` | 20 | 高 40，左右内边距 6；颜色点热区 `floatingToolbarColor`（26），点 `floatingToolbarDot`（14）；按钮 30 | 颜色点悬停 `hover`、按下 `pressed`；选中色外加 1.5pt 同色描边环（与点间隔 2pt `surface`），键盘焦点时环为 `accent`；不用投影 |
| 脑图缩放组 | **新** `surface` | 0.5pt **新** `border` | 18；触屏 22 | 高 36，触屏 44；内边距 3；按钮 30，触屏 36；比例数字最小宽 46，`callout` 等宽数字 | 同工具按钮 |
| 摘录目标标签 | 无 | 无 | — | 同步图标 12 + `footnote` / `secondaryLabel`，最大宽 45% | 只在同步打开且是脑图视图时出现 |
| 翻页条（iPad 常显，Mac 悬停显示） | **新** `surface` | 0.5pt **新** `border` | 18 | 高 36，内边距 4；按钮 28；进度轨 120×3 `fill`，已读 `secondaryLabel`；滑块 12 白色 + 0.5pt `border` | 触屏随表头一起隐藏 |
| iPhone 拇指工具条 | **新** `surface` | 0.5pt **新** `border` | 28 | 高 **新** `MMSizes.thumbDock`（56），左右内边距 6，距底 30；按钮 **新** `thumbDockButton`（46×44），圆角 22，图标 20；分隔 1×22 | 同工具按钮；随滚动隐藏 |
| 原文页面 | `page` | 0.5pt **新** `border` | `page`（3） | 宽 `MMReaderLayout.measure`（680） | iPhone 全宽，无描边、无圆角 |
| 中心主题 | `rootNode`，文字 `onRootNode` | 无 | `card`（12） | 内边距 11×18，16pt 半粗 | 选中：2pt `accent` 描边环，外扩 2 |
| 一级主题 | `fill`，文字 `label` | 无 | `row`（8） | 内边距 8×14，14pt 半粗 | 同上 |
| 摘录卡片 | `card` | 1pt **新** `border` | `card`（12） | 宽 220，内边距 7（8 − 描边）；摘录块圆角 `excerpt`（6），底为高亮色 14%，左侧 3pt 高亮色条，`readingExcerpt` / `excerptText` | 同上；悬停或选中时右上角出现 22pt 定位按钮（**新** `surface` + 0.5pt **新** `border`，图标 `accent`） |
| 连线 | — | 1.5pt `line` | — | — | — |
| 助手面板 | `windowBackground` | Mac 左侧 1pt `separator`；触屏四周 0.5pt **新** `border` | Mac 0；触屏 `sheet`（22），四周留 8 | 宽 `rightPanelWidth`（400） | 标题图标 `research`；输入框 1pt `separator` 描边，圆角 18；发送钮 `research` 底 + `onResearch` |
| 整理笔记弹窗 | `windowBackground` | 0.5pt **新** `border` | `sheet`（22） | 宽 560，内边距 20 | 背后 `scrim`；模板卡 `quaternaryFill` + 1pt `separator`，选中 2pt `accent` 内描边 |
| 提示 toast | **新** `surface` | 0.5pt **新** `border` | 18 | 内边距 9×16，`callout` | 只做淡入和 12pt 上移 |

### 令牌变更

新增：

| 令牌 | 浅色 | 深色 | 用途 |
| --- | --- | --- | --- |
| `MMColors.surface` | `#FFFFFF` | `#323235` | 浮动控件的不透明底，取代 `glass` / `glassOpaque`（值等于原 `glassOpaque`） |
| `MMColors.border` | `#1F000000`（黑 12%） | `#1FFFFFFF`（白 12%） | 浮动控件、侧栏、页面的 0.5pt 外框，摘录卡片的 1pt 描边；取代 `hairline`（原深色值是黑 50%，在深色底上看不见） |
| `MMColors.selectedSegment` | `#FFFFFF` | `#636366` | 分段控件的选中段。深色下 `card` 与轨道几乎同色，原来靠投影区分 |
| `MMSizes.hairline` | 0.5 | | 外框和分隔线宽度 |
| `MMSizes.nodeStroke` | 1 | | 脑图卡片描边宽度 |
| `MMSizes.paneHeaderHeight` | 52 | | 栏表头高度，不含状态栏 |
| `MMSizes.thumbDock` / `thumbDockButton` | 56 / 46×44 | | iPhone 拇指工具条及其按钮 |

修改：

| 令牌 | 改为 | 说明 |
| --- | --- | --- |
| `MMColors.sidebar` | 不透明：浅色 `#F2F2F6`，深色 `#2C2C2F` | 等于原 `sidebarOpaque`；`sidebarOpaque` 随后删除 |
| `MMColors.glassShadow`、`cardShadow`、`sidebarShadow`、`sheetShadow` | `[]` | 先清空，组件迁完后删除字段 |
| `MMColors.glass`、`glassOpaque`、`glassHighlight`、`hairline` | 废弃 | 改用 `surface` / `border` |
| `MMGlass`、`MMLiquidGlass` | 纯色实现：`surface` 底 + 0.5pt `border`，去掉 `BackdropFilter` 和光泽 | 可直接改名为 `MMSurface`；“减少透明度”分支不再需要 |
| `MMSegmentedControl` 选中段 | 去掉 `BoxShadow`，用 `selectedSegment` + 0.5pt `border` | |
| `MMFloatingToolbar` 颜色点选中环 | 用描边画环，不用 `BoxShadow(spreadRadius)` | 视觉不变 |

不变：`separator`、`fill`、`quaternaryFill`、`hover`、`pressed`、`accent*`、`research*`、`line`、`rootNode`、`card` 以及全部尺寸、圆角、字号令牌。

### 自检

`docs/evidence/gul-610/prototype_check.py` 用 Playwright 打开原型，截下 Mac、iPad 横竖屏、iPhone 在浅色 / 深色和每种布局下的画面；检查每个状态（包括打开的菜单、弹窗、面板、选择工具条）里所有元素及其 `::before` / `::after` 都没有阴影、模糊、滤镜和渐变；再把同一套操作在旧原型上重放，逐步比较界面状态，确认交互不变。当前结果：0 处阴影、模糊或渐变，4 种设备 × 2 种外观共 236 步操作与旧原型 0 处差异（`docs/evidence/gul-610/result.json`）。
