# ADR 0004：阅读增强保留原始 PDF 坐标，裁边采用按页裁剪绘制

状态：采用。依据 GUL-547 已批准技术方案；版本 pdfrx 2.10.1（锁文件）。

## 问题与证据

现有 MMPdfView 的选区、搜索、高亮和画笔均使用原始 PDF 页面坐标。pdfrx 的 `layoutPages` 返回的是完整页面的目标矩形，不是 source crop：`pdf_viewer.dart` 的 `_relayoutPages` / `_renderPage` 路径，以及 `_getRectInDocument` / `toRectInDocument` 都将整页换算到该矩形。

`packages/mm_pdf/test/reading_probe_test.dart` 第一项用实际 PdfViewer 和可控文档后端验证：600×800 页面布局为 300×400 后，原页面的两个角仍然映射到整个 300×400 矩形。这是缩放，不是去掉白边，不能使用此方法直接交付裁边。

## 决定

采用按页裁剪绘制。每页保留原始尺寸，绘制到裁边后的可见窗口；正文和标注共用 `PageViewportTransform`。它显式包含左/上裁边、原页高度、缩放和视口偏移，并提供成对正反变换。原 PDF、OCR、导出、持久化标注坐标不变。

`packages/mm_pdf/example/reading_probe.dart` 的裁边页用 PdfPageView 保留完整页面比例，在 ClipRect 内平移；选区通过原 PDF 字符框命中，画笔保存原始点。旁边的 TextField 是视口 Stack 中的同级控件，不放在 pageOverlaysBuilder 内。探针的选择、高亮、笔迹在裁边开关与缩放后保持原始坐标，页边可输入。

两份 PDF 对照继续使用两个现有 MMPdfView，以新增 `readingPosition` / `jumpToReadingPosition` 接口同步。阅读线为视口高度 25%。`ReadingAlignment` 用原页面高度归一化和分段插值；`ReadingSync` 保持异步驱动锁、用户接管和销毁语义；调用端逐帧合并并忽略小于 .001 页的误差，避免舍入/边界引发重复跳转。

## 代价和后续边界

这是技术可行性探针，不是完整裁边阅读器。探针只显示第一页并采用矩形拖选；批次 A 必须实现可见页虚拟化、真实文本选择顺序/跨页选区/触控手柄、搜索/链接/画笔适配和与现有渲染预算一致的缓存。不能把探针的矩形拖选当作完整 pdfrx 文本选择的替代品。批准采用这条路线意味着 A 需要做这些适配，不再尝试仅改 layoutPages。

页边的可交互附加宽度已在探针验证；跨页卡片下压、可见页排布和页末溢出高度由批次 B 完成。双栏测试验证实际 MMPdfView 的双向位置驱动、无历史污染和静止后的稳定性；产品级窗口变化、工具共享和布局恢复由 C 完成。

## 可复现验证

```sh
flutter test packages/mm_pdf/test/reading_probe_test.dart packages/mm_pdf/test/reading_geometry_test.dart
# apps/marginmind 下，原生 PDFium 的可视运行入口：
flutter run -d macos -t ../../packages/mm_pdf/example/reading_probe.dart
# 加 --dart-define=PROBE_SELF_CHECK=true 可执行原生裁剪渲染/文本读取后自动退出。
```

Widget 测试采用现有可控 PDF 后端，验证 pdfrx 布局与交互行为；原生自检额外验证 PDFium 真正能够读取文本并渲染裁剪区域。二者不能互相替代，交付记录分别报告。
