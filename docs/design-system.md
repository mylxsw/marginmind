# 设计系统（mm_design）

规范来源：`design/canvas/Foundations.dc.html`（02 · 基础）与 `design/canvas/Components.dc.html`（03 · 组件）。代码中的令牌与规范一一对应；改值请两边同时改。

## 令牌

| 类 | 内容 |
| --- | --- |
| `MMColors.vocabulary` / `vocabularyTint` | 生词使用系统 `accent` / `accentTint`，这两个名称仅为兼容入口，不再拥有固定青绿色。筛选及列表选中态使用全局中性色，主按钮使用 `accentFill` / `onAccent`；正文提示、状态标记与查词卡片随系统强调色更新。图标继续使用 Lucide `book-a`。 |
| `MMColors` | 语义色（`ThemeExtension`），浅色 `MMColors.light` / 深色 `MMColors.dark`。`withAccent()` 将强调色与实心按钮同步为系统颜色。实心控件的文字和图标统一白色优先，白色对比度低于 3:1 的浅黄、浅橙等底色才改深字；不按黑白对比度较大者选择。`research` / `researchTint` 兼容映射到 `accent` / `accentTint`；`researchWash` 使用强调底色一半透明度，`onResearch` / `onVocabulary` 沿用同一前景规则。状态色 `positive` / `caution` / `critical` 保持系统成功、警告与错误含义；用户选择的标注颜色与脑图配色保持内容含义。 |
| `MMAnnotationColor` | 六种预设标注色与任意 RGB 自定义色。`colorIndex` 保留预设 ID 0–5，自定义色存 `0x01000000 | RGB`，通过 `fromIndex` 统一解码；`highlight`（32%）、`underline`（90%）、`cardTint`（14%）。 |
| `MMInkColor` / `MMInkWidth` | 画笔的六色（红/橙/黄/绿/蓝/墨黑，`stroke` 为 90% 不透明）与三档粗细（1.5 / 2.5 / 4，单位 PDF 点，随页面缩放）。数据只存颜色索引和点数。 |
| `MMTypography` / `MMTextStyles` | macOS 文本样式：title3 15、headline 13 semibold、body 13、callout 12、subheadline 11 semibold、footnote 11；阅读用宋体 16.5/32，摘录 13/20。 |
| `MMSpacing` / `MMRadii` / `MMSizes` | 4pt 间距；同心圆角（窗口 24 → 侧栏 16 → 行 8；胶囊 18 → 按钮 15；卡片 12 → 摘录块 6）；工具栏 56、侧栏 236、行高 28、浮动工具条颜色点 14（热区 26）、右侧面板 400（窄窗口 360）等尺寸。 |
| `MMMotion` | popup 0ms（菜单、色板、锚定弹窗首帧完整显示）；hoverExit 500ms（从标记移入悬停卡片的关闭缓冲）；quick 150ms、standard 200ms、layout 320ms、flash 1600ms、hud 2400ms；AI 扩展的目标脉冲 pulse 1400ms、占位闪烁 shimmer 1100ms。 |

锚定下拉菜单一次完整显示，不使用尺寸展开或逐项淡入。窗口工具栏的拖动、双击缩放只监听背景区域，按钮点击松开即执行，不能等待双击判定。

在代码里读取：

```dart
final c = context.mmColors;   // 颜色
final t = context.mmText;     // 已着色的文本样式
```

对比度：`test/tokens_test.dart` 检查普通正文和次级文字在背景上不低于 4.5:1（深色次级文字因此提亮为 `#AEAEB2`）。按用户确认的系统实心控件外观，按钮文字和图标优先白色，保留系统蓝底，白色不足 3:1 才改深字；不宣称这些小字号白字按钮全部达到正文的 4.5:1。

## 组件

| 组件 | 说明 |
| --- | --- |
| `MMWindowScaffold` | 窗口骨架：可收起的侧栏 + 工具栏 + 内容；桌面侧栏宽 236pt，无额外外边距，顶部 Tab 栏与内容共用窗口背景且不画横向分隔线；Tab 自身保留选中背景和细边框；侧栏收起时工具栏自动给红绿灯让位。上方有 `MMWindowBottomBar` 时，在内容下方显示它提供的底栏（手机的 Tab），软键盘弹出时隐藏；`sheet` 盖在包括底栏在内的整个窗口上。 |
| `MMSidebar` / `MMSidebarSection` / `MMSidebarItem` / `MMCount` / `MMBadge` | 桌面侧栏贴边、无外层圆角/描边/阴影，以不透明侧栏底色区分工作区；触控抽屉保留悬浮玻璃。行高 28pt。 |
| `MMToolbar` / `MMToolbarGroup` / `MMToolbarButton` / `MMToolbarDivider` / `MMToolbarSearchField` | 统一工具栏与玻璃胶囊按钮组；空白处拖动窗口、双击缩放。 |
| `MMSplitView` | 两栏 + 可拖动分隔线（8pt 热区、双击复位），隐藏的面板保持挂载，但不保留键盘焦点；窗口太窄时自动只显示主面板。 |
| `MMSegmentedControl` | 分段控件，选中段为白色浮起。 |
| `MMButton` / `MMIconButton` | 胶囊按钮（主要 / 次要 / 纯文本）与面板内小图标按钮；按钮文字放不下时以省略号结尾。主要按钮默认使用系统强调色；`color` 仅用于有明确含义的覆盖，纯文本按钮的 `color` 是文字色（设置里的 `accent` 链接、`critical` 的“移除服务”）；`MMToolbarButton` 对应的是 `tint`，选中时也保持 `tint`（打开的助手）。 |
| `MMCheckbox` / `MMSwitch` / `MMPill` | 复选框（整行可点）、小开关、状态标签（文字为给定颜色，底为其 12%；不给颜色时为中性）。 |
| `MMSearchField` / `MMTextField` / `MMFormRow` / `MMColorPicker` | 表单控件；Esc 清空搜索。`MMTextField` 可多行（`maxLines` / `minLines`，随内容长高）、隐藏输入（`obscureText`，用于 API Key）并接收外部 `focusNode`；`plain` 用于无底色和焦点环的原地值。设置页统一用 `MMTextField.settings`：高 28、最大宽度 `MMSizes.settingsFieldWidth`（245，窄窗口随可用空间缩小）、右对齐、8pt 内边距，平时无底色和边框，只在聚焦时显示淡底、强调色边框和焦点环；必须提供空值提示和辅助功能名称，关闭自动纠错与输入建议。密钥始终隐藏，不显示明文切换按钮。 |
| `MMInlineTextField` | 原地编辑用的无边框文本框，随所在位置换行（`maxLines: 1` 时保持单行）；Enter 提交、Esc 取消，输入法组合期间这两个键交给输入法；`multiline` 时 ⇧Enter 换行。 |
| `showMMSheet` / `MMSheet` | 从工具栏下方落下的表单面板，Esc 取消。Compact 窗口改为底部 sheet；`showMMDialog` 同理。 |
| `MMBottomSheet` / `showMMBottomSheet` | Compact 窗口的底部 sheet：拖动把手改变高度，向下拖到底关闭。`expand` 有中等（`bottomSheetMedium`）与全高两档，用于助手和卡片详情；否则随内容高度。软键盘弹出时停在键盘上方，`expand` 的 sheet 扩展为全高。 |
| `MMTabBar` | 手机底部 Tab，等宽，位于 Home 指示条安全区之上。iOS 选中项为强调色；Android 用胶囊高亮选中图标，仍是 `mm_design` 的颜色和字体。 |
| `MMBackHandler` | 系统返回（Android 返回键/手势）：页面为当前路由时询问 `onBack`，后挂载的先问；当前路由之上的 sheet、对话框由导航器先关闭。 |
| `MMInput` | 触控判断的唯一来源：`touchPlatform` 决定布局，`phone` 标记手机；`touchInput` 跟随任意设备上最近一次指针（触屏笔记本也走触控菜单、常显控件），`touch` 只在触控平台上跟随，用于 44pt 控件尺寸。 |
| `MMSettingsGroup` / `MMSettingsRow` / `MMSettingsHeader` / `MMPopUpButton` | macOS 系统设置式分组表单（GUL-537）：卡片 `card` 底、圆角 12、0.5pt `hairline` 描边，深色为白 5% 底 + 白 8% 描边；行高 40、左标签右值、行间分隔线从 14 开始；可选 `quaternaryFill` 底栏。`MMPopUpButton` 是弹出按钮（`quaternaryFill`、圆角 6、上下双箭头），菜单里勾选当前值。模型服务展开后，标题栏提供带提示的删除图标，保留删除确认；“模型”标题右侧用加号打开添加弹窗，不另占一行。 |
| `MMDropdownButton` / `MMDropdownItem` | 阅读器共用下拉：对照阅读的 `glassOpaque` 底，14pt 圆角、0.5pt 细边、无外阴影；4pt 外内边距、30pt 桌面行高、12pt medium 文字、14pt 图标、8pt 图文间距、8pt 悬停圆角。触摸行高至少 44pt。缩放菜单 280pt、普通菜单 240pt、文档/对照菜单 340pt；所有宽度共用同一组件，不能按功能重写外观。滑块拖动不关闭菜单，Esc/点外部关闭。 |
| `showMMMenu` / `MMMenuItem` / `MMMenuHeader` | 右键菜单与下拉菜单。`MMMenuItem.checked` 非空时留出勾选列；`minWidth` 用于和按钮同宽（模型菜单 220）。Compact 窗口改为底部 Action Sheet（选项一组、“取消”单独一组）。 |
| `MMHudHost` / `MMHud.show` | 窗口底部的提示胶囊。可带一个 `action`（如“撤销”“在脑图中查看”），只有带操作的胶囊接收点击。 |
| `MMFloatingToolbarSwatch` / `MMFloatingToolbarStrokeWidth` | 浮动工具条里的任意颜色点（`MMFloatingToolbarColor` 基于它）和粗细点（点的直径 = 粗细 × 2 + 2，选中为强调色底）。`MMToolbarButton` 可只有文字（`icon: null` + `label`），用于“完成”。 |
| `MMFloatingToolbar` / `MMFloatingToolbarColor` / `MMFloatingToolbarLayout` | 选区旁的横向玻璃工具条：图标按钮（`MMToolbarButton`）+ 颜色点，每项都有提示文字，Tab / 方向键移动焦点。定位用纯函数 `placeFloatingToolbar`：优先放在选区上方，空间不够放下方，左右超出时向内收，始终完整可见；锚点变化时跟随。 |
| `MMGlass` | 玻璃材质（模糊 + 半透明 + 描边 + 外阴影），“降低透明度”时自动变为不透明。 |
| `MMEmptyState` / `MMProgressBar` | 空状态（图标、可选的标题与说明、操作按钮）与细进度条。 |
| `MMInteractive` | 所有可点击组件共用的悬停 / 按下 / 键盘焦点 / 语义处理（光标保持箭头）。 |
| `MMAppearance` | 向组件提供“降低透明度”“减少动态效果”。 |
| `MMIcons` | 统一图标词表，以 Cupertino 为主，补充 Lucide。业务组件只使用词表，不直接依赖第三方图标包。选区工具栏的脑图操作和顶部脑图视图切换共用 Lucide `network`（`network` / `layoutMap`），翻译入口统一使用 Lucide `languages`（`translate`）；文档切换使用 Lucide `book-open`（`collections`）。阅读器缩放入口使用 `zoomControl`（`plus_slash_minus`），菜单项实际大小为正方形、适合宽度为横向双箭头、适合页面为页面矩形；裁边独立使用 `crop`，不与适配复用图标。 |

同一区域同时支持单击和双击时，使用 `immediateTap`：首击立即执行，第二击识别双击。文本阅读区域可复用 `MMImmediateTapGestureRecognizer`，拖动、长按仍由各自识别器处理。若双击编辑与首击修改状态冲突，应恢复首击实际改动的状态；引用文字采用单击跳转、独立铅笔编辑入口。

运行应用后按 ⌥⌘G（或在“设置”里点“组件库”）可以在浅色/深色下查看所有令牌和组件。

### PDF 阅读配色

PDF 页面侧栏（缩略图／目录／书签／标注）以独立通高卡片呈现：四周 12pt 留白、16pt 圆角、细边框，内容裁切在圆角内；外层占位宽度不变，保留右侧拖动调宽。卡片顶部切换按钮整体居中，窄宽度时允许横向滚动。桌面顶部标签组在主工作区居中，两侧按较宽一侧预留相同空间；标签过多时保留滚动、重排和溢出菜单。

PDF 区域右上角的「PDF 操作」下拉菜单集中控制页面侧栏和阅读配色。`MMReaderStyle` 定义白色、黑暗、纸质、淡绿四套纸张/文字颜色，仅变换页面像素，保留标注颜色与原始导出内容。侧栏开关与阅读区宽度变化后适配页面宽度，保持阅读纵向位置。鼠标滚轮缩放脑图，Shift + 滚轮横向平移，触控板保留平移与捏合。

### 阅读工作区

窗口与顶部工具栏底层、PDF 页面周围和脑图画布共用同一个底色：浅色 `#FFFFFF`，深色 `#1E1E1F`。`windowBackground`、`readerBackground`、`canvas` 保留各自语义，取值来自同一底色常量；浮动玻璃控件叠在其上，PDF 纸张配色独立。

PDF 导航栏与阅读外观、缩放、标注工具分组展示。目录标题单行省略，悬停显示全文，页码右对齐。目录侧栏默认 240，允许在 180–360 之间拖动并保存；窄窗口至少为正文留出 240。打开目录默认收起学习集导航，用户可重新展开。脑图新增子节点按钮保持 32×32 屏幕点击区域，不随画布缩放；摘录目标使用独立文字提示。首次脑图按 100% 展示，“查看全图”允许缩小，“定位选中节点”恢复至少 100%。

脑图底部摘录目标提示为视图控制保留 `MMSizes.mapViewControlsReservedWidth`（380 pt，含“紧凑 / 完整”切换）空间，避免重叠。

阅读器：学习集导航和 PDF 页面导航独立开关；空间不足时仅收起分栏，不改变侧栏开关。缩放/适配收进图标菜单，外观使用统一图标入口。PDF 底部进度滑块仅在悬停或拖动时显示，拖动即时跳页；分割线底部提供收起左右区域的按钮，单栏边缘保留恢复分栏入口。

浮动玻璃控件与提示统一取消外部模糊阴影，保留半透明底色及细边框。PDF 缩放统一为单个双向箭头入口：菜单含居中默认的实时滑块、实际大小、适合宽度、适合页面；裁边为独立图标按钮，点击直接进入裁边编辑；页进度条使用中性灰色玻璃底与无阴影滑块。顶部操作组固定右对齐。

### 对照阅读 · 贴线浮控（2026-10-29）

按用户最新选择，仅将中间分隔改为「贴线浮控」（方案 2），下拉菜单和工具栏仍沿用首稿规范。两栏之间只有 0.5pt 细线，正文各占剩余宽度的一半；同步与对齐放在分隔线底部的小胶囊内，距内容底部 28pt 并避开底部安全区，桌面宽 28pt，以覆盖方式显示，不为按钮另外挤出一列。胶囊使用 `glassOpaque`、14pt 圆角、0.5pt 细边、无外阴影；按钮 24×24pt、图标 14pt，纵向间距 2pt、四周内边距 2pt；选中只高亮图标，不加选中底色，悬停与按下沿用 `MMIconButton` 的中性反馈，蓝色链条表示同步开启。触摸按钮至少 44pt。文件标题单行省略，页码与操作按钮始终可见；AI 翻译对照只显示同步开关，不显示手动对齐。

### 右侧面板与卡片全文（P2-A3 / C01）

工作区右侧只有一个面板，显示“研究”或“卡片详情”其中一种，宽 `MMSizes.rightPanelWidth`（400）。在分栏布局下，从原文打开时收起脑图，从脑图打开时收起原文；窗口放不下侧栏、面板和当前内容时，先收起侧栏并把面板改为 `MMSizes.rightPanelNarrowWidth`（360），再按 `MMSplitView` 的规则收起一栏（`resolveWorkspaceLayout`）。关闭后恢复打开前的布局和侧栏；两栏一直挂载，缩放和位置不变，详情关闭后键盘焦点回到原节点。面板立即出现和消失，不做宽度动画，避免两栏在动画中途经过窄窗口回退。研究面板标题使用 `research` 色。

被截断的摘录卡片（原文超过 4 行或标题超过 1 行）底部显示“展开全文 / 收起”，原地展开，相邻节点让位；⌥空格 切换选中卡片。展开状态只属于本次视图，不写入文件，并作为 `MindMapRenderCache` 的测量键之一。⌘I、双击摘录或右键“显示详情”打开卡片详情：可编辑标题（笔记为正文）、完整原文、回到原文、复制、标签和复习状态。

### 研究（P2-R3）

研究的入口、按钮和选中状态与全局共用系统强调色；`research` / `researchTint` 为兼容名称。启动卡是锚在选区或节点旁的卡片（宽 440，`MMRadii.sheet - 6`），意图为四列网格，推荐项带系统强调色角标；方式是三等分的分段控件，不可用的方式置灰。研究面板从上到下是起点卡、可原地修改的问题、进度行（运行中显示阶段与“取消”，失败显示原因与“重试”）、三个视图（解答 / 资料 / 已摘取）和追问框；勾选的要点、引用编号（`researchTint` 底的小号数字）与原文摘录（衬线体、`research` 竖线）都在解答视图里。资料的读取状态用 `MMPill` 加状态色：已提取正文、已取得字幕为 `positive`，仅摘要、无字幕为 `caution`，读取失败为 `critical`，其余中性。

保存后，原文中被关联的文字画 1.5pt 的 `research` 虚线下划线（`MMPdfHighlight.dashed`），页面右侧边距出现 `research` 圆形标记（`marker`），点击弹出研究笔记卡片；脑图中的研究笔记卡片左侧为 3pt `research` 竖线，第一行“研究笔记 · N 个来源”，标题最多两行、正文最多两行（紧凑显示时只留标题一行），底部“查看全文与引用 ›”。右键菜单用 `MMMenuHeader` 给出“研究「节点」”分组。

### 脑图结构与配色（GUL-567）

脑图右上角“样式”按钮打开弹层（`MMSizes.mapStylePopoverWidth`，300 pt）：4 个结构缩略图（高 `mapStructureThumbHeight` 52 pt）和 6 个配色缩略图（高 `mapPaletteThumbHeight` 44 pt），名称只在 tooltip / semantics 中。悬停即预览、移开恢复、点击应用（一步撤销）；弹层打开时脑图让出弹层区域并缩放到能看到全图，Esc 或点击外部关闭。结构决定连线：思维导图为曲线，逻辑图为圆角折线，括号图在每组子主题前画大括号，树形图从父主题左下方竖线引出、横线接入子主题；树形图的添加子节点按钮在节点下方。

`MMMapPalette`（`system`、`rainbow`、`fresh`、`warm`、`morandi`、`ink`）每套有 `light` / `dark` 两个 `MMMapColors`：中心主题底色与文字、按一级分支循环的分支色、一级主题样式（`MMTopicStyle.fill` 填充 / `tint` 浅色底 / `outline` 描边 / `plain` 系统样式）、概要底色与文字。`system` 即现有外观（`rootNode` / `onRootNode`、`line`、`fill`）。分支色同时用于分支线和概要括号；摘录色条、高亮色和关联线不随配色变化。`tokens_test` 检查每套配色在两种外观下中心主题、一级主题和概要的文字对比度 ≥ 4.5:1。导出 PNG / PDF 使用同一结构和配色。

### 脑图导出（P2-C05）

统一导出表单使用 `MMSizes.mapExportSheetWidth`（560 pt）和 `MMSizes.mapExportPreviewHeight`（180 pt），格式、范围、外观和倍率沿用分段控件。预览和导出使用完整内容，不继承选择、缩放、折叠或编辑状态。透明背景保留卡片底色；研究笔记沿用 `research` / `researchTint`。

阅读底部导航：横向 1pt 细进度线，两端无底色箭头，页码单独居中浮在上方的小型半透明标签内。底部热区高 64pt；平时只淡显进度线，鼠标进入底部、键盘聚焦或拖动时显示完整控件。保留页码输入和拖动定位，减少动效/透明度遵循系统设置。浮动工具条与提示避开整个底部导航区域。

### 文本下划线

下划线设置栏使用现有胶囊工具栏，不显示组标题。三个常用色和更多颜色之后是分隔线、四个线型预览、分隔线和关闭按钮。颜色和线型只通过 tooltip / semantics 命名；按钮、色点、选中背景和尺寸跟随现有主题。`MMToolbarPreviewButton` 用于没有标准图标的视觉预览选择；`AnnotationLineStylePicker` 和 `UnderlineStyleToolbar` 在功能层组合它。共用的 `MMPdfAnnotationLinePainter` 保证预览与文档笔触一致。

内置浏览器地址栏使用 `MMSizes.browserAddress`（30pt）、`browserAddressTouch`（36pt）与 `browserProgressTrack`（2pt）；前置锁形 / 警告图标，底边为强调色加载线。侧栏临时条目通过 `MMSidebarItem.leading` 替换加载图标，`labelColor` 使用 `secondaryLabel`。

网页转换面板使用 `MMSizes.webConversionSheetWidth`（640pt）；预览宽 `webConversionPreviewWidth`（200pt）、高 `webConversionPreviewHeight`（260pt），compact 预览高 `webConversionPreviewCompactHeight`（300pt）。标题、格式分段与预览表达转换方式；快照始终保存。


### 流式阅读（GUL-576）

`MMReaderLayout`：正文 measure 680pt，对页每栏 spreadMeasure 600pt，正文可用宽度达到 spreadMinWidth 1000pt 时启用对页，spreadGap 64pt。左右 margin 48pt / compact 24pt；翻页 topInset 40pt / compact 28pt，滚动 scrollTopInset 36pt / compact 24pt；左右翻页 turnZone 各占 25%。页边列 marginColumn 220pt，阅读设置 settingsWidth 280pt。固定 EPUB 逐页预览使用 thumbnailWidth 112pt / thumbnailHeight 144pt；流式文档不显示缩略图。

`MMReaderTypography`：字号 `[13, 14.5, 15.5, 16.5, 18, 20, 22, 25]`，默认索引 3、手机索引 4；行距 `[1.6, 1.9, 2.2]`，默认索引 1；serif 为 Songti SC，sans 为 Noto Sans，回退沿用 MMTypography。纸色、正文色使用 MMReaderStyle；高亮与下划线使用 MMAnnotationColor，下划线绘制与 PDF 共用。导入完成的条目以 accentTint 强调 MMMotion.flash 时间。

选区在边缘停留 `MMMotion.selectionEdge`（600ms）后自动翻页；滚动模式每 `MMMotion.selectionScroll`（50ms）移动一个 `MMSpacing.xxxl`。触控选区柄热区使用 `MMSizes.touchTarget`。

固定视口的缩放以拟合页面为基准，范围 `MMReaderLayout.minZoom`–`maxZoom`（0.25–16），快捷键每次乘除 `zoomStep`（1.2）；适合页面、适合宽度和实际大小使用视口尺寸计算。

生词选区卡片使用 `MMSizes.vocabularyCardWidth`（360pt），已收录圆点使用 `MMSizes.vocabularyDot`（6pt）。
实心生词按钮文字使用 `MMColors.onVocabulary`（浅色白字、深色深字），保证 4.5:1 对比度。`MMButton.foregroundColor` 用于这种语义色填充。

### 生词本页面（GUL-596）

列表宽使用 `MMSizes.vocabularyListWidth`（340 pt）；宽度低于 600 pt 时与手机一致推入详情，返回保留搜索和筛选。音标朗读使用 `MMIcons.speaker` 与 `MMSpeech` 系统英／美语音（仅受支持平台显示按钮），词形原形固定保留。界面文案与分组依据 `design/prototype/vocabulary.html` 场景 10–11；重新生成仅更新义项，保留用户的行间释义、笔记及词形。

生词详情区块使用 11pt semibold 次级文字；例句卡片为 0.5pt 细边、10pt 圆角，原句沿用宋体，译文为 12pt 常规次级文字，来源与操作同一行。词形与添加输入框均为 20pt 高，删除按钮位于词形内部。

### 全文生词提示（GUL-597）

设置 → 阅读使用 740×420pt 紧凑窗口、176pt 侧栏，其他设置页保留 780×560pt。生词提示使用与阅读外观相同的左标签、右下拉设置行，三档为“关闭 / 仅下划线 / 显示释义”，菜单勾选当前值，不显示额外说明文字。效果预览与下拉行间隔12pt，与下方阅读偏好间隔24pt。效果预览随全局模式即时变化：关闭时仅显示例句，下划线模式标记 `curious`，释义模式同时显示行间释义；点线复用 `MMPdfAnnotationLinePainter` 和 `vocabulary` 语义色。预览为只读示例，不写入生词本。窄内容区或大字号时，预览标签改为上下排布，翻译方向保留窄栏换行布局。

命中卡片宽 `MMSizes.vocabularyHitCardWidth`（300pt）；行间释义使用 `MMSizes.vocabularyGlossSize`（10pt），最多 8 字，仅在行间空隙足够且不会与其他释义重叠时绘制。点线复用 `MMPdfAnnotationLinePainter`，线宽 1.5pt。已掌握使用 `secondaryLabel`。查词卡片词性标签圆角使用 `MMRadii.vocabularyPos`（4pt）、`quaternaryFill` 底色。提示和新增闪烁独立于正文、标注和截图导出图层。

### 脑图 AI 扩展想法（GUL-606）

草稿节点（`MapGhostNode`）与同标题主题同尺寸：`researchWash` 底、`MMSizes.mapDraftBorder` 1pt `research` 虚线（`mapDraftDash` 4 / `mapDraftDashGap` 3）、圆角 12；方向标签与页码 chip 高 `mapDraftTag`（16pt，圆角 `MMRadii.mapDraftTag` 4），方向标签为实心 `research` + `onResearch`。生成 / 审阅底部条高 `MMSizes.ideaBar`（40pt），下沿距脑图面板底 `ideaBarBottomInset`（64pt，避开视图控制和窗口 HUD）；调整菜单宽 `ideaAdjustWidth`（330pt）；扩展计划卡宽 `ideaPlanWidth`（420pt）、行高 `ideaPlanRow`（36pt）。弹层“扩展想法”区圆角 `MMRadii.ideaSection`（10pt），主按钮高 `ideaPrimaryButton`（34pt），方向 chip 高 `ideaChip`（22pt）。图标 `MMIcons.expandIdeas` / `groupParent` / `fillSiblings` / `adjust` 取自 Lucide。完整规格见 [mindmap-ai-expand-ui.md](mindmap-ai-expand-ui.md)。

### 学习笔记（GUL-588）

笔记正文使用 `MMNoteLayout`：正文宽 600、左留白 64（窄栏 20）、右留白 56、上下留白 30/120、块间距 12、引用色条 3、引用缩进 16；目录宽 150，仅在笔记面板至少 1000 时浮动。康奈尔线索栏 170，复习答案模糊半径 5。工具栏高 44。整理与导出面板宽 640/900，导出选项列 280、内容区高 520，范围不够时纵向滚动。

`MMNoteTypography`：标题 24/31、节标题 17/22、正文 14/24.5、宋体摘录 15/27.75、宋体上下文 14/26。颜色复用现有窗口、正文、划线色与黄色批注底色；笔记图标为 `MMIcons.studyNote`（notebookText），导出为 `MMIcons.export`（download）。完整规格见 `docs/study-notes-ui.md`。

笔记窄面板的“更多”使用 `MMDropdownSubmenu` 级联目录与版式，再列“导出笔记…”；宽面板的目录/版式显示文字和下拉箭头，导出显示图标与文字。出处列表按文档身份合并，PDF 页码去重排序，文本文档不重复列出；摘录来源带定位图标和章节 tooltip，批注来源带页码或节点标题。

学习笔记 AI 整理沿用 `research` / `researchTint` 和 `onResearch`；
`MMSizes.noteProgressSheetWidth` 为 820，`MMNoteLayout.aiRule` 为 2。
提纲排序把手使用 `MMIcons.grip`，重新整理使用 `MMIcons.regenerate`。

### 学习笔记分享卡片

`MMShareCardTheme` 固定使用纸张 `#FBF7EE / #2B2A27`、简洁 `#FFFFFF / #1D1D1F`、
夜读 `#1C1C1E / #F2F2F7`，不随系统外观变化。`MMShareCardStyle` 的宽度 330、内边距 24、圆角 14，
标题 18/700、正文 12/1.7、摘录宋体 13.5/1.8、金句宋体 20/1.7、脚注 10。
分享面板宽 860，选项列宽 250；导出 PNG 为卡片的 2×。
预览舞台的卡片阴影为 `MMShareCardStyle.previewShadow`（0/6/24，黑色 14%），不烘焙进导出的 PNG。
笔记栏宽度低于 `MMNoteLayout.exportLabelMinWidth`（720）时，导出按钮只显示图标和提示，给 AI 操作与分享入口留出空间。

### 工作区标签内容页

侧栏顺序为文档、脑图、笔记、学习、卡片（有搜索结果时）、标签（有标签时）。标签默认展示至多 10 个，更多通过展开 / 折叠查看；每个标签旁显示当前脑图中关联的节点数。标签导航使用 `MMSidebarSelectionStyle.accent`：`accentTint` 底、正常正文色，与文档的中性选中区分。

点击标签后，右侧脑图区域显示独立的标签内容页，原文不跳页；标签不会改变侧栏的卡片搜索。页头为返回脑图、标签名和“相关节点 · 当前脑图”。结果采用普通列表与 `hairline` 分隔线，显示节点类型、标题、从脑图开始的上级路径和“在脑图中查看”。主题使用 `network` 图标，避免用新增主题的加号表示已有内容。标签标题使用 `title3`（15pt），结果标题为 `headline`（13pt），数量和路径为 `footnote`（11pt），操作为 `callout`（12pt）；标签图标20pt，结果图标14pt / 容器28pt，图文间距12pt。颜色沿用 `MMColors`，与工作区既有文字密度保持一致。

返回按钮或 Esc 关闭标签页，保留原脑图视野；点击结果则返回脑图，展开上级并定位节点。切换脑图或打开学习笔记时退出标签页。标签被移除后，已经打开的内容页显示空结果，仍可返回。窄窗口省去结果行上的文字操作，仅保留箭头和完整的辅助功能名称；长标题、路径最多两行，多结果独立滚动。

### Foliarc 品牌与应用图标（2026-10-31）

应用展示名称为 Foliarc；B「翻页」是默认图标，A「书叶」与 C「折纸 F」为可选图标，三款共用同一名称。设置 → 通用 → 应用图标提供带预览的三选一控件；选中状态使用边框和背景，不显示额外对勾或常驻说明，支持键盘与辅助功能；设置页不提供组件库入口。切换期间暂停重复操作，系统确认成功后再保存；失败保留原选择并显示重试提示。

macOS 切换 Dock 图标，每次启动恢复选择，不修改已签名应用包；访达中使用默认 B。iOS / iPadOS 使用系统备用图标接口切换主屏幕图标，启动只读取系统当前图标，不弹出更换确认。Android、Windows 和 Web 更新默认图标与展示名称，Linux 更新窗口标题；这些平台暂不展示运行时图标切换入口。原有 Bundle ID、包名、数据路径、钥匙串与内部通信标识保持兼容。Windows 的内部 ProductName 保留原值，因为现有数据和偏好设置使用它定位目录；窗口标题和 FileDescription 显示 Foliarc。

图标母版位于 `apps/marginmind/assets/icon/masters/`；`tool/icons.sh` 只做平台遮罩、留白与尺寸导出，不重绘母版。Flutter 只打包三张 192px 设置预览，避免携带完整母版。

### iPhone 与 iPad 共享组件（2026-10-31）

`context.mmTouchPlatform` 决定手机和平板共用的组件外观：15pt 正文字号、32pt 按钮视觉尺寸与至少 44pt 独立触摸区域、相同圆角与选中状态，以及不透明的工具组、菜单和底部面板。`context.mmTablet` 仅用于平板专属的分栏、面板位置等布局判断；不能用它排除手机的共享样式。文档正文和脑图内容仍使用 `mmContentText`，不跟随界面字号调整。

手机使用单栏；compact 阅读页使用下述共用位，其余布局保留底部工具栏。设置分类按内容宽度横向滚动，选中分类自动露出，标题行常显关闭按钮；极窄或大字号下，设置行改为上下排列。非手机 compact 阅读页的页码、进度和前后页合并为与 iPad 相同的单行胶囊；内容区不足 240pt 时先隐藏进度条，保留页码输入和前后页按钮。手机也使用触摸选区手柄。裁边建议不覆盖正文，裁边功能仍在工具菜单内。脑图样式弹窗以当前面板坐标限制左右边界，横屏空间不足时内部滚动。

模拟器截图检查与复现命令见 `docs/evidence/phone-adaptation/README.md` 和 `tool/capture_mobile_ui.py`。

### 手机重设计基础（GUL-630）

`MMLiquidGlass(phoneStyle: MMPhoneGlass.regular)` 显式选择手机原型材质，`thick` 用于厚底面板。业务接入仅在 `MMInput.of(context).phone` 且 `MMSizeClass.of(context) == MMSizeClass.compact` 时使用；旧构造、MMGlass 和 iPad/macOS 默认外观不变。Gallery 的控件页提供两种预设及不透明退化预览。

regular 使用 10pt 模糊、1.9 饱和度、1.03 亮度；thick 使用 28pt、1.8、1.0。浅深色底、边缘高光与阴影来自 `MMPhoneGlass`，顶部径向高光近似原型 CSS 椭圆光斑。嵌套玻璃只染色，降低透明度与 flat surface 不进行背景过滤，降低透明度强制不透明底。

`MMSizes` 新增 phoneTabBarHeight 64、phoneTabBarHorizontalInset 22、phoneTabBarBottomInset 26、phoneTopControl 44、phoneToolOrb 50、phoneToolBarHeight 56、phonePageCapsuleHeight 36、phoneDrawerWidth 328、phoneSheetPadding 8。`MMRadii.phoneTabBar` 为 32，`phoneSheet` 为 38；`MMMotion.phoneAnnotationCollapse` 为 650ms，`phoneSelectionCollapse` 为 500ms。36pt 页码视觉必须外包至少 44pt 热区，底部距离与安全区取最大值；具体控件负责本地化语义与焦点。

交互模型、所有权与滑动物理方案见 `mobile-redesign-arch.md`；视觉源为 `design/prototype/mobile-redesign.html`。

### 手机导航（GUL-632）

仅 `MMInput.phone && compact` 使用 `MMPhoneNavigation`：标签栏 64pt、左右 22pt、底部 `max(26pt, safeArea.bottom)`，图标尺寸与图标/文字间距分别由 `tabIconSize`（20pt）、`tabLabelGap`（2pt）定义，regular Liquid Glass 材质；透镜以 420ms 回弹曲线滑动。选中透镜局部使用不透明底色，强调色按背景亮度调整至至少 4.5:1，彩色封面仍从其余玻璃区域透出。降低透明度与减少动态效果沿用 `MMAppearance`。

`MMPhoneDrawer` 全高，宽度取 328pt 与屏宽 85% 的较小值（`drawerWidthFraction`）；320pt 窄屏仍露出 48pt 正文/遮罩。资料库及学习集均使用此抽屉，背景沿用页面颜色，外部遮罩黑色不透明度 40%。左边缘右滑打开，向左拖动、点击遮罩、系统返回或无障碍关闭动作收起。`MMPhoneNavigationGroup/Row` 使用 14pt 分组圆角、46pt 最小行高（动态字号可增长）、15.5pt 正文，分组标题用次色。仅复习数量使用 `caution`，卡片数量用次色；学习笔记显示箭头、无计数。学习与标签组不显示 +；笔记展开后保留新增入口。标签默认预览十项，支持展开/收起并保留当前选中项。搜索隐藏无匹配分组，全部为空时显示既有空状态。抽屉背景浅色 #F2F2F7 / 深色 #0E0E10。`MMPhoneReviewProgress` 以分段条表达复习位置，大队列按可用宽度合并段，进度语义使用应用传入的本地化百分比；手机评分按钮高 58pt。iPad（含 compact 分屏）、桌面和非 compact 手机保留旧路径。

### 手机阅读控件（GUL-631）

仅 `MMInput.of(context).phone && MMSizeClass.of(context) == MMSizeClass.compact` 启用三组悬浮玻璃顶部控件和底部共用位。顶部“阅读 / 脑图”使用滑动透镜；下读隐藏、回滚或正文单击显示，工具保持选中不阻止沉浸，实际选区、滑块、菜单、键盘和无障碍状态保持顶部可达；画笔/框选仅保持当前显隐，不因落笔唤回顶部。

`PhoneReaderSlot` 的 page / orb / tools / scrub 四态互斥：选择工具时默认页码；恢复已选标注工具或切换文档后显示工具球，保留工具图标、颜色点与强调色描边。更多菜单提供工具和跳页入口。650ms 完成收回与 500ms 选择工具收回使用既有 `MMMotion` 令牌。画笔颜色条同时提供颜色、笔宽、笔形与橡皮擦，采用两行以保留 44pt 热区；线型、自定义颜色、撤销和完成仍在更多菜单，菜单内状态实时更新，阅读纸色保留选中勾。后续由 GUL-633 替换面板。

`MMPhoneReaderLayout` 对应原型 CSS：水平 inset 14、模式切换宽 170（窄屏可收缩）、底边 24、顶部 inset 4、组间距 10、scroll-edge 64 / 沉浸 6（均从状态栏安全区下方测量）、scrubHeight 74、colorHeight 46、progress 14、工具色点 8 / 球色点 10、toolInset 6、scrubInset 18；工具栏圆角使用 `MMRadii.phoneReaderToolbar` 28。工作区继续使用 flat 材质，仅新控件的外壳通过局部 `MMFlatSurface(enabled: false)` 渲染玻璃，内部按钮恢复 flat 继承以保证其弹出菜单仍为 flat。底部距离与原始安全区取最大值，36pt 页码包在至少 44pt 热区中。50pt 球左右拖动停靠，本机偏好保存停靠侧；切换文档重置瞬态控件并取消旧计时器。

四态互斥优先于原型默认同时显示页码与工具球的示意。流式文档胶囊显示当前章节内页码，进度环和滑块仍覆盖全书；固定 EPUB 按源页面导航。原型已有上述几何值，无需改变视觉源。Linux 的 393×852 浅深色 golden 证据及复现命令见 `docs/evidence/gul-631/`。

### 脑图生成起始页（方案 3）

空脑图以“从资料生成脑图”作为标题，真实资料标题独立显示为系统强调色描边主题节点，来源显示保存的网页域名或文件格式。节点右侧的＋与底部“新建空白主题”共用手动新建行为。`MMSizes.mapEmptyStateWidth` 为620pt；来源节点最大320pt、最小224×76pt，长标题两行省略并保留全文提示。补充要求表单标明选填，底部分隔出设置与生成按钮，下面是三条可切换的要求建议。窄窗使用较短间距并可纵向滚动；触控标签至少44pt。AI实心按钮使用research/onResearch配色。设计及实际渲染对照见 `docs/evidence/map-empty-canvas/design-qa.md`。

研究笔记的 PDF 页边图标：桌面悬停不显示笔记，点击后立即打开笔记卡片；移开鼠标不自动关闭。Esc、点击外部或切换文档关闭卡片。触屏保留点击/长按与页面滑动。

桌面工作区顶部主栏高 44，内容工具栏高 40；仅压缩上下留白，按钮样式与触屏端尺寸保持不变。

### 网页保存到资料库弹窗（2026-11-01）

网页保存沿用 `MMSheet`，最大宽 1080pt。手机上主操作在标题行右侧，表单、预览和整理进度用一层分段切换，不叠放；详见 [网页 AI 整理](web-ai-format.md)。可用内容宽至少 720pt 时使用左右分栏：左侧正文预览约 65%，右侧为单行文档名称和纵向格式选项。预览高度随窗口变化，介于 220–600pt；窄窗上下布局保留 300pt 预览。正文使用 15pt、1.75 行高，展示真实网页标题、来源、段落与图片；允许滚动但禁止系统绘制滚动条。名称始终单行、长标题横向编辑。标题为“保存到资料库”，不显示副标题或格式说明，底部取消和保存保持可见。最新设计对照见 `docs/evidence/web-conversion-split/`。

网页保存的 PDF 预览直接读取文档包中的原始 PDF，使用 `MMPdfDataPreview` 按需渲染全部页面；分辨率跟随栏宽与屏幕像素密度，禁止用首页缩略图放大替代。保留无滚动条的纵向浏览。验证见 `docs/evidence/web-pdf-preview/`。

### 桌面设置按钮与无正文确认框（2026-11-01）

设置窗口通过 `MMButtonTheme(radius: MMRadii.field)` 将桌面文字按钮统一为8pt圆角，与确认框一致。字号、字重、按钮高度和触控平台原有按钮样式保持不变，其余页面不受影响。

`MMSheet` 的 `child` 可省略，用于仅有标题和操作的确认框：标题到操作为20pt，不再为不存在的正文预留额外20pt；桌面上下内边距为20/16pt，较原来整体减少26pt。有正文的弹窗保持原布局。AI功能未保存确认和清理网页数据确认采用此形式。

### 手机弹窗统一（2026-11-03）

底部弹窗标题区统一不显示 ×。`MMModalCloseButton` 在 `MMBottomSheet` 内自动隐藏，`MMPhoneSheetHeader` 默认不绘制关闭按钮；设置、阅读设置、翻译、图片预览、脑图生成/更新等共用此策略。通过下拉、遮罩、返回、Escape 或无障碍关闭退出，继续经过现有草稿保护。删除标签、移除附件、取消任务等内容操作不属于面板关闭。

设置属于完整浏览与编辑流程，手机打开时默认展开到安全区内最大高度（`phoneSheetExpanded`），不要求用户先上拉。普通短表单按内容显示，其他面板按用途选择初始高度；公共材质一致不等于所有窗口都用相同高度。设置分组使用 `card`，主底板使用页面背景，保持深色下底板较暗、分组略亮的层次。最新截图见 [设置高度与配色修正](evidence/settings-correction-2026-11-03/README.md)。

所有应用自有表单和面板共用 `MMModalSurface` 与 `MMModalStyle`：底色统一取 `MMColors.windowBackground`（浅色白、深色 `#1E1E1F`），不使用悬浮控件的亮灰玻璃退化色，完全不透明，只保留一层 `border` 细边框，不叠加模糊、高光或外发光。`MMBottomSheet` 和 `MMSheet` 负责接入，分享导入不维护独立材质。组件同时向内部控件及其弹出菜单传递 flat 样式，按钮聚焦采用清晰描边，分段选择不额外添加玻璃和阴影。iPhone 的原生表单、目录、操作与确认面板通过通道读取同一个 `MMModalStyle` 的颜色、边框和圆角；未保存内容的确认也沿用同一个原生容器。系统文件选择、分享和颜色选择器仍由系统负责。实际导入、设置、原生重命名及确认的深浅色运行验证见 [弹窗材质验证](evidence/modal-material-2026-11-03/README.md)。

独立表单、确认、设置和内容面板统一经过 `showMMSheet` / `showMMDialog` / `showMMBottomSheet`，使用 `MMBottomSheet` 的悬浮半屏与展开状态。iPhone 简单表单、目录和阅读菜单沿用 UIKit 系统 Sheet；复杂 Flutter 内容与安卓共用不透明的 `windowBackground` 背景和一层细边框，支持返回键和键盘避让。玻璃材质只用于悬浮操作控件，不用于承载长文本、菜单和编辑区。

手机容器四周留 `MMSizes.phoneSheetPadding`（12），避开底部手势区。初始高度按任务选择，见下表；比例相对于安全区与键盘之外的可用高度。横屏或键盘弹出时，可展开面板使用可用最大高度。iPhone 圆角 `MMRadii.phoneSheet` 与安卓 `MMRadii.androidSheet` 均为 28。短操作菜单按内容高度显示，子菜单在同一个容器内切换。选区颜色与划线工具条仍贴着原文定位，避开安全区和键盘；系统文件选择、分享、权限及原生颜色选择器遵循平台交互。

手机根级操作菜单直接显示操作列表，不绘制“添加”“更多”等重复标题及其分割线；触发按钮的名称仍保留在无障碍菜单标签中。进入子菜单后才使用 `MMPhoneSheetHeader` 显示返回按钮与具体标题；系统返回先回到上一级，再关闭菜单。两种 AI 面板继续使用共用标题栏，承载助手身份及会话操作。这些可下拉面板均不重复显示关闭按钮，从顶部下拉或点遮罩关闭；容器暴露无障碍关闭动作，返回与 Escape 继续生效。向下关闭时整体移动面板，不压缩标题和输入区。子内容不再绘制第二层面板外框。手机菜单的叶子行与子菜单行共用 52 点最小行高、20 点图标和正文样式，字号增大时允许内容自然换行。

手机资料库导航与学习集资料目录均从左侧滑出，露出当前页面作为返回位置；不绘制关闭叉号及“返回阅读 / 返回脑图”文字。点击外部、向左滑动或系统返回仅收起抽屉，保留原内容和当前布局；学习集顶部“资料库”按钮才离开工作区。目录中文档名称固定单行省略，通过长按提示或无障碍标签获取完整名称；分组与操作仍允许大字号自然增长，至少 44 点触摸高度。横屏键盘空间不足时整个目录可滚动。

初始高度规则（2026-11-04）：

| 类型 | 初始尺寸 | 选择原因 |
| --- | --- | --- |
| 完整 AI 对话、阅读目录 / 书签 / 标注、设置、图片预览、网页保存等完整工作区 | `phoneSheetExpanded`，安全区内最大高度 | 持续阅读或编辑，首次打开即获得完整内容区 |
| 卡片详情、选区翻译 / 查词、生词上下文 | `phonePreviewSheet`，75% | 需要较多内容，仍保留少量原文或画布上下文 |
| AI 快捷操作 | `phoneQuickSheetMedium`，70% | 临时选段任务，完整容纳操作和输入区 |
| 添加、更多、颜色预设、脑图样式、普通短表单及保存笔记 | 按内容高度，`expand: false` | 避免少量操作占据半屏；高度受安全区和键盘约束 |
| 原生阅读工具等紧凑操作 | UIKit medium，必要时可上拉 | 短时调整，保留原文；原生目录显式使用 large |

阅读导航在 iPhone 原生浏览与 Flutter 管理 / 回退路径中都直接铺在主面板，不再嵌套大圆角卡片。目录、书签、标注（PDF 另有缩略图）使用等宽纯文字标签页，中性文字与 24 点居中下划线表示选中；标签最小高 44 点，长英文或大字号时整组横向滚动，不换行。阅读目录正文左右留白 16 点，Tab 到列表留 8 点，每行至少 48 点，标题单行省略；章节行统一普通字重，不显示阅读当前位置的对勾、背景或“当前”标记；点按才显示反馈。子级缩进 16 点、最多占四层宽度。阅读导航顶部不绘制文档名或独立标题栏，把手后直接显示 Tab；原生浏览的“管理”与 Tab 同行，管理界面仅保留 Tab 和必要编辑操作。文档名作为无障碍上下文保留；与文档名相同的起点根条目从导航中省略，子章节提升一级，原始目录和锚点保持不变。手机编辑操作栏不重复显示“目录 / 书签”小标题，使用“添加目录项 / 添加书签”动作及排序入口。旧 Markdown 平面目录依据已保存的标题级别恢复显示层级，不改写原始目录、正文或锚点。手机 PDF 目录保留用户手动展开 / 收起状态，不随正文翻页自动展开或强调章节。无关闭按钮；原生浏览保留“管理”入口，管理面板保留内容编辑操作。`MMModalContent` 让复用的浮动内容在已有底部面板内只输出内容和内边距，避免重复外框；独立桌面浮层仍保留自己的材质。

手机 AI 输入区使用 `MMRadii.phoneComposer`（16）和一层细边框；输入框及推荐操作到面板左右边界的内缩均为 8，快捷输入不再为无意义的侧边栏入口占位。引用条不再套独立底色；底部仅一行：更多选项、可伸缩的模型选择、语音、发送。提及与联网收进更多选项。空对话沿用上方推荐操作，避免在输入区重复绘制。手机推荐操作采用平面列表，主行显示完整动作名，长主题引用放在次色单行辅助文字中，避免动作被引用挤掉。快捷操作的滚动区填满剩余高度，使半屏、展开及键盘状态下的输入框始终贴近面板底部；关闭后重开保留草稿。

手机脑图列表以正文为主，来源移至下方，同一来源连续出现时只显示一次。缩进步长 16，最多占 3 层缩进宽度，正文预览最多 3 行；列表视口避开顶部导航和底部工具栏。列表工具栏收成居中的三个操作，不再显示画布缩放控件。节点、多选与列表工具栏统一为实色 `surface`、24 点圆角和 0.5 点边框。摘录底色透明度为 8%，手机不显示伸出节点边界的来源浮签。手机定位优先将选中节点及直接可见子节点放进可用画布；低于 0.6 倍时保留当前缩放并居中选中节点，避免文字过小。资料库继续学习标题和网格标题均允许两行，待复习角标使用实色底。继续学习使用可增长的列表卡片；窄屏或大字号下，待复习数量与进度改为上下排列。数量角标根据实际字号确定高度，阅读页码在可伸缩区域内单行省略，避免 320 点、150% 字号溢出。

手机“问助手”工具栏使用 `AssistantIcon`，跟随用户的助手颜色设置，与面板标题及顶部入口一致。资料库首分区前置留白为 28 点，并在真实运行中检查搜索区域底边到“继续学习”标题的实际距离，避免只检查组件自己的 padding。

## 手机导图交互

轻点节点显示固定底部操作栏；长按只拾起节点用于结构拖动，拖动期间隐藏操作栏；完整菜单由“更多”按钮主动打开。选中态的节点栏替代视图工具栏，不能叠放。父子高亮、同级插入线和底部说明必须与最终落点一致，取消或空白松手不改结构。详细规则见 [手机导图交互](../design/phone-map-interactions.md)。

手机导图的多选使用独立临时模式：点选补充、单指画框、四角调整、边框平移、双指移动／缩放、屏幕边缘自动平移。选择框松手后保留；数量和候选高亮实时一致；取消不覆盖原选择，完成才提交。选择模式暂停节点结构拖动与编辑，旋转屏幕保留临时选择。详见 [手机导图选择](../design/phone-map-selection.md)。


### 系统分享导入（GUL-659）

导入目标面板复用 MMSheet、MMSegmentedControl、MMSearchField 和 MMButton。iPad 居中宽度使用 MMSizes.incomingShareSheetWidth（500pt）；手机按内容高度显示，让目标列表首次打开即可见。目标行至少 44pt，选中行使用 accentTint，当前/最近学习集优先。预览使用 quaternaryFill 与 card 圆角；间距、颜色和字体均来自既有令牌。手机主操作在标题右侧，iPad 主操作在底部。搜索无结果时禁用导入，保留新建入口。规范稿见 design/mobile-quick-entry.html，浅色/深色界面证据见 docs/evidence/gul-659/。
