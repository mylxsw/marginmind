# GUL-592 导出与分享验收

样例来自 `test/note_rich_export_test.dart` 的真实导出代码：

- `note.pdf` / `note.page-1.png`：A4、11pt 正文、宋体摘录、黄色划线色条、批注底纹、页眉、页码和页底脚注；序号置于引文末尾，跨页引文的脚注与序号同页。由生产 `MapExportChannel.pdf` 编码，PDFKit 验证并渲染，文字可搜索。
- `note.docx` / `docx/page-1.png`：最小 OOXML，内置 Quote 样式、批注底纹、原生 footnotes 及关系表。LibreOffice 26.8.2 打开并转 PDF，再渲染检查中文和脚注。当前机器未安装 Word 或 Pages，没有做过这两种应用的实际打开测试。
- `share-paper.png` / `share-plain.png` / `share-night.png`：Flutter RepaintBoundary 按 2× 输出，宽 660px，不含二维码或链接。系统字体仅用于截图；widget goldens 使用固定英文样本，显式把宋体和系统字体别名映射到锁定 Flutter SDK 的 Ahem.ttf，并加载仓库依赖的图标字体，不依赖宿主字体或中文字体回退。macOS 与 Linux 使用各自的严格像素基线；Linux 基线在 Ubuntu 24.04、Flutter 3.47.2 容器内生成。

复现：在 `apps/marginmind` 执行 `WRITE_NOTE_EVIDENCE=1 flutter test test/note_rich_export_test.dart`。
输出写入本目录；生成的 `pdf-scene.json` 可以交给 `tool/note_pdf_evidence.swift`，与生产 `MapExportChannel.swift` 一起编译运行。
DOCX 渲染需 LibreOffice、Poppler；macOS Homebrew 环境下应设置 `FONTCONFIG_FILE=/opt/homebrew/etc/fonts/fonts.conf`，确保渲染器能找到系统中文字体。

交互测试另覆盖：引用方式切换、Word/PDF 保存、HTML 和纯文本同时拷贝、分享范围截取、隐藏批注与 AI、小窗口、空摘录、取消、失败重试，以及 PNG 图片拷贝。HTML 和 DOCX XML 均有 golden，三种主题分别有 widget golden。

更新 widget golden：在对应系统的 `apps/marginmind` 执行 `flutter test --update-goldens test/note_rich_export_test.dart`。Linux 写入 `test/goldens/linux/`，macOS 写入 `test/goldens/`；实际字体的验收图片使用上面的 `WRITE_NOTE_EVIDENCE` 命令，不作为像素基线。
