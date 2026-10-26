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
