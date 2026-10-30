# GUL-592 导出与分享验收

样例来自 `test/note_rich_export_test.dart` 的真实导出代码：

- `note.pdf` / `note.page-1.png`：A4、11pt 正文、宋体摘录、黄色划线色条、批注底纹、页眉、页码和页底脚注。由生产 `MapExportChannel.pdf` 编码，PDFKit 验证并渲染，文字可搜索。
- `note.docx` / `docx/page-1.png`：最小 OOXML，内置 Quote 样式、批注底纹、原生 footnotes 及关系表。LibreOffice 26.8.2 打开并转 PDF，再渲染检查中文和脚注。当前机器未安装 Word 或 Pages，没有做过这两种应用的实际打开测试。
- `share-paper.png` / `share-plain.png` / `share-night.png`：Flutter RepaintBoundary 按 2× 输出，宽 660px，不含二维码或链接。系统字体仅用于截图；widget goldens 使用 Flutter 的确定性测试字体。

复现：在 `apps/marginmind` 执行 `WRITE_NOTE_EVIDENCE=1 flutter test test/note_rich_export_test.dart`。
输出写入本目录；生成的 `pdf-scene.json` 可以交给 `tool/note_pdf_evidence.swift`，与生产 `MapExportChannel.swift` 一起编译运行。
DOCX 渲染需 LibreOffice、Poppler；macOS Homebrew 环境下应设置 `FONTCONFIG_FILE=/opt/homebrew/etc/fonts/fonts.conf`，确保渲染器能找到系统中文字体。

交互测试另覆盖：引用方式切换、Word/PDF 保存、HTML 和纯文本同时拷贝、分享范围截取、隐藏批注与 AI、小窗口、空摘录、取消、失败重试，以及 PNG 图片拷贝。HTML 和 DOCX XML 均有 golden，三种主题分别有 widget golden。
