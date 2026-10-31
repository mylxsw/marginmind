GUL-617 验证记录（2026-10-31，Dart 3.13.2 / Flutter 3.47.2，macOS arm64）

相对实现起点 `24d85a9`，新增可执行行覆盖率 **570/605 = 94.21%**。用 `git diff --unified=0 HEAD` 的新增行与 LCOV 的 DA 行求交集；mm_assistant 使用最终整包报告，阅读入口使用定向 widget 报告，mm_core 测试适配器补充跨包 VM/widget 覆盖率，避免 Flutter 默认只收集当前包而低估已执行代码。

| 文件 | 新增行覆盖 |
| --- | ---: |
| `apps/marginmind/lib/features/workspace/reader_translation.dart` | 22/27 (81.48%) |
| `apps/marginmind/lib/features/workspace/translation_schedulers.dart` | 35/37 (94.59%) |
| `apps/marginmind/lib/features/workspace/workspace_controller.dart` | 1/1 (100.0%) |
| `packages/mm_assistant/lib/src/providers.dart` | 6/6 (100.0%) |
| `packages/mm_assistant/lib/src/translation.dart` | 35/35 (100.0%) |
| `packages/mm_assistant/lib/src/translation_scheduler.dart` | 434/457 (94.97%) |
| `packages/mm_core/lib/src/content/translation_job.dart` | 5/5 (100.0%) |
| `packages/mm_core/lib/src/testing/in_memory_content_repository.dart` | 2/2 (100.0%) |
| `packages/mm_core/lib/src/testing/in_memory_translation_store.dart` | 24/29 (82.76%) |
| `packages/mm_data/lib/src/file_library_store.dart` | 1/1 (100.0%) |
| `packages/mm_data/lib/src/file_translation_store.dart` | 5/5 (100.0%) |

实际验证（纯 Dart 覆盖率目录在最终运行前清空，避免旧运行记录混入）：

- 根目录 `dart analyze`：无告警；`git diff --check`：通过。
- `packages/mm_assistant`：`dart test --coverage=coverage`：249 项通过，包含原有 `translation_test.dart` 与新增调度器测试；随后 `dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib`。
- `apps/marginmind`：`flutter test --coverage --coverage-path=coverage/translation-lcov.info test/reader_translation_test.dart test/reflow_advanced_test.dart test/selection_translation_test.dart test/reader_compare_test.dart`：48 项通过。
- 跨包报告：`flutter test --coverage --coverage-package='^(marginmind|mm_core|mm_assistant)$' --coverage-path=coverage/translation-cross-lcov.info test/reader_translation_test.dart test/reflow_advanced_test.dart`：21 项通过；纯 Dart VM 原始报告补充 `--report-on=../mm_core/lib`。
- 根目录 `python3 tool/coverage.py`：11 个包/示例测试套件通过；应用 1170 项通过、34 项跳过，3 项笔记分享 golden 失败。paper / plain / night 的预期图片为 330×370，实际为 330×354。在独立 main `7311871` 工作树运行 `flutter test --coverage test/note_rich_export_test.dart --plain-name 'widget golden and 2x PNG'`，同样 3 项失败。本改动不更新这些基线图。
- 根目录 `python3 tool/coverage.py --report-only`：合并已生成报告成功，整体覆盖率如下（全套运行因上述已有 golden 失败退出 1，不能声称全仓测试全绿）。

| Package | Covered / lines | Coverage |
| --- | ---: | ---: |
| apps/marginmind | 28634 / 31993 | 89.50% |
| packages/mm_assistant | 2563 / 2642 | 97.01% |
| packages/mm_book | 1300 / 1364 | 95.31% |
| packages/mm_core | 5474 / 5658 | 96.75% |
| packages/mm_data | 685 / 712 | 96.21% |
| packages/mm_design | 2559 / 2873 | 89.07% |
| packages/mm_layout | 165 / 165 | 100.00% |
| packages/mm_pdf | 2034 / 2186 | 93.05% |
| packages/mm_platform | 610 / 656 | 92.99% |
| packages/mm_reflow | 1058 / 1115 | 94.89% |
| packages/mm_research | 637 / 655 | 97.25% |
| **Total** | **45719 / 50019** | **91.40%** |

Required: 80%.


自审检查了可见页所有段落的优先级、入口到存储的完整链路、批次与手动闸门、重复键和单段并发、重试耗尽、断网恢复、退出/恢复、错误原因与用量 JSON、持久化失败、超时取消、连接生命周期及提示词边界。修复了长连接沿用整段会话截止时间/字节预算、传输层隐藏重试、失败响应漏记用量、恢复命令与落盘收尾竞态、429 worker 无法重新加入，以及关闭窗口覆盖检查点状态的问题。未增加全文翻译 UI；系统联网事件通过调度器的 `setOnline` 端口提供，远程/本机模型的可用性由宿主决定。
