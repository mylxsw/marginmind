# 测试与基线比较

环境：Flutter 3.47.6 / Dart 3.13.5，macOS，同一台机器、同一 SDK。基线为未包含本轮修改的 `f0a976d`，在独立临时工作树运行完整测试；验证后已删除临时工作树。

| 检查 | 结果 |
| --- | --- |
| 完整应用测试，基线 | 1397 通过，54 跳过，21 失败 |
| 完整应用测试，最终 | 1415 通过，54 跳过，20 失败 |
| 新增失败用例 | 0；最终失败均在基线有同名失败 |
| 核心 Tab / 参考 / 编辑事务 / AI 定向组合 | 49 通过；后续完整回归再次覆盖 |
| mm_design 下拉菜单 Escape 回归 | 3 通过 |
| macOS 原生窗口 | 1 通过，5 张深浅色状态截图，未捕获 Flutter 异常 |
| 静态检查 | lib、test、原生视觉测试均无问题 |
| 正常入口 macOS Release | `lib/main.dart` 构建成功，Foliarc.app 93.5MB |

完整测试命令：在 `apps/marginmind` 运行 `flutter test --no-pub --reporter expanded`。静态检查命令为 `flutter analyze --no-pub lib test integration_test/workspace_tabs_visual_test.dart`。正常入口构建命令为 `flutter build macos --release --no-pub --target lib/main.dart`。

本轮修复了从旧入口断言迁移时发现的实际问题：窄窗和 320pt 页面侧栏溢出、关闭的菜单吞掉 Escape、阅读翻译作用域缺失、参考保存提前销毁，以及原文/脑图命令路由。阅读位置、翻译、编辑、原文引用、复习和标签等相关用例已按新规则回归；没有通过更新截图基准来消除失败。

## 最终保留的基线失败

这些同名失败在 `f0a976d` 复现。主要包括已有的截图基准差异、旧菜单/布局断言，以及阅读时单次脑图重建断言；不是完整测试全绿的声明。

- `adaptive_layout_test.dart: touch windows iPad portrait: source above map, sidebar drawer and companion panel`
- `adaptive_layout_test.dart: touch windows iPhone: one pane at a time with a top switch and thumb dock`
- `full_translation_test.dart: FullTranslation Widgets & Visual Evidence FullTranslationCheckpoint renders expanded and collapsed and captures screenshots`
- `full_translation_test.dart: FullTranslation Widgets & Visual Evidence FullTranslationPanel renders running and review states and captures screenshots`
- `full_translation_test.dart: FullTranslation Widgets & Visual Evidence FullTranslationStrip renders key, no-model, offline, budget strips, actions, and goldens`
- `ipad_adaptation_test.dart: tablet split grip and compact tools dark`
- `ipad_adaptation_test.dart: tablet split grip and compact tools light`
- `mobile_polish_test.dart: Android portrait: library title fits and search still filters`
- `mobile_polish_test.dart: iPhone 402×874: library title fits and search still filters`
- `note_rich_export_test.dart: share night widget golden and 2x PNG`
- `note_rich_export_test.dart: share paper widget golden and 2x PNG`
- `note_rich_export_test.dart: share plain widget golden and 2x PNG`
- `popover_response_test.dart: reading, translation, AI and service popovers are complete in their first frame`
- `reader_chrome_test.dart: reader buttons share foreground colors in dark`
- `reader_chrome_test.dart: reader buttons share foreground colors in light`
- `reader_chrome_test.dart: window title (U-R5) reader tools control the sidebar and appearance separately`
- `reading_rebuild_test.dart: disk-backed 300-node workspace ignores reading metadata and library summary emissions`
- `reading_rebuild_test.dart: page changes and debounced saves do not rebuild workspace panes or menus`
- `workspace_chrome_test.dart: phone map dock preserves items through hide and reveal at 393.0`
- `workspace_chrome_test.dart: phone map dock preserves items through hide and reveal at 402.0`

## 验证边界

原生窗口使用本地临时资料和脚本模型，验证实际 Flutter 渲染与界面流转；没有读取用户资料库或发起真实模型请求。手机/iPad 的组件布局回归已运行，实体设备未验证。本轮未替换用户已安装的应用，Release 产物位于工作区 build 目录。
