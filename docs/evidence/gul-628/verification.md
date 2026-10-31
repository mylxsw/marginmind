# GUL-628 验证记录

已合并最新 main `d2d7a04`，按 PR #154 的评审修改场景 2、14 和缓存设置。

章节范围按钮放在文档行标题右侧，仅单选时显示；展开行使用 38pt 左内边距，部分选择显示混合态，无目录使用两个 64pt 页码输入框。页脚按范围计页并排除扫描版，sheet 恢复 `windowBackground`。

扫描提示条独立于生成条，使用规定的图标、文案、主按钮、关闭按钮及卡片样式。设置 sheet 和空脑图入口提前检查 OCR 状态，扫描版禁用生成及快捷键。缓存使用单行 `MMSettingsRow`，移除重复的 `mapCacheTitle`。

| 位置 | 命令 | 结果 |
| --- | --- | --- |
| 仓库根目录 | `flutter analyze --no-pub` | 无问题 |
| `packages/mm_core` | `flutter test --no-pub --coverage` | 321 通过 |
| `packages/mm_assistant` | `flutter test --no-pub --coverage` | 267 通过 |
| `packages/mm_pdf` | `flutter test --no-pub --coverage` | 128 通过 |
| `packages/mm_design` | `flutter test --no-pub --coverage` | 219 通过 |
| `apps/marginmind` | `flutter test --no-pub --coverage` | 1319 通过，46 跳过，8 项既有失败 |
| `apps/marginmind` | `flutter test --no-pub test/map_generation_enhancements_test.dart` | 最终自审修复后，15 项专项测试通过 |
| `apps/marginmind` | 截图测试（下述命令） | 4 项通过，输出 6 张截图 |

8 项失败均在独立的 `d2d7a04` 检出中复现，失败用例集合完全一致，没有新增失败：

- `adaptive_layout_test.dart`：小屏 iPhone 全屏布局、iPhone 顶部切换控件，2 项。
- `workspace_chrome_test.dart`：393/402 宽度的手机脑图 dock，2 项。
- `study_notes_ai_ui_test.dart`：Android 紧凑 AI 设置布局，1 项。
- `note_rich_export_test.dart`：paper/plain/night 金样，3 项。

对照命令：`flutter test --no-pub test/adaptive_layout_test.dart test/workspace_chrome_test.dart test/study_notes_ai_ui_test.dart test/note_rich_export_test.dart test/mind_map_cache_test.dart`；main 为 66 通过、8 失败。`mind_map_cache` 的 p95 用例在本次 main 和 PR 运行中均通过，因此失败数与上一轮评审记录的 9 项不同。

新增可执行行覆盖率 **468 / 483 = 96.89%**。合并上述五处 LCOV，以 main `d2d7a04` 对比新增和替换行，忽略纯缩进变化；包含新增文件及生成的本地化代码。

截图为可选测试，未提交生成文件。运行 `MM_SCREENSHOTS=... MM_FONT=... flutter test --no-pub test/map_generation_screenshots_test.dart --plain-name 'Capture enhancements'`；场景 2、14 各有浅色和深色截图，另有扫描版 sheet 的浅色和深色截图，通过任务附件交付。

深度自审检查了入口到生成/审阅/保留/撤销的链路、空选/页码越界/嵌套目录/同页排序、OCR 失败/取消/并发、控制器释放、缓存隔离、来源能力、安全及文案一致性。原实现中修复了 OCR 副本路径、摘录预览字段误入写入操作、无跳转页目录分组、同页目录排序和窄设置窗口溢出。本轮额外修复：空脑图快捷键绕过扫描检查；关闭待 OCR 提示时，Stack 重排导致提示条状态丢失并立即重现。对应回归测试已通过，未发现新的资源泄漏、越权或敏感信息泄漏。
