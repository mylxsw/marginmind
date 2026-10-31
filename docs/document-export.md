# 导出文档副本（GUL-602）

> 状态：**设计方案，待确认**。配套高保真原型：[`design/prototype/document-export.html`](../design/prototype/document-export.html)（单文件、无依赖，浏览器直接打开；演示控制台有 19 个场景，可切换浅色 / 深色）。
> 依据：当前 `main` 的代码 —— `mm_core` 的 `Annotation` / `MarginNote` / `InkStroke` / `Bookmark` / `DocumentCrop` / `DocumentCapabilities`，`map_export_sheet.dart`、`note_export_sheet.dart`、`NativeMapExport`、`MMPlatformCapabilities`，以及 `docs/layout-density.md` 的扁平化视觉规格。

## 0. 一页结论

- **一个入口、一个面板。** 阅读器「⋯」菜单最后一组、文件菜单、侧栏文档右键都叫 **导出副本…**（⇧⌘S）。打开同一个 `MMSheet`：左列选项，右侧是**所见即所得的实时预览**——预览就是最终文件的页面，勾掉一项，预览立刻少一项。
- **用户只回答一个问题：“副本里留什么”。** 选项按这个问题组织：保留内容（高亮 / 下划线 / 页边批注 / 画笔 / 目录与书签，每项带数量）→ 页面（范围、裁边）→ 标注形式（可编辑 / 合并到页面）。格式只在源文档能写成多种格式时出现。
- **默认就能直接导出。** 全部保留、全部页面、可编辑标注、批注放在页边；文件名 `书名（标注版）.pdf`。设置按源格式记住上次的选择。
- **原文件永远不动。** 只读学习集包里的原件，生成新文件；裁边写成 PDF 的 CropBox，不裁掉内容。
- **格式随源文档：** PDF → PDF；EPUB → EPUB 或 PDF；MOBI / AZW3 → EPUB 或 PDF（不写回 MOBI）；Markdown → Markdown 或 PDF；网页（阅读模式）→ PDF 或 Markdown；网页（原样 PDF）同 PDF。
- **能保留的都写成目标格式的“原生”东西**，别的阅读器打开也认识：PDF 用标准注释（Highlight / Underline / Squiggly / Ink / FreeText）和书签（Outline）；EPUB 用 `<mark>`、EPUB 3 弹出脚注和 `nav.xhtml`；Markdown 用 `<mark>` 和 `[^n]` 脚注。
- **做不到的说清楚，不默默丢。** 目标格式不支持的项（如 EPUB 里的画笔）置灰，并在行尾给出“导出为 PDF 可保留”；位置待确认的标注不导出，并在列表底部提示数量。

## 1. 用户场景

| 场景 | 用户想要什么 | 面板里怎么做 |
| --- | --- | --- |
| 读完一本 PDF，发给同学 | 带着自己的划线和批注，对方用“预览”或 Acrobat 也能看到 | 默认设置直接导出 |
| 只想分享重点 | 只留黄色高亮（“重点”），不带私人批注 | 高亮下面点掉其他颜色；关掉页边批注 |
| 打印 / 发给老师审阅 | 每台电脑显示都一样，标注不会被误删 | 标注形式选“合并到页面”；批注选“文末” |
| 放进 Kindle / 墨水屏 | 页面小，白边浪费 | 打开“应用裁边” |
| 只要讨论到的那几章 | 不要整本 300 页 | 页面范围“有标注的页”或自定义“12–30, 47” |
| EPUB 电子书分享给用 Apple Books 的朋友 | 依旧是可重排的电子书 | 格式选 EPUB；批注成为点按弹出的脚注 |
| EPUB 发给只有 PDF 阅读器的人，或要带画笔 | 固定版式 | 格式选 PDF，版式“与阅读器一致”或 A4 |
| 存一份干净的、目录修好的版本 | 不要标注，但要自己修过的目录 | 关掉所有标注，保留“目录与书签” |

## 2. 入口（场景 1–3）

| 位置 | 文案 | 规则 |
| --- | --- | --- |
| 阅读器工具栏「⋯」（`reader-more`） | `MMIcons.export` + 导出副本… | 放在菜单最后一组，前面一条 `PopupMenuDivider`；正在裁边时置灰 |
| 文件菜单 | 导出副本… ⇧⌘S | 位于“导出笔记…”“导出脑图…”之前，三者一组；当前没有打开文档时置灰。⇧⌘S 未被占用，且与 macOS“存储副本”的习惯一致 |
| 侧栏文档行右键 / ⋯ | 重命名… → **导出副本…** → ─ → 移除文档… | 可以导出不是当前打开的文档 |
| iPhone / iPad | 「⋯」菜单同一位置，文案“分享副本…” | 生成后直接打开系统分享面板（沿用 `MobileFileShare`） |

不在选区工具条、标注工具条里放入口：导出是对整份文档的操作，不属于局部选区。

## 3. 导出面板（场景 4–8）

`showMMSheet`，宽 `noteExportSheetWidth`（900），内容区高 `noteExportBodyHeight`（520）——与“导出笔记”同尺寸、同结构（左列选项 + 右侧预览），两者看起来是一个家族。标题“导出副本”，`titleTrailing` 放源文档名（`footnote`、`secondaryLabel`，单行省略），帮助用户确认导出的是哪一份。

### 3.1 左列（宽 `noteExportOptionsWidth` 280，可滚动）

从上到下，组标题 `subheadline`（`secondaryLabel`，上 12 下 6），与导出笔记一致：

1. **格式**（只有一种可选格式时整组不显示）。格式格子沿用导出笔记的样式：圆角 10、内边距 8×6、上方 28pt 单色图标、下方名称（`footnote`），选中 2pt `accent` 描边 + `accentTint` 底。名称下面一行小字只写“原格式”或不写。
2. **保留内容**。分组列表（`MMFormRow` 风格，行高 32，0.5pt `separator` 分隔），组标题右侧“全部 / 全不保留”文字按钮。每行：16pt 图标（`icon` 色）· 名称 · 数量（`secondaryLabel`，等宽数字）· `MMSwitch`。数量为 0 的行置灰。
   - **高亮**（`highlighter`）：打开时下面展开一行**颜色筛选**——本文档实际用到的颜色（含自定义颜色），每个是 22pt 圆点 + 数量；点按切换，关掉的点变成空心描边。只用了一种颜色时不显示这一行。至少保留一种颜色；全部点掉等同于关掉高亮。
   - **下划线**（`underline`）：保留原线型（实线、虚线、点线、波浪线）。
   - **页边批注**（`marginNote`）：打开时下面出现 `MMSegmentedControl`：PDF 输出为 **页边 | 文末**；EPUB 输出为 **脚注 | 章末**；Markdown 输出没有这一项（固定为脚注）。
   - **画笔**（`pen`）。
   - **目录与书签**（`readerOutline`）：写入你修改过的目录；书签作为目录末尾的“书签”一组。
3. **页面**（仅固定版式输出）。
   - 范围：`MMSegmentedControl` **全部 | 有标注的页 | 自定义**；自定义时下面出现 `MMInlineTextField`，占位“例如 1–12, 20”，失焦时校验，越界或格式不对时边框变 `critical`、“导出…”置灰。
   - **应用裁边**：只在这份 PDF 设置过裁边时出现，默认关。
   - 版式（仅流式文档 → PDF）：**与阅读器一致 | A4**。“与阅读器一致”使用当前字号、行距、字体排版。
4. **标注形式**（仅 PDF 输出，且至少保留一项标注时出现）。`MMSegmentedControl` **可编辑 | 合并到页面**，下面一行 `footnote`：
   - 可编辑：“其他阅读器里可以查看、修改或删除这些标注。”
   - 合并到页面：“标注成为页面的一部分，各阅读器显示一致。”
   这是全面板唯一的说明文字，因为这两个选项的差别看名字不够清楚。
5. **底部提示**（有才显示）：`caution` 图标 + “2 处标注位置待确认，不会导出”，右侧“查看”回到阅读器并定位第一处。

### 3.2 右侧预览

`readerBackground` 底、圆角 12、0.5pt `hairline`。

- **吸顶标签行**（高 36）：`document` 11 + 文件名（`footnote`）；右侧：“可编辑注释”小标签（仅可编辑模式且有标注时）、‹ 第几页 / 总页数 ›、下一处标注（双下箭头）。页数都是**导出后的**页数（范围、文末批注页都算进去）。
- **页面**：按比例缩放到可用区域，居中，四周 20。PDF 预览用原页面渲染 + 与阅读器**同一套标注 painter**（高亮、`MMPdfAnnotationLinePainter`、画笔），所以“预览 = 阅读器里看到的 = 导出结果”。阅读配色（黑暗、纸质等）只是显示设置，预览和导出都用原始页面颜色。
- **页边批注**：选“页边”时页面右侧加宽 40%，批注按阅读器的页边布局排列（复用 `margin_geometry`），细虚线连回原句。选“文末”时原句后加上标序号，文末追加“批注”页，序号双向链接。
- **目录与书签**打开时，页面左侧出现一条 120 宽的“书签”栏，模拟其他阅读器的侧栏，告诉用户“目录也会带过去”。
- 可编辑模式下，悬停预览中的标注显示类似 PDF 阅读器的注释标签（“高亮 · 可编辑”）；合并模式没有悬停。
- EPUB 预览是流式的一章，宽 380，可以在预览里滚动；‹ › 切换章节；脚注上标悬停弹出。Markdown 预览是等宽源文本（`mono`），与导出笔记的 Markdown 预览配色一致。
- 页脚左侧一行统计（`footnote`，等宽数字）：实际会写入的标注、批注、画笔数量和导出页数，如“12 处标注 · 4 条批注 · 2 处画笔 · 248 页”；什么都不保留时写“不含标注”。

### 3.3 页脚与过程（场景 15–17）

- 取消 → **导出…**（`primary`）。移动端为全宽“分享…”。
- 点“导出…”：桌面先弹系统存储对话框（文件名 = 文档标题 +“（标注版）”，去掉 `/ : \` 与控制字符，沿用 `map_export_sheet` 的规则），确认后开始生成。
- 生成时面板不关闭：页脚按钮换成 `MMProgressBar` + “正在生成 120 / 248 页” + “取消”；选项和预览变为不可操作（`.4` 不透明）。小文件（< 1 秒）不显示进度。
- 成功：面板关闭，`MMHud`“已导出”，动作“在 Finder 中显示”（移动端直接是分享面板，无 HUD）。
- 失败：留在面板，页脚上方一行“导出失败”+“重试”（沿用 `exportFailed` / `exportRetry`）。
- 取消：立即停止并删除未写完的临时文件，回到可编辑状态，不提示。

### 3.4 特殊状态（场景 12–14）

| 状态 | 表现 |
| --- | --- |
| 没有任何标注 | 保留内容各行数量为 0、置灰；“目录与书签”仍可用；标注形式不显示。导出等于一份带目录（和裁边）的干净副本。不弹空状态，不拦用户 |
| PDF 设置了“禁止修改”或加密 | 面板顶部一条 `caution` 横幅“这份 PDF 的作者不允许修改，只能导出不带标注的副本”；保留内容整组置灰，只能导出页面范围。尊重原文件权限，不提供绕过 |
| 有位置待确认的标注（`needsReview`） | 见 3.1 第 5 条。不导出，因为位置可能错 |
| 扫描版 PDF（已 OCR） | 二期：增加“文字识别层”开关，把识别结果写成不可见文字层，副本可搜索、可复制 |

### 3.5 iPad 与 iPhone（场景 18–19）

- iPad：同一面板，以表单面板居中；控件为触控尺寸（行高 44，`MMSwitch` 触控版）。
- iPhone（compact）：全高底部面板。顺序：预览（高 300，左右滑动翻页）→ 格式（横向一行）→ 保留内容 → 页面 → 标注形式；底部全宽“分享…”。与导出笔记的 compact 规则一致。

## 4. 每种内容怎么写进副本

| 学习集里的内容 | PDF（可编辑） | PDF（合并到页面） | EPUB | Markdown |
| --- | --- | --- | --- | --- |
| 高亮（6 色 + 自定义色） | `Highlight` 注释，每页一条（跨页标注拆成多条，`NM` 相同前缀），颜色为实际 RGB，`QuadPoints` 取 `AnnotationPage.rects` | 在页面内容上以相同透明度画矩形（multiply 混合） | `<mark class="mm-hl mm-c{n}">`，颜色写进追加的 `marginmind.css` | `<mark>原文</mark>` |
| 下划线 实线 / 波浪线 | `Underline` / `Squiggly` | 画线（复用阅读器线型） | `<span class="mm-ul mm-solid">`（`text-decoration-style`） | `<u>` |
| 下划线 虚线 / 点线 | `Ink` 注释 + 虚线外观流（PDF 没有虚线下划线类型） | 画线 | 同上 | `<u>` |
| 页边批注 | 页边：页面加宽，`FreeText` 注释 + 引线；高亮注释的 `Contents` 同时写入批注文字（不支持 FreeText 的阅读器也能看到）。文末：追加页面，内链双向 | 页边：页面加宽后绘制；文末：追加页面 | 脚注：EPUB 3 `epub:type="noteref"` + `<aside epub:type="footnote">`；章末：章节末尾列表 | `[^n]` 脚注 |
| 画笔（页面坐标 / 段落锚点） | `Ink` 注释 | 绘制 | **不支持**，行置灰：“导出为 PDF 可保留” | 不支持，同上 |
| 目录（含用户修改） | 替换 `Outline` | 同左 | 重写 `nav.xhtml`（EPUB 2 同时写 `toc.ncx`） | 文首目录列表 |
| 书签 | `Outline` 末尾“书签”组 | 同左 | `nav.xhtml` 中 `landmarks` 之后的“书签”列表 | 不支持 |
| 裁边 | 写 `CropBox`，内容不删 | 同左 | — | — |

**不导出（本期）**：生词提示与行间释义、逐段翻译、对照阅读对齐点、脑图卡片和 AI 笔记、阅读配色。它们是“我的学习过程”，不是“我对这份文档做的标记”；对方也没法使用。学习笔记已有“导出笔记”，脑图已有“导出脑图”。

批注作者：PDF 注释的 `T`（作者）字段留空——应用没有账号，不猜系统用户名，避免把本机用户名带进分享文件。

## 5. 架构

依赖方向不变：`apps → mm_platform / mm_pdf / mm_book → mm_core`。

```
mm_core   DocumentExportOptions      纯数据：格式、各项开关、颜色集合、批注位置、范围、裁边、形式、版式
          DocumentExportPlan.build() 纯函数：StudySetContent + Document + Options → 计划
                                     （每页要画的标注、批注、画笔，目录树，输出页码映射，计数，被排除项）
          PageRangeParser            “1–12, 20” → 页码集合，带错误位置
          DocumentExportWriter       端口：Future<Uint8List> write(plan, source, {progress, cancel})
mm_book   EpubAnnotatedWriter        纯 Dart：按 TextAnchor（章节 + 字符偏移）改写 XHTML、加 CSS、重写 nav
          MarkdownAnnotatedWriter    纯 Dart
mm_platform NativeDocumentExport     MethodChannel 'marginmind/document_export'（macOS / iOS：PDFKit）
apps      DocumentExportSheet        面板；预览用 mm_pdf 页面渲染 + 现有标注 painter，数据全部来自 plan
          showDocumentExportSheet    三个入口共用；记住设置：SharedPreferences 'documentExport.<sourceFormat>'
```

- **计划与写入分离。** UI 计数、预览、三种写入器都只消费 `DocumentExportPlan`，所以“预览里看到的”和“文件里写的”来自同一份数据；`DocumentExportPlan` 是纯 Dart，可以在 `mm_core` 里覆盖全部规则测试（颜色筛选、跨页拆分、范围映射、`needsReview` 排除、权限）。
- **PDF 写入**：macOS / iOS 用 PDFKit（`PDFAnnotation`、`PDFOutline`、`PDFPage.setBounds(.cropBox)`；合并模式在 `CGContext` 里先画原页再画标注）。Windows / Android / Linux 用 PDFium 的 `FPDFPage_CreateAnnot` / `FPDFAnnot_AppendAttachmentPoints` / `FPDF_SaveAsCopy`：pdfrx 已经用 `FPDF_SaveAsCopy` 实现 `encodePdf`，但 Dart 绑定里没有注释函数，需要补 FFI 绑定，**先验证随 pdfrx 分发的 PDFium 是否导出了这些符号**。本期按 `mapExport` 的先例只在 Apple 平台开放 PDF 输出，新增 `MMPlatformCapabilities.documentExport`；EPUB / Markdown 写入是纯 Dart，全平台可用。不可用的格式隐藏，不置灰（与导出笔记一致）。
- **流式 → PDF**：用 `mm_reflow` 按所选版式分页，按现有矢量场景格式（`NativeMapExport().pdf(scene)` 使用的命令列表）输出文字与标注，复用 `NotePdf` 的分页方式。
- **原件只读。** 写入器从学习集包读原件到内存，输出新字节；`CroppedDocument` 继续只用于显示（它的注释已写明不能用于导出）。
- **大文件**：写入在后台 isolate（纯 Dart 部分）或原生线程（PDFKit）进行，按页回报进度，支持取消；取消或失败时删除临时文件。
- **新令牌 / 文案**：沿用 `noteExportSheetWidth`、`noteExportOptionsWidth`、`noteExportBodyHeight`、`exportAction`、`exportedHud`、`exportFailed`、`exportRetry`；新增 `MMSizes.exportColorDot`（22）、`MMSizes.exportBookmarkRail`（120）、`MMSizes.exportMarginRatio`（0.4），文案键 `exportCopyMenu`、`exportCopyTitle`、`exportCopyKeep`、`exportCopyAnnotated` 等（中英文见原型）。

## 6. 分期

| 期 | 内容 |
| --- | --- |
| 一期 | PDF → PDF（Apple 平台）：全部保留项、颜色筛选、页面范围、裁边、可编辑 / 合并、页边 / 文末；三个入口；进度、取消、失败、权限、`needsReview` |
| 二期 | EPUB / MOBI → EPUB、Markdown → Markdown（全平台）；流式 → PDF |
| 三期 | Windows / Android / Linux 的 PDF 输出（PDFium 注释绑定）；OCR 文字层 |

## 7. 验收要点

- 默认设置下，副本在 macOS“预览”、Acrobat、Chrome 中都能看到高亮、下划线、批注、画笔和目录；可编辑模式下这些标注能在“预览”里删除。
- 关掉任一项或某种颜色，预览与导出文件同时少掉对应内容；计数随之变化。
- “有标注的页”“自定义范围”下，目录与内链跳到导出后的正确页码；不在范围内的目录项被删除。
- 原学习集包中的文件字节在导出前后完全相同。
- 受保护 PDF 只能导出不带标注的副本；`needsReview` 标注不出现在副本中。
- EPUB 副本通过 epubcheck，在 Apple Books 中点按批注序号弹出脚注。
- 测试：`DocumentExportPlan`、`PageRangeParser`、EPUB / Markdown 写入器单元测试覆盖率 ≥ 80%；面板 widget 测试覆盖各状态；原生 PDF 写入用 RunnerTests 校验注释类型、颜色、QuadPoints 与 Outline。

## 8. 待确认

1. 文件名后缀用“（标注版）”还是“（副本）”？方案取前者，分享时更能说明内容。
2. 默认标注形式取“可编辑”。如果主要场景是打印和发给老师，可以改为“合并到页面”。
3. 一期是否就需要 EPUB 原格式输出（工作量约等于 PDF 一期）？
