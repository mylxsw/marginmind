# 导出副本（GUL-602）

把读过、标过的文档导出成一份可以分享的文件。原文件不变。实际界面见 [evidence/gul-602](evidence/gul-602/README.md)。

## 设计

多数人只想“带上标注导出”，所以面板默认只问一个问题，点一下就完成：

| 选项 | 内容 | 什么时候出现 |
| --- | --- | --- |
| 包含全部标注 | 高亮、下划线、批注、画笔，列出数量 | 文档有标注 |
| 只保留高亮和下划线 | 不含批注和画笔，适合分享 | 同时有划线和批注或画笔 |
| 不带标注 | 与导入时的文件相同 | 总是（没有标注时叫“导出这份文档”） |

点一项直接弹系统存储面板（手机是分享面板），没有“选中再确认”这一步。

需要定制时点“更多选项”：内容换成开关（每种标注一个，高亮可按颜色筛选），PDF 还可以选页面（全部 / 有标注的页 / 指定页）。两种状态不同时显示，也没有预览、版式和注释形式这些选择。

入口：阅读器「⋯」菜单、文件菜单（⇧⌘S）、侧栏文档右键；手机在「⋯」面板里。

相比最初的方案（900pt 双栏面板、实时预览、页边 / 文末、可编辑 / 合并到页面）去掉了这些内容，因为它们让每个用户都要先看懂一屏选项。

## 写入规则

| 源文档 | 带标注的副本 | 不带标注的副本 |
| --- | --- | --- |
| PDF、网页存成的 PDF | PDF，标准注释（Highlight / Underline / Square / Ink / Text） | 原文件 |
| EPUB | EPUB 3，`<mark>`、下划线样式、弹出脚注 | 原文件 |
| MOBI / AZW3 | EPUB（无法写回原格式，面板会写明） | 原文件 |
| 网页阅读模式 | EPUB | EPUB |
| Markdown | Markdown，`<mark>`、`<u>`、`[^n]` 脚注，其余源文本不变 | 原文件 |
| 固定版式 EPUB | 不提供，只能导出原文件 | 原文件 |

不写入副本的内容，面板都会提示：

- 位置待确认的标注（`needsReview`，或属于文本的旧版本）。
- 流式文档上的画笔：EPUB 没有对应结构。
- 作者禁止添加注释的 PDF：只能导出不带标注的副本。
- Web 版的 PDF：PDFium 的注释接口不可用，只能导出原文件。

以下内容有意不写入：生词提示、翻译、脑图、AI 笔记，它们不是对文档的标记。修改过的 PDF 目录和书签也不写入，因为 PDFium 没有写目录的接口。下划线的虚线、点线、波浪线在 PDF 里统一为实线：PDF 没有虚线下划线，macOS“预览”也不显示 Squiggly。

## 架构

- `mm_core` 的 `DocumentExportPlan`：纯函数，决定副本写入哪些标注。面板的数量和所有写入器都读它。
- `mm_pdf` 的 `MMPdfExport`：通过 `useNativeDocumentHandle` 调用 PDFium 注释接口（`pdfium_dart`），macOS、iOS、Android、Windows、Linux 共用一份 Dart 代码；Web 用条件导入跳过。
- `mm_book` 的 `BookEpubWriter`（由存储的书籍模型生成 EPUB，所以 EPUB、MOBI、网页共用一条路径，标注按规范文本偏移落位）和 `BookMarkdownAnnotator`（在源文本里定位引文，容忍行内语法）。
- 应用层：`DocumentExporter` 组合以上部分，`DocumentExportSheet` 是界面。

## 验证

`integration_test/document_export_screens_test.dart` 在真实应用里走完所有状态，并检查写出的文件：PDF 注释用设备自己的 PDFium 读回。`tool/capture_document_export.py` 在每个状态截取真实窗口。
