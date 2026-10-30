# UI 设计稿

`canvas/` 是 MarginMind 设计画布的源文件：每个 `.dc.html` 是一张画板，`canvas.json` 记录画板在画布上的位置和标题。这些画板是在 Claude 的 Design 画布里制作的，依赖它的运行时脚本（`support.js`），所以直接用浏览器打开不会完整渲染；它们主要作为**设计的源与依据**保存在仓库里，供阅读和对照实现。

| 文件 | 画板 | 内容 |
| --- | --- | --- |
| `Library.dc.html` | 00 资料库 · 启动页 | 侧栏筛选、继续学习、图标/列表视图、新建学习集、首次启动 |
| `Main.dc.html` | 01 工作区原型 | 原文 / 分栏 / 脑图、划线即摘录、卡片 ↔ 原文联动、大纲视图 |
| `Foundations.dc.html` | 02 UI 规范 · 基础 | 语义色、材质、标注色板、字体、同心圆角、动效、SF Symbols、窗口布局、Flutter 原生化方案 |
| `Components.dc.html` | 03 UI 规范 · 组件 | 菜单栏、右键菜单、工具栏控件、侧栏、大纲、脑图节点（含原地编辑、多选）、标注状态、浮动控件（选区工具条、高亮工具条）、快捷键、交互规则、资料库 |
| `Architecture.dc.html` | 04 架构 · 分层与模块 | 前后端分层、包结构、依赖规则 |
| `DataModel.dc.html` | 05 架构 · 数据模型与核心链路 | 表结构、划线 → 卡片 → 脑图、卡片 → 原文 |

## 与代码的对应

- 设计令牌 → `packages/mm_design/lib/src/tokens/`
- 组件 → `packages/mm_design/lib/src/widgets/`
- 资料库 → `apps/marginmind/lib/features/library/`
- 工作区 → `apps/marginmind/lib/features/workspace/`
- 菜单与快捷键 → `apps/marginmind/lib/app/app_commands.dart`

实现与设计稿不一致时，以“为什么不同”写进 `docs/` 并同步修改设计稿。目前已知的差异：

1. 深色主题次级文字由 `#A1A1A6` 提亮为 `#AEAEB2`，以满足选中行上的 4.5:1 对比度。
2. 资料库与学习集暂时在同一窗口内切换（设计为独立窗口），原因见 `docs/architecture.md`。
3. 图标使用 Flutter 自带的 Cupertino 图标近似 SF Symbols。
4. 表单标签列由 76 加宽到 96，避免英文标签（如 “Appearance”）换行。
5. 组件画板中的“多选”是 E-08 的目标样式，应用里尚未实现；实现时以画板为准。
6. 菜单栏和右键菜单稿里的“摘录到脑图 ⌘E”“摘录时同步到脑图 ⌥⌘E”尚未实现；目前摘录只在浮动工具条打开时按 E。

### PDF 阅读配色

PDF 区域右上角的「PDF 操作」下拉菜单集中控制页面侧栏和阅读配色。`MMReaderStyle` 定义白色、黑暗、纸质、淡绿四套纸张/文字颜色，仅变换页面像素，保留标注颜色与原始导出内容。侧栏开关与阅读区宽度变化后适配页面宽度，保持阅读纵向位置。鼠标滚轮缩放脑图，Shift + 滚轮横向平移，触控板保留平移与捏合。

阅读工作区更新：目录栏宽度默认 240，可调 180–360，正文至少预留 240；目录单行省略、悬停全文。脑图新增按钮采用固定 32×32 屏幕点击区域，独立于摘录目标提示。详见 `docs/design-system.md`。

脑图底部摘录目标提示为视图控制保留 `MMSizes.mapViewControlsReservedWidth`（380 pt，含“紧凑 / 完整”切换）空间，避免重叠。

PDF 工具栏使用紧凑图标菜单（缩放与适配、阅读外观）；页面适配入口用双向缩放箭头，底部悬停显示页进度滑块。分割线提供左右区域收起按钮，单栏时保留恢复入口，两个侧栏独立开关。

浮动玻璃控件与提示统一取消外部模糊阴影，保留半透明底色及细边框。PDF 放大/缩小常驻，实际大小/适配宽度/适配整页合并为带图标菜单；页进度条使用中性灰色玻璃底与无阴影滑块。顶部操作组固定右对齐。

## 二期高保真原型

`prototype/phase-2.html` 是二期（内容增强与阅读研究）完成后的交互原型，**单文件、无依赖，浏览器直接打开即可**，与上面的画板不同，不需要 Design 画布的运行时。右侧“演示控制台”可以跳到 13 个场景，并切换“无 AI / 断网 / 深色 / 窄窗口”。设计说明与开发方案见 [docs/phase-2-design.md](../docs/phase-2-design.md)。原型中的资料与 AI 回答都是演示数据。

C05 导出表单尺寸：`MMSizes.mapExportSheetWidth` 560 pt，`MMSizes.mapExportPreviewHeight` 180 pt；与 `prototype/phase-2.html` 的导出场景一致。

阅读底部导航：横向 1pt 细进度线，两端无底色箭头，页码单独居中浮在上方的小型半透明标签内。底部热区高 64pt；平时只淡显进度线，鼠标进入底部、键盘聚焦或拖动时显示完整控件。保留页码输入和拖动定位，减少动效/透明度遵循系统设置。浮动工具条与提示避开整个底部导航区域。

## 三期原型：助手

`prototype/phase-3-assistant.html` 在二期原型的基础上，把“研究”简化成对话式“助手”：选中原文或卡片就能直接提问，回答带出处，修改脑图前先给出提议、确认后才应用。原文栏、脑图栏和阅读底部导航都以现有应用为准。这个原型同样是单文件，没有依赖；演示控制台里有 21 个场景。设计说明与 dart_agent_core 接入方案见 [docs/phase-3-assistant.md](../docs/phase-3-assistant.md)。

## 三期原型：阅读增强

`prototype/phase-3-reading.html` 在助手原型的基础上补齐三项阅读能力：**裁边**（一键裁掉白边让文字更大，可按所有页 / 奇偶页 / 单页微调，不改原 PDF）、**页边批注**（选中一句直接在页边写，空间不够时收成页边标记，可一键加入脑图）、**对照阅读**（两份文档同步滚动，没有译本时可以 AI 逐段对照）。单文件、无依赖；演示控制台前 9 个场景是本期内容，后面保留助手原型的全部场景。设计说明、空间分配规则与数据模型见 [docs/phase-3-reading.md](../docs/phase-3-reading.md)。

## 四期原型：更多文档类型

`prototype/phase-4-documents.html` 演示 EPUB、MOBI / AZW3、Markdown 和网页的导入与阅读：电子书、Markdown 与网页阅读模式共用流式引擎，支持标注与阅读设置；网页也可保存为原样分页 PDF。浏览器就绪后显示非模态转换气泡，快照始终保存。界面在现有工具栏位置按格式替换；包含桌面、手机、平板共 27 个场景。规格见 [docs/phase-4-ui.md](../docs/phase-4-ui.md)。转换面板尺寸令牌：`MMSizes.webConversionSheetWidth` 640pt、`webConversionPreviewWidth` 200pt、`webConversionPreviewHeight` 260pt、`webConversionPreviewCompactHeight` 300pt。

## 思维导图操作优化（一期）

`prototype/mindmap-phase-1.html` 演示四项脑图能力：**合并节点**（多选后合并，每一段都能回到自己的原文）、**概要**（升级为可以带细分主题的主题，拖动括号两端调整范围）、**关联线**（从节点右上角拖到目标节点，可以调整弯曲和箭头）、**结构与配色**（4 种结构、6 套配色，悬停预览）。单文件、无依赖；演示控制台有 9 个场景，并说明各自的规则和待确认项。设计说明与对数据模型的影响见 [docs/mindmap-phase-1.md](../docs/mindmap-phase-1.md)。

## 学习笔记：AI 整理与导出

`prototype/study-notes.html` 演示把划线、页边批注和脑图笔记整理成一篇带出处的学习笔记：**整理设置**（范围、组织方式、AI 参与程度、上下文）、**确认提纲**（拖动划线、调整小节）、**三种声音**（宋体原文 / 我的批注 / 带 AI 标签的整理内容）、**自动关联上下文**（前后句、补全指代、跨节关联）、**增量更新**（改过的段落不会被覆盖）、**三种版式**（读书笔记 / 康奈尔 / 复习提纲），以及 **Markdown、Obsidian、PDF、Word 导出和分享长图**。单文件、无依赖；演示控制台有 14 个场景，可以切换“未配置 AI”。设计说明与数据模型见 [docs/study-notes.md](../docs/study-notes.md)，界面规格见 [docs/study-notes-ui.md](../docs/study-notes-ui.md)。

## 生词本（GUL-582）

`prototype/vocabulary.html` 演示阅读时的生词学习：选中单词时「翻译」变为「查词」，查词卡片和短语翻译卡片可以**加入生词本**；加入后全文所有词形（如 plateau / plateaus）用生词色点状下划线标出，也可以切到**行间释义**，点按命中处查看释义并在本文各处之间跳转；工具栏、阅读设置和 ⇧⌘U 可以关闭提示或只在本文档隐藏；生词本页面按学习集 / 状态筛选，例句可回到原文。单文件、无依赖；演示控制台有 12 个场景。设计说明、数据模型与分期见 [docs/vocabulary.md](../docs/vocabulary.md)。

### 生词本页面（GUL-596）

列表宽使用 `MMSizes.vocabularyListWidth`（340 pt）；宽度低于 600 pt 时与手机一致推入详情，返回保留搜索和筛选。音标朗读使用 `MMIcons.speaker` 与 `MMSpeech` 系统英／美语音（仅受支持平台显示按钮），词形原形固定保留。界面文案与分组依据 `design/prototype/vocabulary.html` 场景 10–11；重新生成仅更新义项，保留用户的行间释义、笔记及词形。

生词详情区块使用 11pt semibold 次级文字；例句卡片为 0.5pt 细边、10pt 圆角，原句沿用宋体，译文为 12pt 常规次级文字，来源与操作同一行。词形与添加输入框均为 20pt 高，删除按钮位于词形内部。

### 全文生词提示（GUL-597）

命中卡片宽 `MMSizes.vocabularyHitCardWidth`（300pt）；行间释义使用 `MMSizes.vocabularyGlossSize`（10pt），最多 8 字，仅在行间空隙足够且不会与其他释义重叠时绘制。点线复用 `MMPdfAnnotationLinePainter`，线宽 1.5pt。已掌握使用 `secondaryLabel`。查词卡片词性标签圆角使用 `MMRadii.vocabularyPos`（4pt）、`quaternaryFill` 底色。提示和新增闪烁独立于正文、标注和截图导出图层。

学习笔记一期使用 `MMNoteLayout`、`MMNoteTypography` 和现有语义颜色；600pt 正文、1000pt 浮动目录阈值、640/900pt 设置与导出面板。规格与令牌清单以 `docs/study-notes-ui.md` 和 `docs/design-system.md` 为准；不在组件中复制原型 CSS 的固定颜色。

## 脑图 AI 扩展想法（GUL-581）

`prototype/mindmap-ai-expand.html` 演示在脑图上用 AI 扩展想法：选中主题后点 ✦ 或按 ⌥⇥，AI 的结果以**虚线草稿节点**流式出现在脑图上；可以逐条取舍、改字、在草稿上继续扩展，↩ 一次保留（一步撤销），Esc 放弃。多选时可以分别扩展、归纳上级主题、补全同级；选中中心主题时，先给出扩展计划（总数不设上限），再扩展整张脑图。单文件、无依赖；演示控制台有 15 个场景，可切换未配置 AI、断网和深色。设计说明与技术方案见 [docs/mindmap-ai-expand.md](../docs/mindmap-ai-expand.md)，界面规格见 [docs/mindmap-ai-expand-ui.md](../docs/mindmap-ai-expand-ui.md)。

学习笔记 AI 整理使用 820pt 进度面板（`MMSizes.noteProgressSheetWidth`），
AI 块左侧细线使用 `MMNoteLayout.aiRule`（2pt）；排序与重新整理图标来自共享 `MMIcons`。

学习笔记分享使用 `MMShareCardTheme` 的纸张、简洁、夜读主题，卡片按 2× 输出。
舞台阴影使用 `MMShareCardStyle.previewShadow`（0/6/24，黑色 14%），只用于预览。
笔记栏低于 `MMNoteLayout.exportLabelMinWidth`（720pt）时，导出按钮只显示图标和提示，避免与 AI 操作、分享入口挤占空间。
