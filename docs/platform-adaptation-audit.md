# 多平台适配实测与移动端（iPad 优先）适配方案

> GUL-538 · 2026-10-28 · 代码基线 `06a2fe9`（`origin/main`）。本文是对 [跨平台支持评估与开发方案](platform-support-plan.md) 的实测补充：先确认各平台“能否构建、能否启动、能否用”，再列出跨平台问题，重点给出 iPad 的适配方案。配套交互设计稿：[`design/prototype/cross-platform.html`](../design/prototype/cross-platform.html)。
>
> 本次**没有修改应用代码**。iOS/Android/Web 工程只在临时副本中生成用于验证，没有提交；是否正式加入仓库由 MOB-01 / WEB-01 决定。

## 1. 结论

| 平台 | 构建 | 启动 | 核心闭环（阅读→摘录→脑图） | 判定 | 证据 |
| --- | --- | --- | --- | --- | --- |
| macOS | 既有 CI / DMG | 是 | 可用 | **可用（基准）** | 历史验收，本轮未重测 |
| Linux（ARM64，X11/Xvfb） | `flutter build linux --debug` 通过 | 是 | 能打开示例学习集，PDF 与脑图正常渲染；原生能力缺口同 plan §1.1 | **可运行，功能不全** | `linux-arm64-*.jpg` |
| Windows | 未构建（本轮无 Windows 主机） | — | — | **未实测** | 仅代码审查 |
| iPadOS | 临时生成 `ios/` 后 `flutter build ios --simulator` 通过（Xcode 27.1） | 是（iPad Pro 13" M5 模拟器） | PDF、脑图可渲染；**触控无法操作脑图、菜单不可达、工具栏压在状态栏下** | **能跑，不可用** | `ipad13-*.jpg`、触控探针 |
| iOS（iPhone） | 同上 | 是（iPhone 17 Pro 模拟器） | 桌面侧栏占满屏幕，工具栏溢出 345px，脑图被隐藏 | **能跑，不可用** | `iphone17pro-*.jpg` |
| Android | 临时生成 `android/` 后 `assembleDebug` 通过（JDK 21、SDK 36，首次约 12.5 分钟） | 是（Pixel 8 模拟器，API 36） | 与 iPhone 相同：侧栏占满屏幕，工具栏溢出 329px，脑图被隐藏 | **能跑，不可用** | `android-pixel8-*.jpg` |
| Web | 临时生成 `web/` 后 `flutter build web --release` 通过 | **白屏** | — | **不可用** | `web-chrome-blank.jpg` |

一句话：Flutter 层面的 Dart 代码在所有平台都能编译，桌面布局在 Linux 上也能跑；**移动端的问题不在编译，而在交互模型与布局完全是桌面的**——没有安全区、没有尺寸断点、菜单只能右键打开、脑图手势按鼠标设计。iPad 需要一轮专门的“触控优先”改造，才能进入 MOB-02 的验收。

## 2. 验证环境与方法

### 2.1 主机

| 主机 | 用途 |
| --- | --- |
| Ubuntu 24.04.5 ARM64（Agent 主机），Flutter 3.47.2 | Linux 构建与 Xvfb 运行、Web 构建与 Headless Chrome、Widget 级触控探针 |
| macOS 26.6.2 Mac mini（arm64），Xcode 27.1，Flutter 3.47.2 | iOS 模拟器构建、iPad Pro 13" (M5) / iPhone 17 Pro 模拟器运行与集成探针；Android（用户目录下临时安装的 Temurin JDK 21 + Android SDK 36，Pixel 8 AVD） |

### 2.2 实际运行的命令与结果

| 命令 | 结果 |
| --- | --- |
| `flutter create --platforms=ios,android,web .`（临时副本） | 成功，未提交 |
| `flutter build ios --simulator --debug --no-codesign` | 成功（约 90s） |
| `xcrun simctl install/launch`（iPad Pro 13"、iPhone 17 Pro） | 均可启动到资料库 |
| `flutter test integration_test/probe_test.dart -d <模拟器>`：打开示例学习集、截图、旋转为横屏、收集布局错误 | iPad：通过，无溢出错误（横屏请求被系统忽略）；iPhone：通过，**3 次 RenderFlex 右溢出（345 / 48 / 14 px）**，横屏 874×402 可旋转；Android（Pixel 8，411×914dp，安全区 上 50 / 下 24）：通过，**3 次右溢出（329 / 39 / 1.3 px）** |
| `flutter build web --release` / `--profile` + Chrome | 构建成功；页面白屏，未捕获 `MissingPluginException`（方法通道无 Web 实现） |
| `flutter build linux --debug` + Xvfb 1440×900 | 成功；资料库与工作区正常渲染 |
| `flutter test test/zz_touch_probe_test.dart`（临时 Widget 探针，触控指针） | 见 §3 M5 的实测数据 |

Android 构建时 Gradle 提示 `desktop_drop` 仍使用 Kotlin Gradle Plugin，未来 Flutter 版本会构建失败（见 A2）。探针源码保存在 [`evidence/platform/GUL-538/probes/`](evidence/platform/GUL-538/probes/)，截图在同目录。模拟器的安全区实测：iPad Pro 13" 竖屏 1032×1376pt，上 32 / 下 20；iPhone 17 Pro 402×874pt，上 62 / 下 34。

### 2.3 未覆盖与原因

- **Windows**：没有 Windows 主机；结论沿用 plan §1.1 的代码审查。
- **Android 平板**：只跑了手机 AVD；平板布局规则与 iPad 相同（§4），未单独实测。
- **iPad 横屏截图**：`SystemChrome.setPreferredOrientations` 在支持多任务的 iPad 上被系统忽略，模拟器旋转需要 GUI 操作；横屏结论来自竖屏实测 + 布局代码推导（1376pt 宽可放下现有三栏）。
- **真机、Apple Pencil、外接键盘/触控板、软键盘**：模拟器无法验证，列入 MOB-02 验收。
- 未接真实模型服务；未运行全仓 analyze / coverage（本次未改代码）。

## 3. 跨平台问题清单

优先级沿用 plan：P0 阻断使用；P1 影响完整性；P2 后续补齐。

### 3.1 移动端（iOS / iPadOS / Android 共通）

| ID | 级别 | 问题 | 实测 / 依据 | 位置 |
| --- | --- | --- | --- | --- |
| M1 | P0 | 没有 iOS / Android 平台工程 | 仓库只有 macos/windows/linux | `apps/marginmind/` |
| M2 | P0 | 没有安全区处理 | iPad 工具栏与状态栏重叠，右上布局/助手按钮落在 Wi-Fi/电量图标下；iPhone 内容进入灵动岛和 Home 指示条区域。全仓只有 `MMSheet` 用了 `SafeArea` | `mm_design/.../window_scaffold.dart` |
| M3 | P0 | 只有桌面一套布局，没有尺寸断点 | 侧栏 236 + 阅读最小 420 + 脑图最小 360 + 面板 400，最小窗口 960×600。iPhone：3 次 RenderFlex 溢出，侧栏占 60% 宽，PDF 缩到约 150pt，脑图被隐藏；iPad 竖屏：阅读工具栏折成两行，脑图只剩约 370pt、根节点被截断 | `workspace_layout.dart`、`metrics.dart`、`split_view.dart` |
| M4 | P0 | 右键是菜单的唯一入口 | 节点、关联线/概要、学习集、侧栏、对话列表的菜单全部挂在 `onSecondaryTapUp`（18 处），全仓 `onLongPress` 为 0。触屏无法删除、导出、改名、定位原文 | `mind_map_canvas.dart:1152`、`library_screen.dart:424`、`study_set_list.dart:162`、`sidebar.dart:173`、`assistant_conversations.dart:151` |
| M5 | P0 | 脑图手势按鼠标设计 | 触控探针（800×600 画布、4 个节点）：单指拖空白处 → **框选全部 4 个节点**，不是平移；双指捏合 → 缩放 1.000 → 1.000（`scaleEnabled:false`，缩放只接触控板 `PointerPanZoom` 与滚轮）；从节点上单指拖动 → 立即进入 `Draggable` 移动节点，画布不动；长按节点 → 无任何响应 | `mind_map_canvas.dart:1290-1345`（`onPointerDown` 只判断 `buttons == 1`，未区分 `PointerDeviceKind`）、`:961` |
| M6 | P1 | 只在 hover 时出现的控件 | 阅读页码导航只在 hover/聚焦时显示；折叠按钮 hover 前 0.45 透明度；共 30 处 `MouseRegion` | `reader_pane.dart:44`、`mind_map_canvas.dart:2121` |
| M7 | P1 | 手指 / Pencil 没有分工 | 区域摘录与手写的 `GestureDetector` 同时接受 touch 与 stylus，手指滚动与绘制冲突；没有“Pencil 画、手指滚”的策略 | `mm_pdf/.../pdf_view.dart:1325、1348` |
| M8 | P1 | 导出依赖桌面“另存为” | `getSaveLocation` 在 iOS/Android 不支持（file_selector 1.1.0）；PNG/PDF 编码只在 macOS 原生通道 | `map_export_sheet.dart:184`、`map_export.dart` |
| M9 | P1 | 拖入导入用 `desktop_drop` | 不支持 iOS/Android；iPad 分屏从“文件”拖 PDF 进来没有入口 | `shared/pdf_drop.dart` |
| M10 | P1 | 软键盘遮挡 | 窗口脚手架不处理 `viewInsets`；助手输入框、节点重命名、搜索在手机上会被键盘盖住 | `assistant_composer.dart`、`inline_text_field.dart` |
| M11 | P2 | iPad 分屏 / Stage Manager | 需要支持 ½、⅓ 宽度（约 684 / 507pt）与任意窗口尺寸 | `Info.plist` |
| M12 | P1 | 原生能力通道 | 凭据（Keychain）、OCR（Vision）、外链（NSWorkspace）、正文解析（WebKit）只注册在 macOS Runner；iOS 可复用大部分 Swift，但需在 iOS Runner 注册并改用 UIApplication 等 API | `mm_platform/lib/src/*`、`macos/Runner/*.swift` |
| A1 | P1 | Android 文件与返回 | SAF `content://` 需要复制进沙盒；系统返回应先关 sheet / 退出编辑，而不是直接退出 | `pdf_picker.dart` |
| A2 | P2 | `desktop_drop` 使用 Kotlin Gradle Plugin | Gradle 警告：未来 Flutter 版本将因此构建失败；移动端本来也不需要它（M9），应按平台条件引入或替换 | `apps/marginmind/pubspec.yaml` |

### 3.2 桌面（Windows / Linux）

与 plan §1.1、CP-01～CP-12 一致，本轮没有新增阻断项。新增的实测证据：Linux ARM64 + Xvfb 下 debug 构建可以完成“启动 → 打开示例学习集 → 渲染 PDF 与脑图”，说明 CP-01 在 ARM64 上的构建链（CMake/Ninja/GTK、PDFium）可用；x64 与 release 包仍待 CP-01 验收。触屏笔记本（Windows）同样需要 §4.2 的触控手势。

### 3.3 Web

| ID | 级别 | 问题 | 依据 |
| --- | --- | --- | --- |
| B1 | P0 | 启动链依赖 `path_provider` 与 `dart:io` | `main.dart:21` 直接 `getApplicationSupportDirectory()`，Web 无实现 → 未捕获异常 → 白屏；`mm_data`、`mm_research`、`mm_assistant` 共 14 个文件 import `dart:io` |
| B2 | P0 | 助手网络无法照搬 | DNS/IP 固定、TLS 策略在浏览器不可用，需要 CORS 或服务端代理（WEB-01/03） |
| B3 | P1 | 浏览器快捷键冲突 | Ctrl+F / S / W / N 被浏览器占用 |

Web 仍按 plan 第 5 节先做 WEB-01 可行性 ADR，不建议在移动端之前投入。

## 4. iPad 适配方案（重点）

iPad 是最重要的移动平台：屏幕足够放下“阅读 + 脑图”的双栏，又有 Pencil，最接近 MarginMind 的核心场景。目标是**横屏与 macOS 同构、竖屏上下分栏、分屏退化为单面板**，交互全面触控优先，同时保留外接键盘和触控板的桌面体验。

### 4.1 尺寸档（新增 `MMSizeClass`）

按可用逻辑宽度（不是设备类型）判断，窗口尺寸变化时实时切换：

| 档位 | 条件 | 典型场景 | 布局 |
| --- | --- | --- | --- |
| Regular | 宽 ≥ 1180pt 且横向 | 桌面、iPad 13"/11" 横屏、Android 平板横屏 | 现有三栏：侧栏 + 阅读/脑图左右分栏 + 右侧面板。触控设备上侧栏默认收起为浮层，给脑图留宽度 |
| Medium | 600 ≤ 宽 < 1180pt，或竖向 | iPad 竖屏、iPad mini、横屏 iPad ⅔ 分屏 | **阅读在上、脑图在下的上下分栏**，分隔条可拖动、双击回 50/50，可一键让任一侧全屏；侧栏为左侧抽屉；助手 / 卡片详情为右侧浮动面板 |
| Compact | 宽 < 600pt | iPhone、Android 手机、iPad ½ 与 ⅓ 分屏 | 单面板。iPad 用顶部“阅读 / 脑图”分段控件（全屏↔分屏切换时不跳变），手机用底部 Tab（资料库 / 阅读 / 脑图 / 复习）；助手、导出、详情为底部 sheet；菜单为 Action Sheet |

桌面窗口宽度 ≥ 1180pt 时，现有布局和 `resolveWorkspaceLayout` 的结果保持不变；macOS 回归以此为准。

### 4.2 输入模型

| 输入 | 阅读区 | 脑图 |
| --- | --- | --- |
| 单指 | 滚动 / 翻页；轻点关闭选区 | **拖空白处 = 平移**；轻点 = 选中；双击 = 打开详情 / 改名 |
| 双指 | 捏合缩放页面 | **捏合缩放（以双指中心为锚点）**、双指平移 |
| 长按 | 选字（系统式选择柄 + 放大镜）→ 浮动工具栏：摘录到脑图 / 高亮 / 问助手 / 拷贝 | **长按节点 = 上下文菜单**（触感反馈，iPad 为气泡菜单，手机为 Action Sheet）；**长按后不松手拖动 = 移动节点** |
| Apple Pencil | **Pencil 划过文字 = 直接选字摘录**；区域工具、手写、橡皮只响应 Pencil，手指仍然滚动；双击 Pencil 切换工具 | Pencil 可拖动节点、框选 |
| 外接键盘 | 沿用 ⌘ 快捷键与 `app_commands.dart`；按住 ⌘ 显示 iPadOS 快捷键面板 | 方向键导航、Tab 添加子节点、Enter 改名 |
| 触控板 / 鼠标 | 沿用桌面 hover、右键菜单、双指滚动 | 同 macOS：拖空白 = 框选 |

框选在触控下改为工具栏上的“多选”模式按钮：进入后单指拖动框选，再点一次退出。判断依据是 `PointerDeviceKind`，而不是平台：触屏笔记本、iPad 接触控板时各自走对应行为。

### 4.3 布局细节

- **安全区**：`MMWindowScaffold` 统一包 `SafeArea`（顶部状态栏、底部 Home 指示条、横屏时左右）；背景色铺满，内容避让。
- **命中区**：触控下工具栏按钮、侧栏行、菜单项最小 44pt（现为 28–34pt）；节点卡片宽度 210、正文 13pt。
- **常显控件**：页码导航、折叠按钮、节点“+”在触控下常显；只有指针设备才使用 hover 渐显。
- **工具栏**：Regular 下与桌面一致；Medium 下合并为一行，次要工具收进“更多”；不再为红绿灯预留 78pt（只有 macOS 需要）。
- **Pencil 工具板**：阅读区底部居中的浮动调色板（笔 / 高亮色 / 区域 / 橡皮），对应现有 `AnnotationTool`。
- **软键盘**：助手输入框、重命名、搜索随键盘上移；键盘弹出时 sheet 扩展为全高。
- **多任务**：声明支持所有方向和分屏；½ 分屏时从右侧“文件”App 拖入 PDF / 图片即可导入（替代 `desktop_drop`，iOS 端用 `UIDropInteraction`）。

### 4.4 文件、导出与原生能力

- 导入：`file_selector` 打开“文件”选择器，结果立即复制进 `.mmset/documents`，不依赖外部授权（MOB-03）。
- 导出：生成文件后交给系统分享面板（`UIActivityViewController`，可“存储到文件”），不调用 `getSaveLocation`。
- 能力声明：凭据（Keychain 可直接复用）、外链（`UIApplication.open`）、正文解析（WKWebView）、OCR（Vision）在 iOS Runner 注册后才标记为可用；未注册前按 CP-02 显示原因。

## 5. 手机（iPhone / Android）

手机定位为“随身复习 + 轻量摘录”，不追求与平板相同的编辑密度：

- 底部 Tab：资料库 / 阅读 / 脑图 / 复习；“复习”是一等入口，大按钮评分。
- 阅读里选字摘录后弹出 toast“已加入脑图 · 查看”，不强制切页。
- 脑图支持平移、缩放、长按菜单、长按拖动；批量编辑和整图导出放在“更多”。
- Android 沿用 `mm_design`，不换 Material 组件；导航栏胶囊高亮、Noto Sans SC 字体、系统返回（`PopScope`）先关闭 sheet/编辑态；文件走 SAF 并复制进沙盒，导出走 `ACTION_SEND`。

## 6. 建议的任务拆分

在 plan 第 5 节的 MOB-01～03 之下细化（编号为本文内部编号）：

| ID | 依赖 | 内容 | 验收 |
| --- | --- | --- | --- |
| MOB-01 | CP-02 | 提交 `ios/`、`android/` 工程；Info.plist 文件访问与多任务声明；签名说明；CI 增加 iOS 模拟器构建 | 模拟器与真机启动、沙盒内打开 PDF |
| MOB-02a | MOB-01 | `MMSizeClass` 与安全区：`MMWindowScaffold` 加 SafeArea；`resolveWorkspaceLayout` 增加 Medium（上下分栏）与 Compact（单面板 + 分段/Tab）；桌面 ≥ 1180pt 结果不变 | 布局单测覆盖 402 / 684 / 744 / 1032 / 1376pt；iPhone 无 RenderFlex 溢出；macOS 布局测试不变 |
| MOB-02b | MOB-02a | 触控手势：按 `PointerDeviceKind` 分流脑图平移/框选；触控双指缩放；节点改为长按后拖动；所有 `onSecondaryTapUp` 同时提供 `onLongPress`（抽成 `MMContextMenuRegion`） | Widget 测试：touch 单指拖空白平移、双指缩放比例变化、长按出菜单；mouse 行为不变 |
| MOB-02c | MOB-02b | 触控下常显控件、44pt 命中区、Pencil 与手指分工、Pencil 工具板 | 真机 iPad + Pencil 手测；截图更新设计稿 |
| MOB-02d | MOB-02a | 软键盘与 sheet：助手、重命名、搜索避让键盘；Compact 下助手/详情/导出改为底部 sheet | iPhone / Android 软键盘不遮挡发送与确认 |
| MOB-03 | MOB-02 | 导入复制入沙盒、系统分享导出、iOS 原生通道注册（凭据/外链/正文解析/OCR）、拖入导入 | 见 plan MOB-03 |

MOB-02a、MOB-02b 是 iPad 能用的最小集合，建议先做；它们大部分修改 Dart 层，不依赖签名与真机。

## 7. 设计稿

[`design/prototype/cross-platform.html`](../design/prototype/cross-platform.html) 为单文件高保真交互原型，直接用浏览器打开：

- **平台**：macOS、Windows、Linux、iPad 横屏 / 竖屏 / ½ 分屏 / mini、iPhone、Android 手机 / 平板、Web，各自带系统外框（标题栏、状态栏、安全区、导航条）。
- **场景**：资料库、阅读 + 脑图、助手、复习、导入 / 导出。
- **视图**：“目标设计”是按本文方案的交互稿；“现状（实测）”显示本轮真实截图并标注问题，没有截图的平台说明未实测原因。
- **可交互**：点段落模拟选字 → 摘录到脑图；拖动脑图平移、滚轮或按钮缩放；触控平台长按节点（0.5s）出菜单，桌面右键出菜单；助手面板与软键盘；复习翻卡与评分；导入/导出在各平台显示对应的系统选择器 / 分享面板 / 下载；iPad ½ 分屏可把右侧“文件”中的 PDF 拖进来。
- 右侧面板列出每个平台的实测结论、布局规则、输入模型、设计要点和对应问题编号。

## 8. 测试工具链说明

Android 工具链安装在 Mac 主机的 `~/macrun-work/android-tools`（约 6.3 GB，JDK + SDK + 系统镜像 + NDK），只用于本次验证，没有修改系统级配置；不再需要时可直接删除该目录。iOS / Android / Web 平台工程生成在临时克隆 `~/macrun-work/mm-gul538` 与 Agent 主机 `/tmp/mm-web`，同样未提交。
