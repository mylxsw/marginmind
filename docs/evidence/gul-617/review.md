GUL-617 review 修订验证（2026-10-31）

批量请求在发起时保存所属 job ID；每次重试、异步准备后的发送以及段落失败记录都要求该任务仍为 running。打包拆分沿用相同 job ID，避免 stopped 重新开放按需闸门后，旧批量请求误用该权限。成功的在途结果继续保存，显式单段请求仍可绕过批次闸门。

修复前先运行新增回归测试，复现单段 4 次、双段 8 次调用，以及停止后写入段落失败。修复后的回归测试验证：

- 退避期间停止：单段总计 1 次、双段总计 2 次调用，内存和持久化 failures 均为空。
- 停止后到达的段落错误不写入 failures。
- 停止后的无效打包响应不发出拆分请求，显式单段请求仍能成功。

合并 main `fb4b6e3`。`packages/mm_core/lib/testing.dart` 同时保留 `in_memory_translation_store.dart` 与 `map_generator.dart`；main 随后新增脑图引擎造成的 `packages/mm_assistant/lib/mm_assistant.dart` 冲突也已解决，同时保留 `translation_scheduler.dart` 与 `map_generation.dart`。

实际验证：

| 命令 / 工作目录 | 结果 |
| --- | --- |
| `dart analyze packages/mm_assistant packages/mm_core packages/mm_data apps/marginmind` / 根目录 | 无告警 |
| `dart test --coverage=coverage` / `packages/mm_assistant`（事先清空 coverage） | 266 项通过 |
| `dart test test/translation_scheduler_test.dart` / `packages/mm_assistant` | 27 项通过 |
| `dart test` / `packages/mm_core` | 319 项通过 |
| `dart test` / `packages/mm_data` | 77 项通过 |
| `flutter test test/reader_translation_test.dart test/reflow_advanced_test.dart test/selection_translation_test.dart test/reader_compare_test.dart` / `apps/marginmind` | 48 项通过 |
| `dart format --output=none --set-exit-if-changed` / 本轮三个修改的 Dart 文件 | 无格式变化 |
| `git diff --check` | 通过 |

使用 `dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib` 生成报告。相对修订前 `d9d687a`，本轮调度器新增可执行行覆盖率为 **12/12（100%）**，整个调度器为 **440/463（95.03%）**，明细见 `review-coverage.json`。本轮未重新运行全仓测试，初次全仓验证及已有 golden 失败见 `coverage.md`。

自审核对了任务身份和状态的请求边界、打包递归、异步发送前的再次检查、停止后的失败记录、在途成功结果保存，以及停止后新的按需/显式请求权限。没有把 stopped 全局禁用，以保留结束任务后的正常对照阅读。
