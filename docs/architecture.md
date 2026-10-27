# 架构

本地单机版也分“前端”和“后端”：前端是 Flutter 界面，后端是同一进程里的本地核心。两者只通过领域层定义的端口和查询对话，所以以后把核心放进后台 Isolate、或者接入同步服务，都不需要改界面。

设计稿对应画板：`design/canvas/Architecture.dc.html`、`design/canvas/DataModel.dc.html`。

## 包与依赖

```
apps/marginmind ──► mm_design    (令牌、主题、组件)
        │      ──► mm_platform  (窗口、快捷键、系统外观)
        │      ──► mm_pdf ─────┐ (PDF 渲染、选字、高亮叠加)
        │      ──► mm_research ┤ (研究 HTTP、AI 流式适配器；纯 Dart)
        │      ──► mm_data ────┤ (学习集文件包)
        │      ──► mm_layout   │ (脑图树布局；纯 Dart)
        └──────► mm_core ◄─────┘ (实体、编辑操作、端口、查询；纯 Dart)
```

| 包 | 职责 | 可以依赖 |
| --- | --- | --- |
| `mm_core` | 实体（`StudySet`、`Folder`）、仓库端口（`StudySetRepository`）、纯查询（`LibraryQuery`）。`testing.dart` 提供内存实现和示例数据。 | 仅 Dart 标准库与 `meta` |
| `mm_research` | Anthropic Messages、OpenAI Responses、兼容 Chat Completions；SSE、引用候选、预算、安全 HTTP。协议与持久化实体分离。 | `mm_core`、`http`（纯 Dart） |
| `mm_design` | 设计令牌、`MMTheme`、所有可复用组件。不含业务概念，不含文案。 | Flutter、`cupertino_icons` |
| `mm_platform` | 原生窗口（透明标题栏、红绿灯位置、拖动、缩放）、平台快捷键、系统强调色与辅助功能设置。 | Flutter、`mm_core`、`window_manager`、`macos_window_utils` |
| `mm_data` | `FileLibraryStore`：同时实现 `StudySetRepository` 和 `StudySetContentRepository`。每个学习集一个 `.mmset` 文件夹（`studyset.json` + `documents/` + `images/`），写入先写临时文件再改名，同一学习集的写入串行。 | `mm_core`、`crypto`、`path` |
| `mm_pdf` | `MMPdfView`（渲染、选字、可点击的高亮叠加、笔迹层、`reveal` 定位）和 `MMPdfEngine`（初始化、读取页数）。其余代码不直接引用 pdfrx。 | Flutter、`pdfrx`、`mm_core`（`PageRect`） |
| `mm_layout` | `TreeLayout`：向右生长的树，父节点在子树块中垂直居中；`balanced: true` 时中心主题的分支按子树高度分到左右两侧（前一部分在右，其余在左并镜像生长），左侧节点记在 `leftSide`。输入节点尺寸（及概要标签尺寸），输出矩形、连线和概要位置。 | 仅 `meta` |
| `apps/marginmind` | 组合根：Riverpod providers、路由、菜单与快捷键、功能界面、多语言。 | 以上全部 |

### 数据模型（`mm_core/content`）

`StudySetContent` 是一个学习集的全部内容，不可变：`Document`（文件、页数、读到的页）、`Annotation`（多页 PDF 坐标矩形 + 原文 + 颜色索引）、`Card`（topic / excerpt / note / image）、`MindMap`（独立脑图）、`MapNode`（卡片在指定脑图中的位置：mapId + 父节点 + 排序 + 是否折叠）、`MapRelation` / `MapSummary`（脑图上的关联线与概要）、`ReviewState`（每张卡片的复习排期）、`ReviewLog`（逐次评分日志）、`MemoryState`（可选 FSRS 记忆状态）。所有修改都是 `StudySetEditor` 上的纯函数（`createExcerpt`、`attachCard`、`addTopic`、`move`、`setCollapsed`、`rate`、`removeDocument`…），仓库的 `update(id, change)` 负责原子地应用并保存，这也让测试不依赖界面。

### 文件包格式（当前 format 7）与兼容接口

- `Annotation.pages` 是按阅读顺序排列的 `AnnotationPage(page, rects)` 列表，页码从 1 开始，矩形继续使用 PDF 坐标。一条高亮仍有同一个 ID、文档、引文和颜色。旧构造参数 `page/rects` 以及首页面的读取属性保留，用于定位到摘录的起始页；写盘只保存 `pages`，复制和改色保留全部页面。
- 图片卡片用 `CardKind.image`，`imageFileName` 引用包内资源，`annotationId` 定位原文区域。`StudySetContentRepository.importImage` 接受 PNG/JPEG 文件，通过内容签名确定扩展名、SHA-256 字节摘要去重，原子写入 `images/<hash>.png|jpg`。同一学习集内多个卡片复用同一路径；不自动回收图片，以免破坏撤销快照。`StudySetEditor.createImage` 只处理引用，不执行文件 IO。框选截图通过 `importImageBytes` 以同样的规则写入。
- `StudySetContent.maps` 保存 `MindMap(id, title)`；旧数据进入稳定 ID `main` 的默认图（空标题代表沿用学习集标题）。节点以 `(mapId, cardId)` 唯一，`parentId` 引用同图内的卡片；同一卡片可在不同图中有不同父级、排序和折叠状态。`node`、`childrenOf`、`pathOf`、`search`、剪贴板和导出接受 `mapId`，默认仍是 `main`。
- `StudySetEditor(mapId: ...)` 的结构编辑只作用于该图，`placeCard` 可复用已有卡片。卡片标题、高亮颜色及复习排期属于共享内容。移除子树时，仍被其他图引用的卡片保留；删除原文高亮则移除各图中的对应子树。删除脑图保留卡片及复习记录，至少保留一张脑图；活动图被删除时切换至列表中的第一张。撤销 / 重做恢复全部图的结构与共享卡片，阅读位置和复习排期继续保留。复习按卡片去重，工作区入口按当前脑图筛选，资料库入口覆盖整个学习集。
- 加载文件包时只接受 `format: 1`～`7`，未知/缺失版本不载入也不改写。迁移逐级进行（1→2 多页高亮与多张脑图，2→3 卡片标签，3→4 关联线与概要）。1→4 迁移先转换并解析数据，再把原始字节备份为 `studyset.json.format-1.bak`，最后写同目录临时文件、flush、rename 替换 `studyset.json`。文档资源不移动；复习记录、阅读位置、节点结构和 ID 保持不变。已存在且与源文件相同的备份允许重试，不同则中止，绝不覆盖备份；单包的格式或 IO 失败只跳过该包，并通过只读 `packageLoadErrors` 按包路径记录原因，其余学习集仍可读写；修复失败包后重新打开资料库可重试迁移。根目录或资料库级初始化失败会向调用者报错，但不缓存失败的 future，同一实例后续操作可重试。从 format 2 或 3 升级沿用相同的原子迁移流程，原始字节按源版本备份为 `studyset.json.format-<源版本>.bak`，已有内容保持不变；再次打开当前 format 7 不重复迁移。format 4 只新增 `relations` 和 `summaries` 两个列表；升级版本号是为了让旧版应用拒绝打开，而不是读入后保存时丢掉它们。原子替换沿用单进程文件包约定，不支持多个进程同时编辑同一包。
- **格式 5→6（GUL-511）**：format 5 增加 `bookmarks`；format 6 新增 `reviewLogs`、`memoryStates` 两个列表及 `Card.suspended`（缺省 false，false 可省略）。5→6 只增加空列表，旧 `ReviewState`、卡片和其他内容原样保留，不推断历史日志或 FSRS 参数。仍先解析后备份源字节到 `studyset.json.format-5.bak`，再原子替换；失败重试与备份冲突保护不变。已是当前格式时不迁移，不改写文件或备份。
- **格式 6→7（GUL-515 / P2-A2）**：只新增 `researchNotes`、`noteAttachments`、`evidence`、`researchSources`、`inkStrokes` 空列表。卡片增加 `research` 类型（只保存 `researchNoteId`）、`textFormat`（缺省 `plain`）、可选 `imageOrigin`；`MapNode.width` 属于单图位置，`MindMap.density` 缺省 `full`。旧纯文本、高亮、图片、图结构、复习日志与排期保持不变。先完整解析再备份原字节至 `studyset.json.format-6.bak`，最后 flush 临时文件并 rename；同字节备份允许恢复中断，不同字节备份中止。
- **研究内容**：`ResearchNote`、`NoteAttachment`、不可修改的 `Evidence`、带不可修改版本的 `ResearchSource` 索引与 `InkStroke` 都在 `studyset.json` 内，随完整内容快照一步撤销/重做。笔记关联使用 `PdfTarget`（文档 ID、多页 PDF 坐标、原句和邻文）或 `CardTarget`（共享卡片 ID），不保存屏幕坐标。保存笔记、证据与关联是一个纯函数编辑。删除 PDF 清除其关联与笔迹，删除卡片的最后一个图位置清除其卡片关联；两者都保留笔记和证据。删除笔记清除全部关联和引用卡片，引用卡片下的其他节点提升至父级；证据保守保留供撤销和其他笔记使用。笔迹按页存储，拒绝无效坐标、宽度、形状和超过 10000 点的单笔；文本导出不包含笔迹。
- **研究独立文件**：`ResearchSessionRepository` 原子读写 `research/sessions/<id>.json`，保存问题、意图、方式、`SourceAnchor`、上下文范围、关键词、查询/对话、资料 ID、勾选/编辑草稿、任务状态与时间；历史不进入撤销。保存笔记 ID 列表以当前内容为准，内容保存时同步、读取会话时再次校正，能恢复内容已落盘但会话更新中断的情况。同步失败通过只读 `researchSessionSyncErrors` 报告，不把已经提交的内容编辑误报为失败；后续笔记编辑重试同步。删除原文后 `SourceAnchor.canLocate` 返回 false，不跳到其他位置。`ResearchSnapshotRepository` 将 UTF-8 正文按 SHA-256 写入 `research/snapshots/<hash>.md`；同内容去重且不改写已有文件，冲突和读入时哈希不符报错。独立文件与内容共用单学习集串行写队列，单次失败不阻塞后续重试。不自动回收快照，避免破坏证据和撤销窗口。
- **研究复制与导出**：剪贴板 v3 携带被复制卡片关联的笔记、证据、来源版本、PDF 关联和快照正文，同时保留格式、图片来源与节点宽度。控制器先原子导入快照，再用新 ID 重建笔记/证据/来源/卡片关联；同次粘贴的共享笔记只复制一次，不带会话 ID。目标缺少 PDF 时移除对应 PDF 关联、保留卡片关联并记录 `sourceLocationMissing`（原文位置未随复制），不留下跨学习集引用。Markdown 以“研究笔记”列表项输出标题，下方保留正文、引用（标题 · 网址 · 抓取时间）和每页出处；OPML 的 `text` 是笔记标题，`_note` 为正文、引用和出处。
- **复习数据 API**：`ReviewLog(id, cardId, reviewedAt, rating, intervalBefore, intervalAfter)` 每次 `StudySetEditor.rate` 追加一条；时间和排期使用同一次时钟采样。间隔单位为天，与 `ReviewState.intervalDays` 一致（学习与重学分钟步骤为 0），首次评分的前间隔为 0；预览不记日志，已删除卡片不接受新评分。`reviewLogsOf(cardId)` 按追加顺序读取不可变列表。日志与排期保留已删除卡片的记录，删除/撤销/重做不删除或重复日志。
- **FSRS 与暂停的数据基础**：`MemoryState(cardId, stability, difficulty, phase, learningStep)` 独立于旧排期；stability 单位为天，phase 为 learning/review/relearning，learningStep 默认 0；没有记录表示尚未初始化 FSRS。`setMemoryState` 按卡片替换，`memoryOf` 查询；设置参数不改变到期时间，FSRS 评分原子地更新这些参数与排期。撤销/重做保留当前记忆状态。`setSuspended` 修改共享卡片标记，可由内容快照撤销。FSRS 初始化/算法见下节；暂停过滤与入口见下文“复习范围”。
- **FSRS-5（GUL-508 / L-01）**：`ReviewScheduler.schedule` 是纯函数，返回 `review` 与 `memory`；`StudySetEditor.rate` 将两者和唯一评分日志一起写入。预览传入相同的记忆状态与 `FsrsParameters`。默认采用 ts-fsrs v4.5.2 的 19 项 FSRS-5 参数、90% 保留率、36500 天上限和确定性学习步骤（无随机扰动）。整组参数可通过 `StudySetEditor.fsrsParameters` 注入。新卡 Again/Hard/Good 为 1/5/10 分钟、Easy 进入长期复习；学习/重学 Again/Hard 为 5/10 分钟，Good/Easy 毕业；复习 Again 进入 5 分钟重学。间隔取完整经过天数，预览不修改状态。达到最大间隔时允许 Hard/Good/Easy 相同，避免越过上限。
- **旧排期初始化**：文件仓库加载后调用 `StudySetEditor.initializeMemory`，仅为没有记忆状态的旧排期补值：正间隔作为 stability（限制 .01～36500 天），零间隔用默认 Again stability 并进入 relearning；difficulty = clamp(5 + 2 × (2.5 − ease) + ln(1 + lapses), 1, 10)。这是缺少历史日志时的确定性估计，并非恢复真实历史。已有记忆状态不覆盖，旧 due / last / interval / ease / reps / lapses、日志保持不变；实际评分后才重新排期。初始化本身不写盘，下次原子保存时写入，重复打开结果一致。复用格式 6 的既有字段，无格式结构变化或版本升级；旧版格式 6 客户端不应继续交替评分。

- 内部剪贴板写 version 3，继续读取 version 1 / 2；携带多页位置、图片引用和复制时图片文件的绝对路径（`imagePath`）。同包粘贴（源文档仍在，或包内已有卡片引用该图片）直接复用图片；粘贴到其他学习集时，控制器只读取以条目自身 `images/<sha256>.png|jpg` 结尾的路径，经 `importImage` 校验并导入后，图片卡片保留图片但不带原文位置；读取失败或路径不符时降为文字笔记。阅读器将选区按页保存，分页绘制同一 ID 的高亮；跨页引文按阅读顺序以换行连接，回到原文定位到起始页。工作区维护活动脑图 ID，画布、大纲、拖拽、查找、剪贴板与导出均使用该 ID；侧栏管理脑图，节点菜单可以将同一卡片加入其他脑图。
- **框选摘录（C-02）**：阅读器的“框选”工具（⇧⌘R）下，`MMPdfView(areaSelecting: true)` 用一个半透明的拖动识别器优先接管指针拖动（滚轮和触控板滚动仍交给 PDF 视图），矩形限制在起点所在页，松开后回调 `MMPdfArea`（页码 + PDF 坐标矩形）。`MMPdfViewController.captureArea` 用 PDFium 按每点 3 像素（最长边不超过 3000）渲染该区域为 PNG。控制器先导入图片，再用 `StudySetEditor.createAreaExcerpt` 一次写入“空引文的单矩形高亮 + 图片卡片”，只记一步撤销；截图或导入失败不改动内容。框选的高亮在原文上以描边显示，点击后的浮动工具条没有“复制”。移除图片卡片（且不在其他脑图中）时同时删除它的框选高亮。脑图、大纲、侧栏和复习中的图片通过 `CardImageScope` 解析为包内文件；脑图节点按框选矩形的宽高比预留图片高度，无需先解码。

- **基础圈画（GUL-518 / P2-C04）**：标注工具组的“画笔”（⇧⌘M，`AnnotationTool.ink`）只属于当前窗口和本次运行，不写入设置，重启后回到选择工具；Esc 或“完成”退出。画笔下 `MMPdfView(ink: MMPdfInk)` 用与框选相同的半透明拖动识别器接管指针（滚轮、触控板照常滚动缩放），并关闭文字选择与高亮点击。笔迹以 PDF 页面坐标记录（pdfrx `toPdfPoint` / `toOffset`，与高亮同一坐标系，含页面旋转），起点所在页为准、越界夹到页边；松手后自由线做 Douglas–Peucker 简化（0.3 点起，超过 1000 点加倍容差），圈画规整为外接椭圆（按住 ⇧ 保留手绘，存为自由线），箭头只存起止两点；宽度单位是 PDF 点，随缩放一起变粗。橡皮擦按下即判定，点击或划过约 6 屏幕像素内的整条笔迹，一次手势回调一次 `onInkErased`。每页一个 `IgnorePointer` + `RepaintBoundary` 的 `CustomPainter`，按页保留列表身份（同 ID 序列复用旧列表），擦除中的隐藏集合按页通知，所以只有变化的页面重绘；正在画和刚画完、等待父层保存的笔迹在视口层单独绘制，父层的 `inkStrokes` 出现新 ID 后移交给页面层，2 秒未确认则放弃显示。控制器 `addInkStroke` / `eraseInkStrokes` 各是一次 `_update`，所以每一笔、每一次擦除各一步撤销；模型拒绝的笔迹（如页码越界）直接丢弃。

- **外部图片（GUL-517 / P2-C02）**：脑图菜单、右键菜单和右下角按钮共用 PNG / JPEG 选择入口；拖入脑图按同一路径导入。macOS 粘贴优先保留内部节点，否则读取 PNG / JPEG 或 Finder 文件 URL；系统截图只有 TIFF 时转成 PNG。文字框保留自己的粘贴，脑图之外只处理图片。`insertImages` 把资源导入和卡片创建放在同一个串行编辑操作中，整批只记一步撤销；失败不新增卡片，撤销保留包内资源以便重做。`Card.imageOrigin` 复用格式 7 的字符串字段：`pasted` 或 `file:<原始文件名>`；题面复用 `Card.title`。外部图片没有高亮引用，详情和复习不显示原文跳转；有题面先显示题面，没有题面显示父节点和分支路径，翻面才显示图片。双击 / 空格及详情图片可打开缩放预览，预览按原分辨率解码。

- **标签（C-05）**：`Card.tags` 保存共享标签；`StudySetEditor.setTags` 去掉首尾空白、忽略空标签并按大小写不敏感去重，一次保存记一步撤销。旧卡片缺少 `tags` 时读为空列表。`StudySetContent.tags(mapId:)` 列出当前图的标签；`search(query, mapId:, tag:)` 同时匹配标题、引文和标签，可与精确标签筛选组合，空查询配合标签会返回该标签下的全部卡片（含折叠后代）。侧栏“标签”列出当前图标签，点选后在卡片分组展示匹配结果，点“全部标签”清除筛选。节点菜单与“脑图”菜单可编辑标签，内部剪贴板保留标签。

- **关联线与概要（C-04）**：`MapRelation(mapId, fromId, toId, label)` 是同一张脑图中两张卡片之间的有向线；`MapSummary(mapId, parentId, fromId, toId, label)` 概括同一父节点下从 `fromId` 到 `toId` 的连续兄弟（按当前顺序，两端可颠倒）。两者都属于脑图，不属于卡片；`relationsOf` / `summariesOf` 只返回两端仍在图中、范围仍完整的条目。`StudySetEditor` 的 `addRelation`（拒绝自连和同向重复）、`addSummary`（所选节点须同一父级，相同范围不重复）、`relabel*`、`remove*` 都是纯函数。结构编辑会顺带维护：移除节点时删除以其为端点的关联线；移动或移除使概要的端点离开父级时，概要收缩到仍留在原范围内的兄弟，一个都不剩则删除；插入父节点时新父节点接替被包裹节点在概要中的位置；删除脑图时一并删除。`TreeLayout.layout(summaries: …)` 把概要放在所覆盖子树（含其中的概要）的外侧（右侧分支在右，左侧分支在左）、子树所占横带之内，因此不会压到其他节点，只加宽画布；同一父级的重叠范围由窄到宽依次向外排。平衡布局分配中心主题的分支时不会把一个概要的范围拆到两侧。画布在节点下方绘制虚线关联线（目标端带箭头，标签在曲线中点；两端是上下叠在同一列、右侧没有子节点的节点时，线从两者右侧引出，绕过这一段里所有节点和概要标签的右边，标签放在弧顶右侧，不再压住中间的节点；左侧分支镜像处理，从左边绕开，标签在弧顶左侧且不超出画布）和花括号，关联线和标签超出树的部分也计入画布尺寸，适应窗口时一并显示；标签是可点击的组件；点线或括号可选中，F2 / 空格 / Enter / 双击编辑标签，⌫ 删除，右键有菜单。选中两个节点时“添加关联线”（⌥⌘R）直接连接（先选的指向后选的），只选一个时进入连线状态，下一个点击的节点为终点，Esc 或点空白取消。“添加概要”（⌘]）与新建主题一样，创建和标签算一步撤销，Esc 或清空标签则不留下概要。导出 Markdown 时概要作为范围后的一行，关联线列在文末；OPML 用自定义属性 `_mmId`、`_mmRelations`、`_mmSummaries`（JSON）保存。剪贴板不携带关联线和概要。
- **撤销 / 重做**：控制器的独立编辑自动记录一步快照（最多 100 步）；跨多次写入的原地编辑用 `await beginTransaction()` 开始，`await commitTransaction()` 提交，`await abortTransaction()` 放弃。嵌套事务加入外层事务，最外层提交只记一步；放弃取消整个事务且保留原有重做记录。空事务及内容未变化的编辑不记历史。事务期间禁用控制器级撤销 / 重做，文字框负责自身撤销。写入和事务边界按调用顺序串行执行。撤销、重做和放弃均用 `StudySetEditor.restore` 保留当前复习记录和阅读页码。
- **脑图编辑基础 API**：`insertSibling`（`before` 指定前后）、`promote`、`insertParent`、`removeMany`、`moveMany`、`recolorMany` 均为 `StudySetEditor` 纯函数。虚拟根节点以 `null` 表示；在根上加兄弟节点会添加根的子节点，提升和插入父节点则不操作。批量移动按脑图先序排列、合并选中的父子树，目标落在任一选中子树内或不存在时整批拒绝；`index` 指移除所选节点后的目标兄弟列表位置。批量改色只作用于选中摘录关联的高亮（格式 1 的主题和笔记不存颜色），不隐式修改后代。控制器的 `removeCards` / `moveCards` / `recolorCards` 各只记一步历史。
- **多选与剪贴板**：工作区保留主选中节点和不可变的选中集合；批量删除、拖动和改色复用上述批量 API。`MapClipboard` 在纯 Dart 中将选中子树转换为先序大纲，包含折叠后代，并去重重叠选择；文本支持制表符、空格、空行及列表符号。`StudySetEditor.paste` 一次插入整片森林，重新生成卡片 ID，不复制复习记录；内部格式保留原高亮 ID，目标中仍存在且未关联卡片的高亮会被复用（剪切后粘贴不增加高亮）。原卡片仍存在时，复制摘录生成独立高亮，以保持两张卡片可独立改色和删除；此时相同 PDF 位置会叠加高亮。目标学习集没有原文时，摘录降为保留原文文字的笔记。macOS 通过 `mm_platform` 的原生通道在同一个剪贴板项写入纯文本和带版本的内部格式；其他平台使用系统纯文本剪贴板。粘贴优先读取内部格式，格式无效则解析缩进文本；目标为当前节点的子节点（根选中时插入顶层），整次操作只记一步撤销。
- **拖拽**：画布不在每个节点上放 `DragTarget`，而是由 `MapDrop.resolve` 按指针的场景坐标和节点绘制位置算出落点（节点上下各占一半兄弟间距，上 / 下四分之一插在前后，中部成为子节点，根节点只接受子节点，正在拖动的节点及其后代不接受）。预览和放下读同一个 `MapDrop`，所以落点总与预览一致。指针靠近或越过画布边缘时，计时器按距离平移画布，平移到脑图另一侧进入视野为止，每一步都重新计算落点；指针在画布外时没有落点。
- **复习**：`ReviewScheduler` 是 FSRS-5（见上文“FSRS-5”）。`reviewQueue(now)` 给出到期卡片（最逾期在前）和最多 20 张新卡片；资料库的待复习数也由它计算。
- **复习范围（L-03）**：`reviewQueue(now, mapId:, branchId:, tag:)` 是纯函数：暂停的卡片（`Card.suspended`）一律不进队列，因而也不计入任何待复习数；`branchId` 只留该卡片及其在 `mapId`（缺省主图）上的全部后代（含折叠的，见 `branch()`）；`tag` 按大小写不敏感的精确匹配筛选。筛选先于新卡片上限。`ReviewRoute` 携带同样的范围，复习界面副标题显示分支标题或标签。入口：节点菜单“复习此分支”（有子节点且分支内有待复习卡片时才出现）与“暂停复习 / 恢复复习”（主题不参与复习，不出现），侧栏标签右键“复习此标签”，以及“脑图”菜单复习分组里的同名命令。暂停记一步撤销；脑图上暂停的卡片内容半透明，大纲里用次级文字色。
- **复习统计（GUL-509）**：`ReviewStats`（`mm_core`，纯函数）只读复习日志：`daily` 按本地日历日汇总最近 30 天的复习量与“记住”（评分不是“重来”）数，`retention` 求整体记住率，`upcoming` 把到期时间分到未来 30 天（已逾期算今天）；到期时间来自 `StudySetContent.scheduledDues`（已排期、可复习、未暂停的卡片）。`StudySet.reviewLogCount` 让资料库不加载内容就知道有没有日志。入口是资料库侧栏和学习集侧栏“学习”分组里的“统计”（以及“学习”菜单），没有日志时不显示；`StatsRoute(studySetId)`，为空时汇总所有学习集。图表是 `BarChartPainter`，颜色只取令牌。
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
├─ shared/pdf_picker.dart    选择 PDF 的打开面板（测试中替换）
└─ l10n/                     ARB 源文件与生成的本地化代码
```

### 状态管理

- **Riverpod 3**。每个界面有一个 `Notifier` 管 UI 状态（筛选、布局、侧栏开关、标签页），业务数据来自仓库的 `Stream`（`StreamProvider`）。
- **数据单向流动**：界面只调用控制器或仓库方法。工作区各视图读取 `WorkspaceState.content`；写入完成及仓库流通知都会读取仓库当前快照后发布，避免延迟的旧流载荷覆盖已完成的编辑。异步读取以请求序号保序，旧读取等待更新的读取完成；相同快照不重复发布。当前文件仓库和内存仓库的 `load` 都返回内存快照，不增加每次编辑的磁盘读取。仓库仍是事实来源，持久化格式和领域端口不变。
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
- **页面侧栏与文内搜索（GUL-496）**：`MMPdfViewController` 是 `ChangeNotifier`，向外报告页码、页数、目录（`MMPdfOutlineItem`，纯函数 `activeOutlineItem` 求当前章节）和搜索状态（`PdfTextSearcher`，命中处由页面绘制回调高亮）；跳转通过 `jumpToPage` / `jumpToRect` 记入 `PageHistory`，`goBack`（⌘[）依此返回，滚动不记录。控制器由 `readerPdfProvider(studySetId)` 持有，菜单、侧栏和查找条都不需要拥有 PDF 视图。缩略图用 `MMPdfThumbnail`（pdfrx `PdfPageView`）按需渲染。书签是 `Bookmark`（`StudySetContent.bookmarks`，空标题表示未命名，界面显示页码），编辑是 `StudySetEditor.toggleBookmark / renameBookmark / removeBookmark`，随撤销快照；删除文档同时删除它的书签。文件包格式升到 5（迁移只补 `bookmarks: []`）。⌘F 是否查找 PDF 由 `AppMenus` 按焦点是否在原文面板（`ReaderNavIntent` 的 `Actions` 祖先）决定。

- **新摘录文本（GUL-498）**：`mm_pdf` 的 `buildExcerptText` 是不依赖 Flutter / PDF 引擎的纯函数，接收完整页文字、字符矩形和选区索引。视图只额外加载所选页的直接邻页作为重复证据；按矩形选出几何最上/最下行，位于上下 8%、与正文分离、至少两页文字及位置一致时才剔除；变化的行首/行尾页码要求数字差等于 PDF 页码差，支持书眉及 HTTP(S)/文件路径页脚；日期单独归一化。证据不足保留原文。段内中文直接连接，西文加空格，处理软连字符、PDFium U+0002 和拉丁断词；空行及明显几何段间距保留。新高亮矩形按同一基线合并，跨大列间隙不连。松开后用清理矩形绘制选区并隐藏引擎的临时预览，持久行高亮接入按页索引和 overlay LRU，临时选区单独绘制，不污染持久缓存；清理结果直接进入现有高亮 / 摘录 / 卡片链路；旧数据、渲染旧矩形和 format 5 均不变。

- **阅读器界面（GUL-504）**：窗口标题是当前文档名，副标题只放页码；只有一份文档时不显示标签栏，页面侧栏开关在工具栏。`MMSplitView.resolveNarrow` 根据窗口宽度推出实际显示：分栏放不下时先收起侧栏，再退化为只看原文；偏好（`sidebarVisible`、`layout`）不改，窗口放宽后恢复，布局按钮按实际显示着色。浮动工具条（`placeFloatingToolbar(avoid:)`）避开页码胶囊，两侧都压到时放在选区上方。“添加笔记”调用 `excerptAndEditNote`：摘录和空笔记在同一事务中创建，原地编辑（E-06），确认后记一步撤销，Esc 或留空整体放弃。颜色选择收进工具栏的 `MMColorMenuButton`。

### 研究接入（GUL-514）

`mm_core/src/research/ports.dart` 定义 `AiProvider`、`SearchProvider`、`ContentExtractor`、
`SecretStore`、`ResearchSessionRepository<T>`、请求/事件/引用候选与取消令牌。AI 输出带会话和请求 ID，
应用层负责防止迟到响应写入新请求。`ResearchCitation` 不等于已保存的证据，只有校验到快照原文后才能归档。
会话实体、快照与 format 7 存储由 P2-A2 定义；本任务不改变文件格式。

`mm_platform` 的 `KeychainSecretStore` 实现 SecretStore；原生处理器随 macOS Runner 注册。
`mm_research` 不依赖 Flutter 或 mm_platform，组合根读取密钥后注入适配器。
新包已加入 workspace 和 `tool/coverage.py`。详细预算、方式映射及验证限制见
[ADR 0001](decisions/0001-research-ai-integration.md)。

### 扫描 PDF 文字识别（GUL-521）

`mm_platform` 的 `VisionPdfOcr` 通过方法通道调用 Runner 的 `PdfOcrChannel`。后台串行队列逐页使用 Vision、Core Graphics 和 Core Text 生成带隐藏文本层的 `documents/<hash>.ocr.pdf`，原 PDF 不变。副本由约定文件名发现，沿用 format 7，不新增模型字段。应用层 `readerOcrProvider(sourcePath)` 管理进度、取消和副本重载；阅读器打开副本后复用 pdfrx 的选字、搜索、摘录和高亮坐标。坐标、取消语义和资源上限见 [验证记录](evidence/gul-521/README.md)。

### 研究笔记复习（P2-R4）

复用 format 7 的 `Card(kind: research, researchNoteId: …)` 与 `suspended`，
每条笔记首次加入复习时建立一个 `research-review:<noteId>` 卡片，作为唯一 FSRS 载体。
该卡片没有 MapNode 或 NoteAttachment，不计入可见卡片数；多个脑图关联仍共用同一排期。
详情开关默认关闭，关闭后保留 ReviewState / MemoryState / ReviewLog，重新开启继续原排期。
PDF-only 笔记可进入整图/学习集复习；分支与标签筛选通过可见研究卡匹配，不混入无关分支。
题面取 ResearchNote.question，答案实时投影正文及固定版本的引用。删除笔记删除载体，撤销
恢复载体和已有排期；复制新笔记默认不加入复习。无需新增持久化字段或升级格式。
