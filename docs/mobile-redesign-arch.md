# 手机端重设计技术方案（GUL-629）

状态：架构已批准（含 workspace_screen.dart 区块归属调整）。本方案基于仓库锁定的 pdfrx 2.10.1 源码。

## 范围与文件归属

新行为仅在 `MMInput.of(context).phone && MMSizeClass.of(context) == MMSizeClass.compact` 启用。不改变 iPad，包括 compact 分屏，以及 macOS 的默认路径。无持久化数据模型或数据库迁移。

下表路径以 `apps/marginmind/lib/features/workspace/` 为基准；新增文件标注“新增”。每个文件只由一项任务提交。

| 任务 | 独占落点 | 接入约定 |
| --- | --- | --- |
| GUL-630 基础 | `packages/mm_design/lib/src/widgets/glass.dart`、`tokens/metrics.dart`、`tokens/phone_glass.dart`、相关导出与测试；Gallery、设计文档和原型 | 扩展已有 MMLiquidGlass；不改业务页面 |
| GUL-631 阅读控件 | `widgets/reader_pane.dart`、`reader_toolbar.dart`、`reader_annotation_tools.dart`、`reader_page_field.dart`、`workspace_chrome_controller.dart`、`workspace_screen.dart` 的手机顶部 Stack 和 editing hold 区块；新增 `phone_reader_controls_controller.dart`、`widgets/phone_reader_controls.dart` | 底部共用位与顶部浮控；通过回调请求打开更多面板 |
| GUL-632 标签栏/抽屉/物理 | `workspace_screen.dart`、`widgets/workspace_sidebar.dart`、`packages/mm_design/lib/src/widgets/tab_bar.dart`；新增手机导航组件；`packages/mm_pdf/lib/src/pdf_view.dart`、新增 `phone_scroll_physics.dart` 与导出/测试 | 仅修改 workspace_screen 的 `_drawer`、`sidebarVisible`、MMWindowScaffold sidebar 参数；mm_pdf 暴露行为配置，不依赖 mm_design |
| GUL-633 更多面板 | 新增 `widgets/phone_more_sheet.dart`、`phone_reader_appearance_sheet.dart`；`reader_zoom_control.dart` | Stage 3 在前两项合并后，小范围修改 reader_pane/workspace_screen 接入入口；双击缩放若需改 pdf_view，也只在 Stage 3 接入并明确列入 PR |

GUL-631/632 按上述互不重叠区块修改 workspace_screen，GUL-631 自行接线并端到端验证顶部控件与沉浸模式；后合并的一方负责 rebase。共享 ARB 采用 `phoneReader*`、`phoneNavigation*`、`phoneMore*` 前缀分别归属三个任务，各自生成本地化文件并在合并时 rebase；不复写其他前缀。本任务 Gallery 新文字使用 `phoneGlass*`。

## 底部共用位

瞬态模型：`PhoneReaderSlot { page, orb, tools, scrub }`，单个枚举决定渲染，禁止多个布尔开关同时显示。`selectedTool`、每种工具颜色和球的左右位置独立于 slot；收起不取消已选工具。标注工具沿用 workspace 现有状态，控制器不复制持久业务数据。

| 事件 | 转换与副作用 |
| --- | --- |
| 打开文档 | page；撤销旧计时器，显示顶部 |
| 点击页码 | page → scrub；暂存当前页，拖动预览并实时跳页 |
| 顶部工具入口 | 任意 → tools；结束 scrub，取消收起计时器 |
| 点击工具球 | orb → tools；显示原选工具和颜色 |
| 选择工具或颜色 | 保持 tools；更新业务工具，取消过期计时器 |
| 标注/画笔完成 | 重置 650ms 计时器；到期 tools → orb，保留工具 |
| 关闭工具栏/点击正文 | tools → orb；正文点击同时 reveal 顶部 |
| 阅读滚动 | tools → orb、scrub → 返回态；正在画笔/框选/拖滑块时不作为阅读滚动 |
| 关闭/提交跳页 | scrub → 进入前的 page 或 orb；保留工具 |
| 退出标注模式 | tools/orb → page，工具恢复 select |
| 文档切换、dispose | 取消计时器；不允许回调改变新文档 |

API 草案：`slot`、`selectedTool`（由业务同步）、`openTools()`、`selectTool(tool)`、`annotationCompleted()`、`collapseTools()`、`openScrub()`、`closeScrub()`、`onReadingScroll()`、`reset(documentId)`、`dispose()`；采用 ChangeNotifier，计时器可注入以便测试。滑块值与实际跳页由现有阅读控制器管理。

原型 CSS 可并列显示部分浮控，本任务明确要求四态互斥，以此状态模型为准；实现 PR 说明该差异。选 select 后的自动折叠按原型为 500ms，标注完成为 650ms，两者独立令牌。

## 顶部沉浸与 hold

沿用 WorkspaceChromeController 的阅读方向累积阈值与 WorkspaceChromeBar 的布局保持、IgnorePointer、ExcludeFocus、ExcludeSemantics。向下阅读隐藏，反向滚动显示，正文单击调用 reveal（不切换为隐藏）；顶部不参与底部四态切换。

现有 workspace_screen 的 editing hold 包含 `state.tool != AnnotationTool.select`，会导致工具保持选中时永不隐藏。手机 compact 分支移除此条件，改为只在实际选区编辑、画笔/框选手势、tools/scrub 交互中 hold；orb 保持工具选中不 hold。由 GUL-631 接线并验证。drawer/panel/keyboard/popup/focus/accessibility 的 hold 保留，所有关闭、取消和 dispose 路径成对 release。

mm_pdf 的 onUserScroll 当前在 onInteractionUpdate 中报告位置差，onInteractionEnd 清空跟踪；继续只消费用户阅读手势，不将程序跳页、缩放布局变化误识别为阅读。VoiceOver/accessibleNavigation 保持顶部可达；减少动态效果使用 MMAppearance.duration。

## PDF 滑动手感

| 环节 | 已核对源码与落点 |
| --- | --- |
| 入口 | mm_pdf `pdf_view.dart` 的 PdfViewerParams 当前未指定 scrollPhysics |
| 默认速度 | pdfrx `interactive_viewer.dart` pan 手势结束读取 ScaleEndDetails.velocity.pixelsPerSecond，默认没有 ×1.6 |
| 默认减速 | scrollPhysics 为 null 时，interactionEndFrictionCoefficient 驱动 FrictionSimulation 的终点，实际动画是 Curves.decelerate Tween；直接设置 0.998 不能复现每毫秒衰减 |
| 可扩展路径 | PdfViewerParams.scrollPhysics 非空时，pdfrx 截断速度后调用 createBallisticSimulation，随后 animateWith；可由 mm_pdf 内部的自定义 ScrollPhysics 实现 |

建议 mm_pdf 增加可选 `MMPdfScrollProfile` 配置，默认 null 保留旧路径。手机配置在 createBallisticSimulation 中仅对释放速度乘 1.6，模拟使用每秒阻尼 `pow(0.998, 1000)`（约 0.1351），即 `v(t)=1.6*v0*0.998^(1000*t)`。边界外返回回弹模拟；边界内惯性撞到边缘后切换回弹，不能只用无边界 FrictionSimulation。避免对捏合缩放速度和鼠标滚轮同时放大；检查 pdfrx 的 scrollPhysicsScale 路径以隔离缩放行为。无需 fork 依赖。

测量：固定文档、缩放比和起点，在 393×852 环境注入相同拖动轨迹，记录抬手速度、每帧屏幕位移、总行程、停止时间、帧耗时；按屏幕逻辑像素计算，排除边界段后拟合速度对数斜率，目标每秒 `1000*ln(0.998)`。覆盖低/中/高速、上下方向、页面首尾、放大后横向边界、捏合后惯性、快速再次触摸中断。真机对比系统阅读应用；原型也允许倍率按实测调整，任何偏差写入 PR。不得把浏览器示意参数直接声称为系统真实实现。

## 材质与令牌

扩展现有 MMLiquidGlass，新增显式手机 `phoneStyle: MMPhoneGlass.regular/thick` 预设；原构造默认值、MMGlass 与 MMGlassBar 保持兼容。调用方仅在 phone + compact 选择新预设。复用嵌套玻璃检测，禁止重复 BackdropFilter；MMFlatSurface 的不透明优先级保留。

| 参数 | regular | thick |
| --- | --- | --- |
| 模糊/饱和度/亮度 | 10 / 1.9 / 1.03 | 28 / 1.8 / 1.0 |
| 浅色底 | 白 46% | #FAFAFC 80% |
| 深色底 | #242428 62% | #242428 84% |
| 边缘 | 0.5pt 外沿、1pt 渐变高光 | 同左 |
| 顶部高光 | 偏左顶部径向渐变，白色 22% / 深色 6% | 同左 |

颜色、描边和阴影均从原型 CSS 对应令牌进入 mm_design，不从业务层传硬编码值。降低透明度时去除滤镜与透光叠层，强制 alpha=1（包括自定义底色），浅色白/深色 #1C1C1E，保留足够边界对比。

| 拟新增令牌 | 值 |
| --- | --- |
| MMSizes.phoneTabBarHeight / phoneTabBarHorizontalInset / phoneTabBarBottomInset | 64 / 22 / 26 |
| MMRadii.phoneTabBar | 32 |
| MMSizes.phoneTopControl / phoneToolOrb / phoneToolBarHeight / phonePageCapsuleHeight | 44 / 50 / 56 / 36 |
| MMSizes.phoneDrawerWidth / phoneSheetPadding | 328 / 8 |
| MMRadii.phoneSheet | 38 |
| MMMotion.phoneAnnotationCollapse / phoneSelectionCollapse | 650ms / 500ms |

底部 26 为原型屏幕边距，布局需与设备安全区取最大值，不能重复相加；抽屉宽度上限 328 并受可用宽度限制。36pt 页码视觉外包至少 44pt 热区。所有图标按钮都有本地化 VoiceOver 标签、选中状态；页码滑块提供当前值和增减语义。动态字号下允许内容适配，不裁掉操作；不加解释性副标题。

## 验证与交付

基础组件单测覆盖 regular/thick、浅深色、降低透明度、flat surface、嵌套玻璃、旧构造默认值；Gallery 提供手机尺寸预览。393×852 浅深色 golden 作为无模拟器时的证据；iPad compact 与 macOS 对照断言旧路径不变。状态机后续测试覆盖计时器重置/销毁、滚动与手势竞争、工具保持选中、hold 成对释放。

实现提交前运行 flutter analyze、dart format --set-exit-if-changed apps packages、受影响测试及 python3 tool/coverage.py；核实变更代码覆盖率至少 80%。新增界面文案更新中英文 ARB 后执行 flutter gen-l10n。GUL-630 只实现基础材质与令牌，不修改具体业务页面；验证结果与截图见 PR。
