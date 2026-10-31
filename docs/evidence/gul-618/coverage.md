# GUL-618 验证与覆盖率

比较基线：`62c179ecbb4f6dbe0bb3d7812b0ebef21a1a1d46`。环境：Linux aarch64、Flutter 3.47.2、Dart 3.13.2。

本 PR 新增/变更可执行行：**1599/1831 (87.33%)**，要求 ≥80%。

统计包含全部改动的生产 Dart 文件（也包含格式化造成的变更行），排除测试、生成的 l10n 和非可执行资源。逐行数据见 `changed-coverage.json`。图标和尺寸为 const，LCOV 不产生可执行行。

## 实际检查结果

- `dart format --output=none --set-exit-if-changed apps packages`：0 个改动。
- `flutter analyze --no-pub`：No issues found（最后的空白页修复与 45 项测试在隔离检出中验证，再原样应用）。
- `python3 -m unittest discover -s tool/tests`：26 个测试通过。
- 5 个全文翻译相关测试文件：**45 项通过**，包括六张 Linux golden 的精确比对。
- 原始 `python3 tool/coverage.py`：退出 1，停在 mm_design 的 `phone_glass_light` golden；当前分支与独立 main 均为相同的 79 像素差异。
- 继续对 `mm_platform`、`mm_pdf`、`apps/marginmind` 执行 `flutter test --no-pub --coverage --reporter expanded`。前两包分别 61、121 项通过。
- 全量应用：**1246 通过、36 跳过、10 基线失败**。下表列明，未把全量测试写作通过。
- `python3 tool/coverage.py --report-only`：合并全部 12 个包的实测报告，汇总如下。

## 全仓 LCOV 汇总

| Package | Covered / lines | Coverage |
| --- | ---: | ---: |
| apps/marginmind | 31946 / 35779 | 89.29% |
| packages/mm_assistant | 2719 / 2799 | 97.14% |
| packages/mm_book | 1300 / 1364 | 95.31% |
| packages/mm_core | 5804 / 6000 | 96.73% |
| packages/mm_data | 685 / 712 | 96.21% |
| packages/mm_design | 2598 / 2918 | 89.03% |
| packages/mm_layout | 165 / 165 | 100.00% |
| packages/mm_pdf | 2034 / 2186 | 93.05% |
| packages/mm_platform | 609 / 656 | 92.84% |
| packages/mm_reflow | 1058 / 1115 | 94.89% |
| packages/mm_research | 637 / 655 | 97.25% |
| **Total** | **49555 / 54349** | **91.18%** |

Required: 80%.

## 全部改动文件

| 文件 | 全文件覆盖率 | 新增/变更执行行覆盖率 |
| --- | ---: | ---: |
| `apps/marginmind/lib/app/app_commands.dart` | 729/801 (91.01%) | 17/22 (77.27%) |
| `apps/marginmind/lib/features/map_generation/map_generation_controller.dart` | 383/434 (88.25%) | 14/17 (82.35%) |
| `apps/marginmind/lib/features/map_generation/widgets/generate_map_sheet.dart` | 238/265 (89.81%) | 167/179 (93.30%) |
| `apps/marginmind/lib/features/map_generation/widgets/map_generation_bar.dart` | 206/245 (84.08%) | 13/14 (92.86%) |
| `apps/marginmind/lib/features/workspace/full_translation.dart` | 188/214 (87.85%) | 188/214 (87.85%) |
| `apps/marginmind/lib/features/workspace/reader_translation.dart` | 158/167 (94.61%) | 8/8 (100.00%) |
| `apps/marginmind/lib/features/workspace/translation_schedulers.dart` | 89/93 (95.70%) | 55/57 (96.49%) |
| `apps/marginmind/lib/features/workspace/translation_task_summary.dart` | 41/44 (93.18%) | 41/44 (93.18%) |
| `apps/marginmind/lib/features/workspace/widgets/full_translation_capsule.dart` | 92/92 (100.00%) | 92/92 (100.00%) |
| `apps/marginmind/lib/features/workspace/widgets/full_translation_checkpoint.dart` | 144/174 (82.76%) | 144/174 (82.76%) |
| `apps/marginmind/lib/features/workspace/widgets/full_translation_notifications.dart` | 19/22 (86.36%) | 19/22 (86.36%) |
| `apps/marginmind/lib/features/workspace/widgets/full_translation_panel.dart` | 272/295 (92.20%) | 272/295 (92.20%) |
| `apps/marginmind/lib/features/workspace/widgets/full_translation_sheet.dart` | 308/359 (85.79%) | 308/359 (85.79%) |
| `apps/marginmind/lib/features/workspace/widgets/map_ghost_node.dart` | 34/38 (89.47%) | 7/7 (100.00%) |
| `apps/marginmind/lib/features/workspace/widgets/map_source_chip.dart` | 24/27 (88.89%) | 4/4 (100.00%) |
| `apps/marginmind/lib/features/workspace/widgets/mind_map_canvas.dart` | 1927/1993 (96.69%) | 5/5 (100.00%) |
| `apps/marginmind/lib/features/workspace/widgets/reader_compare_controls.dart` | 250/264 (94.70%) | 18/20 (90.00%) |
| `apps/marginmind/lib/features/workspace/widgets/reader_pane.dart` | 785/1059 (74.13%) | 12/41 (29.27%) |
| `apps/marginmind/lib/features/workspace/widgets/reader_translation_view.dart` | 304/337 (90.21%) | 164/196 (83.67%) |
| `apps/marginmind/lib/features/workspace/widgets/workspace_sidebar.dart` | 290/331 (87.61%) | 43/45 (95.56%) |
| `apps/marginmind/lib/features/workspace/workspace_screen.dart` | 330/368 (89.67%) | 4/4 (100.00%) |
| `packages/mm_core/lib/src/testing/map_generator.dart` | 27/38 (71.05%) | 4/12 (33.33%) |
| `packages/mm_design/lib/src/icons/mm_icons.dart` | 无可执行行 | 无可执行行 |
| `packages/mm_design/lib/src/tokens/metrics.dart` | 无可执行行 | 无可执行行 |

## 基线失败核对

独立 main 检出固定在 `62c179ec`，使用同一 SDK、同一宿主运行以下失败用例，结果一致；没有更新范围外 golden 或放宽比较阈值。

| 用例 | 核对结果 |
| --- | --- |
| `mm_design/test/phone_glass_test.dart`：393x852 phone materials light | main 同样 79px 差异 |
| `liquid_glass_test.dart`：Android 411×914: the tab bar floats as a glass capsule clear of the safe area (variant: TargetPlatform.android) | 独立 main 复现相同失败 |
| `liquid_glass_test.dart`：iPhone 402×874: the tab bar floats as a glass capsule clear of the safe area (variant: TargetPlatform.iOS) | 独立 main 复现相同失败 |
| `note_rich_export_test.dart`：share night widget golden and 2x PNG | 独立 main 复现相同失败 |
| `note_rich_export_test.dart`：share paper widget golden and 2x PNG | 独立 main 复现相同失败 |
| `note_rich_export_test.dart`：share plain widget golden and 2x PNG | 独立 main 复现相同失败 |
| `study_notes_ai_ui_test.dart`：compact AI setup and outline wrap all footer actions without overflow (variant: TargetPlatform.android) | 独立 main 复现相同失败 |
| `workspace_chrome_test.dart`：phone map dock preserves items through hide and reveal at 393.0 | 独立 main 复现相同失败 |
| `workspace_chrome_test.dart`：phone map dock preserves items through hide and reveal at 402.0 | 独立 main 复现相同失败 |
| `workspace_chrome_test.dart`：phone reader dock preserves items through hide and reveal at 393.0 | 独立 main 复现相同失败 |
| `workspace_chrome_test.dart`：phone reader dock preserves items through hide and reveal at 402.0 | 独立 main 复现相同失败 |

复现命令（在独立 main 检出对应包下）：

```sh
flutter test --no-pub test/phone_glass_test.dart --plain-name '393x852 phone materials light'
flutter test --no-pub test/liquid_glass_test.dart --plain-name 'the tab bar floats'
flutter test --no-pub test/note_rich_export_test.dart --plain-name 'widget golden and 2x PNG'
flutter test --no-pub test/study_notes_ai_ui_test.dart test/workspace_chrome_test.dart --name 'compact AI setup and outline|dock preserves items'
```

## 统计方法

全仓使用仓库 `tool/coverage.py` 合并 LCOV。新增/变更覆盖率取 `git diff --unified=0 origin/main` 的新增行与 LCOV `DA` 执行行的交集，逐文件保留命中数和未命中行。

全量应用运行后，最后修复了任务面板的空白末页显示。为避免跨版本行号混合，丢弃全量报告中旧 `full_translation_panel.dart` 的记录，改用最终 45 项相关测试产生的该文件报告；其余生产源文件与全量运行完全相同。再以仓库工具的 `merge` / `write_lcov` 合并未变化文件和最终相关测试，最后运行 `--report-only`。未合并过期的面板执行行，也未修改任何命中数或阈值。

## 自审结论

检查入口、文档/语言作用域、启动/暂停/继续/检查点/停止/移除/重开恢复链路，非法与极值输入、慢加载和失败分支，异步销毁、订阅释放、在途结果保存、缓存去重、设计令牌、文案和凭证边界。修复了自适应工具栏遗漏、空闲胶囊遗漏、页码校验、Enter 误启动、删除与读取竞态、销毁后访问 provider，以及末尾空白页网格遗漏；相关测试和 golden 通过。
