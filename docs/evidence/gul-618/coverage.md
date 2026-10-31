# GUL-618 验证与覆盖率

比较基线：`93f78c04214ae26842bf4af57afb910395e6bd48`。环境：Linux aarch64、Flutter 3.47.2、Dart 3.13.2。

本 PR 新增/变更可执行行：**1406/1614 (87.11%)**，要求 ≥80%。

统计包含全部改动的生产 Dart 文件（也包含格式化造成的变更行），排除测试、生成的 l10n 和非可执行资源。逐行数据见 `changed-coverage.json`。图标和尺寸为 const，LCOV 不产生可执行行。

## 实际检查结果

- `dart format --output=none --set-exit-if-changed apps packages`：0 个改动。
- `flutter analyze --no-pub`：合并最新 main（93f78c04）后 No issues found。
- `python3 -m unittest discover -s tool/tests`：26 个测试通过。
- 5 个全文翻译相关测试文件：**45 项通过**，包括六张 Linux golden 的精确比对。
- 合并 95c79cee 后，对上述 5 文件以及 `map_update_test.dart`、`map_generation_ui_test.dart`、`map_generation_flow_test.dart` 执行 `flutter test --no-pub --concurrency=4 --coverage --coverage-package='^(marginmind|mm_core|mm_assistant)$'`：**67 项通过**；`mm_assistant` 的 `dart test --coverage=coverage/postmerge test/map_generation_test.dart`：**13 项通过**。
- 最后同步 93f78c04 后，运行下列应用集成回归：**192 项通过、4 项基线失败**；45 项翻译测试全部通过。失败仅为 `workspace_chrome_test.dart` 中已独立复现的 393/402 宽度 reader/map dock 四项。设计包相关测试 **71 项通过**，PDF 包全量 **127 项通过**。
- 原始 `python3 tool/coverage.py`（合入 95c79cee 前）：退出 1，停在 mm_design 的 `phone_glass_light` golden；当时的分支与独立 main（62c179ec）均为相同的 79 像素差异。
- 继续对 `mm_platform`、`mm_pdf`、`apps/marginmind` 执行 `flutter test --no-pub --coverage --reporter expanded`。前两包分别 61、121 项通过。
- 合并 95c79cee 前的全量应用：**1246 通过、36 跳过、10 基线失败**。这是历史全量结果；93f78c04 修复后的 `liquid_glass_test.dart` 在最终集成回归中通过，`workspace_chrome_test.dart` 的四项既有失败仍在。未声称最终版本全量测试全部通过。
- `python3 tool/coverage.py --report-only`：合并全部 12 个包的实测报告，汇总如下。

## 全仓 LCOV 汇总

| Package | Covered / lines | Coverage |
| --- | ---: | ---: |
| apps/marginmind | 29533 / 36649 | 80.58% |
| packages/mm_assistant | 2729 / 2802 | 97.39% |
| packages/mm_book | 1300 / 1364 | 95.31% |
| packages/mm_core | 5860 / 6001 | 97.65% |
| packages/mm_data | 685 / 712 | 96.21% |
| packages/mm_design | 2769 / 3093 | 89.52% |
| packages/mm_layout | 165 / 165 | 100.00% |
| packages/mm_pdf | 2076 / 2228 | 93.18% |
| packages/mm_platform | 609 / 656 | 92.84% |
| packages/mm_reflow | 1058 / 1115 | 94.89% |
| packages/mm_research | 637 / 655 | 97.25% |
| **Total** | **47421 / 55440** | **85.54%** |

Required: 80%.

## 全部改动文件

| 文件 | 全文件覆盖率 | 新增/变更执行行覆盖率 |
| --- | ---: | ---: |
| `apps/marginmind/lib/app/app_commands.dart` | 731/801 (91.26%) | 17/22 (77.27%) |
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
| `apps/marginmind/lib/features/workspace/widgets/map_source_chip.dart` | 27/27 (100.00%) | 4/4 (100.00%) |
| `apps/marginmind/lib/features/workspace/widgets/reader_compare_controls.dart` | 250/264 (94.70%) | 18/20 (90.00%) |
| `apps/marginmind/lib/features/workspace/widgets/reader_pane.dart` | 556/1060 (52.45%) | 12/41 (29.27%) |
| `apps/marginmind/lib/features/workspace/widgets/reader_translation_view.dart` | 304/337 (90.21%) | 164/196 (83.67%) |
| `apps/marginmind/lib/features/workspace/widgets/workspace_sidebar.dart` | 261/380 (68.68%) | 41/43 (95.35%) |
| `apps/marginmind/lib/features/workspace/workspace_screen.dart` | 299/377 (79.31%) | 4/4 (100.00%) |
| `packages/mm_core/lib/src/testing/map_generator.dart` | 38/38 (100.00%) | 12/12 (100.00%) |
| `packages/mm_design/lib/src/icons/mm_icons.dart` | 无可执行行 | 无可执行行 |
| `packages/mm_design/lib/src/tokens/metrics.dart` | 无可执行行 | 无可执行行 |

## 最终集成回归命令

在 `apps/marginmind` 下：

```sh
flutter test --no-pub --concurrency=4 --coverage --coverage-package='^(marginmind|mm_core|mm_assistant)$' \
  test/full_translation_test.dart test/translation_controls_test.dart \
  test/translation_lifecycle_test.dart test/translation_entry_points_test.dart \
  test/translation_page_grid_test.dart test/map_update_test.dart \
  test/map_generation_ui_test.dart test/map_generation_flow_test.dart \
  test/document_map_navigation_test.dart test/phone_layout_test.dart \
  test/phone_navigation_redesign_test.dart test/phone_sidebar_regression_test.dart \
  test/phone_workspace_sidebar_test.dart test/phone_settings_layout_test.dart \
  test/settings_test.dart test/library_test.dart test/review_card_view_test.dart \
  test/review_scope_test.dart test/workspace_chrome_test.dart \
  test/liquid_glass_test.dart test/assistant_settings_ui_test.dart --reporter expanded
```

在 `packages/mm_design` 下：

```sh
flutter test --no-pub --coverage test/phone_navigation_test.dart test/phone_test.dart test/liquid_glass_test.dart test/tokens_test.dart --reporter expanded
```

在 `packages/mm_pdf` 下：

```sh
flutter test --no-pub --coverage --reporter expanded
```

## 历史全量失败的基线核对

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

最终推送时 main 又合入 GUL-627（95c79cee），随后再次同步。将相对 3491cdaf 变化的 10 个生产源文件旧覆盖率记录全部丢弃，以合并后 67 项应用测试和 13 项模型测试的当前源码记录替换；未变化的源文件保留全量实测记录。按包重新写入报告，再运行 `python3 tool/coverage.py --report-only`。因此本表使用最新文件与行号，未把合并前的旧行号应用到新代码。

最后同步 main 的 GUL-626/GUL-632（93f78c04），再次移除相对 a0d39a11 变化的所有生产源文件旧记录，改用最终 192 项应用、71 项设计和 127 项 PDF 测试的当前源码覆盖率；仅保留内容未变化文件的既有记录，再由仓库工具重新汇总。

## 自审结论

检查入口、文档/语言作用域、启动/暂停/继续/检查点/停止/移除/重开恢复链路，非法与极值输入、慢加载和失败分支，异步销毁、订阅释放、在途结果保存、缓存去重、设计令牌、文案和凭证边界。修复了自适应工具栏遗漏、空闲胶囊遗漏、页码校验、Enter 误启动、删除与读取竞态、销毁后访问 provider，以及末尾空白页网格遗漏；相关测试和 golden 通过。
