# GUL-631 阅读控件验收

本轮评审修复基于 main `62c179ec`；按评审要求，待 #152 合并后再 rebase 到 main。仅 phone + compact 启用新控件；iPad compact、iPad 横屏、macOS 和非 compact 手机保留旧路径。

393×852 浅深色截图由 Linux arm64 的 Flutter golden renderer 生成，安全区为顶部 54 / 底部 34；没有 iOS 模拟器，未运行 iOS 原生构建或真机验收。正文截图使用流式样本文档，画笔截图使用 PDF 占位背景；PDF 的跳页、标注、同步与撤销通过可控 PDF 后端验证。

| 场景 | 浅色 | 深色 |
| --- | --- | --- |
| 2 阅读 | [截图](02-reading-light.png) | [截图](02-reading-dark.png) |
| 3 工具栏与颜色 | [截图](03-tools-light.png) | [截图](03-tools-dark.png) |
| 3 画笔颜色、笔宽、笔形 | [截图](03-pen-light.png) | [截图](03-pen-dark.png) |
| 3 保留工具的球 | [截图](03-orb-light.png) | [截图](03-orb-dark.png) |
| 4 跳页 | [截图](04-scrub-light.png) | [截图](04-scrub-dark.png) |
| 5 沉浸 | [截图](05-immersive-light.png) | [截图](05-immersive-dark.png) |
| 9 脑图 | [截图](09-map-light.png) | [截图](09-map-dark.png) |

复现手机交互、截图和覆盖率（在 `apps/marginmind`）：

```bash
MM_SCREENSHOTS=1 MM_FONT=/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc \
  flutter test --no-pub test/phone_reader_controls_test.dart test/phone_reader_screenshots_test.dart \
  --coverage --coverage-path coverage/phone-reader-final.info --update-goldens
```

手机交互测试 14 项全部通过，截图测试 2 项通过，生成 14 张截图。变更执行行覆盖率 **87.12%（812 / 932）**，本轮评审修复为 **89.01%（162 / 182）**，见 `changed-coverage.json`。变更行来自相对 `62c179ec` 的 `git diff --unified=0`，按实际 LCOV 执行行计算，包含生成本地化代码；常量和抽象声明不计入执行行。控制器、手机组件、菜单和流式阅读器使用最终专项报告的行号；其余代码合并本轮受影响 app 和 mm_design 套件的 LCOV，未混用上一轮旧行号。

`flutter analyze --no-pub` 正常退出，No issues；20 个变更 Dart 文件 format 检查通过。4 个旧平台用例另行重跑通过，明确断言原有 flat 材质、菜单和导航仍保留。

受影响 app 套件命令：

```bash
MM_SCREENSHOTS=1 MM_FONT=/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc \
flutter test --no-pub --concurrency=3 --coverage --coverage-path coverage/review-final.info --update-goldens \
  test/phone_reader_controls_test.dart test/phone_reader_screenshots_test.dart test/workspace_chrome_test.dart \
  test/mobile_polish_test.dart test/liquid_glass_test.dart test/reader_tool_test.dart \
  test/reader_navigation_test.dart test/reader_crop_test.dart test/reader_zoom_test.dart \
  test/ink_test.dart test/reflow_reader_test.dart test/reader_ink_annotations_test.dart \
  test/workspace_pane_chrome_test.dart test/workspace_toolbar_test.dart \
  test/reader_chrome_test.dart test/ipad_adaptation_test.dart test/phone_layout_test.dart
```

本轮结果：155 通过、4 项既有失败（`liquid_glass_test` 两个资料库标签材质断言、`workspace_chrome_test` 两个脑图 fit 入口断言）。新阅读功能没有新增失败。本轮没有运行完整 app 包，也没有声称整包通过。最终手机与流式阅读器联合复检 23 项通过，最后的非订阅读取与 dock 专项 2 项通过。复检命令为 `flutter test --no-pub test/reflow_reader_test.dart test/phone_reader_controls_test.dart --coverage --coverage-path coverage/review-reflow-final.info`，以及 `flutter test --no-pub test/phone_reader_controls_test.dart --name 'event-only scope lookup|reflow reader shares' --coverage --coverage-path coverage/review-last.info`。

`packages/mm_design` 本轮全套：209 通过，1 项既有浅色材质 golden 相差 79 像素（0.02%）；在未修改的 `62c179ec` 独立 worktree 上复现了完全相同的差异，未更新原有基准图。

上一轮全仓 `python3 tool/coverage.py` 先行通过 mm_core、mm_book、mm_reflow、mm_reflow/example、mm_research；在未修改的 mm_assistant 的 map_generation 协议用例遇到 30 秒超时后退出。该用例单独以 `dart test test/map_generation_test.dart --plain-name 'timeouts, bytes, input, stop reasons, control and tool protocols' --timeout=2m --concurrency=1` 重跑通过。未修改超时阈值或生产代码，也未声称整仓覆盖率通过。

本轮使用 `dart format --output=none --set-exit-if-changed apps packages` 检查且不写文件，仍检出 main 已有 8 个格式差异：map_generation 的 controller、sheet、bar，map_ghost_node、map_source_chip、mind_map_canvas、workspace_sidebar，以及 mm_core/testing/map_generator。这些文件保留原样；本次修改文件单独 format 通过。GUL-627 的文件未作修改。

自审修复：底部边距与 SafeArea 重复相加；工具按钮被误当作正文点击；Esc 退出仍停留在 tools；脑图/浏览器的阅读入口未回到原文；上一笔异步保存结果可能收起下一笔的工具栏。复检涵盖空值/单页、手势取消、计时器重置/文档切换/dispose、停靠偏好、键盘/无障碍、能力禁用和 iPad/macOS 隔离。没有新增第三方 UI 依赖、文档数据迁移或敏感信息存储。

原型差异按批准方案处理：底部四态严格互斥，选择工具时默认只显示页码；恢复已选工具或切换文档后显示工具球，包含图标、色点和强调色描边。工具通过更多入口打开；颜色沿用可持久化的现有调色板，色点热区至少 44pt；动效复用应用现有 layout 令牌和降低动态效果设置。画笔条以两行显示颜色、笔宽、笔形和橡皮擦，以保留 44pt 热区；更多菜单保留撤销和完成，并实时跟随状态。跳页仅显示章节、页码与滑块，通过正文点击、阅读滚动、Esc 或无障碍 dismiss 收起。

边界外的小改动：`reflow_reader.dart` 接入相同共用位和全书进度；`mm_design` 新增手机几何令牌、独立下划线图标和向后兼容的 `MMFlatSurface.enabled` 局部覆盖；旧平台图标与默认 flat 行为不变；设计文档同步新行为。

本轮深度自审覆盖入口与文档切换、空值/边界、计时器及指针取消、dispose 顺序、异步回调与菜单关闭、材料作用域与弹出层继承、语言与令牌一致性、安全与平台隔离。除评审条目外，修复了玻璃作用域被顶部菜单捕获的问题、菜单选中回调持有已销毁 ref 的风险，并保留非手机流式导航原有 hover 区域。ReaderPane 和流式正文事件均以非订阅方式获取 slot 控制器。未引入新连接、后台异步任务、权限变更或敏感数据存储。
