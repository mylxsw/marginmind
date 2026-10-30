# 工作区布局技术架构（GUL-611）

本方案供 GUL-613、GUL-614 串行实现；本 PR 只交付文档，方案验收后才改产品代码。不新增业务数据、数据库迁移或服务端 API。

基线：`main` 的 `31589e4`；设计输入：PR #132 的 `design/gul-609-layout-density`（本次读取 `69490ab`）中的 `docs/layout-density.md`、`design/prototype/layout-density.html`。GUL-610 正在补充扁平化规格。旧说明里的“玻璃、半透明”不作为实现要求：采用纯色填充、0.5pt 分隔线，不使用模糊、渐变、外投影。具体颜色、圆角与尺寸以 GUL-610 合并后的令牌表为准；下文新增 API / 令牌均为提案，不能当成现有代码引用。

输入差异处理：旧原型按固定宽度把框选/画笔收纳、竖屏脑图表头不隐藏，并多放一个定位按钮；本方案遵循当前任务的测量收纳、触屏表头隐藏和底部缩放组要求，定位选中节点移入脑图更多菜单并保留快捷键。页面侧栏按钮原型常驻，本方案收进 Aa 以满足“只留标注工具”的要求。以上差异随本方案一起验收；若 GUL-610 最终规格不同，开发前由 GUL-609 负责人统一两份文档。

## 1. 总体结构与状态边界

保留 Flutter、Riverpod、现有阅读会话和 `mm_design`，不增加依赖。业务状态继续由 `workspaceProvider(studySetId)` 管理（当前文档、分栏选择、比例、脑图密度、助手面板等）；尺寸和显隐不写入持久化业务状态。

| 层 | 职责 | 所在位置 |
| --- | --- | --- |
| 几何解析 | 实际侧栏/助手占位、有效分栏模式、每栏矩形与表头矩形 | `workspace_layout.dart` + `MMSplitView` 共用几何函数 |
| 工作区组合 | 将原文、脑图或笔记表头与全局动作装入对应矩形 | 新 `widgets/workspace_toolbar.dart`、`workspace_screen.dart` |
| 原文命令 | 标注、Aa、切换文档；调用原有阅读会话 | 新 `widgets/reader_toolbar.dart`、`reader_pane.dart` |
| 脑图命令 | 脑图/大纲、样式；变换和选区继续归 MapPane | `map_header.dart`、`map_pane.dart`、`map_style_popover.dart` |
| 触屏 chrome | 本窗口的隐藏/显示、锁定原因、滚动基线 | 新 `workspace_chrome_controller.dart` |
| 通用外壳 | 安全区、拖窗、统一材质、测量收纳与命中 | `mm_design`，不读取业务 provider |

不把 PDF controller、脑图 TransformationController 搬入持久化 provider。新增工作区局部的 `WorkspacePaneChromeController`（ChangeNotifier，由 WorkspaceScreen 创建/销毁，通过 scope 传递）：ReaderPane / MapPane 绑定各自的命令适配器，表头监听可用性与选中态，并调用适配器；初始化前显示禁用命令，dispose 时解绑且按实例校验，避免旧文档解绑新会话。适配器只暴露命令和只读状态，不暴露 RenderBox、BuildContext 或 Widget 缓存。

原文适配器覆盖 zoom/fit、阅读设置、标注模式、裁边和文档能力；脑图适配器覆盖视图、样式、fit/zoom。应用层动作（打开文档、布局、助手、整理笔记）直接使用原 controller。这样提取工具栏后仍操作当前会话，不依赖 GlobalKey 访问私有 State，也不用重复创建 reader。

## 2. 一行工具栏与共享几何

### 几何契约

新增不可变 `MMSplitGeometry`，由 `MMSplitView.resolveGeometry(...)` 返回：effectiveMode、axis、primaryExtent、secondaryExtent、dividerExtent。输入为实际内容 extent、mode、fraction、两栏最小 extent、collapseWhenNarrow。保留现有主栏计算与窄屏缩放行为，但把计算从 build 抽成唯一实现；表头与正文消费同一结果。分隔槽保留现有 1pt 占位，在槽中心画 0.5pt 线；不要把拖动命中区宽度当成占位。

`WorkspaceLayoutGeometry` 组合 split geometry 和实际 sidebarExtent、panelRect、contentRect、readerRect、mapRect、headerRects。sidebar 的动画每帧实际宽度、iPad 助手 8pt gap、桌面 panelWidth 均参与计算。先解析外部侧栏/助手，再用剩余内容宽度计算 split，禁止表头拿整个窗口宽度乘 splitFraction。保留 `resolveWorkspaceLayout` 的助手 preservePanes 和 `resolveTabletWorkspaceLayout` 的横竖屏策略；不因软件键盘变矮而判定设备旋转。

在 `MMWindowScaffold` 内、侧栏占位之后增设 `contentBuilder(context, constraints)` 命名构造入口，与原 toolbar/body 入口互斥。新入口由工作区一次构造整个表头+正文+助手布局；scaffold 仍负责 drawer、sheet、安全区、窗口 chrome，不能再额外包一条旧 toolbar。工作区内部用一个布局 delegate 分配以上矩形。既有页面保持原构造入口。

| 场景 | 表头放置与动作归属 |
| --- | --- |
| Mac / iPad 横向分栏 | 原文、脑图两段横排，分隔线 x 与正文相同；全局动作在脑图段末端 |
| 侧栏展开/收起/动画 | 以 scaffold 当前约束重算两段，表头与正文同帧更新；不能各做一份宽度动画 |
| 仅原文 / 仅脑图 | 可见栏占满 contentRect，只放对应工具及全局动作；隐藏栏 Offstage 且 ExcludeFocus，保留会话 |
| iPad 竖屏上下分栏 | 顶部原文表头带全局动作；脑图表头位于下半栏顶部，只含脑图工具。不是把两个表头硬挤在窗口最上面 |
| 桌面右侧助手 | pane headers 截止于 contentRect 右边，助手区域保留自身表头；其上不重复放脑图工具。若其他 panel 浮层显示则不减 pane 宽度 |
| iPad 助手 | 横向占位时两段宽度一起缩短；纵向占位时减少正文高度，保持原文/脑图 header 与自己的 pane 对齐；沿用 panel 自身独立标题和关闭动作 |
| 窄栏 / 大字号 | 按实际测量收纳，最后保留 Aa、切换文档、全局“更多”等必要入口；不强制切换用户布局来让按钮放得下 |

第一行保持 Mac/iPad 56pt（`MMSizes.toolbarHeight`），iPhone 新增 `phoneWorkspaceToolbarHeight = 50`；系统顶部 safe inset 只加一次。iPad 视觉控件与触控区域分别处理，维持至少 44pt 命中区，不把视觉 36pt 当点击范围。触屏内容在纯色表头下延展；Mac 同样使用 overlay 几何，滚动到首尾必须能完整露出内容。页边批注、裁边、OCR 进度、查找条属于上下文内容，不塞进永久 chrome，也不重复累计 toolbar 高度。

### 通用 API 兼容与窗口行为

- `MMToolbar` 保留现有 title 构造给资料库、复习、统计等；增加 `MMToolbar.content({required Widget child, required String semanticLabel, double height})`。工作区只走 content 入口，不再显示 title/subtitle，避免全仓强制删 title。
- `MMWindowScaffold` 新布局入口向子树提供 `MMWindowChrome`，并支持明确的 toolbarExtent / 可见进度；`MMChromeInsets` 的 top/bottom 表示当前可见遮挡（含安全区）。旧入口默认行为不变。触屏底栏与顶部的遮挡由同一个状态计算。
- 拖窗背景沿用 MMToolbar 的 sibling GestureDetector：按钮/菜单在其上方命中，空白处 pan 调用 `onDragStart`，空白双击调用 `onTitleDoubleTap`。不能将双击 recognizer 包在按钮祖先，避免 300ms 点击延迟。分割线拖拽在背景之上，不能拖动窗口。
- macOS 红绿灯只从 `MMWindowChrome.toolbarLeadingInset` 取值，第一段内部扣除；不能改变正文分隔线坐标，也不能两段各加 inset。侧栏动画收起开始就预留安全区域，展开完成后才释放，避免过渡期按钮盖住红绿灯。全屏沿用 `WindowChrome.showsWindowButtons` 行为。
- 不修改 AppKit 的 unified toolbar / 全屏转场机制；人工验证原生拖窗、双击缩放、全屏往返、红绿灯命中。web 模拟截图无法替代此项。
- `MMSplitView` 增加 `showModeButtons`（默认 true 保持其他调用兼容），工作区 false；保留拖动、双击 50:50 和键盘/语义调整。此期拖动只调整比例并受最小尺寸约束，收起通过工具栏完成；不增加未定义的越界折叠阈值。

## 3. 标题、文档切换与无障碍

当前 `DesktopWindow.initialize(title: ...)` 只设初始窗口标题，没有文档级更新。新增 `DesktopWindow.setTitle(String)`，通过已有 window_manager 的 setTitle 实现，非桌面 no-op；不必新增原生 method channel。在 app 层新增可替换的 windowTitle sink/provider，监听当前 route、学习集名、当前文档名，去重并按最新值串行提交，防止异步旧值覆盖新值。工作区标题为“文档名 — 学习集名 — MarginMind”（去除相同/空项）；无文档退到学习集，离开工作区恢复目标页面标题。Web 使用 Flutter Title 提供浏览器标题，桌面保持 hideTitle 但更新系统窗口名。

工作区根 Semantics 使用同一语义标题，控件各有本地化 label/tooltip，不放一个隐藏 Text 去占布局，也不在每次滚动播报标题。保留 `_DocumentSwitcher` 的 ID 选中逻辑并提取为可复用控件：菜单以 activeDocumentId 勾选、selected semantics；不能按标题匹配（同名文档）。文档关闭/删除后高亮实际 fallback 文档；空集保持导入入口；对照阅读时菜单明确作用于主文档，对照文档选择保留原入口。

## 4. 原文工具栏拆分和测量收纳

把 `_toolbar` 拆为 `ReaderToolbar`、`ReaderAppearanceMenu` 和 `DocumentSwitcher`，现有 `ReaderAnnotationTools` / `ReaderInkToolbar` 复用内部动作，不复制 PDF 与 reflow 两套命令。固定行排列：选择、高亮、下划线、画笔、框选；摘录同步；Aa；切换文档。Aa 容纳缩放/适配、阅读配色、页边批注、生词提示、对照阅读、裁边、阅读设置以及原 reader-more 未重复的动作。原目录/缩略图/书签入口迁入 Aa 的“目录与书签”，OCR 入口保留原能力判断，运行进度仍在阅读区上下文条显示。

新增通用 `MMAdaptiveToolbar`，每个 item 提供稳定 id、控件、溢出菜单表示与收纳优先级。同帧测量实际 RenderBox dry layout/布局尺寸（包括 localized text、TextScaler、44pt hit box、组间距、padding），先扣 leading/trailing 固定项和全局动作，再判断是否放得下。隐藏项不参与 paint、hitTest、semantics；不要用 Offstage 全部控件拼出双份可访问按钮。菜单由同一命令模型生成。

收纳顺序：先框选，后同步，均进入 Aa 并保留选中态；仍不足时画笔、下划线、高亮依次进入 Aa。只保留选择、Aa、切换文档仍放不下时，选择也进 Aa，文档切换可作为 Aa 内子菜单。全局工具先去文字 label，再把布局和整理笔记收进“更多”，助手优先保留；最终极窄约束允许单一更多菜单访问全部命令，不溢出、不换第二行。脑图段同样测量，脑图/大纲可降级为单个视图菜单。

不使用现有 `constraints.maxWidth >= 460` 决定工具是否存在，不新增按设备型号的断点。测量缓存若采用，键必须含约束、语言、字号、输入密度与命令集合；第一帧就应正确，不能靠 postFrame setState 反复试宽。禁用态继续使用 activeCapabilities、crop.editing、compare 等现有条件；移入菜单不能重新启用不支持的命令。resize 时关闭已收纳项的旧 anchor 菜单并恢复焦点到新入口。

## 5. 脑图表头、密度与底部

`MapHeader` 改为 controls / 可选 contextual commands 的测量布局，删除 title 槽和标题让位算法。常驻行只放脑图/大纲与样式；目前可见的 map command bar 属于上下文编辑动作，可移入样式旁的更多菜单，选区动作仍由 `MapSelectionBar` 承担，不丢失快捷键。StudyNoteView 占据副栏时显示笔记自己的动作，不显示脑图视图/样式，保留全局布局和助手入口。

`MapStylePopover` 增加 `density: MapDensity`、`onDensity: ValueChanged<MapDensity>`；紧凑/完整立即调用原有 workspace controller 的密度更新通路。structure/palette hover preview 不改变 density，Esc 只撤销预览，不回滚已明确点击的密度；大纲模式也能访问密度。数据模型和保存格式不变。

底部仅保留 fit、−、比例（点击回 100%）、+。摘录目标为独立的小同步标签，仅同步开启时出现，超长省略且提供完整语义；不再常驻说明句。不能把它计为另一组底部操作栏。

废弃 `MMSizes.mapViewControlsReservedWidth = 380` 及 map_pane 中 iPad 特例 460，改为测量缩放组的 bounds，使用 `zoomWidth + MMSpacing.s` 给同步标签/选择浮层避让。新增需要的组内 spacing、边距令牌，禁止把旧常量简单改成新的猜测宽度。`MapHeaderGeometry.toolbarTopInset` / fit viewport 使用统一 header 实际遮挡与 bottom exclusion rects，移除旧 header 的重复留白；不因每帧 chrome 动画自动 fit、重置 transform 或抢走选中节点。

## 6. 触屏滚动隐藏

新增 `WorkspaceChromeController`，生命周期归单个 WorkspaceScreen，通过 scope 提供给 panes，内部 ChangeNotifier/ValueListenable 即可，不存 settings，不跨窗口共用 family provider。它管理 visible/hidden、手势累计距离、当前 document/geometry 基线以及一组 hold 原因。动画 controller 由宿主 widget 管理，controller 只发目标显隐。

输入契约：`onUserScroll(delta, atStart, geometryKey)`、`reveal()`、`hold(reason)`、`release(reason)`、`reset(documentKey)`。使用逻辑像素累计，建议初值下行 24pt 隐藏、反向上行 8pt 恢复；方向改变重置累计，阈值放 motion/chrome 令牌并做边界测试。无滚动范围/顶部回弹不隐藏；程序化跳页、缩放、旋转、布局变化重建基线，不作为阅读滚动。

PDF 使用 `MMPdfController.scrollPosition` 和 `PdfScrollPosition.sameGeometry` 比较显示距离，接入已有 onViewportChanged，但必须结合用户滚动生命周期过滤程序化变换；若 PDF 适配层无法可靠区分，给 `MMPdfView` 新增可选 onUserScroll 回调，默认 null，不把全部 viewport 变化视为 scroll。reflow 在 `reflow_scroll_reader.dart` 的实际 ScrollNotification / scroll activity 层接入，只处理正文主滚动，不响应 Aa 菜单、代码块横向滚动或助手列表。分页模式无连续竖向滚动时维持可见，不用翻页动画猜滚动方向。脑图 pan/zoom 不触发隐藏，大纲真实纵向用户滚动可接入相同规则。

| 事件/状态 | 行为 |
| --- | --- |
| 触屏正文持续下行 | 顶部表头和本工作区底部控件一起隐藏；iPad 上下分栏两个 pane header 共用目标 |
| 上行或空白轻点正文 | 显示；轻点只在无链接/选区/绘制操作时处理，不能截获正文交互 |
| Mac、触控板输入的桌面窗口 | 始终显示；按 touchPlatform 判定，不因最近一次输入是触摸就启用 |
| 选区、拖选手柄、画笔、框选、裁边、查找/编辑 focus | hold 并显示；选择工具条不跟随隐藏，按实际 exclusion rect 避让 |
| 菜单、popover、侧栏、sheet 打开 | hold，保证 anchor 不移出屏幕；关闭释放对应 reason，不能清掉其他 hold |
| 键盘出现 | 顶部显示并 hold，底部操作条隐藏，依 viewInsets 抬升编辑内容；键盘关闭恢复可见且重置累计 |
| accessibleNavigation / 屏幕阅读器模式、键盘焦点在 chrome | 禁用自动隐藏，保持语义导航和可发现性 |
| reduceMotion / disableAnimations | 使用 MMAppearance.duration 得到零动画；显隐规则不变，避免滑动过渡 |
| 换文档/route、旋转、切栏 | 显示并重置；dispose 取消监听/动画，不延迟操作已释放会话 |

隐藏使用 clip + translation；完全隐藏时 IgnorePointer、ExcludeFocus、ExcludeSemantics。顶部安全区背景始终存在。`MMChromeInsets` 表示可见遮挡，用于浮层和末端可见性；正文 viewport 尺寸不随动画每帧变动，以免 PDF 自动 fit/reflow 反复重排。将文档首尾 clearance 与 overlay exclusion 分开：滚动布局保留稳定首尾 padding，控制条平移后中段直接露出更多正文；初始顶部若因隐藏调整 padding，必须保持阅读锚点且不得产生伪用户 scroll。选择浮层、页码胶囊、缩放组和 iPhone 工具条都使用同一可见遮挡，不遗留不可见占位或覆盖最后一页。

## 7. iPhone 与路由

`app/app.dart` 的 bottom-bar 条件从单纯 showsPhoneTabs 改为“phone compact 且 route 为 LibraryRoute / ReviewRoute / StatsRoute”。学习集 WorkspaceRoute 不注入 PhoneTabBar，Gallery / Vocabulary 也不注入；保留 MMWindowBottomBar scope 常驻，bar=null、extent=0，避免重建路由子树。资料库/复习现有标签导航仍可返回最近学习集。iPad 紧凑 Split View 仍按 tablet 逻辑，不能误判成 iPhone。

WorkspaceRoute 内顶部为侧栏、原文/脑图分段、助手、更多。原文/脑图是同一个 route 的 state.layout（primary/secondary），不新增 route、不 push 导航历史；手机上 split 的有效显示映射为 primary，不覆盖保存的桌面分栏偏好。分段切换调用现有 setLayout，隐藏 pane 保留页码、缩放、草稿和 undo。

拇指区工具条复用 ReaderToolbar 命令模型；脑图工具条提供大纲、样式和缩放。增加工作区局部底栏 slot，由 scaffold 统一 safe.bottom/viewInsets；禁止同时保留旧 map zoom capsule 或 reader 常驻工具条形成重复入口。正文页码导航继续可用但与底栏共享避让矩形。

资料库入口进入 `navigation.showLibrary()`；侧栏和顶部更多提供复习（`startReview(studySetId)`），更多保留整理笔记、生词本（`showVocabulary(studySetId: ...)`）及必要的资料库后备入口。学习集不存在/已删除时复习禁用并返回资料库。保留现有 Review 返回和 VocabularyRoute.returnTo 语义，不在布局任务中另改 AppNavigation.back。测试从更多进复习、再回学习集、从生词本返回以及系统返回，不把视觉分段切换变成导航返回步骤。

## 8. 扁平化与图标

选择工作区 scope 内的显式材质策略，避免直接全局改 MMGlass 使资料库/复习全部变样。新增 `MMSurfaceStyleScope(style: flat)` 与 `MMFlatSurface`；MMGlass、MMLiquidGlass、MMGlassBar 在 flat scope 直接返回纯色 surface，不进入 BackdropFilter / sheen / outer shadow 分支。默认维持旧行为，兼容其他页面。toolbar/group/dropdown/popover/floating toolbar/tab bar 使用统一 surface 工厂；弹到根 Overlay/Navigator 的菜单需显式传递捕获的 style（建议 scope 采用 InheritedTheme），不能因离开工作区子树漏回玻璃。

复用 `MMColors.card` / `windowBackground` 做不透明底色；quaternaryFill 若含 alpha，先与基础表面合成不透明色，不能直接让正文透出。hover、pressed、accentTint/accent 沿用语义令牌；0.5pt hairline/separator 区分边界；高对比设置保留现有强调方式。最终取值遵循 GUL-610；不为“扁平”增加用户偏好开关。

工作区自己的侧栏、助手、节点、摘录卡片、选区条、菜单和底部控件需检查直接使用 BoxShadow / gradient 的路径，scope 不会自动移除手绘装饰。节点/摘录用纯色填充和 1pt 描边。PDF/电子书内容自带图片、渐变不属于 chrome，不改变文档内容。其他页面只接受组件兼容性回归测试，不批量更新其视觉；后续全应用迁移另开范围。

在 `mm_icons.dart` 添加 `MMIcons.organizeNote = LucideIcons.notebookPen`；替换工作区 `toolbar-organize-note` 和 iPhone 更多里的同一动作图标，tooltip/快捷键不变。助手保留 `MMIcons.ai`（sparkles）及 research 色，不能全局替换 ai；生成图标字体子集的构建需确保 notebookPen 没被裁剪。

## 9. 测试与验收

本 PR 无运行时代码，不新建镜像实现的测试。实现 PR 必须按以下矩阵补测试；使用既有测试 harness / PDF backend，禁止吞掉 RenderFlex overflow 当成通过。

| 测试层 | 更新/新增文件与断言 |
| --- | --- |
| 几何单测 | `workspace_layout_test.dart`、`mm_design/test/split_view_test.dart`：比例极值、最小尺寸、助手 preservePanes、侧栏动画中间帧、竖屏/键盘、effective mode；表头和正文边界误差不超过 0.5 logical px |
| 表头 widget | `reader_chrome_test.dart`、`reader_layout_position_test.dart`、`map_header_test.dart`、`map_toolbar_layout_test.dart`：无可见标题、单行、删除/切换同名文档、对照阅读、笔记副栏、空文档、Aa 每项功能与能力禁用 |
| 测量收纳 | 新 adaptive toolbar 测试：中英、TextScaler 1/1.3/2、宽度临界前后、异步字体、44pt target；收纳顺序、所有动作可达、hidden semantics 消失、resize 菜单安全 |
| 密度/样式 | `map_style_test.dart`：density 在 popover、持久化、大纲可操作、preview 与 Esc；同步标签仅开启显示、测量避让不覆盖 zoom |
| 触屏状态机 | 新 `workspace_chrome_controller_test.dart`：24/8 边界、方向反转、hold 叠加、键盘、geometry reset、dispose；新 widget 测试以 PDF/reflow 用户滚动验证，程序化跳页和 map pan 不误触发 |
| 手机路由 | `phone_layout_test.dart`、`adaptive_layout_test.dart`：工作区无 phone-tabs、资料库/复习仍有、分段不改 route、返回与会话保持、键盘与安全区、iPad compact 不误用手机条 |
| 通用组件回归 | `toolbar_response_test.dart`、`immediate_tap_test.dart`、`tablet_chrome_test.dart`、`semantics_test.dart`、liquid_glass 测试：按钮立即响应、背景拖窗回调、flat scope 无滤镜/渐变/阴影、菜单继承、scope 外不变 |
| 系统标题 | mock window title sink：打开/重命名/切换/关闭文档、离开工作区、快速切换的最终标题；Mac 原生人工验证窗口菜单和 VoiceOver 名称 |

Golden：扩展 `toolbar_density_test.dart`、`map_style_screenshots_test.dart` 和工作区截图套件，Mac 1280×800、iPad 横/竖、iPhone 393×852，各浅/深主题；补侧栏收起、助手打开、单栏、工具溢出、触屏隐藏/恢复。先核对 GUL-610 视觉再更新快照，不批量接受未知差异；已有 GUL-612 的 Mac golden 修复是实现阶段前置条件。

每个实现 PR 运行 `flutter analyze`、`dart format --set-exit-if-changed apps packages`、`python3 tool/coverage.py`；该脚本运行全部包测试并检查合并行覆盖率 >=80%，不能以旧 lcov 或 report-only 代替。新增 controller / geometry 核心分支要求有正反例，改动代码目标 >80%。截图覆盖无障碍/大字号另加 widget 断言；原生窗口行为在 macOS 集成环境验证。仅文档 PR 的命令结果见 PR 描述，若基线失败必须如实列出，不把后续实现验收标准当成本次已通过结果。

## 10. 两个串行开发任务

### 开发任务 1：GUL-613 — Mac / iPad 一行工具栏与扁平化

前置：本方案和 GUL-610 视觉规格验收合并、GUL-612 恢复测试基线。先落通用布局/材质接口，再接阅读/脑图动作，最后更新截图；同一个 PR 保持可运行，暂不启用滚动隐藏和手机新条。

文件清单（新增名称为建议）：

- `packages/mm_design/lib/src/widgets/{toolbar,window_scaffold,split_view,glass,tab_bar,menu,dropdown}.dart`，新增 adaptive toolbar / flat surface scope 并通过 `mm_design.dart` 导出；`tokens/{metrics,motion}.dart`、`icons/mm_icons.dart`。
- `apps/marginmind/lib/features/workspace/{workspace_screen,workspace_layout}.dart`；新增 `workspace_pane_chrome_controller.dart`、`widgets/{workspace_toolbar,reader_toolbar}.dart`；修改 `widgets/{reader_pane,reader_annotation_tools,map_pane,map_header,map_style_popover,tablet_workspace_panes}.dart`，按需连接笔记副栏与节点/卡片装饰路径。
- `packages/mm_platform/lib/src/desktop_window.dart`；`apps/marginmind/lib/app/app.dart` 与新增 window title binding；本地化 ARB 和生成文件（只添加实际缺少的动作名，不增加解释文案）。
- 本节前述几何、表头、测量、样式、通用组件、标题测试及对应 goldens。

接口交付：共享 MMSplitGeometry / WorkspaceLayoutGeometry；MMToolbar.content；scaffold contentBuilder、明确 extent；局部 pane 命令适配器；MMAdaptiveToolbar；flat scope；MapStylePopover density；DesktopWindow.setTitle。后续任务只能消费这些入口，不再次移动 PDF/map controller。

验收：Mac/iPad 横竖屏一栏一行；拖动、侧栏动画、助手开关同帧对齐；无标题与分割线收起按钮；Aa 所有能力可达；密度搬迁、底部简化、图标区分；工作区含 Overlay 均扁平；原有其他页面不回归；截图、原生窗口检查、测试和覆盖率达标。

### 开发任务 2：GUL-614 — 触屏隐藏与 iPhone

前置：任务 1 合并。不另建第三个并行实现任务，以免两边同时改 scaffold 与 reader。

文件清单：新增 `features/workspace/workspace_chrome_controller.dart`、`widgets/phone_workspace_toolbar.dart`；修改 `workspace_screen.dart`、`workspace_toolbar.dart`、`reader_pane.dart`、`reflow_scroll_reader.dart`（必要时 `reflow_reader.dart`）、`map_pane.dart` / `outline_view.dart`、`workspace_sidebar.dart`；`app/{app,phone_tabs,navigation}.dart`（navigation 原则上只补测试，沿用既有路由方法）；`mm_design` 的 window_scaffold/chrome insets、motion/metrics；仅无法区分用户滚动时扩展 `mm_pdf/lib/src/pdf_view.dart` 的可选事件；相关 ARB 与上述触屏、手机、安全区测试/goldens。

接口交付：WorkspaceChromeController 输入与 hold 集合；用户滚动适配；顶部/底部共同显隐目标；按 route 判定 PhoneTabBar；手机底栏 slot。没有业务 schema 或 route 枚举变更。

验收：iPad/iPhone 下行隐藏、上行/空白轻点恢复；Mac 始终显示；选区、画笔、键盘、无障碍和 reduce motion 无互相干扰；手机一条顶栏+拇指条、学习集无 PhoneTabBar，资料库/复习/生词本及返回仍可达；PDF/reflow 不跳位置，地图不误隐藏；浅深色截图、全部测试和覆盖率达标。
