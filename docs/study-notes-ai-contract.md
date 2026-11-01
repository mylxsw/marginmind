# 学习笔记：AI 与界面集成契约

GUL-586；依据 `study-notes.md` 第 4、6、8、12 节。领域实现不调用模型，不包含 UI。

## Schema 与模型端口

完整 JSON Schema 在 [`study-notes-ai-contract.schema.json`](study-notes-ai-contract.schema.json)。默认入口为 `$defs.write`；提纲和增量分别用 `$defs.outline`、`$defs.place`。所有对象禁止额外字段，字符串不能全为空白。Dart DTO 的 `fromJson` 执行相同结构校验，失败抛 `FormatException`。

`NoteOrganizer` 的三个异步方法：

- `outline(NoteMaterials, NoteSettings) → NoteOutline`：提出分节，每节 `title / refs / why?`。
- `write(NoteMaterials, NoteOutline, NoteSettings) → NoteDraft`：写结构化内容。即使用户调整提纲，也使用原来的同一份素材字典。
- `place(NoteMaterials, StudyNote) → NotePlacements`：为新素材提出插入位置，不修改笔记。`materials.items` 是新素材；`catalog` 是该次收集的完整素材，仅供定位旧摘录位置。

输入素材使用 `NoteMaterial.toJson()`：`id` 为本次整理内的短 ID（划线 `h1…`，其他素材 `n1…`），`text` 为原文或已有笔记，附分组、来源种类、来源声音和上下文。短 ID 不持久化，不能在重新收集后套用旧响应。批处理必须共享整次整理的字典，不能每批重新编号。后续 AI 实现负责预算、模型请求、分批、取消和流式进度。

write 示例：

```json
{"sections":[{"title":"主动回想","why":"都在讨论检索练习","blocks":[{"type":"summary","text":"检索练习帮助巩固记忆。"},{"type":"quote","ref":"h1"},{"type":"gloss","ref":"h1","text":"这里指前文的实验。"},{"type":"own","ref":"n1"},{"type":"points","items":["间隔复习"]},{"type":"action","text":"明天复习本章"}],"question":"检索为什么有效？"}]}
```

- `quote` 和 `own` **只有 type / ref**，不接受模型返回的引文或用户批注文字。应用只按 ID 读取真实来源。
- `gloss` 使用 `ref / text`，只能引用划线；`summary / paragraph / action` 使用 `text`；`points` 使用非空 `items`。
- `xref` 使用 `to / text`，`to` 为本次 write 响应内从零开始的节序号。组装后转成稳定 section ID，空节及无效目标的链接移除。
- 未知或类型不匹配的素材 ID 被丢弃并记录在 `NoteAssembly.rejectedRefs`。重复划线只保留首次引用，关联批注也只出现一次。未引用划线在 `unusedAnnotationIds` 返回。
- `NoteOrganizationRunner.run` 遇到结构错误重试整个 outline/write 一次，再按原文顺序回退；保留明确选择的脑图组织方式。返回 `usedFallback` 供界面提示。网络错误、预算错误和取消向上传播，不吞掉，便于应用保留已经收到的部分结果。
- `depth=none` 不调用传入的 AI organizer，直接执行本地整理。

place 示例：

```json
{"placements":[{"ref":"h8","sectionId":"section-id","beforeBlockId":"block-id","title":"主动回想","why":"位于现有摘录之前"}]}
```

`sectionId=null` 创建新节，可用 `newSectionKey` 区分同名章节（缺省按标题合组）；已有节可用 `beforeBlockId` 或 `afterBlockId` 指定位置，两者不能同时指定。不指定位置时追加。重复和未知素材 ID 不插入；失效的节或块目标拒绝应用。预览阶段不提交，`NoteUpdater.apply` 对比整份笔记快照，发现并发编辑时抛 `StateError`，调用方需重新预览。`organizedAt` 使用素材收集时间，不使用模型返回时间，避免遗漏生成期间新建的素材。未被放置的新划线保留在未用上列表。

## 公共 API（从 mm_core.dart 导出）

| API | 后续任务用途 |
| --- | --- |
| `StudyNote / NoteSection / StudyNoteBlock` | 笔记、节和稳定块 ID；新基类避免与现有格式化 `NoteBlock` 重名 |
| `QuoteBlock / OwnBlock / TextBlock / PointsBlock / XrefBlock` | 渲染和编辑五种块，复用 `NoteOrigin`；用户修改生成内容为 mixed + edited |
| `NoteScope` 五个子类、`NoteSettings / NoteTemplate` | 范围设置和版式持久化，版式不修改内容 |
| `StudySetContent.studyNotes / noteSourceArchive` | 可选顶层字段，旧文件为空，文件格式版本不变 |
| `NoteTextSource / NoteMaterialCollector / NoteMaterials / NoteContext` | 输入已经取得的章节或 PDF/OCR 文本，纯函数收集与上下文；noText 与 unresolved 分开 |
| `NoteOrganizer / NoteOutline / NoteDraft / NotePlacements` | AI 实现端口；JSON 与实体边界 |
| `LocalNoteOrganizer / NoteAssembler / NoteOrganizationRunner` | 本地整理、ID 核对和结构失败回退 |
| `NoteUpdater / NoteUpdatePreview` | 新素材检测、预览、应用以及保护 edited 块的重新整理合并 |
| `StudyNoteEditing.saveStudyNote / deleteStudyNote / editStudyNoteBlock` | StudySetEditor 扩展，返回一次不可变内容更新，OwnBlock 修改同步到原笔记 |
| `resolveNoteSource / ResolvedNoteSource / NoteSourceStatus` | 实时原文优先；删除后读取归档，明确是否可跳转 |
| `NoteExporter / NoteExportOptions / NoteExportResult` | Markdown、Obsidian；三种出处、所有开关、附件复制清单 |

`WorkspaceController` 提供 `saveStudyNote / deleteStudyNote / editStudyNoteBlock`，调用现有 `_update`，持久化和全局撤销复用原栈。mm_data 的 FileLibraryStore 通过 StudySetContent JSON 直接往返，无独立笔记文件。

## 来源与边界

原文永不保存在 QuoteBlock 中。删除划线（包括删除文档、删除图片卡片所带的区域）前，只归档仍被笔记引用的 Annotation 与文档标题，与删除同一次提交。最后一个引用消失时同步清理；撤销恢复完整快照。

上下文按 UTF-16 锚点匹配章节正文；文本不匹配则 `unresolved`，没有文本则 `noText`。PDF 重复文字无法唯一定位、跨页引文与逐页文本拼接结果无法精确匹配、以及没有字符位置的章节起始页，保守地不提供上下文，不猜测章节边界。应用可以提供更准确的已解析文本后重新收集。残句由本地规则判断，原文不改写。

导出是纯函数：`NoteExportResult.attachments` 返回目标相对路径 → 学习集资源路径，调用方实际复制图片到附件目录。YAML 使用 JSON 标量/数组语法安全转义；出处页码链接为 `[[书名#p12]]`。默认中文导出标题属于导出文件内容，不新增界面文案。PDF、Word、富文本和 UI 不在本任务范围。

## Heavy Runtime（GUL-653）

生产入口 `noteSessionFactoryProvider` → `createModelNoteOrganizer` →
`RuntimeNoteOrganizer` / `PersistentNoteStages` → `PersistentTaskAssembly`。
组织、提纲、分节生成、增量安置、解释、改写和复习问题全部使用 `study_notes`，
不再读取旧目录的默认模型，不在失败后自动切换到旧模型或本地 AI 替代实现。
用户明确选择“只排版”仍使用 `LocalNoteOrganizer`。

领域导出 `studyNotesSpec`、`studyNotesKnowledge`（`notes.organize@2`）、
`registerStudyNotesTask`。公共设置的 12 项 specs 聚合由父任务完成；
本领域预检已经使用真实 spec（tools + historyReplay），未知能力在发送前拒绝。
应用领域工厂提供知识版本与注册，不覆盖公共 provider 或兄弟任务工厂。
历史 `ModelNoteOrganizer` 仅保留原有离线回归/独立诊断工具兼容，生产会话不构造它。

- 每个用户会话冻结模型、思考策略、单次输出上限和知识版本。内部阶段继承父快照，
  不随设置编辑更换模型。每次实际分发仍重新检查服务与凭据。
- 没有任意整任务字符数、token 总额或会话总时长配额。单次输出上限为 8192，
  与服务能力上限取小值；每个请求受 Runtime 的容量/传输/超时边界约束。
  输入以完整 JSON 编码大小和冻结模型容量进行保守分块，包含上下文、schema、工具和修复预留。
  少量超长材料也拆分，保留同一材料 ID 和片段偏移；不再以 200 条划线作为容量判断。
  超长改写和解释也逐片段完成。无法容纳的单条元数据或复习问题明确拒绝，不截断原文。
- 提纲保留各容量批次的主题组，在可编辑提纲中汇集，不把所有原文重新塞进一个合并请求。
  分节内部也可拆分；只发布完整章节。引文/手写材料始终用 ID 返回，重复片段引用在领域装配前去重。
- 校验材料 ID、材料类型、唯一覆盖、请求章节标题、全局跨节索引和真实插入锚点。
  结构错误由 Runtime 有限修复；覆盖遗漏以 partial 持久化，只对缺失 ID 发起一次修复阶段。
  已验证内容不再次消费。修复仍缺失或非法时保留阶段存档并报错，不能伪装成功。
  用户在提纲中有意未分配的材料保留在未用清单，并使会话摘要为 partial。
- 每个阶段有持久化指纹与结果。恢复已完成阶段直接加载结果；中断阶段须由用户“继续”明确恢复。
  取消/失败的再次尝试使用新阶段 ID，旧记录不变。保存失败保留待保存的验证结果；
  下一次继续先保存，不能重新请求模型。笔记写入失败后的改写重试也复用原会话阶段。
- 每个完整章节通过既有 `acceptNoteDraft` / `NoteAssembler` 保存，续写状态（材料字典、提纲、
  已验证章节、冻结会话 ID）按版本持久化，重启后可继续。保存前核对现有来源仍存在且文字相同。
  原始摘录、用户手写块、revision、人工确认、撤销与增量预览继续使用原领域层。
  模型/提示版本更新不会自动删除已有成果；不兼容的续写版本拒绝恢复并保留原存档。
- 固定规则与 JSON schema 处于系统层；原文和用户笔记只进入用户/工具数据。
  `read_selection` 只能读取当前阶段的授权材料，不能扩大范围或执行写入。

本地验证仅覆盖命名回归、定向分析和格式检查。SDK/HTTP fixture 不是实际模型质量证明；
未使用真实服务凭据，未知生产组合仍然 unknown。实体 macOS/iOS 操作和语义质量留待真实环境验收。
