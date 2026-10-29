# 设计系统（mm_design）

规范来源：`design/canvas/Foundations.dc.html`（02 · 基础）与 `design/canvas/Components.dc.html`（03 · 组件）。代码中的令牌与规范一一对应；改值请两边同时改。

## 令牌

| 类 | 内容 |
| --- | --- |
| `MMColors` | 语义色（`ThemeExtension`），浅色 `MMColors.light` / 深色 `MMColors.dark`。`withAccent()` 套用系统强调色。研究专用色 `research`（浅色 `#5E5CE6`、深色 `#7D7AFF`）与 `researchTint`（12% / 20%）固定，不随系统强调色变化。状态色 `positive` / `caution` / `critical`（浅色 `#248A3D` / `#C93400` / `#D70015`，深色 `#30D158` / `#FF9F0A` / `#FF453A`，即系统绿 / 橙 / 红的高对比版本）用于状态文字，底色取自身 12%（如资料的读取状态）。 |
| `MMAnnotationColor` | 六种标注色（系统黄/绿/蓝/粉/橙/紫）。数据只存索引；`highlight`（32%）、`underline`（90%）、`cardTint`（14%）。 |
| `MMInkColor` / `MMInkWidth` | 画笔的六色（红/橙/黄/绿/蓝/墨黑，`stroke` 为 90% 不透明）与三档粗细（1.5 / 2.5 / 4，单位 PDF 点，随页面缩放）。数据只存颜色索引和点数。 |
| `MMTypography` / `MMTextStyles` | macOS 文本样式：title3 15、headline 13 semibold、body 13、callout 12、subheadline 11 semibold、footnote 11；阅读用宋体 16.5/32，摘录 13/20。 |
| `MMSpacing` / `MMRadii` / `MMSizes` | 4pt 间距；同心圆角（窗口 24 → 侧栏 16 → 行 8；胶囊 18 → 按钮 15；卡片 12 → 摘录块 6）；工具栏 56、侧栏 236、行高 28、浮动工具条颜色点 14（热区 26）、右侧面板 400（窄窗口 360）等尺寸。 |
| `MMMotion` | quick 150ms、standard 200ms、layout 320ms、flash 1600ms、hud 2400ms。 |

在代码里读取：

```dart
final c = context.mmColors;   // 颜色
final t = context.mmText;     // 已着色的文本样式
```

对比度：`test/tokens_test.dart` 会检查所有文字令牌在其所在背景上不低于 4.5:1（深色主题的次级文字因此比初版设计稿提亮为 `#AEAEB2`）。

## 组件

| 组件 | 说明 |
| --- | --- |
| `MMWindowScaffold` | 窗口骨架：可收起的悬浮侧栏 + 工具栏 + 内容；侧栏收起时工具栏自动给红绿灯让位。上方有 `MMWindowBottomBar` 时，在内容下方显示它提供的底栏（手机的 Tab），软键盘弹出时隐藏；`sheet` 盖在包括底栏在内的整个窗口上。 |
| `MMSidebar` / `MMSidebarSection` / `MMSidebarItem` / `MMCount` / `MMBadge` | 悬浮玻璃侧栏与 28pt 行。 |
| `MMToolbar` / `MMToolbarGroup` / `MMToolbarButton` / `MMToolbarDivider` / `MMToolbarSearchField` | 统一工具栏与玻璃胶囊按钮组；空白处拖动窗口、双击缩放。 |
| `MMSplitView` | 两栏 + 可拖动分隔线（8pt 热区、双击复位），隐藏的面板保持挂载，但不保留键盘焦点；窗口太窄时自动只显示主面板。 |
| `MMSegmentedControl` | 分段控件，选中段为白色浮起。 |
| `MMButton` / `MMIconButton` | 胶囊按钮（主要 / 次要 / 纯文本）与面板内小图标按钮；按钮文字放不下时以省略号结尾。主要按钮可用 `color` 换成功能色（研究用 `research`），纯文本按钮的 `color` 是文字色（设置里的 `accent` 链接、`critical` 的“移除服务”）；`MMToolbarButton` 对应的是 `tint`，选中时也保持 `tint`（打开的助手）。 |
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
| `MMIcons` | 图标词表（Cupertino 图标，注释里标了对应的 SF Symbol）。阅读器缩放入口使用 `zoomControl`（左上/右下双向缩放箭头），菜单项实际大小为正方形、适合宽度为横向双箭头、适合页面为页面矩形；裁边独立使用 `crop`，不与适配复用图标。 |

运行应用后按 ⌥⌘G（或在“设置”里点“组件库”）可以在浅色/深色下查看所有令牌和组件。

### PDF 阅读配色

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

研究的入口、按钮和选中状态一律用 `research` / `researchTint`，与选择用的强调色分开。启动卡是锚在选区或节点旁的卡片（宽 440，`MMRadii.sheet - 6`），意图为四列网格，推荐项带紫色角标；方式是三等分的分段控件，不可用的方式置灰。研究面板从上到下是起点卡、可原地修改的问题、进度行（运行中显示阶段与“取消”，失败显示原因与“重试”）、三个视图（解答 / 资料 / 已摘取）和追问框；勾选的要点、引用编号（`researchTint` 底的小号数字）与原文摘录（衬线体、`research` 竖线）都在解答视图里。资料的读取状态用 `MMPill` 加状态色：已提取正文、已取得字幕为 `positive`，仅摘要、无字幕为 `caution`，读取失败为 `critical`，其余中性。

保存后，原文中被关联的文字画 1.5pt 的 `research` 虚线下划线（`MMPdfHighlight.dashed`），页面右侧边距出现 `research` 圆形标记（`marker`），点击弹出研究笔记卡片；脑图中的研究笔记卡片左侧为 3pt `research` 竖线，第一行“研究笔记 · N 个来源”，标题最多两行、正文最多两行（紧凑显示时只留标题一行），底部“查看全文与引用 ›”。右键菜单用 `MMMenuHeader` 给出“研究「节点」”分组。

### 脑图导出（P2-C05）

统一导出表单使用 `MMSizes.mapExportSheetWidth`（560 pt）和 `MMSizes.mapExportPreviewHeight`（180 pt），格式、范围、外观和倍率沿用分段控件。预览和导出使用完整内容，不继承选择、缩放、折叠或编辑状态。透明背景保留卡片底色；研究笔记沿用 `research` / `researchTint`。

阅读底部导航：横向 1pt 细进度线，两端无底色箭头，页码单独居中浮在上方的小型半透明标签内。底部热区高 64pt；平时只淡显进度线，鼠标进入底部、键盘聚焦或拖动时显示完整控件。保留页码输入和拖动定位，减少动效/透明度遵循系统设置。浮动工具条与提示避开整个底部导航区域。
