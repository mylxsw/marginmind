# GUL-631 阅读控件验收

已在 #152 合并后 rebase 到 main `93f78c04`。保留 `MMPdfView.scrollProfile`（位于 `documentSurface`）、完整 drawer wrapper，以及双方 ARB、生成本地化、材质/布局测试和设计文档。仅 phone + compact 启用新阅读控件，iPad compact、iPad 横屏、macOS 和非 compact 手机沿用旧路径。

本轮集成发现 main 新增文档脑图横幅在 393pt 英文界面溢出 76px。仅在 phone + compact 约束两个按钮宽度，沿用 MMButton 的省略显示及完整语义，并计入边框以保证两行各有 44pt 热区。新增回归覆盖中英文、320/393pt、正常及 1.5 倍字号。桌面和平板横幅分支保持原样。

393×852 浅深色截图由 Linux arm64 Flutter golden renderer 验证，安全区为顶部 54 / 底部 34；没有 iOS 模拟器，未运行 iOS 原生构建或真机验收。正文使用流式样本文档，画笔截图使用 PDF 占位背景；PDF 行为以可控测试后端验证。本轮仅更新两张脑图场景截图，反映 main 的文档脑图横幅，其他 12 张截图一致。

| 场景 | 浅色 | 深色 |
| --- | --- | --- |
| 2 阅读 | [截图](02-reading-light.png) | [截图](02-reading-dark.png) |
| 3 工具栏与颜色 | [截图](03-tools-light.png) | [截图](03-tools-dark.png) |
| 3 画笔颜色、笔宽、笔形 | [截图](03-pen-light.png) | [截图](03-pen-dark.png) |
| 3 保留工具的球 | [截图](03-orb-light.png) | [截图](03-orb-dark.png) |
| 4 跳页 | [截图](04-scrub-light.png) | [截图](04-scrub-dark.png) |
| 5 沉浸 | [截图](05-immersive-light.png) | [截图](05-immersive-dark.png) |
| 9 脑图 | [截图](09-map-light.png) | [截图](09-map-dark.png) |

验证结果：`flutter gen-l10n`、`flutter analyze --no-pub` 正常退出；22 个改动 Dart 文件 format 通过。手机/抽屉/材质/文档导航组 79 项通过，PDF 物理组 6 项通过，截图组 2 项通过；阅读器扩展组 111 通过、2 项既有脑图 fit 入口断言失败；mm_design 全套 217 通过、1 项既有浅色材质 golden 相差 79px（0.02%，上一轮已在未修改 main worktree 复现）。新横幅和阅读控件没有剩余失败。

变更执行行覆盖率 **87.19%（817 / 937）**，相对当前 base `93f78c04` 计算，见 [明细](changed-coverage.json)。方法为 `git diff --unified=0` 的变更 Dart 行与 LCOV 执行行取交集，包含生成本地化代码；常量/抽象声明不计入执行行。横幅仅使用最终报告的行号，其余源码合并本轮报告，未混用 rebase 前的旧行号。

在 `apps/marginmind` 运行以下命令：

```bash
flutter test --no-pub --concurrency=3 --coverage --coverage-path coverage/rebase-phone-final.info \
  test/phone_reader_controls_test.dart test/phone_navigation_redesign_test.dart \
  test/phone_workspace_sidebar_test.dart test/phone_sidebar_regression_test.dart \
  test/liquid_glass_test.dart test/phone_layout_test.dart \
  test/phone_document_map_banner_test.dart test/document_map_navigation_test.dart

flutter test --no-pub --concurrency=3 --coverage --coverage-path coverage/rebase-reader.info \
  test/workspace_chrome_test.dart test/mobile_polish_test.dart test/reader_tool_test.dart \
  test/reader_navigation_test.dart test/reader_crop_test.dart test/reader_zoom_test.dart \
  test/ink_test.dart test/reflow_reader_test.dart test/reader_ink_annotations_test.dart \
  test/workspace_pane_chrome_test.dart test/workspace_toolbar_test.dart \
  test/reader_chrome_test.dart test/ipad_adaptation_test.dart

MM_SCREENSHOTS=1 MM_FONT=/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc \
  flutter test --no-pub test/phone_reader_screenshots_test.dart --coverage \
  --coverage-path coverage/rebase-screens-verified.info --update-goldens
```

在 `packages/mm_pdf` 运行 `flutter test --no-pub test/phone_pdf_scroll_test.dart test/phone_scroll_physics_test.dart`，验证手机滑动物理、边界、打断和输入隔离；调用端的 phone/compact/旋转 gating 由 `phone_navigation_redesign_test` 验证。在 `packages/mm_design` 运行 `flutter test --no-pub --coverage --coverage-path coverage/rebase.info`。

全仓 `dart format --output=none --set-exit-if-changed apps packages` 仍检出 3 个 main 既有差异：map_ghost_node、map_source_chip 和 mm_core/testing/map_generator，未修改这些 GUL-627 文件。全仓 `python3 tool/coverage.py` 上一轮在未修改的 mm_assistant 协议用例遇到 30 秒超时；单独重跑通过。本轮按受影响套件验证，未声称整仓检查全绿。

深度自审确认没有丢失已通过评审的工具恢复、四态互斥、计时器取消、沉浸绘制、实时菜单、局部玻璃和旧平台隔离。复核了重放三次提交的 range-diff、旋转/抽屉入口、边界和触摸热区、provider 作用域及资源释放、无关文件范围、文案和文档一致性。没有新增后台工作、第三方依赖或敏感数据。之前的条件唤醒已停用。

原型差异：底部四态严格互斥；选择工具时默认页码，恢复标注工具或切换文档后显示带图标/色点/描边的工具球；画笔条以两行保留 44pt 热区；调色板、动效与减少动态效果沿用既有机制。范围外改动限于流式接入、mm_design 令牌/图标/兼容的局部 flat 覆盖，以及本轮手机横幅布局修复。
