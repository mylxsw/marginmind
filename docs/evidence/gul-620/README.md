# GUL-620：全文翻译段落操作

基线：`d2d7a049`（最新 main 上的 GUL-618）。环境：Linux aarch64，Flutter 3.47.2 / Dart 3.13.2。

实现已译段落的 28pt MMGlass 悬停工具条、单段重新翻译与追加旧值撤销、原地编辑与复制，以及失败段落原地重试。面板 / 检查点的失败重试和移除确认沿用现有链路，并补充真实 widget 回归。没有改动标题条和任务胶囊。

`paragraph-light.png` / `paragraph-dark.png` 是 Flutter widget 实际渲染的 2× 截图，包含悬停工具条与失败段落。中文字体只用于截图；golden 使用测试字体，图标加载仓库锁定的字体资源。

截图命令（在 `apps/marginmind` 下）：

```sh
TRANSLATION_EVIDENCE_DIR="$PWD/../../docs/evidence/gul-620" \
TRANSLATION_EVIDENCE_FONT=/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc \
flutter test --no-pub test/translation_paragraph_test.dart \
  --plain-name 'paragraph failure and hover toolbar golden' --reporter expanded
```

自审覆盖入口到持久化及 reader 更新、空编辑与 IME、键盘保存/换行/放弃、离线/失败、相同文本复用、异步与关闭、作用域和凭证边界。修复了重译在途时覆盖新编辑、过期撤销覆盖后续编辑、失败写入丢弃后续付费结果、离开 reader 后 HUD 操作访问已销毁状态、切换目标语言时编辑串写，以及编辑标记进入选区的问题。编辑标记在可选文本外；摘录卡片沿用译文正文与原文 PDF 段落定位。

## Review 修正（PR #157）

Enter 保存时先 trim：内容为空或与当前译文相同，直接退出编辑并保留旧值；不访问编辑控制器、不追加日志、不显示保存 HUD，也不会把 AI 译文误标为手动修改。

新增四个 widget 回归：原样保存、仅改变首尾空白、空字符串、纯空白。均验证编辑框关闭、显示值与 `store.entries` 不变、持久化出处仍为 AI、没有 ✎ 或保存 HUD；原有编辑/键盘/拷贝综合用例中的空文本断言同步更新。

- `dart analyze`：No issues found。
- 两个变更 Dart 文件的 `dart format --output=none --set-exit-if-changed`：0 改动；`git diff --check` 通过。
- 下述七个翻译文件的最终覆盖率测试：**71 项通过**，其中段落 **15 项**；原有 Enter、⌘Enter 保存、Shift+Enter 换行、Esc、拷贝及持久化回归仍通过。
- 重新执行 `python3 tool/coverage.py`：前八个包通过，随后在 `mm_design` 的 `393x852 phone materials light` golden 失败（217 通过、1 失败），退出 1；该差异已在独立 main 复现，未改其 golden。后续包沿用下述既有完整报告，不宣称本次全量通过。
- `python3 tool/coverage.py --report-only`：**通过，91.52%（51,519 / 56,295）**；PR 新增/变更可执行行 **226/240（94.17%）**。丢弃应用旧报告的整个段落组件记录，使用本次 71 项测试的新记录，再合并源码未变部分的既有报告；`changed-coverage.json` 的 SHA-256 同步更新。
- 自审检查了空值/trim/未修改分支、重复 Enter 的 busy 守卫、实际编辑保存链路、异步和销毁、安全与文档一致性；修复 review 指出的两处行为偏差，没有新增资源或异步任务。

## 验证记录

- `dart analyze`：No issues found。
- `dart format --output=none --set-exit-if-changed apps packages`：826 个文件，0 个改动。
- `python3 -m unittest discover -s tool/tests`：26 项通过。
- 七个翻译测试文件（`translation_paragraph`、`reader_translation`、`full_translation`、`translation_controls`、`translation_lifecycle`、`translation_entry_points`、`translation_page_grid`）：冻结最终实现后 67 项全部通过，其中段落测试 11 项（含阅读纸张对比度、完成任务后唯一失败段落的在途展示）。
- `mm_assistant` 全量：272 项通过。最终调度器改动后，`dart test test/translation_scheduler_test.dart test/paragraph_operations_test.dart --coverage=coverage/current`：32 项通过。
- `mm_core` 最终状态推导回归：8 项通过。
- `mm_platform`：61 项通过；`mm_pdf`：127 项通过。
- `mm_design`：217 项通过，1 项既有失败（`phone_glass_light`，79px）。独立 `d2d7a049` 检出同样失败，没有更新其 golden 或比较阈值。
- 在独立 `d2d7a049` 检出验证应用基线：三张 note-share golden、393/402 宽度的 map dock、compact AI setup，以及 500 节点 p95 性能用例均复现失败。没有修改这些文件或阈值。

相关测试命令（在 `apps/marginmind`）：

```sh
flutter test --no-pub --concurrency=4 --coverage \
  --coverage-path=coverage/translation-current.info \
  --coverage-package='^(marginmind|mm_core|mm_assistant)$' \
  test/translation_paragraph_test.dart test/reader_translation_test.dart \
  test/full_translation_test.dart test/translation_controls_test.dart \
  test/translation_lifecycle_test.dart test/translation_entry_points_test.dart \
  test/translation_page_grid_test.dart --reporter expanded
```

基线验证命令（在独立检出的对应包）：

```sh
flutter test --no-pub test/phone_glass_test.dart --plain-name '393x852 phone materials light'
flutter test --no-pub --concurrency=2 test/touch_workspace_test.dart \
  test/workspace_chrome_test.dart test/note_rich_export_test.dart \
  test/study_notes_ai_ui_test.dart \
  --name 'touch selection mode remains|dock preserves items|widget golden and 2x PNG|compact AI setup and outline'
flutter test --no-pub test/mind_map_cache_test.dart \
  --plain-name '500 nodes: single text edit + measurement + reflow p95 below 16 ms'
```

失败原文和编辑标记沿用当前阅读墨色，避免深色应用内保留白纸时失去对比度；精确 golden 固定 Linux 渲染器，交互测试在所有宿主机运行。

## 新增/变更覆盖率

相对 `d2d7a049` 新增或变更的可执行生产 Dart 行：**226/240（94.17%）**，要求 ≥80%。逐文件未命中行见 `changed-coverage.json`。统计取 `git diff --unified=0 d2d7a049` 的新增行与 LCOV 执行行交集，排除测试与生成的 l10n；没有调整命中数或阈值。

## 全量结果与报告合并

`python3 tool/coverage.py` 的原始执行未完成（退出 143）；后续按包执行测试与覆盖率收集，最后运行 `python3 tool/coverage.py --report-only`：**通过，91.52%（51,517 / 56,293）**。

应用全量命令为 `flutter test --no-pub --concurrency=4 --coverage --reporter expanded`：原始结果 **1,310 通过、42 跳过、13 失败**。不能据此声称全量全绿。

- 9 项在独立 main 复现：3 张 note-share golden、2 项 map dock、compact AI setup、2 项 adaptive layout、500 节点性能阈值。设计包另有上述 79px golden 基线差异。
- 4 项为较早启动的全量编译版本与后补测试断言的差异：保存 HUD、移除 HUD、唯一失败段落的在途状态、白纸对比度。检查该轮 Dart kernel 的内嵌源码，确认 `_save` 仍是没有 HUD 的早期实现。冻结最终源码后，七个翻译文件的 **67 项全部通过**，其中包含这四项；调度器 32 项、状态模型 8 项再次通过。

补充的 main 复现命令：

```sh
flutter test --no-pub test/adaptive_layout_test.dart \
  --plain-name 'small iPhone 320×568: every screen lays out without overflow'
flutter test --no-pub test/adaptive_layout_test.dart \
  --plain-name 'iPhone: one pane at a time with a top switch and thumb dock'
```

覆盖率使用实际报告合并：丢弃较早全量中的六个变更生产文件及 l10n 查找器的旧记录，使用冻结源码后的翻译、调度器和状态测试报告；未变化文件保留全量记录。语言 getter 只在末尾追加，原有前缀行号不变。没有把过期行号应用到变更文件，也没有调整命中数或阈值。`changed-coverage.json` 保留最终生产源码 SHA-256，且已逐一校验。

| Package | Covered / lines | Coverage |
| --- | ---: | ---: |
| apps/marginmind | 33606 / 37469 | 89.69% |
| packages/mm_assistant | 2762 / 2835 | 97.43% |
| packages/mm_book | 1300 / 1364 | 95.31% |
| packages/mm_core | 5854 / 6002 | 97.53% |
| packages/mm_data | 685 / 712 | 96.21% |
| packages/mm_design | 2767 / 3094 | 89.43% |
| packages/mm_layout | 165 / 165 | 100.00% |
| packages/mm_pdf | 2076 / 2228 | 93.18% |
| packages/mm_platform | 609 / 656 | 92.84% |
| packages/mm_reflow | 1058 / 1115 | 94.89% |
| packages/mm_research | 637 / 655 | 97.25% |
| **Total** | **51519 / 56295** | **91.52%** |

Required: 80%.
