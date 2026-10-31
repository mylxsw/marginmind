# 文档生成脑图：核心契约与应用接入

GUL-622；依据已确认的 `mindmap-from-document.md`。本文固定后续模型、应用层和界面任务的边界；下列 mm_core API 已实现，Riverpod 控制器、模型适配器与磁盘缓存由后续任务实现。

## 1. 文件归属与依赖

| 层 | 文件 | 职责 |
| --- | --- | --- |
| mm_core | `lib/src/content/map_generation.dart` | MapGeneration / MapSource / CardSource、哈希、保护与更新判断、缓存键 |
| mm_core | `lib/src/content/models.dart` | 可选 MindMap.generation、Card.source，JSON 往返 |
| mm_core | `lib/src/assistant/map_generation.dart` | MapLine、MapLineContext、解析、提议转换、MapGenerator 端口和输入类型 |
| mm_core | `lib/src/assistant/proposals.dart`、`writes.dart` | 来源能力、摘录复用、受保护节点校验、单事务写入 |
| mm_core | `lib/src/testing/map_generator.dart` | 可配置 FakeMapGenerator；从 `package:mm_core/testing.dart` 导入 |
| mm_assistant | `lib/src/map_generation.dart`（后续） | ModelMapGenerator，直连 AssistantConnection，三类提示和流解析 |
| 应用 | `features/assistant/map_generation_context.dart`（后续） | DocumentDigestBuilder：读取、按章节/页切段、预算、别名、指纹 |
| 应用 | `features/assistant/map_generation_cache.dart`（后续） | MapDigestCache：学习集包内读写/清理缓存 |
| 应用 | `features/assistant/map_generation_controller.dart`（后续） | 状态机、并发、重试、预览与一次提交 |

以上应用路径均位于 `apps/marginmind/lib/`。依赖方向为应用 → mm_assistant → mm_core；mm_core 不依赖 Flutter、Riverpod、文件系统或模型服务。文档读取沿用 WorkspaceReader/OCR；写入沿用 WorkspaceMapEditExecutor → workspace.applyAssistantChange → AssistantWrites.apply，不新增存储事务链路。

## 2. 持久化、保护和依据指纹

`MindMap.generation: MapGeneration?`、`Card.source: CardSource?` 缺失时为 null，null 不输出 JSON；copyWith 保留原值，显式传 null 清除。旧文件无需迁移。出处页码从 1 开始。

MapGeneration 字段：sources（非空、documentId 唯一）、organization（chapter/topic/question）、depth（2..4）、instructions（≤500 Unicode 字符，可空）、generatedAt（UTC ISO-8601）、generated（cardId → 版本化哈希）。MapSource 包含 documentId、chapters（目录条目 ID；无目录时为 `page-N` 页码集合；空为全文）、fingerprint、readThrough（≥1）。CardSource 仅有 documentId 和 page。

**generated 不仅哈希标题。** `generatedNodeHash(card, node)` 为 `v1:` + SHA-256(canonical JSON `[title, parentId, order]`)；parentId=null 表示根，order 是现有双精度同级顺序。必须同时保存位置才能检测换父和同级拖动；折叠、宽度不算用户结构修改。`isMapNodeProtected(content, mapId, cardId)` 在卡片/放置缺失、非 topic、没有基线或哈希不同时返回 true。手动新增天然没有基线。未知版本的旧基线保守视为不匹配。判断以当前快照对比生成基线；撤销恢复原快照后恢复原保护状态，不维护独立编辑历史。

写入只为这次实际新增/改名/移动的 AI 主题计算新基线，绝不把全图重新标成 AI 内容；保留原来未参与的基线，因此用户内容不会因更新而解除保护。摘录、笔记、图片始终保护。AI 改名另行拒绝跨图共享主题，以免在另一张图造成隐式改写；跨图共享摘录仍可挂入。

`mapContentHash` 使用 UTF-8、SHA-256、小写十六进制；JSON 对象键递归排序，数组顺序保留。应用构造 `mapSourceFingerprint(pageCount, textHash, annotations, notes)`：

- textHash：页码升序排列的 `[page, pageText]` 数组的 mapContentHash，使用当前文字层/OCR 后文本；不可只用文件名或 mtime。
- annotations：以标注 ID 为键的对象，值含 quote、pages/textAnchors、kind；排除颜色、createdAt 等展示信息。
- notes：以批注/附着笔记 ID 为键，值含文字正文及锚点；覆盖该文档上的用户批注，删除也会改变集合。
- pageCount 是当前文档总页数。readThrough 独立取阅读进度，不把 lastReadAt 算入内容指纹。

`mapSourcesChanged(generation, currentSources)` 检查文档集合、指纹、readThrough 和章节选择；章节集合顺序不影响结果。文档被删也算变化。应用据此显示紫点；只改要求仍允许更新，不依赖紫点。生成时冻结来源快照，应用后保存的是本次实际使用的来源，不能用提交时最新指纹冒充已经处理的新内容。

## 3. 生成器端口与输入

```dart
abstract interface class MapGenerator {
  Stream<MapLine> readChapter(MapChapterInput input, CancellationToken cancel);
  Stream<MapLine> generate(MapBuildInput input, CancellationToken cancel);
  Stream<MapLine> update(MapBuildInput input, CancellationToken cancel);
  Future<void> close();
}
```

每个流输出**已经过 parseMapLine 校验**的行，按到达顺序 yield。控制器先对章节调用 readChapter，最多并发 3 个；收集可用要点后调用 generate 或 update。并发、缓存与单章重试归控制器，适配器不隐藏多章调度。

- `MapChapterInput(chapterId, documentAlias, context, textByPage, annotations, organization, instructions)`：一章/分段的实际文字；annotations 为标注别名 → 已裁剪的原文和批注。chapterId 在本学习集的本次计划内唯一（文档 ID + 章节 ID + 分段序号），仅用于本地调度。
- `MapBuildInput(title, generation, context, points, existingTitles, existingParents, onlyNewContent, titleConstraints)`：第二段仅发送要点；existingTitles/Parents 的键为 N1…，父为 N…/ROOT。generation 携带组织方式、层数、要求，不能直接序列化给模型。
- `MapLineContext(phase, mapId, draftPrefix, documents, pages, nodes, annotations, protectedNodeIds, existingTitles, maxDepth, rootParentId)`：本地解析状态。documents=D1…→真实文档 ID；nodes=N1…→卡片 ID；annotations=A1…→标注 ID；pages=文档别名→本次输入实际携带的页集合；protectedNodeIds 是真实卡片 ID 集合。其余别名表仅留本地。生成到已有分支时 rootParentId=该分支真实 ID，模型仍使用 ROOT；缺省 ROOT 映射 mapId。事务再次校验分支属于目标图。
- GUL-627 补充：`onlyNewContent` 默认 true，将更新范围作为明确的模型输入；`titleConstraints` 是审阅中改过的标题列表，换一批时传入，不发送草稿 ID，也不改写保存的用户要求。更新使用已有节点别名及保护集合，所有选中差异仍通过 `diffToProposal` 一次提交。
- `draftPrefix` 对会话、代次、章节/重试调用唯一；每次请求创建全新 context，不复用已经消耗 ref 的实例。existingTitles 包含全图、已保留草稿和前轮排除标题；控制器跨并发章节合并时再去重。

适配器只显式提取模型需要的文本与别名；不序列化 MapGeneration、MapLine 或 context。第二段将 point.source.documentId 与 point.marks 反查为 D…/A…，为要点重新分配 p1…及父引用，不发送真实 ID。第二段 pages 白名单来自成功要点所依据的实际输入页，按文档分别保留，不能把多文档页码做无归属并集。

复用 CancellationToken、ResearchFailure。取消必须绑定网络请求与静默流等待；close 中止正在进行的请求、关闭连接。取消后不再 yield；已 yield 的有效结果仍由控制器保留。单章超时/协议错误只结束该章流，其他章继续；重试只新建失败章节的输入/context，成功缓存不失效。部分失败可以成图；失败章节的部分要点可显示，但完成前不写成功缓存。全部无有效结果报 protocol/noValidMapContent，不留空预览。

传输沿用扩展的 LF/CRLF、跨 chunk、最后一行无换行规则；单行超过 64 Ki 字符丢弃至下一换行。只记录固定错误码，不记录原文。默认章节 90 秒/2048 输出 tokens，合成与更新 120 秒/4096；响应 2 MiB，每次输入遵循模型窗口预算。取消、timeout、network、authentication、rateLimited、budget、protocol、refusal 使用既有错误分类。UI 不显示 token 数。

FakeMapGenerator 可配置 chapters（chapterId→原始行列表）、generation、diff、chapterFailures、generationFailure、diffFailure、逐行 delay；共享真实解析器，记录 calls，失败可在已输出有效行后抛出。修改失败表后以新 context 重试，可用于界面独立开发。close 后调用报 StateError。

## 4. NDJSON、选择与提议

三种 phase 不能混用。单文档 doc 可省略；多文档没有 doc 或不认识 doc 时去掉出处，不丢主题。

```json
{"k":"point","id":"p1","title":"编码","doc":"D1","page":2,"marks":["A1"]}
{"k":"point","id":"p2","parent":"p1","title":"加工水平","page":3}
```

章节行允许 k/id/parent/title/doc/page/marks。parent 缺省 ROOT；引用必须先出现，marks 必须属于本地标注白名单。标题使用 expansionTitle 截短、normalizeExpansionTitle 跨分支去重。

```json
{"ref":"a","parent":"ROOT","title":"编码","doc":"D1","page":2}
{"ref":"b","parent":"a","title":"加工水平","doc":"D1","page":3}
{"mark":"A1","parent":"b"}
```

成图只允许新增主题和引用已有标注。ref 是 1..64 个 ASCII 字符，首字母，后续字母/数字/下划线/短横线；ROOT 与 D/N/A数字保留。parent 只能 ROOT 或更早的主题 ref；maxDepth 表示根下面最多新增几层。主题重复、ref 重复、未知字段、类型错误、前向引用、超深行跳过；无效行不占 ref。mark 同一轮只能挂入一次，不改原文。

```json
{"op":"add","ref":"x","parent":"N2","title":"新主题","doc":"D1","page":4}
{"op":"excerpt","mark":"A1","parent":"x"}
{"op":"rename","node":"N3","title":"新名称"}
{"op":"move","node":"N4","parent":"x"}
{"op":"remove","node":"N5","why":"与编码主题重复"}
```

差异 parent 还允许已有 N… 别名。remove 必须带非空 why，默认 kept=false；其他类型默认 true。rename/move/remove 对受保护节点直接返回 null；允许在受保护节点下新增。页码是整数且在该文档本次上下文内时才形成 CardSource，否则保留节点、source=null。完整环/图归属检查在事务里进行，不能只信模型提示。

MapLine 是统一行结果（point/add/excerpt/rename/move/remove）；id 是宿主生成，parentId 已转为 mapId、真实节点 ID 或 `new:<草稿id>`，nodeId 已解析，source/annotationId/marks 使用真实 ID。`copyWith(kept, title)` 供审阅；`toExpansionDraft()` 仅用于 add 主题，复用既有布局与选择组件；出处、摘录和差异信息以 MapLine 旁表保存。

`generationToProposal` 接受 additions；`diffToProposal` 接受 additions 和更改。两者均为命名参数：proposalId/studySetId/mapId/baseRevision/generation/lines，以及可选 createMap。转换拓扑排序、级联剔除未选父项的后代，拒绝重复 ID、环、缺失父项和空选择。只包含选中的操作；UI 应调用一次 `executor.apply(proposal, proposal.operations.map((o) => o.id).toSet())`。

新图：先分配 mapId，但不落盘；createMap=MindMap(id,title)，baseRevision=assistantMapRevision(before,newMapId)。AssistantWrites 在同一返回快照里创建地图、节点、出处、generation 和 receipt；放弃不创建图。已有图：不传 createMap，提交时核对旧 revision。

`MapEditProposal.document` 是宿主内存能力，放开 50 条限制；JSON 不保存能力，也不恢复 generation/createMap。MapEditOperation.fromJson 默认拒绝 addExcerpt/remove/source；仅写入器对文档来源开启 documentGeneration。普通 propose_map_edits 工具 schema 明确只列原五种操作；不可把新增 enum 自动暴露给对话。扩展来源仍只能 addTopic/move。

写入重复校验版本、依赖、节点归属、保护状态和来源文档存在性。addExcerpt 调用现有 attachCard：已有卡片则同卡跨图放置；本图已有则跳过，不移动用户摘录；不存在则创建摘录卡。remove 只删除本图放置，保留其他图使用的卡片；先执行非删除，再按原树深度从深到浅删除。**删除父项不隐式删除后代**：每个后代必须有明确选中的 remove 且成功移除，否则父项跳过；任何受保护/未选子项都会阻止祖先删除。跳过原因写入 receipt.skipped；全部跳过则不提交空更新、不推进依据指纹。

完整前后快照走 StudySetEditor.restore，generation 随同节点一起撤销/重做；receipt 保持既有持久幂等语义。提交期间禁用重复按钮；成功 kept/applied，失败仍可审阅，不能伪报成功。

## 5. Riverpod 与预览状态机（后续应用任务）

`map_generation_controller.dart` 声明：

```dart
final mapGeneratorProvider = Provider<Future<MapGenerator> Function()>(...);
final mapGenerationControllerProvider =
    NotifierProvider.autoDispose.family<MapGenerationController, MapGenerationPreview?, String>(...);
```

family key=studySetId。应用负责创建 provider；模型任务只实现 ModelMapGenerator，不新增 Riverpod 依赖。mapGeneratorProvider 返回工厂：读取既有模型设置/密钥，每次生成会话创建独立连接；测试 override 为返回 FakeMapGenerator。不要用同名 provider 同时提供实例与工厂。MapDigestCache 在 `map_generation_cache.dart` 由 `mapDigestCacheProvider = Provider.family<MapDigestCache,String>` 提供；关闭学习集释放控制器与请求，保留磁盘成功缓存。

应用定义 `MapGenerationRequest`（位于 controller 文件）：studySetId、mapId、title（均 String）；sources 为 `List<MapDocumentSelection>`（documentId、chapters: List<String>，空表示全文）；organization: MapOrganization；depth: int；instructions: String?；includeAnnotations: bool=true；extractQuotes: bool=false；destination: newMap/branch/update；parentId: String?（branch 必填，本图内真实卡片 ID）；onlyNewContent: bool=true。新图的 mapId 由宿主提前分配。控制器在启动时读取 snapshot，构建带指纹的 MapGeneration，不能让 UI 自行构造哈希。extractQuotes 开启时，章节 point 可附 quote；本地逐字匹配本次输入的页面文字，不匹配只丢弃 quote。PDF 再用文字层字符坐标定位；重排文档用 canonical chapter 的 TextAnchor 定位。quoteSource 只记录本地定位单元，不作为重排文档的 PDF 页码出处。

MapGenerationPreview 字段约定：request（宿主设置/目标）、phase、generation（来源冻结快照）、lines、chapterProgress（chapterId→pending/reading/done/failed）、chapterFailures、baseRevision、proposalId、round、isApplying、failure。phase 枚举 reading/streaming/review/kept/discarded/failed/stopped/update/diff/applied；null 表示没有会话。选择用 MapLine.kept，remove 初始 false；edited 草稿约束由控制器另存 title overrides，换批时携带。

| 事件 | 状态转移/效果 |
| --- | --- |
| start(request) | null → reading；构建章节计划、查缓存、缺失章并发读取 |
| 章节完成/部分失败 | 更新进度；其余章节继续；完成后有可用要点 → streaming |
| 成图有效行 | streaming；虚拟节点逐行加入预览 |
| 成图结束 | 有有效内容 → review；无内容 → failed 并移除空树 |
| startUpdate(request) | update（包含缺失章节读取）；调用 update 流；完成 → diff |
| stop() | 取消当前代；有节点/要点 → stopped；已读要点保留，可继续成图；无内容则取消并清空 |
| retryChapter(id) | 只重试该章；成功后重建合成输入、生成新一批，保留用户改字约束 |
| toggle/edit | review/diff/stopped；复用 selectExpansionDraft 的祖先恢复/后代取消；差异更改独立选择 |
| regenerate(settings) | round+1，取消旧代；复用未失效要点、重新合成；编辑过标题作为约束 |
| keep()/apply() | review/stopped→kept，diff/stopped→applied；提交时 isApplying，出错回原状态 |
| discard()/dispose | 取消流、忽略迟到回调、清内存草稿；discarded，不写学习集 |

只有要点而没有成图节点的 stopped 状态不允许 keep；用户继续成图时从缓存/保留要点开始。UI 对生成器错误展示“重试”，不会把章节要点当作可直接落盘的节点。

复用 ExpansionPreview 的虚拟树与交互：生成新增主题用 ExpansionDraft 适配给既有画布；不要伪造持久卡片。章节骨架、excerpt、rename/move/remove 标记通过旁表和预览覆盖层补充。既有 ExpansionPreview 的 request 强依赖 ExpansionRequest，不能把文档请求强转进去；应用任务可抽取共享预览投影/选择组件，保留原扩展 provider/API 行为。差异列表和画布共享 MapLine.id 作为选择与定位 key。

沿用 expansionBusyProvider 与助手 busy 租约，一学习集一次任务；本机模型排队由连接/模型调度器负责。学习集打开期间保持 family provider 存活，切换文档/地图不销毁；关闭学习集才 dispose。各代使用 token+递增 generation ID，stop/discard/retry 后忽略迟到事件。生成和审阅期间锁目标图的编辑，允许阅读、平移与切图；应用任务需将文档预览纳入现有 workspace 编辑锁，提交时给 WorkspaceMapEditExecutor 的特权路径加上 isDocumentGeneration（沿用 expansion 提交豁免机制），不能永久放宽普通对话写入。

## 6. 学习集缓存

目录固定为 `<study-set-package>/ai-cache/map-digests/v1/<cacheKey>.json`，不得保存到全局目录。MapDigestCache 接口：`read(key) → Future<List<String>?>`、`write(key, rawPointLines) → Future<void>`、`clear() → Future<void>`、`sizeBytes() → Future<int>`。返回规范化 point NDJSON 字符串列表；写入只接受完成并校验成功的章节，原子临时文件替换；缓存损坏/版本不符视为 miss。读回以新 context 重新解析并映射标注，不复用旧 draft ID。

`mapDigestCacheKey(source, chapterId, chapterFingerprint, model, organization, instructions, schemaVersion=1)` 返回 64 字符 SHA-256：source 只取 documentId；chapterFingerprint 是本章实际输入的页码/文字/标注/批注（含影响读取范围的进度）canonical hash；model 必须包含服务配置 ID、模型名及可获得的模型版本，不含密钥。另含章节/分段标识、组织方式、要求和提示/缓存 schema 版本。章节输入不同即 miss；其他章节变化不使本章失效。depth 不影响第一段，改详细程度仅重做第二段。预算切段范围/文本裁剪变化也必须改变 chapterFingerprint。

缓存文件 envelope：`{schema:1,key,documentAlias,annotationAliases,lines}`；别名表只存本地来源 ID，读回检查对应来源仍存在；不保存 API key、完整原文、请求日志或失败片段。清除设置只删 map-digests 子目录；删除文档时相关缓存可惰性失效，学习集删除随包删除。清理与写入使用应用层同一串行队列/缓存 epoch，避免清空后旧调用重新落盘。清缓存不改 generation 指纹或已保留脑图。

## 7. 验证与后续范围

核心测试覆盖 JSON/旧文件、不可变集合、规范哈希、更新判定、三类 NDJSON 与异常行、越界页码/多文档、保护/依赖/权限、80 个节点一次提交、同卡跨图、删除不误伤、元数据撤销/重做、单章失败重试、取消和关闭。回归包含 mm_core 全套、mm_assistant proposals/expansion、应用 expansion/multiple_maps、mm_data assistant_transaction。

本任务不实现模型提示词/传输、章节切分/OCR 自动继续、磁盘缓存、Riverpod 控制器和 UI。GUL-628 扩展：章节 point 的可选 quote 必须在宿主传入的 quoteTextByPage 中逐字存在。宿主重新定位后，将虚线下划线标注暂存在内存，通过 A… 别名供第二阶段引用；审阅中的摘录与主题使用同一选择链路。MapEditProposal.document 的 excerptAnnotations 是不可从 JSON 恢复的宿主能力；仅在被选中的 addExcerpt 执行时创建对应标注，与脑图和 generation 同事务提交、一起撤销。放弃或取消不写标注。模型仍不能直接创建任意原文或标注。扫描版使用 ReaderOcr/PdfOcrService；控制器监听成功完成后重新读取识别副本并继续，失败/取消不自动重试。设置汇总各学习集缓存的实际字节数，清理只删除 map-digests 子树。
