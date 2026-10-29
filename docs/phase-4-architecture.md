# 四期文档技术架构

GUL-570，2026-10-29。初始基线 main `4e376a0`，交付工作区已 rebase 至 `6a1ac58`。架构方向已由项目负责人于 2026-10-29 确认。技术验证结果另见 evidence/gul-570；架构确认不等于性能 Go。

以 `phase-4-documents.md` 第 0、6 节为产品约束：统一 Flutter 流式引擎、原文锚点、Markdown 可标注、四平台持久浏览器。其余旧稿的 PDF 中转、Markdown 只读和手动重新排版不再适用。UI 由已合入 main 的 GUL-571 `phase-4-ui.md` 提供；其中“固定版式沿用 PDF”的旧表述被负责人本任务确认的纯 Flutter 固定视口决定覆盖。

## 1. 包与依赖

| 包 | 所有权与边界 |
| --- | --- |
| mm_core | 纯 Dart：文档格式、能力、原文位置、标注目标、阅读位置、编辑命令与仓库端口。不可引用 Flutter 或解析库。 |
| mm_book（新增） | 纯 Dart，依赖 mm_core：解包、解析、CSS 子集、规范文本与 IR、目录、资源清单、锚点解析。使用纯 Dart archive/xml/html/markdown 适配器；版本在实现时锁定。无文件系统、网络或 UI；资源由端口注入。 |
| mm_reflow（新增） | Flutter，依赖 mm_book/mm_core/mm_design：段落布局、分页、命中、选区、高亮、可访问语义与视图控制器。无持久化和网络。 |
| mm_data | 原文件、IR 和资源事务落盘；学习集格式升级；Web 存储适配器遵循相同逻辑路径。 |
| mm_platform | 所有原生浏览器、会话、DOM 抓取、网页打印、字体和平台调用；不暴露第三方插件对象。 |
| app | 组合根、命令、ARB、能力驱动工具栏；选择 PDF 或流式适配器。 |

mm_pdf 保持实现不变。通用阅读交互适配放 app，不把流式页码伪装成 PDF 坐标。两个新包加入 workspace、CI 和覆盖率收集。

## 2. IR 与文本契约

`Book(version:1, revision, metadata, spine, toc, resources)`；revision 为规范内容与资源清单摘要。`Chapter(id, sourceHref, blocks, canonicalText, sourceMap)`。同一版本章节 ID 使用规范化 spine href；Web 固定为 main；Markdown 固定为 main。块 ID 使用源节点路径，跨版本不承诺稳定。

块为 paragraph、heading(level)、list(items, ordered, start)、quote、code(language)、image、table(rows,cells,spans)、rule、footnote。容器保留嵌套，叶块持有章节 `[start,end)`。内联为 text、emphasis、strong、code、link、hardBreak、ruby(base,annotation)、footnoteRef；样式存计算后的值与资源 ID，不在渲染阶段再解析 DOM。目录节点含稳定 ID、标题、章节/offset 目标和子节点；资源含摘要、MIME、长度、固有尺寸和包内相对路径。

偏移统一为 Dart/Flutter **UTF-16 code unit**，范围为半开区间。解析时解码实体、CRLF→LF；普通文本按 HTML white-space 规则折叠空白，pre 保留；叶块间一个 LF，表格单元格间 TAB、行间 LF，图片用 U+FFFC 占位（alt 不混入原文）。ruby 注音不计入基础正文。软连字符保留在规范文本，视觉换行不添加字符。源 DOM 到规范文本映射必须随 IR 保存。

规范化规则带版本；字号、行距、字体、分页完全不能改变 canonicalText。命中结果向字素簇边界吸附，不能切断 surrogate、组合音标、emoji ZWJ。列表标号、脚注弹层、页眉不重复计入正文。跨章节选择生成有序 `TextAnchor` 列表，不拼出一个跨章 offset。

解析端口：`parse(SourceBytes, ResourceResolver, CancellationToken) -> ParsedBook`；结果包含 IR、资源及结构化 diagnostics，不直接写学习集。支持 EPUB2/3 的 container/OPF/spine/nav/NCX；MOBI6、KF8 解析适配器输出同一 IR。混合 MOBI 优先 KF8；DRM、KFX 明确拒绝；AZW4 检测 PDF 后交既有导入器。不能以桌面 calibre 子进程作为全平台依赖。MOBI/HUFF/CDIC 和 KF8 重建由 GUL-574 用真实样本验证，未支持变体必须报错而非返回残缺成功。

## 3. HTML/CSS 范围

支持 p、div、section、article、h1–h6、span、em/i、strong/b、u、s、a、br、hr、ul/ol/li、blockquote、pre/code、img/figure/figcaption、table/thead/tbody/tr/th/td、sup/sub、ruby/rt 和 EPUB 脚注。未知结构元素展开子节点；script/style 内容不进入正文，表单/音视频用静态替代内容；iframe 不抓取跨域正文。

CSS 支持元素/class/id/后代选择器、内联样式、继承、specificity/source order/important；支持 font family/size/weight/style、line-height、color、text decoration/alignment/indent、white-space、margin/padding、width/max-width、break-before/after/inside。长度支持 px/em/rem/%（百分比按包含块宽或继承字号解析）。用户字号、行距、主题和字体覆盖出版者正文设置；em 比例保留。资源字体需完成加载后才能计入稳定布局。

不实现 flex/grid、float、absolute/fixed、动画、伪元素、复杂选择器和竖排；忽略声明并记录诊断，内容按 DOM 顺序进入普通块流。display:none 的内容不进入可阅读文本；不可见交互控件不作为隐藏正文抓取。横排 ruby 初版展示基础字加括号注音（注音为非锚点装饰）。MathML 用 alttext 或保留可读文本；无替代文本显示不可呈现占位并保留原文件。复杂表格超宽时局部水平滚动；跨行单元格作为不可拆行组，超高组允许内部滚动，不裁掉内容。

## 4. 排版、分页与缓存

每个文本叶块由 TextPainter 排版，块坐标统一左上原点逻辑像素。保留 TextPainter 的 offset、行指标和 selection boxes。分页在已排好的行边界切片，保留同一段落的字形布局并裁剪绘制；不得重新对分页子串排版，否则连字与行宽会变化。图片等比缩放到可用区域，固有尺寸预读避免下载后跳页。表格按行组分页并重复非正文表头；代码保留缩进、局部横滚。脚注用可返回的弹层/独立块，不做本期页底浮动脚注排版。

连续滚动与分页共用 `ChapterLayout`。输出块/行矩形、字符范围、分页片段，不持久保存全书页数。进度按已知章节规范文本长度计算；图片章以至少一个位置计权。章节目录永远指向原文位置。

`layout(chapter, LayoutSpec, generation) -> ChapterLayout`；`hitTest(point) -> TextPosition`；`boxes(anchor) -> List<LayoutBox>`；`reveal(position)`；`selectionChanged(List<TextAnchor>)`。LayoutSpec 包含视口、内边距、字号、行距、字体资源摘要、locale、text direction、text scale 和引擎版本。盒子必须携带 generation，旧布局点击/回调直接丢弃。

解析/规范化在 worker 执行（Web 使用适配器，不直接导入 dart:io）；Flutter 文本布局留 UI isolate，每批块按约 4ms 工作预算让出事件循环。当前可见块优先，向前后预排；布局缓存 LRU 初始最多三章/32MiB 估算预算，图片另限解码像素预算。释放 TextPainter/图片句柄；不得把全书保留为可绘制 Paragraph。

参数变化立即递增 generation，捕获视口顶端 TextPosition 及行内相对位置；当前章重排完成后按原位置恢复，预排邻章。缓存键为 chapter revision + LayoutSpec，不以章名或字号单独作为键。字体加载失败回退并更新 key；晚到结果不得覆盖新字号。100ms 是待测完整章重排目标，不等于可阻塞单帧 100ms。超长章分块调度，但必须仍报告整章总耗时。

CJK/中英混排交 Flutter shaping/断行，不按字符逐个测宽。真实验证覆盖行首标点、NBSP、英文长词、RTL 混排和 emoji；不承诺 CSS hyphens 或完整出版级禁则。选择矩形直接取引擎 boxes，保留双向文本多个不相邻矩形，不把一行强行合成大框。[Flutter 官方选区 API](https://api.flutter.dev/flutter/painting/TextPainter/getBoxesForSelection.html)

## 5. 位置、模型与迁移

`TextAnchor(chapterId,start,end,quote,prefix,suffix,revision,normalizationVersion)`，前后文各最多 32 个字素。同版本先校验范围与 quote；不同版本在原章节查找 exact quote，再用前后文消歧；不能唯一确定即 unresolved，保留旧锚点并列入人工处理，不静默选最近匹配。跨章节迁移只接受唯一 quote+上下文匹配，章节重命名不能直接丢标注。

`ReadingPosition` 为 `PdfPosition(page)` 或 `TextPosition(revision,chapterId,offset,affinity)`；屏幕页码和像素偏移不作为流式持久位置。书签、目录、返回历史、翻译关联、研究引用和 MarginNote 都接受相同位置/目标联合类型。

`DocumentFormat = pdf/epub/mobi/azw3/markdown/web/unknown` 表示来源；`DocumentLayout = fixed/reflow` 表示阅读表示。网页保存原样 PDF 仍能保留 web 来源和 fixed 布局。Document 新增 sourceFileName、contentManifest、revision、layout、origin、readingPosition；fileName 对 PDF 保持原路径，对流式指向 IR manifest。流式不使用 pageCount/lastPage，兼容字段保留为 0/1，任何 UI 只读位置接口。

Annotation 新增 `textAnchors`（可跨章），PDF 的 pages JSON 不变；两类定位必须且只能有一种。构造器与校验同时支持两种，copyWith 保留所有锚点；page/rects 兼容 getter 仅用于 PDF，流式调用抛 StateError，不伪造 page=1。改造所有公共编辑/序列化/剪贴板/导出/删除/撤销路径，按目标类型分派。`AnnotationAnchor`、`PdfTarget`、MarginNote 和 InkStroke 同样加入流式变体，避免只扩展 Annotation 后关联功能仍要求页矩形。

代码当前 `currentStudySetFormat=10`，旧架构正文的 7 已过时。由 GUL-573 独占 10→11 迁移：缺 format/layout 的旧文档读为 pdf/fixed，旧标注和位置原样；新联合类型明确 discriminator，未知类型拒绝可写加载。先完整校验、备份原字节、同目录 flush+rename；未来版本拒绝写回。旧版应用拒绝 format 11，避免保存丢新字段。同步扩展 io/browser 两种存储、testing 内存仓库、复制和导出。若 main 提前占用 11，GUL-573 统一顺延并更新文档，不由各任务分别加版本。

## 6. 能力与功能

`DocumentCapabilities.resolve(format,layout,contentFeatures,runtime)` 是领域纯查询；浏览器平台能力由 mm_platform 注入。命令、菜单、快捷键、工具条和拖入入口使用同一能力。能力包括 selectText/annotate/excerpt/marginNotes/parallel/translate/ink/capture/search/outline/bookmarks/readingSettings/crop/ocr/thumbnails/recapture。流式默认提供前述阅读功能，关闭 crop/ocr/thumbnails；纯图固定页关闭 selectText/search，不能显示不可执行动作。

| 功能 | 实现 |
| --- | --- |
| 选区/高亮/下划线 | 命中→规范偏移→TextAnchor；重排后重新求 boxes；跨页拖动自动翻页，移动端选择柄和桌面拖选共用状态机。 |
| 摘录/回原文 | 同一事务创建 Annotation+Card；定位解析目标版本，未解析时保留引文并提示，不跳错位置。 |
| 页边批注 | TextAnchor→可见首行几何→现有页边栏避让；窄屏收成标记，几何不写盘。 |
| 对照/逐段翻译 | 双文档用显式段落配对表，PDF 端用页/区域位置；禁止简单按全书百分比假装段落对应。翻译按段落 revision+语言缓存并存学习集，迟到结果不覆盖新版本。 |
| 画笔 | 每笔挂一个叶块 ID+原文定位；记录捕获时块宽和相对起点坐标，重排按宽比均匀缩放，不按新高度拉伸。跨块笔迹分段，保留同一撤销组；段落消失列为未对齐。 |
| 框选 | 截取当前 Flutter 阅读层生成不可变图片卡，带覆盖块 TextAnchor 列表和捕获参数；截图不随字号重做。 |
| 搜索 | 在 canonicalText 查找并输出 anchors，定位时仅排命中章；大小写等搜索归一化需保留回原偏移表。 |
| 目录/书签 | 保存原文位置；排序按 spine+offset，不用临时页码。 |

固定版式 EPUB 采用纯 Flutter 固定视口渲染：mm_book 解析 rendition:layout=pre-paginated、viewport meta 及 absolute/fixed 页面盒子（img、svg image、文本）；mm_reflow 按屏幕等比缩放。文本进入同一 canonicalText/TextAnchor，保留搜索、选择、高亮、摘录。无法解析的页面回退为该页流式内容并记录诊断。双页跨页后续实现；不依赖平台 PDF 转换。固定版式不进入本任务 Go 门槛，GUL-572/574 负责样本验证。

## 7. 内置浏览器与网页转换

采用 mm_platform 自有原生桥：macOS/iOS WKWebView，Windows WebView2，Android WebView。复用已有 Readability.js 资源和许可证；不引入远程 CDN。接口 `BrowserSession.navigate/back/forward/reload/stop/clearData`，事件带 navigationId；`capture(navigationId,mode,cancel)` 返回 url/title/capturedAt/dom/resources/diagnostics 或 PDF 字节。导航变化使旧抓取失效。

Apple 最低系统使用应用内 WKWebsiteDataStore.default 持久会话，与 Safari 隔离；新系统可用固定 UUID 的 store，不能直接将 macOS 14/iOS 17 API 用于旧部署目标。[WebKit 官方说明](https://webkit.org/blog/14423/building-profiles-with-new-webkit-api/)。Windows 使用 Application Support 下专属 WebView2 userDataFolder；[Microsoft UDF 契约](https://github.com/MicrosoftDocs/edge-developer/blob/main/microsoft-edge/webview2/concepts/user-data-folder.md)。Android 使用应用沙盒 WebView/CookieManager 会话。清除会话要关闭视图、清 Cookie/存储/缓存并重建，不能只清历史。Cookie 不写入学习集。

主框架 load 完成、DOM mutation 及可观测请求静默 800ms 提示就绪，15s 上限提示仍可转换；这是启发式，长轮询/跨域 iframe 等不可保证观测完整。手动转换始终可用，load 失败时禁用。每次导航最多自动提示一次，SPA 内容变化更新 navigationId/捕获代次。

在当前已登录页面的 DOM clone 上运行同一份 Readability JS，随后清洗，再交 mm_book HTML 适配器；不重新 HTTP 请求正文。脚本在页面 DOM 环境运行，不用无 DOM 的 JSCore 冒充 Readability 运行时。抓取 img.currentSrc、baseURI、可读 blob/data 图片；受认证资源通过会话内请求读取，跨域不可读资源记为缺失，不泄露 Cookie 到 Dart 下载器。正文、资源和快照一致后原子提交。

原网页 PDF：限步自动滚动触发懒加载，恢复位置，再用 WKWebView 原生分页打印、WebView2 PrintToPdf、Android PrintDocumentAdapter；各平台的分页与取消必须原生验收，createPDF 截长图不能冒充分页。[Android WebView API](https://developer.android.google.cn/reference/android/webkit/WebView)。超时/失败返回错误，不回退成阅读模式后宣称原样成功。Web/Linux 的 addWebPage 能力 false，阅读既有快照不受影响。

## 8. 学习集布局与事务

```text
studyset.json
documents/<source-sha>.<ext>
books/<document-id>/<revision>/manifest.json
books/<document-id>/<revision>/chapters/<chapter-hash>.json
books/<document-id>/<revision>/resources/<sha>.<ext>
web/<document-id>/<revision>/snapshot.html
web/<document-id>/<revision>/resources.json
images/<sha>.png
translations/<document-id>/<revision>/<language>.json
```

Web 后端使用相同逻辑键，不要求磁盘目录。原文件不可变；规范 IR 和快照带 schema/version/hash；浏览器 profile 和排版缓存不进学习集。原网页快照清除脚本/事件、活动表单值和会话信息，仅作为离线内容；保留来源 URL 和抓取时刻，不承诺可重新运行网页应用。

导入先 staging，验证全部路径/资源后写引用；取消/失败清理本次 staging。ZIP 防路径穿越、解压总量/条目数/压缩比设上限；资源 MIME 按内容校验，拒绝任意本地文件读取。新版本抓取成功才切换 Document revision，旧版本与未对齐标注保留；撤销窗口内资源不自动回收。只从不可变 manifest 读取，不能半写半读。

## 9. 并行实现边界

| 任务 | 负责 | 消费/交付接口 |
| --- | --- | --- |
| GUL-571 | UI 规格 | reading settings、窄屏、错误/未对齐状态；不决定数据结构。 |
| GUL-572 | mm_reflow | 消费 Book/anchors，交付 layout/hitTest/boxes/reveal 与视图控制器。 |
| GUL-573 | mm_core/mm_data、格式入口 | 独占 format 11 迁移、能力、仓库、导入事务、所有定位联合类型。 |
| GUL-574 | mm_book | 独占 IR/schema/canonicalText/解析器和 fixture；提供固定 JSON 示例供 572 开发。 |
| GUL-575 | mm_platform 浏览器 | 独占 BrowserSession、持久会话、平台视图和 capture/print 原生端口。 |
| GUL-576 | app 流式阅读器 | 组合能力、引擎和编辑操作；选区、高亮、摘录、搜索/目录/书签。 |
| GUL-577 | 网页转换编排 | 消费 575 抓取、574 HTML→IR、573 事务；来源版本、重新对齐。 |
| GUL-578 | 进阶阅读 | 消费通用位置和 boxes，不新增另一种文本锚点；段落画笔、批注、翻译和截图。 |

本任务原型确认后放 mm_reflow/example；IR 最小契约先落 mm_book，由 574 接续扩展，避免 572/574 各创一份 Book。外部 API 更动由本架构文档统一更新，fixture 包含中文/emoji/表格/图片/跨章选择。

## 10. 技术验证计划与当前结论

已完成可运行原型和 Android ARM64 AVD profile 测量；真实数据与结论见 [验证报告](evidence/gul-570/README.md)。后续各段为完整验收协议；已完成项目、未完成项目须以验证报告为准，不能把计划视为运行结果。

验证使用三份真实、合法可再分发 EPUB：中文正文、含实际 table/code 的技术书、含多张插图的英文书。下载时检查作品和图片授权、登记源 URL、作者、许可证、下载日期、SHA-256 和原章节数量；不能用合成文本或转换 TXT 冒充真实 EPUB。素材清单与许可凭证纳入 evidence；原文件按许可提供或用校验下载脚本重建。

实现可复现 harness：全章节完整布局（含真实图片尺寸、表格、字体）、16→22 字号重排、320/768/1200 宽度、翻页及连续滚动。冷启动 5 次，热身后至少 30 次；逐章记录 UTF-16 长度/块数/图片数、p50/p95/max，总耗时与调度等待分开。字体与图片解码冷/热分别记录，不能只测 lorem 文本或只报告最快章。

Android 记录设备/AVD 型号、API、ABI、内存、屏幕、刷新率、Flutter/Dart/engine 版本、build mode、宿主机；优先 profile 真机或支持 profile 的模拟器。无法 profile 时 debug 只能用于功能，不能作为性能结论。保存 FrameTiming 的 build/raster p95、超过刷新周期帧占比、进程峰值 PSS 与基线增量，200 次翻页后内存回落；附屏录证明触摸选择与高亮。macOS 数据作为补充，不能替代 Android。

断言：改字号/宽度前后 TextAnchor 字节相同，quote 与 canonicalText 切片一致；新 boxes 对准对应文字；跨页/跨章/emoji/重复引文不跳错；缓存失效和乱序结果不覆盖新布局。新增 lib 覆盖率 ≥80%，执行 CONTRIBUTING 全部提交前检查。最终 evidence 列出实际执行命令、退出码和原始 CSV/JSON，不预填“通过”。

Go 门槛：三本书实际打开且各类内容不丢失；Android 选区/高亮/重排正确；正常章完整重排 p95<100ms，超长章单列；翻页预排后 p95 build/raster 均不超设备帧预算，超预算帧<1%；缓存有界且循环阅读无持续内存增长。固定版式与浏览器原生打印由后续专项验证，不进入本原型 Go 门槛。

失败时明确 No-Go 并 blocked：优先收敛 CSS 子集、优化分块与缓存再测；若根本无法达标，提出 DOM/WebView 阅读器或固定 PDF 作为替代评审，但两者改变已定产品决定，不能擅自切换。固定版式已确定纯 Flutter 固定视口解释器，由 GUL-572/574 做兼容样本验证。MOBI 变体、复杂表格、字体回退、全平台固定版式和原生 PDF 打印是当前主要风险。


## 11. 已批准的原型边界与依赖

本次只交付最小 mm_book IR/EPUB 适配、paragraph/heading/list/quote/code/image/table 及 text/emphasis/strong/code/link，mm_reflow 分页/滚动、命中/选区/高亮/改字号与基准。MOBI、浏览器、固定版式、格式迁移、翻译都留给后续任务。原型的锚点值对象暂在 mm_book，GUL-573 接续迁到 mm_core，不能产生第二份规范文本契约。

复用当前 lock 中 archive 4.5.2（MIT）、xml 7.0.1（MIT）、html 0.15.7（MIT）、markdown 7.3.1（BSD-3-Clause）；均为纯 Dart。mm_book 只引用 archive.dart 的内存 API，不引用 archive_io.dart；资源由字节输入。原型只实际依赖前三者，Markdown 解析在 GUL-574 接入时锁定 7.3.1。许可证需随发布保留，原文来自本机 pub-cache 对应版本 LICENSE；以 Web 构建验证入口的可移植性。


## 12. 接口边界 / 风险（2026-10-30 负责人裁决）

保留 Flutter 路线。GUL-570 本 PR 的补充 Go 门槛限定为：SVG 解码绘制、图片原位、Calculus 全章 profile 重测（原参数，最慢章重排 p95 <100ms、超预算帧 <1%）以及至少五轮/50 次切章的简单 PSS 稳定性检查。`unsupported_image` 须为零，若有剩余必须逐项列出限制；冷/热解码与绘制成本分别保存。它不是完整 EPUB 产品验收，也不要求在本任务完成下列后续能力。

| 接口/后续验收归属 | 必须验收的内容 |
| --- | --- |
| GUL-576 app 选区状态机 | 跨页/跨章选区、移动端选择柄、无障碍语义；消费统一 UTF-16 锚点及布局盒子。 |
| GUL-572 引擎调度 | LRU/generation/分块调度、长期内存、真机；调用方拥有图片句柄，布局仅借用，旧布局先释放再释放图片。 |
| GUL-574 解析器 | 恶意 EPUB fuzz、nav/NCX、完整 CSS、脚注/ruby；当前 IR 不是完整 CSS 或固定版式实现。 |

原型的 `InlineRun.resource` 在原 DOM 位置占一个 U+FFFC；`BookCell.runs` 保留单元格内相同内联结构，TAB/LF 分隔规则不变。`mm_reflow` 通过 TextPainter placeholder dimensions 排版，再在 inlinePlaceholderBoxes 绘制资源，不另移图片。原型只读图片 width/height 的 px/em/ex/% 内联尺寸；ex 暂按 0.5em，公式垂直对齐采用 middle；完整字体 x-height、CSS vertical-align、复杂合并单元格交 GUL-572/574 验收。这属于排版精度限制，不是图片丢失。

新增 `mm_design.MMBookImage` 封装 raster image / SVG Picture 的 decode、size、paint、dispose；不向 mm_reflow 暴露任何第三方类型。SVG 编译字节使用库的有界缓存，Picture 由章节调用方显式释放；清缓存 API 仅供冷测。

| 新增或调整的锁定依赖 | 许可证 / 可移植性 | 归属 |
| --- | --- | --- |
| flutter_svg 2.3.2 | MIT，纯 Dart/Flutter，无原生插件 | mm_design 唯一直依赖 |
| vector_graphics 1.2.4 | BSD-3-Clause，Flutter canvas，无原生插件 | flutter_svg 间接依赖 |
| vector_graphics_codec 1.1.13、vector_graphics_compiler 1.3.4 | BSD-3-Clause，纯 Dart | 间接依赖 |
| path_parsing 1.1.0 | MIT，纯 Dart | 间接依赖 |
| xml 7.0.1 | MIT，纯 Dart；从 7.1.0 调整以满足 compiler 的 <=7.0.1 约束，不使用 dependency_overrides | mm_book / compiler 共用 |

已检查下载包 pubspec 与 LICENSE；许可证副本在 evidence/gul-570/licenses，均与仓库 MIT 分发兼容。[flutter_svg 官方说明与许可证](https://pub.dev/packages/flutter_svg/versions/2.3.2)。所有解码在 Dart/Flutter 中完成，无外部转换程序。最终运行证据和剩余限制以验证报告为准；本节覆盖第 10 节原完整验收计划中超出此次 Go 的条件。
