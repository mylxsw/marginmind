# GUL-628 验证记录

基于 `29b0c4d`，已同步手机端改动并解决文案与 PDF 导出的冲突。

| 位置 | 命令 | 结果 |
| --- | --- | --- |
| 仓库根目录 | `flutter analyze --no-pub` | 无问题 |
| `packages/mm_core` | `flutter test --no-pub --coverage` | 321 通过 |
| `packages/mm_assistant` | `flutter test --no-pub --coverage` | 267 通过 |
| `packages/mm_pdf` | `flutter test --no-pub --coverage` | 128 通过 |
| `apps/marginmind` | `flutter test --no-pub --coverage` | 1271 通过，44 跳过，8 项既有失败 |

8 项失败均在独立的 `29b0c4d` 检出中复现，没有新增失败：

- `adaptive_layout_test.dart`：小屏 iPhone 全屏布局、iPhone 顶部切换控件，2 项。
- `workspace_chrome_test.dart`：393/402 宽度的手机脑图 dock，2 项。
- `study_notes_ai_ui_test.dart`：Android 紧凑 AI 设置布局，1 项。
- `note_rich_export_test.dart`：paper/plain/night 金样，3 项。

新增可执行行覆盖率 **361 / 376 = 96.01%**。合并上述四处 LCOV，以父提交 `29b0c4d` 对比新增和替换行，忽略纯缩进变化；包含新增文件及生成的本地化代码。

截图为可选测试，未提交生成文件。运行 `MM_SCREENSHOTS=... MM_FONT=... flutter test --no-pub test/map_generation_screenshots_test.dart --plain-name 'Capture enhancements'`；场景 2、14 各有浅色和深色截图，通过任务附件交付。

自审检查了范围和页码校验、逐字匹配与锚点、保留/放弃/撤销、OCR 失败/取消/并发、缓存隔离和来源能力。修复了 OCR 副本路径、摘录预览字段误入写入操作、无跳转页目录分组、同页目录排序和窄设置窗口溢出。
