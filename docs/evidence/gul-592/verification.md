# GUL-592 验证记录

已 rebase `origin/main` 的 `6d3ec22`。导出和分享的实现与附件可供评审；由于 main 的现有阅读器测试失败，PR 保持草稿，任务未达到全量测试全绿的交付条件。

| 检查 | 实际结果 |
| --- | --- |
| `flutter analyze --no-pub` | 通过，无问题 |
| `dart format --set-exit-if-changed apps packages` | 通过，694 个文件无改动 |
| `python3 -m unittest discover -s tool/tests` | 26 项通过 |
| `dart test --coverage=coverage`（mm_core） | 292 项通过 |
| `flutter test --coverage --no-pub`（mm_design） | 178 项通过 |
| `flutter test --no-pub test/note_rich_export_test.dart test/study_notes_ui_test.dart`（app） | 24 项通过，包含 14 项新增导出/分享测试 |
| `flutter test --no-pub test/note_files_test.dart test/note_rich_clipboard_test.dart`（mm_platform） | 6 项通过 |
| `flutter test --coverage --no-pub`（app，最终复跑） | 1010 项通过、34 项跳过、1 项失败（下述 main 问题） |
| `python3 tool/coverage.py` | 已执行各包检查，在应用测试失败处返回非零；其余包测试通过 |
| `python3 tool/coverage.py --report-only` | 最终报告汇总通过 80% 门槛；不表示全量测试通过 |
| `xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=macOS' -enableCodeCoverage YES` | 26 项通过，包括新增原生剪贴板、A4 分页 PDF 测试 |
| `flutter build macos --debug --no-pub` | 构建通过 |

## 当前阻塞

`apps/marginmind/test/reflow_reader_test.dart:397` 的 `phone long press exposes selection handles and compact actions` 仍在“更多”菜单寻找 Underline，main 已把它移为选区工具栏的独立按钮。在独立 `origin/main` 检出中复现相同失败。

候选修正仅将测试定位改为 `ValueKey('selection-underline')`；在临时检出中该修正已通过。原任务限定只改导出/分享文件，因此没有把这项范围外改动加入本 PR，等待确认。

## 自审与文件验证

核对了入口、能力判断、内容过滤、出处、脚注、分页、文件名、XML/HTML 转义、失败重试、异步 mounted 检查和图像/文字绘制资源释放。修复了自定义划线色丢失、隐藏 AI 后复习题泄露、中等宽度工具栏溢出、Web 下载路径、Android 分享 MIME 和空下拉可点击的问题。

DOCX 的 6 个 XML 部件均可解析；使用 LibreOffice 打开、转 PDF，并逐页检查中文、Quote 样式、底纹和原生脚注。PDF 通过生产原生编码器和 PDFKit 验证并渲染；三种 660px 长图均已查看。Word/Pages 本机未安装，没有做这两种应用的实际打开测试；Android/iOS/Web 未做真机或浏览器验收。

## 覆盖率

本次新增/修改 Dart 可执行行：**628/688（91.28%）**。按暂存差异行与合并 LCOV 匹配，不包含 Swift/Kotlin。

| Package | Covered / lines | Coverage |
| --- | ---: | ---: |
| apps/marginmind | 25570 / 28537 | 89.60% |
| packages/mm_assistant | 2076 / 2132 | 97.37% |
| packages/mm_book | 1300 / 1364 | 95.31% |
| packages/mm_core | 5184 / 5337 | 97.13% |
| packages/mm_data | 542 / 558 | 97.13% |
| packages/mm_design | 2065 / 2288 | 90.25% |
| packages/mm_layout | 165 / 165 | 100.00% |
| packages/mm_pdf | 1814 / 1941 | 93.46% |
| packages/mm_platform | 610 / 654 | 93.27% |
| packages/mm_reflow | 1058 / 1115 | 94.89% |
| packages/mm_research | 637 / 655 | 97.25% |
| **Total** | **41021 / 44746** | **91.68%** |

Required: 80%.
