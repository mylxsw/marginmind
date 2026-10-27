# 助手底座契约（GUL-528）

本阶段不接 UI、不替换研究入口。`mm_core` 定义端口；纯 Dart `mm_assistant` 负责框架、工具、Hooks、不可变视图模型与假实现；`mm_data` 负责对话文件；应用层负责 Riverpod、设置和钥匙串组合。依赖固定为 `dart_agent_core 2.1.8`。

## UI 接入

GUL-530 起由 `AssistantScope`（`features/assistant/widgets/assistant_panel.dart`）在学习集窗口外层建立 ProviderScope，override `assistantDependenciesProvider` 与 `assistantControllerProvider`；窗口存在期间对话一直存活，关闭面板或切换文档不中断生成（切换对话仍按控制器契约先停止旧运行）。依赖由 `assistantDependenciesForProvider(studySetId)` 组合：对话存储 `assistantArchiveProvider`（文件仓库用 `ConversationStorage`，内存仓库用 `MemoryConversationArchive`）、GUL-531 的 executor / NoteSaver、`assistantNetworkProvider`（默认 null，GUL-532 提供）；revision 与 parents 取自同一个 content 快照（`assistantMapRevision`、`mapParents`，根节点为 mapId）。读取端口为 `WorkspaceReader`：选区原文来自本轮问题的 ContextItem（`displayText` 即原句），重启后也能重读；上下文与读取里的脑图根节点 ID 为 `__root__`，与画布一致。对话列表首次加载前执行一次 `LegacyConversationMigration`；只读对话不显示输入区，回答只保留复制。

窗口外的入口（菜单栏、选区工具条、节点菜单、卡片详情）只调用 `askAssistant` / `askAboutPassage` / `askAboutNode`：写入 `assistantUiProvider`（附带的上下文、待发送问题、聚焦请求、来源抽屉），由窗口内的宿主发送。对 GUL-528 契约的向后兼容扩展：`AssistantController.rename`、`ConversationStorage.list`、`AssistantSettingsController.saved/select/models`。

| 模型 | 字段与含义 |
| --- | --- |
| Conversation | id、studySetId、title、model、messages、online；`running` 派生 |
| Message | id、requestId、role(user/agent)、text、contexts、traces、citations、proposals、status、errorKind、skill、noteId、online |
| ContextItem | id、kind(selection/node/branch/page/document/map)、documentId/page/mapId/nodeId、displayText、auto |
| TraceStep | id(toolCallId)、toolName、status(running/done/error)，不含原始参数和异常 |
| Citation | marker、documentId/page 或 sourceId/version/paragraphId/url、实际读取的 quote |
| ProposalView | proposal、status(pending/applied/dismissed)、selected(opId 集合)、receipt |
| MessageStatus | running / done / stopped / error（配合 ResearchFailureKind）/ interrupted |

所有视图集合不可变。SDK AgentState 不暴露给 UI。`Message.online` 表示本轮有成功的联网步骤；`Conversation.online` 表示允许联网，两者不能混用。显示引用时只解析正文中存在的合法 marker，引用定位来自 Citation，不从模型正文猜测 URL。

控制器公开异步动作：

```dart
send(text, contexts: contexts, skill: 'explain');
stop(); retry(messageId); newConversation(); openConversation(id);
switchModel(model); setOnline(enabled);
selectOperation(proposalId, opId, selected);
applyProposal(proposalId); dismissProposal(proposalId); reopenProposal(proposalId);
saveNote(messageId, SaveNoteRequest(title: title, mapId: mapId, parentId: parentId, anchor: anchor));
```

并发 send 拒绝；重试创建新 requestId，保留旧消息和原问题的上下文。切换对话/模型和联网状态先停止旧运行。发送前先持久化问题和 running 占位；失败不请求模型。流式事件先经 Hook 净化再落状态，fullModelMessage 替换当前模型段落，不重复追加，也不提前结束整轮。functionCallRequest 是 **List<FunctionCall>**；functionCallResult 是 **FunctionExecutionResultMessage**（包含整批结果）。停止/错误保留部分正文；迟到工厂结果会关闭，不污染下一对话。dispose 取消运行；磁盘中尚为 running 的记录在下次打开时恢复成 interrupted，不自动重发。

## 读取、联网与 Skills

`scopeFromContexts` 只从显式可见上下文派生 ReadScope；auto 不增加权限。选区授权 selectionId；页授权指定 documentId/page；整本授权有界读取和检索；节点/分支授权相应节点；整图授权该图。Reader 接口每次带 ReadScope 和 CancellationToken，不能接受路径。

常驻读工具为 read_selection、read_pages、search_study_set、read_branch。单次分支最多 200 个节点、检索最多 20 项；页读取受整轮 5 页预算。`search_study_set` 只返回有界定位，不登记页面证据。读取成功返回的正文才登记引用。

8 个内存 Skill 的名字：explain、translate、verify、summarize、quiz、organize、papers、videos。`skill` 可显式激活，或由模型通过 activate_skills 激活。解释/翻译/总结只有读工具；出题/整理增加提议；查证/论文/视频增加联网工具。动态激活不能绕过联网开关、Policy 或 ReadScope。没有文件系统 Skill、脚本、MCP、规划、子 Agent 或隐式模型诊断。

`AssistantNetwork` 的三个方法：search(keywords)、papers(keywords)、fetch(url)，均带取消令牌。GUL-532 实现真实后端：

- Claude/Responses 复用现有 mm_research 供应商内置搜索，仅转换为标题、URL、摘要；丢弃其结论与引用。
- compatible/Ollama 使用设置中的 SearXNG endpoint；未配置时明确 unavailable。
- fetch 必须再次使用独立网页 UrlPolicy、安全传输、快照持久化和段落编号，成功提交后才返回 kind=snapshot 的 AssistantSource。OpenAlex 返回 kind=openAlex 的元数据，不假称全文。
- 内存实现只供测试；没有真实后端时返回 unavailable，不声称已经联网。真实联网接入是 GUL-532 的范围，不是本阶段已完成能力。

`[page:N]` 为本轮唯一主文档的 1-based 页码；其他文档通过 `[source:N]` 登记本地引用。外部 source 只接受已提交快照或 OpenAlex。每轮新建登记表；流式尾部未闭合括号被缓冲，完整后校验，伪造编号和悬空引用丢弃。引用与本轮读取登记表一同持久化；后者位于 metadata 的 `assistant.reads[requestId]`，中断恢复也能追溯已读取的内容。

## 写操作与后续实现

`propose_map_edits({ops:[...]})` 是唯一模型写工具。op.kind 为 addTopic / addNote / addReviewCard / move / rename，各自字段见 mm_core 的 MapEditOperation。proposal 的 studySetId/mapId/baseRevision 来自宿主，不相信模型传值；id 由 requestId + toolCallId 生成。

新增节点临时 ID 为 `new:<opId>`，只能引用之前的新增操作。取消父操作勾选会递归取消依赖操作，勾选依赖会带上父操作。Policy → Proposal → Citation 顺序固定；合法提议存入 metadata 后 defer，afterToolCall stop 阻止模型继续请求。同批其他读工具仍受预算约束，不执行写入。

GUL-531 实现 `MapEditExecutor.apply(proposal, selectedIds)`：事务内重验学习集/脑图归属、节点存在性、循环、依赖、baseRevision；整组仅一个撤销记录；同事务提交以 proposalId 为键的 MapEditReceipt（含 operationIds、nodeIds、revision、undoHandle）。`receipt(proposalId)` 查询必须持久可靠。receipt 优先于重执行，用于修复“已修改脑图但对话保存失败”。控制器双击共用一次 Future；applied 不允许再次应用；dismissed 可重新打开。下一轮系统消息包含提议实际状态和所选操作。

`NoteSaver.save` 仅由 UI 按钮调用，携带 conversationId/messageId/body/SaveNoteRequest；后续实现负责脑图与原文双位置关联。MemoryMapEditExecutor、MemoryNoteSaver 是可测试的假实现，不持久化真实内容，也不能宣称提供正式撤销功能。

## 文件、设置与恢复

每学习集 `conversations/<id>.json` 为 AgentState JSON，命名空间 metadata 保存 assistant.view / assistant.proposals / assistant.proposalViews / assistant.reads。`ConversationStorage` 在调用时捕获 JSON 快照，串行化操作，同目录唯一临时文件 flush 后 rename；路径 ID 采用白名单，拒绝对话目录/文件符号链接。损坏文件报错，不覆盖。该防护针对应用输入与已有路径，不承诺抵抗另一个本机进程恶意并发替换目录。

`openConversation` 恢复 running → interrupted，并核对执行凭据；不会执行未完成工具。文件存储保留原始 running 标记，由控制器完成恢复写回。旧研究会话迁移见下文 GUL-531 接入。ResearchNote 的 conversationId 为可选字段，旧文件 null；copyWith/JSON 复制保留，学习集格式不升级。

设置存 SharedPreferences，按供应商保留模型和 endpoint；联网默认 true，本机模型默认 false，另有 searxngEndpoint。Key 只在 Keychain SecretStore：claude→anthropic，responses→openai，compatible→compatible，ollama→assistant.ollama；复用现有研究 Key，不把 Key 写入对话或 preferences。切换设置时 UI 应调用控制器 switchModel/setOnline，使当前会话同步。

## 验证与限制

使用假 LLM、SDK generate 模式 RecordingLLMClient/严格 ReplayLLMClient（SDK 2.1.8 不记录流模式），每 Skill 三例；另测真实 runStream 映射、停止、恢复、提议与存储边界。未使用真实账号，不宣称供应商联网验证通过。

预算默认搜索 3 次、页 5、输出 4096 tokens、输入 60000 字符（含历史/系统提示/工具 schema）、响应 2 MiB、90 秒；另限 20 次工具与 8 次模型调用。输入每次检查，输出按供应商 usage 累计并下调后续 maxTokens；未报 usage 时仍保留供应商单次上限和整轮字节/次数/时限边界，不声称本地有通用精确 tokenizer。取消远端接收不能撤回已计费计算。安全传输继承 ADR 0001 中 TLS 握手取消的已知限制。

交付验证（2026-10-27）：`flutter analyze` 无问题；`dart format --set-exit-if-changed apps packages` 无改动；`python3 -m unittest discover -s tool/tests` 11 项通过；`python3 tool/coverage.py` 全部包通过。补充边界测试后重新运行 mm_assistant 覆盖率并用 `--report-only` 合并：总计 92.46%，mm_assistant 96.17%，AssistantController 98.06%，AssistantSettings 94.55%，新核心契约和 ConversationStorage 100%。mm_assistant 53 项，控制器/设置定向回归 11 项；唯一跳过项为既有 mm_research 的可选公网测试。普通入口和 Agent 探针的 macOS Release 构建通过，体积见 ADR 0002。

## 写操作接入（GUL-531）

应用层 `features/assistant/assistant_writes.dart` 提供按学习集绑定的
`assistantMapEditExecutorProvider(studySetId)` 和 `assistantNoteSaverProvider(studySetId)`，
分别传入 `AssistantDependencies.executor` / `.notes`。共用 WorkspaceController 的串行写入和撤销历史；
一次 proposal/save 是一次持久化、一步撤销。编辑框或手动事务尚未结束时拒绝写入，调用方保留提议供重试。

为 runFactory 提供 `assistantMapRevision(content, mapId)` 作为 baseRevision，并从同一个 content 快照构造
parents；包含图内节点及虚拟根 `{mapId: null}`。op.parentId 等于 mapId 表示根节点。
revision 是目标图可编辑内容的稳定指纹，不含阅读位置、复习历史和执行凭据。
应用时版本不同则拒绝；当前版本中缺失/跨图的目标或未选择的依赖安全跳过，
`MapEditReceipt.skipped` 保存 opId → 原因（旧凭据缺省为空）。

凭据与节点同存于 `StudySetContent.assistantReceipts`，以 proposalId 去重；撤销保留凭据，
因此已应用后再撤销的提议不会重复执行，需要用重做恢复。所有操作都跳过时只提交凭据，不制造空撤销步骤。
新节点通过 WorkspaceState.flashCardIds 一次发布，画布同时闪烁，flashCardId 提供滚动目标。
Card.body 是向后兼容的可选字段：空值保留旧复习行为，非空时 title 为题面、body 为答案；
继续使用 CardKind.note 和既有 FSRS 队列、侧栏订阅。JSON、剪贴板、Markdown/OPML 导出保留正文。

NoteSaver 使用 conversationId/messageId 生成稳定笔记 ID，避免对话保存失败后的重复保存。
request.mapId 表示创建笔记节点（parentId 可空），request.anchor 表示附到原文或现有节点；
两者同时提供会创建双位置关联，均在事务中校验。无有效目标时抛错，不悄悄改存到根节点。
删除沿用 deleteResearchNote，关联和节点一起删除并可撤销。

`mm_assistant.LegacyConversationMigration` 接收 studySetId、ResearchSessionRepository、
StudySetContentRepository、同学习集 StateStorage 和显示用 model。入口替换时先 await migrate()，
返回的 legacy-<sessionId> 可直接交给 openConversation；不要将旧研究模型重新发给供应商。
迁移保留每轮问题、回答及带定位的引用；原始 ResearchSession JSON 完整保存在
metadata['assistant.legacySession']，旧文件不删除。原笔记保留 sessionId、证据及目标，新增 conversationId。
先写对话后补笔记链接，失败可重跑，已有归档不覆盖。Conversation.readOnly 在 JSON 往返和 copyWith 中保留，
控制器拒绝发送、提议操作、保存笔记和设置修改；UI 应隐藏这些控件，仍可新建普通对话。
