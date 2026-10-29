# GUL-551 对照阅读验证

生产入口支持两份 PDF 对照：文档菜单、导入、左右互换、各自裁边、共同标注工具、页边标记、同步与对齐，以及退出恢复布局。对齐复用 ReadingAlignment / ReadingSync，阅读线为视口高度 25%；ComparePair 随学习集保存，同一文档对反向打开时交换锚点轴。窗口变化保持原始 PDF 阅读坐标。

语言在本地从 PDF 首页文字判断，无法提取时回退到文档名；中英异语文档排在菜单前，同组保持学习集顺序。AI 翻译本批次禁用：依次显示模型未配置、离线模式、需要 OCR，其他情况显示“暂未提供”，后续批次接入翻译会话。

## 原生复现

`apps/marginmind/example/compare_acceptance.dart` 运行生产阅读器与 PDFium。学习集、文档批注和设置均在内存中，PDF 副本写入应用自己的临时目录；不改用户学习集或偏好。

在 `apps/marginmind` 运行：

```sh
flutter run -d macos -t example/compare_acceptance.dart
flutter run -d macos -t example/compare_acceptance.dart --dart-define=COMPARE_SELF_CHECK=true
```

验收 PDF 是原创中英测试文字，生成器为 `example/compare_fixture.swift`。不使用私人文档。可在 `apps/marginmind` 重新生成：

```sh
swift example/compare_fixture.swift assets/sample/compare-fixture.pdf assets/sample/compare-source.pdf
```

## macOS 实机截图

Mac mini（Apple 芯片），Flutter 3.47.2，Debug 构建，真实 PDFium 渲染。截图通过系统窗口捕获取得：

- [双栏对照](01-compare.png)：中英 PDF、各自标题与阅读线页码、批注标记、同步和对齐按钮。
- [两栏均裁边](02-both-cropped.png)：每栏裁自己的文档，保持相同正文显示比例，标记跟随页面。
- [已对齐](03-aligned.png)：恢复同步并保存当前位置，HUD 提供撤销。

## 验证范围

- 对齐点：插值、反向、端点、不同页数、重复替换、交叉拒绝；ComparePair 编解码和仓储重开沿用数据底座回归。
- Widget：进入、菜单导入、单文档、切换、互换、同步开关、双向同步与稳定性、用户接管、对齐和撤销、文档对重用、resize、退出恢复、平板禁用与手机隐藏入口。
- 两栏分别写批注、摘录、高亮和裁边；模拟支持 OCR 的平台，确认右栏也执行文档检查；Esc 先保存批注、关闭标记弹层，再退出对照。
- 写盘失败：同步状态回退、未保存批注保留，互换和退出不会丢弃草稿。

## 自审

检查了完整入口和退出、文档身份与坐标、空状态、异常分支、原始 PDF 坐标、同步回环与用户接管、过期任务、计时器和渲染资源、输入与注入、敏感信息、文案与现有架构一致性。

修复了双栏页码保存共用计时器、对齐撤销未通知呈现层、裁边文档重挂载时读取尚未生成的视口尺寸、resize 保留中心而非阅读线、右栏 OCR 检查未触发，以及批注弹层 Esc 被退出动作覆盖。互换和退出先保存批注；失败保留当前会话。外部文档切换失败回退原文档，关闭最后一份打开的 PDF 自动退出对照。

## 验证命令与结果

- `dart format --set-exit-if-changed apps packages`：435 个 Dart 文件，无改动。
- `flutter analyze --no-pub`：无问题。
- `python3 -m unittest discover -s tool/tests`：17 项通过。
- PDF 包 `flutter test --no-pub --coverage`：104 项通过，退出码 0。
- 应用阅读区 `flutter test --no-pub --coverage --concurrency=8 test/reader_*test.dart test/selection_toolbar_test.dart test/ink_test.dart test/area_excerpt_test.dart test/coverage_flows_test.dart`：105 项通过，退出码 0。
- 设计组件包 `flutter test --no-pub --coverage`：137 项通过，退出码 0。
- 对照阅读 `flutter test --no-pub --coverage test/reader_compare_test.dart`：9 项通过，退出码 0。
- `python3 tool/coverage.py --report-only --minimum 80`：整体 91.10%，改动可执行行 652/719（90.68%，含生成的本地化代码）；见 [覆盖率](coverage.md) 和 [逐文件明细](changed-coverage.json)。
- macOS `flutter build macos --debug --no-pub -t example/compare_acceptance.dart --dart-define=COMPARE_SELF_CHECK=true` 后运行应用：退出码 0，输出 `NATIVE_COMPARE_OK persisted=1 swap={page: 1, y: 520.0} layout=restored`。

本地全应用命令日志显示 645 项断言通过，工具最终返回 143；当前阅读代码已以上述专项命令重新验证。覆盖率合并完整应用报告与后续阅读报告，发生修改的文件使用新报告的行位置。PR 的 CI 另行运行全量包测试与所有平台构建。

已 rebase 到 `8e47f35`（GUL-554），保留纸张背景与行内计数，同时在对照时禁用展开页边。以上阅读区、PDF、设计组件与静态分析已在集成后重新运行，截图也使用该版本。
