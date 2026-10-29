# 阅读增强技术架构

基于 `origin/main` 的 `1b2c78e` 和 `docs/phase-3-reading.md`。技术方案经 GUL-546 负责人批准；本文记录已实现的数据底座、验证结论，以及 A–D 后续批次契约。

## 分层与批次

| 层 | 本任务与后续职责 | 公开契约 |
| --- | --- | --- |
| mm_core | 本任务：纯 Dart 模型、编辑操作与引用约束 | DocumentCrop、MarginNote、ComparePair、TranslationCache；StudySetEditor 纯函数操作 |
| mm_data | 本任务：格式 7 → 8、持久化回归 | 复用 StudySetContentRepository.update；增加阅读数据仓储扩展方法 |
| mm_pdf | 本任务：独立验证入口；A：裁边几何；B：页边布局；C：位置事件 | PageViewportTransform、PdfReadingPosition、位置订阅与跳转、页边布局结果 |
| mm_assistant | D：直接模型翻译适配器、排队与取消 | ParagraphTranslator、TranslationSession |
| apps/marginmind | A–D：ReaderPane 编排、工具栏、快捷键、空间规则和撤销 | 单个阅读会话持有双栏、布局快照、同步协调器 |

不在 mm_core 引入 Flutter 或 pdfrx。mm_pdf 不依赖助手，也不直接写仓储。mm_data 延续现有原子 update，避免新增第二套存储与观察流。

## 数据契约

在 `packages/mm_core/lib/src/content/reading.dart` 集中新增模型并从 `mm_core.dart` 导出；`models.dart` 的 Document 引用 DocumentCrop；`study_set_content.dart` 持有 marginNotes、comparePairs、translationCaches 三个集合。

- `CropInsets(left, top, right, bottom)`：有限、非负 PDF point。具体页面必须留下正宽高，否则拒绝应用，不能静默改变用户输入。
- `DocumentCrop(enabled, mode, scope, all, odd?, pages)`：页码从 1 开始。all 范围用 all；oddEven 范围奇数页用 odd（缺省回退 all），偶数页用 all；page 范围使用 pages 中的覆盖值，其他页零裁边。停用时保留参数便于重新启用。Document.copyWith 支持明确清空 crop。
- `AnnotationAnchor(pages, quote)`：复用 AnnotationPage / PageRect，不复用 Annotation 的身份和生命周期。MarginNote 要求 anchor 与 lineY 恰有一个，lineY 使用原始页底部为原点的 point；跨段选择按产品规则降级为行锚点。保存时校验文档、页码、颜色范围及锚点。
- `MarginNote`：按产品定义保存时间戳与文本。空白草稿只留在内存，已有批注清空时执行可撤销删除。
- `ComparePair`：right 使用带 kind 判别字段的 PDF / AI 联合类型，避免 documentId 与 targetLang 同时存在。PDF 模式持有对齐点；AI 模式使用段落对应关系。左右不能指向同一文档。
- `TranslationCache`：以 documentId + targetLang 定位缓存，段落指纹映射译文；model 记录来源，createdAt 为缓存创建时间。只落盘完整段落，不把流式残片当成功缓存。切换模型不自动废弃已保存译文；同模型显式重译替换对应结果。当前缓存的 model 是整个缓存的来源；切换模型不废弃缓存，若主动使用新模型重译，先删除旧缓存，避免混合来源被误标。
- 所有模型提供 JSON 往返与 copyWith；可空字段必须支持“保持”和“清空”两种语义。集合防御性复制，禁止外部修改绕过仓储更新。

### 脑图关联需要明确的适配

当前 MapNode 没有独立 id，其定位键是 `(mapId, cardId)`，不能直接写入一个并不存在的节点 id。按已批准决定保留产品字段 `nodeId`，定义其值为关联 cardId，另加可选 mapId（默认主脑图）。多图中同一张卡共享内容；删除关联位置清空链接，其他图内已有卡片保留。

批注是文本的唯一编辑来源，编辑关联卡片时也通过同一批注命令更新，防止两个副本互相覆盖。加入脑图时创建兼容现有摘录体系的 Annotation / Card 或普通笔记 Card；删除批注保留当时的卡片与出处快照。删除节点只解除链接，不删除批注。删除文档时清理该文档的批注、缓存及引用它的对照对，并按现有文档删除策略处理出处；必须覆盖撤销恢复。

### 仓储与迁移

已提供仓储扩展：`setDocumentCrop`、`upsertMarginNote` / `removeMarginNote`、`upsertComparePair` / `removeComparePair`、`mergeTranslationParagraphs` / `removeTranslationCache`。每次在现有 update 回调内读取最新内容并调用编辑操作；翻译完成不能写回请求开始时的整个内容快照。

`format_migration.dart` 的 currentStudySetFormat 由 7 改为 8。迁移仅补缺失的三个空集合，不重写文档、标注、复习数据；不存在 crop 仍表示未裁边。保留未知字段和已有集合。未来版本继续拒绝写入，旧版本应用无法打开 v8，防止静默丢字段。文件仓储和浏览器仓储共用同一格式路径并分别测试。

## PDF 几何与三个验证门槛

当前 `_pagePoint` 通过整个 layout bounds 与原始页面尺寸换算坐标。因此，“缩小 layoutPages 中的矩形就完成裁边”不能直接成立：必须验证是否发生整页缩放，以及选区内部是否仍使用完整页面矩形。

统一变换：原始 PDF 点 `(x,y)`、页高 H、左/上裁边 L/T，对应裁边后局部点 `(x-L, H-y-T)`；之后应用页面布局平移、zoom 和视口矩阵。逆变换必须成对实现。高亮、画笔、命中、搜索定位和阅读位置均通过同一几何适配器；存储和导出始终使用原始 PDF 坐标。

| 验证 | 原型与通过条件 | 失败后的实现路线 |
| --- | --- | --- |
| 裁边 | `packages/mm_pdf/example/reading_probe.dart`：不对称裁边、多页不同尺寸；验证选区、既有高亮和新画笔在缩放与重排后仍重合 | 按页裁剪绘制并自主管理可见页；复用 PDFium 渲染、文本与现有标注几何，完整补齐选区命中，不能仅裁剪位图就宣称兼容 |
| 页边列 | 同一入口：页边可交互卡片位于视口 Stack；验证页末卡片跨页排布、滚动命中、输入焦点不被 PDF 抢占 | 页面绘制保持原尺寸，外层布局预留列和页末溢出高度，显式维护完整布局 extent |
| 双栏 | 同一入口：两个实际 PdfView，从任意侧滚动、快速交替操作、resize、退出重进；记录驱动来源与回调次数 | 通过统一位置事件和无动画跳转适配现有 controller，禁用同步时保持各自导航 |

验证结论：**layoutPages 缩小页面矩形不可作为裁边；采用按页裁剪绘制替代路线。页边交互可行，双 MMPdfView 同步可行。** 原型位于 `packages/mm_pdf/example/reading_probe.dart`，三项可复现测试位于 `packages/mm_pdf/test/reading_probe_test.dart`；变换、插值和异步防回环测试位于 `reading_geometry_test.dart`。选定路线与后续适配成本见 `docs/decisions/0004-reading-geometry.md`。

探针裁边页用 PdfPageView + ClipRect 和共享几何层，不依赖 pdfrx 原生 selection delegate；验证的是原始字符框命中、标注和笔迹的几何一致性。完整多页文本选择（含触控手柄）、可见页缓存和搜索命中适配由 A 完成。页边验证为视口侧栏输入，跨页卡片排布属于 B；不能将探针的可行性证据误报为完整产品验收。

页边排序使用 `(anchorY, createdAt, id)`；排序后线性下压，卡片间隔 8pt。总复杂度为排序 O(n log n) + 排布 O(n)，不能把未排序输入声称为 O(n)。仅排布可见页及相邻页，跨页溢出必须纳入布局高度，避免卡片叠在下一页上。

## PDF 对照映射

PdfReadingPosition 保存 1-based page 与原始 PDF y。内部统一转换为自上向下的标量 `s = page - 1 + (H-y)/H`，末页底部为 pageCount。该标量不受裁边或视口缩放影响。

1. 默认端点为 `(0,0)` 与 `(leftPageCount,rightPageCount)`，实际跳转钳制到目标可阅读范围。
2. 用户对齐点按左标量排序，左右必须严格递增；重复左位置替换旧点，交叉点拒绝保存，不产生非单调反向映射。
3. 在相邻点 `(aL,aR)`、`(bL,bR)` 间，`r = aR + (l-aL)*(bR-aR)/(bL-aL)`；反向交换左右即可。互换文档时同时交换锚点轴。
4. 将目标标量还原为页面与 PDF y，再由几何适配器换算目标视口位置。阅读线固定为视口高度的 25%，空白页间隙映射到最近页边界。
5. 每帧合并滚动事件。程序跳转携带来源/代号，匹配目标位置的回调不再传播；异步跳转完成或取消后释放当前代号。用户主动拖动任意侧会撤销旧驱动并取得主导权。不能只在同步函数栈内使用一个 bool 锁。
6. resize、crop 和页边切换先保存 PdfReadingPosition，再重新布局恢复；关闭/切换对照对时移除监听与过期任务。

## AI 翻译会话

复用 `AssistantServices.defaultModel` 和 `connectAssistant`，由既有凭证服务取密钥，直接调用模型客户端，工具列表为空，不通过 Agent 工具执行文档内容。复用现有网络约束、取消令牌、超时、响应大小与预算边界；会话累计预算需要单独计账，不能以每段新建预算绕过总限制。

段落描述包含原文文档内容摘要、页码/矩形、规范化文本、切分算法版本与稳定序号。指纹包含这些身份信息，避免同文档重复段落错误绑定、OCR 更新命中旧译文。目标语言属于缓存外层键。

调度采用可见段落优先、相邻段落预取、其他段落随后；初始并发 2，同一缓存键去重。滚动重排待执行任务，已开始任务不因每次滚动取消。退出、切换文档/语言或会话销毁时取消请求，并用 generation 检查阻止迟到结果写入错误会话。保留之前完整保存的段落；取消项不写成功缓存。429/5xx 沿用适配器重试策略，不双重重试。

译文占位高度按原文段落估算；长译文不可能同时保证固定高度与完整展示，采用高度变化时恢复阅读线锚点，避免阅读位置跳动。两侧 hover 与滚动均根据段落身份关联。译文摘录保留译文正文和原文段落出处；译文不提供批注编辑入口。扫描页无识别文本时禁用翻译。

## 验证与交付

- 模型：JSON、默认值、可空清除、非法参数、奇偶页与单页范围。
- 迁移：v1–v7 升级、v8 幂等、未来版本拒绝、旧数据逐字段不变。
- 仓储：文件重新打开、浏览器回归、watch 通知、并行翻译合并、删除引用与撤销。
- 几何：变换往返、多尺度/不对称裁边、页边不参与正文命中；真实渲染原型验证选区和笔迹。
- 对齐：单页、不同页数、端点、重复/交叉点、正反插值、异步回调与用户中断。
- 后续 A–D：按产品原型前 9 个场景执行 macOS 验收，严格保留 78% / 900pt / 140% 空间规则及简洁文案。

实现后运行 `flutter analyze`、`python3 tool/coverage.py --minimum 80`（全部包测试），并从 LCOV 单独核验改动代码覆盖率 ≥80%；整体覆盖率不能替代改动覆盖率。创建精简 PR，任务明确要求等待 CI 结果，收集一次前台 CI 检查，通过后 squash 合并，再交付 PR、命令与实测结果。

已实现文件关系：`reading.dart` 定义值对象；Document / StudySetContent 挂载并编解码；`reading_editor.dart` 实现纯编辑操作；`reading_repository.dart` 在现有原子 update 内复用编辑器；`editor.dart` 处理节点/文档删除与关联标题回写；`format_migration.dart` 升级 v8。PDF 端 `reading_geometry.dart` 提供变换/映射/同步器，`pdf_view.dart` 提供位置读取与跳转接口。

注意：项目已有用于学习集摘要的 ReadingPosition，新的 PDF 坐标类型命名为 PdfReadingPosition，以区分二者。原型前 9 个场景已使用 Chrome 打开检查，无页面脚本异常。测试和覆盖率的最终数值见任务交付评论。

## 批次 B：页边批注

页边纸面由 `mm_pdf` 的视口绘制层按 `MMPdfMargin.backgroundColor` 绘制，应用传入 `MMReaderStyle.marginFill`。原文和页边共用外缘阴影，页末溢出也属于同一张纸；纸面绘制裁在阅读视口内，交互卡片和引导线仍独立叠加。

`MMPdfMargin` 在原有页面矩形之外增加 200pt 列宽和卡片溢出高度；原页 / 裁边显示页的尺寸与坐标保持不变。`MMPdfMarginViewport` 仅返回可见页和相邻页，交互卡片在视口层绘制。只有这些页面测量卡片高度，访问过的页面保留溢出高度；新高度先纳入文档布局再绘制卡片。展开时跨页和缩放使用无动画跳转，避免 pdfrx 重排取消动画导致等待不结束；连续操作以最后一次为准，缩放后恢复原始阅读线。空间判断与实际适合宽度缩放使用同一分母（页面 + 200pt + 页面间距），阈值为 78%；`forceCollapsed` 供调整裁边和后续对照阅读复用。锚点、连线和行点击统一使用 `PageViewportTransform`。高度缓存只保留当前缩放，避免缩放手势累计缓存。

`ReaderMarginSession` 保存内存草稿、展开意图和标记弹层。离开输入框 / Esc / 主修饰键 + Enter 提交；空白新草稿不写仓储，清空已有批注执行可撤销删除。保存并发合并，写盘期间继续输入会补交最新文本；失败保留草稿。跨段与跨页选择降为第一行，打开编辑前确保锚点可见。卡片上滚轮继续驱动原文。

脑图通过 `WorkspaceController` 和既有 `ReadingEditor` 的原子编辑关联，`nodeId` 仍是 cardId，`mapId` 定位所属脑图。沿用现有卡片模型：笔记文本存于 `Card.title`，摘录正文存原文；关联标题编辑回写批注，删除节点解除关联，删除批注保留卡片与出处。加入操作保持布局；父主题使用当前选择，否则取同页最近摘录的主题，最后回退根节点。

原生复现入口：`apps/marginmind/example/margin_acceptance.dart`；`MARGIN_SELF_CHECK=true` 的 Dart define 启用原生保存、脑图同步、删除保留、撤销与位置检查。界面验收见 `macos-acceptance.md` 的 GUL-550 用例。
