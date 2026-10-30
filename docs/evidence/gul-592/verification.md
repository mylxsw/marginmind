# GUL-592 验证记录

已 rebase `origin/main` 的 `31bc5b3`。下列本地全量测试与覆盖率数据基于 rebase 前的 `22c256f`；rebase 后再次通过 analyze、format（705 个文件）和导出/笔记界面 26 项定向测试。最终 Linux 全量 CI 结果在 PR 和任务回复中记录。

| 检查 | 实际结果 |
| --- | --- |
| `flutter analyze --no-pub` | 通过，无问题 |
| `dart format --set-exit-if-changed apps packages` | 通过，701 个文件无改动 |
| `python3 -m unittest discover -s tool/tests` | 26 项通过 |
| `python3 tool/coverage.py` | 全部包测试通过，总行覆盖率 91.73%，超过 80% 门槛 |
| 应用全量测试（由 coverage.py 执行） | 1021 项通过、34 项跳过、0 失败 |
| `flutter test --no-pub test/study_notes_ai_ui_test.dart test/study_notes_ui_test.dart test/note_rich_export_test.dart`（app） | 32 项通过，包括中等宽度工具栏回归测试 |
| `flutter test --no-pub test/note_rich_export_test.dart test/study_notes_ui_test.dart test/reflow_reader_test.dart`（app，rebase 后首轮定向） | 32 项通过 |
| `git diff --check` | 通过 |
| `xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=macOS' -enableCodeCoverage YES`（此前已执行） | 26 项通过，包括新增原生剪贴板、A4 分页 PDF 测试；本次 rebase 未改动原生代码 |
| `flutter build macos --debug --no-pub`（此前已执行） | 构建通过 |

## Review 修正

- 三主题 golden 使用固定英文样本，显式加载锁定 Flutter SDK 的 Ahem.ttf 到宋体和系统字体别名，并加载固定图标字体，避免宿主字体和中文回退差异。实际验收图片仍使用系统字体。
- 图片保存与文件导出共用标题清理函数，保存成功使用 `studyNoteSavedImage`（已存储 / Saved）；覆盖取消、失败重试、非法字符和空标题回退。
- PDF 脚注序号放到引文末尾，跨页时把脚注放在序号所在页；已重新渲染并检查 PDF。
- 长图出处使用“书名 · 位置”；舞台阴影为 0/6/24、黑色 14%，位于截图边界外。三种主题图片已重新检查。
- 连续 HTML 要点合并成单个 `<ul>`，分段及列表位于文末的情况均有测试，三个 HTML golden 已更新。

本轮 `flutter test --no-pub test/note_rich_export_test.dart` 15 项通过；core 富文本导出定向测试 8 项通过。全仓 `python3 tool/coverage.py` 通过，应用 1021 项通过、34 项跳过、0 失败。Linux CI 的最终结果在 PR 和任务回复中记录。

## 原有阅读器测试

最新 main 已修复 `apps/marginmind/test/reflow_reader_test.dart:397` 的过时 Underline 定位，改用 `ValueKey('selection-underline')`。因此没有纳入额外候选补丁，该文件相对 main 无改动；rebase 后定向及全量测试均通过。

## 自审与文件验证

核对了入口、能力判断、内容过滤、出处、脚注、分页、文件名、XML/HTML 转义、失败重试、异步 mounted 检查和图像/文字绘制资源释放。实现阶段修复了自定义划线色丢失、隐藏 AI 后复习题泄露、Web 下载路径、Android 分享 MIME 和空下拉可点击的问题。

本次 rebase 保留了 main 新增的 AI 整理菜单与文案。首轮全量测试发现 677px 笔记栏的 AI 操作与分享按钮组合导致工具栏溢出 5px；已让低于 720px 的导出按钮使用图标和提示，并补充含 AI、分享、导出入口的回归测试。修复后定向与全量复跑通过。

DOCX 的 6 个 XML 部件均可解析；使用 LibreOffice 打开、转 PDF，并逐页检查中文、Quote 样式、底纹和原生脚注。PDF 通过生产原生编码器和 PDFKit 验证并渲染；三种 660px 长图均已查看。Word/Pages 本机未安装，按评审确认留到最终验收补做，不作为阻塞项；Android/iOS/Web 未做真机或浏览器验收。

## 覆盖率

本次新增/修改 Dart 可执行行：**880/944（93.22%）**。按 rebase 前相对 main `22c256f` 的差异行与合并 LCOV 匹配，不包含 Swift/Kotlin。

| Package | Covered / lines | Coverage |
| --- | ---: | ---: |
| apps/marginmind | 26330 / 29341 | 89.74% |
| packages/mm_assistant | 2077 / 2133 | 97.37% |
| packages/mm_book | 1300 / 1364 | 95.31% |
| packages/mm_core | 5189 / 5342 | 97.14% |
| packages/mm_data | 542 / 558 | 97.13% |
| packages/mm_design | 2065 / 2288 | 90.25% |
| packages/mm_layout | 165 / 165 | 100.00% |
| packages/mm_pdf | 1814 / 1941 | 93.46% |
| packages/mm_platform | 610 / 654 | 93.27% |
| packages/mm_reflow | 1058 / 1115 | 94.89% |
| packages/mm_research | 637 / 655 | 97.25% |
| **Total** | **41787 / 45556** | **91.73%** |

Required: 80%.
