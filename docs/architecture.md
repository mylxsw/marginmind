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
| `mm_data` | `FileLibraryStore`：同时实现 `StudySetRepository` 和 `StudySetContentRepository`。每个学习集一个 `.mmset` 文件夹（`studyset.json` + `documents/` + `images/`），写入先写临时文件再改名，同一学习集的写入串行。 | `mm_core`、`crypto`、`path` |
| `mm_pdf` | `MMPdfView`（渲染、选字、可点击的高亮叠加、`reveal` 定位）和 `MMPdfEngine`（初始化、读取页数）。其余代码不直接引用 pdfrx。 | Flutter、`pdfrx`、`mm_core`（`PageRect`） |
| `mm_layout` | `TreeLayout`：向右生长的树，父节点在子树块中垂直居中。输入节点尺寸（及概要标签尺寸），输出矩形、连线和概要位置。 | 仅 `meta` |
| `apps/marginmind` | 组合根：Riverpod providers、路由、菜单与快捷键、功能界面、多语言。 | 以上全部 |

### 数据模型（`mm_core/content`）

`StudySetContent` 是一个学习集的全部内容，不可变：`Document`（文件、页数、读到的页）、`Annotation`（多页 PDF 坐标矩形 + 原文 + 颜色索引）、`Card`（topic / excerpt / note / image）、`MindMap`（独立脑图）、`MapNode`（卡片在指定脑图中的位置：mapId + 父节点 + 排序 + 是否折叠）、`MapRelation` / `MapSummary`（脑图上的关联线与概要）、`ReviewState`（每张卡片的复习排期）。所有修改都是 `StudySetEditor` 上的纯函数（`createExcerpt`、`attachCard`、`addTopic`、`move`、`setCollapsed`、`rate`、`removeDocument`…），仓库的 `update(id, change)` 负责原子地应用并保存，这也让测试不依赖界面。

### 文件包格式（当前 format 4）与兼容接口

- `Annotation.pages` 是按阅读顺序排列的 `AnnotationPage(page, rects)` 列表，页码从 1 开始，矩形继续使用 PDF 坐标。一条高亮仍有同一个 ID、文档、引文和颜色。旧构造参数 `page/rects` 以及首页面的读取属性保留，用于定位到摘录的起始页；写盘只保存 `pages`，复制和改色保留全部页面。
- 图片卡片用 `CardKind.image`，`imageFileName` 引用包内资源，`annotationId` 定位原文区域。`StudySetContentRepository.importImage` 接受 PNG/JPEG 文件，通过内容签名确定扩展名、SHA-256 字节摘要去重，原子写入 `images/<hash>.png|jpg`。同一学习集内多个卡片复用同一路径；不自动回收图片，以免破坏撤销快照。`StudySetEditor.createImage` 只处理引用，不执行文件 IO。框选截图通过 `importImageBytes` 以同样的规则写入。
- `StudySetContent.maps` 保存 `MindMap(id, title)`；旧数据进入稳定 ID `main` 的默认图（空标题代表沿用学习集标题）。节点以 `(mapId, cardId)` 唯一，`parentId` 引用同图内的卡片；同一卡片可在不同图中有不同父级、排序和折叠状态。`node`、`childrenOf`、`pathOf`、`search`、剪贴板和导出接受 `mapId`，默认仍是 `main`。
- `StudySetEditor(mapId: ...)` 的结构编辑只作用于该图，`placeCard` 可复用已有卡片。卡片标题、高亮颜色及复习排期属于共享内容。移除子树时，仍被其他图引用的卡片保留；删除原文高亮则移除各图中的对应子树。删除脑图保留卡片及复习记录，至少保留一张脑图；活动图被删除时切换至列表中的第一张。撤销 / 重做恢复全部图的结构与共享卡片，阅读位置和复习排期继续保留。复习按卡片去重，工作区入口按当前脑图筛选，资料库入口覆盖整个学习集。
- 加载文件包时只接受 `format: 1`～`4`，未知/缺失版本不载入也不改写。迁移逐级进行（1→2 多页高亮与多张脑图，2→3 卡片标签，3→4 关联线与概要）。1→4 迁移先转换并解析数据，再把原始字节备份为 `studyset.json.format-1.bak`，最后写同目录临时文件、flush、rename 替换 `studyset.json`。文档资源不移动；复习记录、阅读位置、节点结构和 ID 保持不变。已存在且与源文件相同的备份允许重试，不同则中止，绝不覆盖备份；单包的格式或 IO 失败只跳过该包，并通过只读 `packageLoadErrors` 按包路径记录原因，其余学习集仍可读写；修复失败包后重新打开资料库可重试迁移。根目录或资料库级初始化失败会向调用者报错，但不缓存失败的 future，同一实例后续操作可重试。从 format 2 或 3 升级沿用相同的原子迁移流程，原始字节按源版本备份为 `studyset.json.format-<源版本>.bak`，已有内容保持不变；再次打开 format 4 不重复迁移。format 4 只新增 `relations` 和 `summaries` 两个列表；升级版本号是为了让旧版应用拒绝打开，而不是读入后保存时丢掉它们。原子替换沿用单进程文件包约定，不支持多个进程同时编辑同一包。
- 内部剪贴板写 version 2，继续读取 version 1；携带多页位置、图片引用和复制时图片文件的绝对路径（`imagePath`）。同包粘贴（源文档仍在，或包内已有卡片引用该图片）直接复用图片；粘贴到其他学习集时，控制器只读取以条目自身 `images/<sha256>.png|jpg` 结尾的路径，经 `importImage` 校验并导入后，图片卡片保留图片但不带原文位置；读取失败或路径不符时降为文字笔记。阅读器将选区按页保存，分页绘制同一 ID 的高亮；跨页引文按阅读顺序以换行连接，回到原文定位到起始页。工作区维护活动脑图 ID，画布、大纲、拖拽、查找、剪贴板与导出均使用该 ID；侧栏管理脑图，节点菜单可以将同一卡片加入其他脑图。
- **框选摘录（C-02）**：阅读器的“框选”工具（⇧⌘R）下，`MMPdfView(areaSelecting: true)` 用一个半透明的拖动识别器优先接管指针拖动（滚轮和触控板滚动仍交给 PDF 视图），矩形限制在起点所在页，松开后回调 `MMPdfArea`（页码 + PDF 坐标矩形）。`MMPdfViewController.captureArea` 用 PDFium 按每点 3 像素（最长边不超过 3000）渲染该区域为 PNG。控制器先导入图片，再用 `StudySetEditor.createAreaExcerpt` 一次写入“空引文的单矩形高亮 + 图片卡片”，只记一步撤销；截图或导入失败不改动内容。框选的高亮在原文上以描边显示，点击后的浮动工具条没有“复制”。移除图片卡片（且不在其他脑图中）时同时删除它的框选高亮。脑图、大纲、侧栏和复习中的图片通过 `CardImageScope` 解析为包内文件；脑图节点按框选矩形的宽高比预留图片高度，无需先解码。

- **标签（C-05）**：`Card.tags` 保存共享标签；`StudySetEditor.setTags` 去掉首尾空白、忽略空标签并按大小写不敏感去重，一次保存记一步撤销。旧卡片缺少 `tags` 时读为空列表。`StudySetContent.tags(mapId:)` 列出当前图的标签；`search(query, mapId:, tag:)` 同时匹配标题、引文和标签，可与精确标签筛选组合，空查询配合标签会返回该标签下的全部卡片（含折叠后代）。侧栏“标签”列出当前图标签，点选后在卡片分组展示匹配结果，点“全部标签”清除筛选。节点菜单与“脑图”菜单可编辑标签，内部剪贴板保留标签。

- **关联线与概要（C-04）**：`MapRelation(mapId, fromId, toId, label)` 是同一张脑图中两张卡片之间的有向线；`MapSummary(mapId, parentId, fromId, toId, label)` 概括同一父节点下从 `fromId` 到 `toId` 的连续兄弟（按当前顺序，两端可颠倒）。两者都属于脑图，不属于卡片；`relationsOf` / `summariesOf` 只返回两端仍在图中、范围仍完整的条目。`StudySetEditor` 的 `addRelation`（拒绝自连和同向重复）、`addSummary`（所选节点须同一父级，相同范围不重复）、`relabel*`、`remove*` 都是纯函数。结构编辑会顺带维护：移除节点时删除以其为端点的关联线；移动或移除使概要的端点离开父级时，概要收缩到仍留在原范围内的兄弟，一个都不剩则删除；插入父节点时新父节点接替被包裹节点在概要中的位置；删除脑图时一并删除。`TreeLayout.layout(summaries: …)` 把概要放在所覆盖子树（含其中的概要）的右侧、子树所占横带之内，因此不会压到其他节点，只加宽画布；同一父级的重叠范围由窄到宽依次向右排。画布在节点下方绘制虚线关联线（目标端带箭头，标签在曲线中点；两端是上下叠在同一列、右侧没有子节点的节点时，线从两者右侧引出，绕过这一段里所有节点和概要标签的右边，标签放在弧顶右侧，不再压住中间的节点）和花括号，关联线和标签超出树的部分也计入画布尺寸，适应窗口时一并显示；标签是可点击的组件；点线或括号可选中，F2 / 空格 / Enter / 双击编辑标签，⌫ 删除，右键有菜单。选中两个节点时“添加关联线”（⌥⌘R）直接连接（先选的指向后选的），只选一个时进入连线状态，下一个点击的节点为终点，Esc 或点空白取消。“添加概要”（⌘]）与新建主题一样，创建和标签算一步撤销，Esc 或清空标签则不留下概要。导出 Markdown 时概要作为范围后的一行，关联线列在文末；OPML 用自定义属性 `_mmId`、`_mmRelations`、`_mmSummaries`（JSON）保存。剪贴板不携带关联线和概要。
- **撤销 / 重做**：控制器的独立编辑自动记录一步快照（最多 100 步）；跨多次写入的原地编辑用 `await beginTransaction()` 开始，`await commitTransaction()` 提交，`await abortTransaction()` 放弃。嵌套事务加入外层事务，最外层提交只记一步；放弃取消整个事务且保留原有重做记录。空事务及内容未变化的编辑不记历史。事务期间禁用控制器级撤销 / 重做，文字框负责自身撤销。写入和事务边界按调用顺序串行执行。撤销、重做和放弃均用 `StudySetEditor.restore` 保留当前复习记录和阅读页码。
- **脑图编辑基础 API**：`insertSibling`（`before` 指定前后）、`promote`、`insertParent`、`removeMany`、`moveMany`、`recolorMany` 均为 `StudySetEditor` 纯函数。虚拟根节点以 `null` 表示；在根上加兄弟节点会添加根的子节点，提升和插入父节点则不操作。批量移动按脑图先序排列、合并选中的父子树，目标落在任一选中子树内或不存在时整批拒绝；`index` 指移除所选节点后的目标兄弟列表位置。批量改色只作用于选中摘录关联的高亮（格式 1 的主题和笔记不存颜色），不隐式修改后代。控制器的 `removeCards` / `moveCards` / `recolorCards` 各只记一步历史。
- **多选与剪贴板**：工作区保留主选中节点和不可变的选中集合；批量删除、拖动和改色复用上述批量 API。`MapClipboard` 在纯 Dart 中将选中子树转换为先序大纲，包含折叠后代，并去重重叠选择；文本支持制表符、空格、空行及列表符号。`StudySetEditor.paste` 一次插入整片森林，重新生成卡片 ID，不复制复习记录；内部格式保留原高亮 ID，目标中仍存在且未关联卡片的高亮会被复用（剪切后粘贴不增加高亮）。原卡片仍存在时，复制摘录生成独立高亮，以保持两张卡片可独立改色和删除；此时相同 PDF 位置会叠加高亮。目标学习集没有原文时，摘录降为保留原文文字的笔记。macOS 通过 `mm_platform` 的原生通道在同一个剪贴板项写入纯文本和带版本的内部格式；其他平台使用系统纯文本剪贴板。粘贴优先读取内部格式，格式无效则解析缩进文本；目标为当前节点的子节点（根选中时插入顶层），整次操作只记一步撤销。
- **拖拽**：画布不在每个节点上放 `DragTarget`，而是由 `MapDrop.resolve` 按指针的场景坐标和节点绘制位置算出落点（节点上下各占一半兄弟间距，上 / 下四分之一插在前后，中部成为子节点，根节点只接受子节点，正在拖动的节点及其后代不接受）。预览和放下读同一个 `MapDrop`，所以落点总与预览一致。指针靠近或越过画布边缘时，计时器按距离平移画布，平移到脑图另一侧进入视野为止，每一步都重新计算落点；指针在画布外时没有落点。
- **复习**：`ReviewScheduler` 是简化的 SM-2（重来 10 分钟后再出现；良好 1 天 → 3 天 → 间隔 × 难度系数）。`reviewQueue(now)` 给出到期卡片（最逾期在前）和最多 20 张新卡片；资料库的待复习数也由它计算。
- **导出**：`MapExporter` 把当前脑图转成 Markdown（嵌套列表）或 OPML 2.0（摘录原文放在 `_note`），关联线与概要见上文。

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
