# 设计系统（mm_design）

规范来源：`design/canvas/Foundations.dc.html`（02 · 基础）与 `design/canvas/Components.dc.html`（03 · 组件）。代码中的令牌与规范一一对应；改值请两边同时改。

## 令牌

| 类 | 内容 |
| --- | --- |
| `MMColors` | 语义色（`ThemeExtension`），浅色 `MMColors.light` / 深色 `MMColors.dark`。`withAccent()` 套用系统强调色。研究专用色 `research`（浅色 `#5E5CE6`、深色 `#7D7AFF`）与 `researchTint`（12% / 20%）固定，不随系统强调色变化。 |
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
| `MMWindowScaffold` | 窗口骨架：可收起的悬浮侧栏 + 工具栏 + 内容；侧栏收起时工具栏自动给红绿灯让位。 |
| `MMSidebar` / `MMSidebarSection` / `MMSidebarItem` / `MMCount` / `MMBadge` | 悬浮玻璃侧栏与 28pt 行。 |
| `MMToolbar` / `MMToolbarGroup` / `MMToolbarButton` / `MMToolbarDivider` / `MMToolbarSearchField` | 统一工具栏与玻璃胶囊按钮组；空白处拖动窗口、双击缩放。 |
| `MMSplitView` | 两栏 + 可拖动分隔线（8pt 热区、双击复位），隐藏的面板保持挂载，但不保留键盘焦点；窗口太窄时自动只显示主面板。 |
| `MMSegmentedControl` | 分段控件，选中段为白色浮起。 |
| `MMButton` / `MMIconButton` | 胶囊按钮（主要 / 次要 / 纯文本）与面板内小图标按钮；按钮文字放不下时以省略号结尾。 |
| `MMSearchField` / `MMTextField` / `MMFormRow` / `MMColorPicker` | 表单控件；Esc 清空搜索。 |
| `MMInlineTextField` | 原地编辑用的无边框文本框，随所在位置换行（`maxLines: 1` 时保持单行）；Enter 提交、Esc 取消，输入法组合期间这两个键交给输入法；`multiline` 时 ⇧Enter 换行。 |
| `showMMSheet` / `MMSheet` | 从工具栏下方落下的表单面板，Esc 取消。 |
| `MMHudHost` / `MMHud.show` | 窗口底部的提示胶囊。 |
| `MMFloatingToolbarSwatch` / `MMFloatingToolbarStrokeWidth` | 浮动工具条里的任意颜色点（`MMFloatingToolbarColor` 基于它）和粗细点（点的直径 = 粗细 × 2 + 2，选中为强调色底）。`MMToolbarButton` 可只有文字（`icon: null` + `label`），用于“完成”。 |
| `MMFloatingToolbar` / `MMFloatingToolbarColor` / `MMFloatingToolbarLayout` | 选区旁的横向玻璃工具条：图标按钮（`MMToolbarButton`）+ 颜色点，每项都有提示文字，Tab / 方向键移动焦点。定位用纯函数 `placeFloatingToolbar`：优先放在选区上方，空间不够放下方，左右超出时向内收，始终完整可见；锚点变化时跟随。 |
| `MMGlass` | 玻璃材质（模糊 + 半透明 + 描边 + 外阴影），“降低透明度”时自动变为不透明。 |
| `MMEmptyState` / `MMProgressBar` | 空状态（图标、可选的标题与说明、操作按钮）与细进度条。 |
| `MMInteractive` | 所有可点击组件共用的悬停 / 按下 / 键盘焦点 / 语义处理（光标保持箭头）。 |
| `MMAppearance` | 向组件提供“降低透明度”“减少动态效果”。 |
| `MMIcons` | 图标词表（Cupertino 图标，注释里标了对应的 SF Symbol）。 |

运行应用后按 ⌥⌘G（或在“设置”里点“组件库”）可以在浅色/深色下查看所有令牌和组件。

### PDF 阅读配色

PDF 区域右上角的「PDF 操作」下拉菜单集中控制页面侧栏和阅读配色。`MMReaderStyle` 定义白色、黑暗、纸质、淡绿四套纸张/文字颜色，仅变换页面像素，保留标注颜色与原始导出内容。侧栏开关与阅读区宽度变化后适配页面宽度，保持阅读纵向位置。鼠标滚轮缩放脑图，Shift + 滚轮横向平移，触控板保留平移与捏合。

### 阅读工作区

PDF 导航栏与阅读外观、缩放、标注工具分组展示。目录标题单行省略，悬停显示全文，页码右对齐。目录侧栏默认 240，允许在 180–360 之间拖动并保存；窄窗口至少为正文留出 240。打开目录默认收起学习集导航，用户可重新展开。脑图新增子节点按钮保持 32×32 屏幕点击区域，不随画布缩放；摘录目标使用独立文字提示。首次脑图按 100% 展示，“查看全图”允许缩小，“定位选中节点”恢复至少 100%。

脑图底部摘录目标提示为视图控制保留 `MMSizes.mapViewControlsReservedWidth`（380 pt，含“紧凑 / 完整”切换）空间，避免重叠。

阅读器：学习集导航和 PDF 页面导航独立开关；空间不足时仅收起分栏，不改变侧栏开关。缩放/适配收进图标菜单，外观使用统一图标入口。PDF 底部进度滑块仅在悬停或拖动时显示，拖动即时跳页；分割线底部提供收起左右区域的按钮，单栏边缘保留恢复分栏入口。

浮动玻璃控件与提示统一取消外部模糊阴影，保留半透明底色及细边框。PDF 放大/缩小常驻，实际大小/适配宽度/适配整页合并为带图标菜单；页进度条使用中性灰色玻璃底与无阴影滑块。顶部操作组固定右对齐。

### 右侧面板与卡片全文（P2-A3 / C01）

工作区右侧只有一个面板，显示“研究”或“卡片详情”其中一种，宽 `MMSizes.rightPanelWidth`（400）。在分栏布局下，从原文打开时收起脑图，从脑图打开时收起原文；窗口放不下侧栏、面板和当前内容时，先收起侧栏并把面板改为 `MMSizes.rightPanelNarrowWidth`（360），再按 `MMSplitView` 的规则收起一栏（`resolveWorkspaceLayout`）。关闭后恢复打开前的布局和侧栏；两栏一直挂载，缩放和位置不变，详情关闭后键盘焦点回到原节点。面板立即出现和消失，不做宽度动画，避免两栏在动画中途经过窄窗口回退。研究面板标题使用 `research` 色；研究入口（⌃⌘R、工具栏按钮）已注册，研究流程接通前不显示。

被截断的摘录卡片（原文超过 4 行或标题超过 1 行）底部显示“展开全文 / 收起”，原地展开，相邻节点让位；⌥空格 切换选中卡片。展开状态只属于本次视图，不写入文件，并作为 `MindMapRenderCache` 的测量键之一。⌘I、双击摘录或右键“显示详情”打开卡片详情：可编辑标题（笔记为正文）、完整原文、回到原文、复制、标签和复习状态。

### 脑图导出（P2-C05）

统一导出表单使用 `MMSizes.mapExportSheetWidth`（560 pt）和 `MMSizes.mapExportPreviewHeight`（180 pt），格式、范围、外观和倍率沿用分段控件。预览和导出使用完整内容，不继承选择、缩放、折叠或编辑状态。透明背景保留卡片底色；研究笔记沿用 `research` / `researchTint`。
