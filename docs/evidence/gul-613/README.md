# GUL-613 验证记录

实现以 `docs/layout-density.md` 的 52pt 表头及视觉规格为准，交互与组件边界遵循 `docs/layout-density-architecture.md`。原型为 `design/prototype/layout-density.html` 的新方案。

## 截图

每组 `*-comparison.png` 左侧为原型、右侧为应用；对应的单独 PNG 保留原始尺寸。

| 场景 | 应用逻辑尺寸 | 浅色 | 深色 |
| --- | --- | --- | --- |
| Mac | 1280 × 800 | [对照](mac-light-comparison.png) | [对照](mac-dark-comparison.png) |
| iPad 横屏 | 1194 × 834 | [对照](ipad-landscape-light-comparison.png) | [对照](ipad-landscape-dark-comparison.png) |
| iPad 竖屏 | 834 × 1194 | [对照](ipad-portrait-light-comparison.png) | [对照](ipad-portrait-dark-comparison.png) |

六组应用图由 Flutter Web release 构建、真实 PDF 示例和内存学习集生成；iPad 使用触屏平台覆盖，验证响应式布局，不代表 iPadOS 真机截图。浏览器没有系统状态栏，且平台能力会隐藏原生助手入口。原型与应用的示例内容、PDF 页数和当前脑图视口不同，对照用于检查工具栏及分栏结构，不是像素金图。`browser-errors.json` 为页面错误采集结果（0 项）。临时截图入口及平台覆盖未纳入产品代码。

`native-mac-light.png`、`native-sidebar-hidden.png` 来自 macOS release 应用，包含原生红绿灯、助手入口及侧栏收起状态。原生系统窗口名通过 Accessibility 读回为“学习的底层逻辑 — 认知科学入门 — MarginMind”；全屏状态读回 0 → 1 → 0，窗口尺寸从 1280 × 820 变为 1920 × 1080 后恢复。

自动化工具的拖动使用 AXPosition，无法证明真实标题栏拖动；双击未观察到窗口缩放。物理鼠标拖窗、双击缩放及 iPadOS 真机交互仍需人工验收。

## 本地检查

- `python3 tool/coverage.py` 全仓通过；最终应用与设计包重跑 `flutter test --coverage` 后，`python3 tool/coverage.py --report-only` 为 **91.68%（44113 / 48116）**，门槛 80%。应用 1125 项通过、34 项跳过；设计包 194 项通过。新增文档菜单用例单独通过。
- `python3 -m unittest discover -s tool/tests`：26 项通过。
- `flutter analyze`：无问题；`dart format --set-exit-if-changed apps packages`：733 个文件、0 改动；`git diff --check`：通过。
- Web 与 macOS release 截图构建通过；移除临时入口后，常规 `flutter build web --release` 也通过。
- `flutter test integration_test/reflow_reader_test.dart -d macos --reporter expanded`：1 项通过，覆盖真实原生应用的导入、阅读、摘录、通过 Aa 调整字号和返回原文。旧的直接点击阅读设置入口已同步；本机 Xcode 有模拟器服务及前台激活提示，但 macOS 构建和测试均成功。

新增回归覆盖：真实宽度溢出与命中/语义移除、文字按钮折叠和恢复、浮层扁平主题、侧栏动画和助手面板下表头/正文分隔对齐、不同设备与主题、系统标题写入顺序、旧 pane 解绑、比较阅读主文档切换和文档菜单命令。现有阅读/脑图/笔记用例同步到新入口。

自审检查了完整入口、空值与窄宽度、文档切换后的命令归属、异步通知与标题写入、浮层关闭和焦点恢复、权限及敏感数据。修复了描边引入布局内边距导致换行、有限画布外点击不能取消选择、比较阅读丢失主文档切换语义，以及极窄栏文档菜单遗漏操作的问题。
