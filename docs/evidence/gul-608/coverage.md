GUL-608 validation

多主题支持分别扩展、归纳上级和补全同级；整图扩展先确认计划，每个分支 1–8 条，总数不设上限，最多同时运行 3 个调用。归纳移动只影响预览，保留通过一个提议一次提交。

新增可执行行覆盖率：**463 / 473（97.89%）**。基准为本分支起点 `6d3ec223df1c375ab83febd8507e0910047ff96c`（PR merge base）；按新增行与合并 LCOV 的可执行行取交集统计，详情见 `changed-coverage.json`。

| Source | Covered / added executable lines | Coverage |
| --- | ---: | ---: |
| `apps/marginmind/lib/app/app_commands.dart` | 1 / 1 | 100.00% |
| `apps/marginmind/lib/features/assistant/expansion_context.dart` | 47 / 47 | 100.00% |
| `apps/marginmind/lib/features/assistant/expansion_controller.dart` | 163 / 165 | 98.79% |
| `apps/marginmind/lib/features/assistant/widgets/assistant_quick_actions.dart` | 5 / 5 | 100.00% |
| `apps/marginmind/lib/features/assistant/widgets/expansion_widgets.dart` | 130 / 132 | 98.48% |
| `apps/marginmind/lib/features/workspace/widgets/map_pane.dart` | 47 / 49 | 95.92% |
| `apps/marginmind/lib/features/workspace/widgets/mind_map_cache.dart` | 24 / 24 | 100.00% |
| `apps/marginmind/lib/features/workspace/widgets/mind_map_canvas.dart` | 19 / 20 | 95.00% |
| `packages/mm_design/lib/src/widgets/menu.dart` | 27 / 30 | 90.00% |

实际验证记录：

- `flutter analyze`：无问题。
- `dart format --set-exit-if-changed apps packages`：684 个文件，无改动。
- `git diff --check`：通过。
- `python3 tool/coverage.py`：所有包及完整应用套件均已运行。应用首轮为 1008 通过、34 跳过、1 失败；唯一失败是原有 Android 阅读测试还从“更多”查找已移至工具条的下划线。仅更新该测试入口，产品行为未改。
- 在 `apps/marginmind` 运行 `flutter test --no-pub --coverage --coverage-path=coverage/reflow-lcov.info test/reflow_reader_test.dart`：修正后 8 项全部通过。
- 在 `apps/marginmind` 运行 `MM_SCREENSHOTS=../../docs/evidence/gul-608 flutter test --no-pub --coverage --coverage-path=coverage/expansion-lcov.info test/expansion_test.dart`：25 项全部通过，包括多目标并发上限、停止后迟到结果隔离、归纳预览恢复、共同上级校验、计划数量调整、中心主题主/次按钮及兼容入口、选中主题原文范围，以及 64 条一次保留、一张凭据、一步撤销与重做。
- 合并完整应用 LCOV 与上述两个补充报告后运行 `python3 tool/coverage.py --report-only`：通过，整体 91.73%。

共享机器上并行运行时，原有 500 节点布局基准 p95 为 17.17 ms，超过 16 ms。完整应用套件通过临时 `concurrency: 1` 配置串行执行，该基准 median=1.009 ms、p95=1.580 ms；未修改或跳过测试和门槛。临时配置已删除。

自审检查了入口到写入的闭环、空结果与部分失败、共同上级与原文范围、取消/重试/连接释放、模型输入别名、预览与真实树隔离、revision 校验及一次提交/撤销。修复了多选自动缩放的单目标假设、英文选项溢出、部分分支无新内容时误丢弃其他草稿、计划新分支的选择恢复和层级额度，以及归纳上下文未区分选中/未选主题的问题。预览中新增与移动的操作全部交给现有执行器，未新增文件格式或修改对话提议限制。

截图：[多选入口](multi-options.png)、[多目标审阅](multi-review.png)、[归纳预览](group-preview.png)、[中心主题入口](root-options.png)、[计划卡](map-plan.png)、[整图审阅](map-review.png)、[64 条草稿](map-64-review.png)。均由 widget 测试生成并目视检查。

| Package | Covered / lines | Coverage |
| --- | ---: | ---: |
| apps/marginmind | 25454 / 28382 | 89.68% |
| packages/mm_assistant | 2076 / 2132 | 97.37% |
| packages/mm_book | 1300 / 1364 | 95.31% |
| packages/mm_core | 5063 / 5207 | 97.23% |
| packages/mm_data | 542 / 558 | 97.13% |
| packages/mm_design | 2067 / 2290 | 90.26% |
| packages/mm_layout | 165 / 165 | 100.00% |
| packages/mm_pdf | 1814 / 1941 | 93.46% |
| packages/mm_platform | 596 / 639 | 93.27% |
| packages/mm_reflow | 1058 / 1115 | 94.89% |
| packages/mm_research | 637 / 655 | 97.25% |
| **Total** | **40772 / 44448** | **91.73%** |

Required: 80%.
