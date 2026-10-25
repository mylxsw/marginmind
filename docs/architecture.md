# 架构

本地单机版也分“前端”和“后端”：前端是 Flutter 界面，后端是同一进程里的本地核心。两者只通过领域层定义的端口和查询对话，所以以后把核心放进后台 Isolate、或者接入同步服务，都不需要改界面。

设计稿对应画板：`design/canvas/Architecture.dc.html`、`design/canvas/DataModel.dc.html`。

## 包与依赖

```
apps/marginmind ──► mm_design    (令牌、主题、组件)
        │      ──► mm_platform  (窗口、快捷键、系统外观)
        │      ──► mm_pdf ─────┐ (PDF 渲染、选字、高亮叠加)
        │      ──► mm_data ────┤ (学习集文件包)
        │      ──► mm_layout   │ (脑图树布局；纯 Dart)
        └──────► mm_core ◄─────┘ (实体、编辑操作、端口、查询；纯 Dart)
```

| 包 | 职责 | 可以依赖 |
| --- | --- | --- |
| `mm_core` | 实体（`StudySet`、`Folder`）、仓库端口（`StudySetRepository`）、纯查询（`LibraryQuery`）。`testing.dart` 提供内存实现和示例数据。 | 仅 Dart 标准库与 `meta` |
| `mm_design` | 设计令牌、`MMTheme`、所有可复用组件。不含业务概念，不含文案。 | Flutter、`cupertino_icons` |
| `mm_platform` | 原生窗口（透明标题栏、红绿灯位置、拖动、缩放）、平台快捷键、系统强调色与辅助功能设置。 | Flutter、`window_manager`、`macos_window_utils` |
| `mm_data` | `FileLibraryStore`：同时实现 `StudySetRepository` 和 `StudySetContentRepository`。每个学习集一个 `.mmset` 文件夹（`studyset.json` + `documents/`），写入先写临时文件再改名，同一学习集的写入串行。 | `mm_core`、`crypto`、`path` |
| `mm_pdf` | `MMPdfView`（渲染、选字、可点击的高亮叠加、`reveal` 定位）和 `MMPdfEngine`（初始化、读取页数）。其余代码不直接引用 pdfrx。 | Flutter、`pdfrx`、`mm_core`（`PageRect`） |
| `mm_layout` | `TreeLayout`：向右生长的树，父节点在子树块中垂直居中。输入节点尺寸，输出矩形和连线。 | 仅 `meta` |
| `apps/marginmind` | 组合根：Riverpod providers、路由、菜单与快捷键、功能界面、多语言。 | 以上全部 |

### 数据模型（`mm_core/content`）

`StudySetContent` 是一个学习集的全部内容，不可变：`Document`（文件、页数、读到的页）、`Annotation`（页码 + PDF 坐标矩形 + 原文 + 颜色索引）、`Card`（topic / excerpt / note）、`MapNode`（卡片在脑图中的位置：父节点 + 排序 + 是否折叠）、`ReviewState`（每张卡片的复习排期）。所有修改都是 `StudySetEditor` 上的纯函数（`createExcerpt`、`attachCard`、`addTopic`、`move`、`setCollapsed`、`rate`、`removeDocument`…），仓库的 `update(id, change)` 负责原子地应用并保存，这也让测试不依赖界面。

- **撤销 / 重做**：控制器的独立编辑自动记录一步快照（最多 100 步）；跨多次写入的原地编辑用 `await beginTransaction()` 开始，`await commitTransaction()` 提交，`await abortTransaction()` 放弃。嵌套事务加入外层事务，最外层提交只记一步；放弃取消整个事务且保留原有重做记录。空事务及内容未变化的编辑不记历史。事务期间禁用控制器级撤销 / 重做，文字框负责自身撤销。写入和事务边界按调用顺序串行执行。撤销、重做和放弃均用 `StudySetEditor.restore` 保留当前复习记录和阅读页码。
- **脑图编辑基础 API**：`insertSibling`（`before` 指定前后）、`promote`、`insertParent`、`removeMany`、`moveMany`、`recolorMany` 均为 `StudySetEditor` 纯函数。虚拟根节点以 `null` 表示；在根上加兄弟节点会添加根的子节点，提升和插入父节点则不操作。批量移动按脑图先序排列、合并选中的父子树，目标落在任一选中子树内或不存在时整批拒绝；`index` 指移除所选节点后的目标兄弟列表位置。批量改色只作用于选中摘录关联的高亮（格式 1 的主题和笔记不存颜色），不隐式修改后代。控制器的 `removeCards` / `moveCards` / `recolorCards` 各只记一步历史。
- **多选与剪贴板**：工作区保留主选中节点和不可变的选中集合；批量删除、拖动和改色复用上述批量 API。`MapClipboard` 在纯 Dart 中将选中子树转换为先序大纲，包含折叠后代，并去重重叠选择；文本支持制表符、空格、空行及列表符号。`StudySetEditor.paste` 一次插入整片森林，重新生成卡片 ID，不复制复习记录；内部格式保留原高亮 ID，目标中仍存在且未关联卡片的高亮会被复用（剪切后粘贴不增加高亮）。原卡片仍存在时，复制摘录生成独立高亮，以保持两张卡片可独立改色和删除；此时相同 PDF 位置会叠加高亮。目标学习集没有原文时，摘录降为保留原文文字的笔记。macOS 通过 `mm_platform` 的原生通道在同一个剪贴板项写入纯文本和带版本的内部格式；其他平台使用系统纯文本剪贴板。粘贴优先读取内部格式，格式无效则解析缩进文本；目标为当前节点的子节点（根选中时插入顶层），整次操作只记一步撤销。
- **拖拽**：画布不在每个节点上放 `DragTarget`，而是由 `MapDrop.resolve` 按指针的场景坐标和节点绘制位置算出落点（节点上下各占一半兄弟间距，上 / 下四分之一插在前后，中部成为子节点，根节点只接受子节点，正在拖动的节点及其后代不接受）。预览和放下读同一个 `MapDrop`，所以落点总与预览一致。指针靠近或越过画布边缘时，计时器按距离平移画布，平移到脑图另一侧进入视野为止，每一步都重新计算落点；指针在画布外时没有落点。
- **复习**：`ReviewScheduler` 是简化的 SM-2（重来 10 分钟后再出现；良好 1 天 → 3 天 → 间隔 × 难度系数）。`reviewQueue(now)` 给出到期卡片（最逾期在前）和最多 20 张新卡片；资料库的待复习数也由它计算。
- **导出**：`MapExporter` 把主脑图转成 Markdown（嵌套列表）或 OPML 2.0（摘录原文放在 `_note`）。

## 应用内的分层

```
lib/
├─ main.dart                 初始化窗口 → 读取偏好 → ProviderScope
├─ app/
│  ├─ app.dart               MaterialApp（主题、语言）、AppShell（按路由选择界面）
│  ├─ app_commands.dart      命令：一处定义，生成 macOS 菜单栏或其他平台的快捷键
│  ├─ navigation.dart        路由（资料库 / 学习集 / 复习 / 组件库）与焦点请求
│  └─ providers.dart         外层服务：偏好存储、仓库、时钟、系统外观
├─ settings/                 外观与语言设置（持久化）、系统外观
├─ features/
│  ├─ library/               资料库：控制器 + 界面 + 组件
│  ├─ workspace/             学习集工作区：控制器 + 侧栏 / 原文 / 脑图面板
│  ├─ review/                复习：会话控制器 + 翻卡界面
│  └─ gallery/               组件库（开发用）
├─ shared/l10n.dart          多语言辅助（颜色名、相对时间、复习间隔）
├─ shared/pdf_drop.dart      从 Finder 拖入 PDF 的放置区域
└─ l10n/                     ARB 源文件与生成的本地化代码
```

### 状态管理

- **Riverpod 3**。每个界面有一个 `Notifier` 管 UI 状态（筛选、布局、侧栏开关、标签页），业务数据来自仓库的 `Stream`（`StreamProvider`）。
- **数据单向流动**：界面只调用控制器或仓库方法，变化通过仓库的流回到界面。等 `mm_data` 接入后，SQLite 就是唯一的事实来源。
- **命令**：所有用户命令定义在 `AppMenus` 里，macOS 上生成 `PlatformMenuBar`，其他平台注册为 `CallbackShortcuts`。需要聚焦某个输入框的命令（⌘F）通过 `focusRequestsProvider` 通知当前界面。

## 窗口模型

设计稿里资料库和每个学习集都是独立窗口。Flutter 的多窗口支持还在实验阶段，所以 v0.1 先在一个窗口里用路由切换（`AppNavigation`），交互上保持一致：⇧⌘L 回到资料库，资料库里双击打开学习集。等多窗口稳定后，只需要把路由换成窗口，界面代码不用改。

## 原生化

Flutter 自己绘制每个像素，“像 Mac”不会自动发生。目前交给系统的部分：

| 方面 | 做法 |
| --- | --- |
| 窗口与红绿灯 | `macos_window_utils`：透明标题栏、全尺寸内容视图，红绿灯移到悬浮侧栏内 |
| 窗口拖动 / 双击缩放 | `window_manager.startDragging()`，由工具栏和侧栏顶部的空白区域触发 |
| 菜单栏 | Flutter `PlatformMenuBar`（生成真正的 NSMenu，含“关于”“服务”“隐藏”等系统项） |
| 强调色、降低透明度、减少动态效果 | `macos/Runner/MainFlutterWindow.swift` 中的 `marginmind/system_appearance` 通道 |
| 字体 | 不打包字体；macOS 上使用系统字体（SF Pro + 苹方），原文用宋体 |

尚未完成：侧栏使用真正的 `NSVisualEffectView`（目前用 Flutter 的 `BackdropFilter` 模拟）、右键原生菜单、多窗口。

## 存储位置

macOS 上资料库在应用沙盒的 Application Support 目录：`~/Library/Containers/io.github.mylxsw.marginmind/Data/Library/Application Support/io.github.mylxsw.marginmind/Library/sets/<id>.mmset/`。
