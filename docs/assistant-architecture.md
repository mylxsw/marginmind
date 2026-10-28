# 助手底座契约（GUL-528）

本阶段不接 UI、不替换研究入口。`mm_core` 定义端口；纯 Dart `mm_assistant` 负责框架、工具、Hooks、不可变视图模型与假实现；`mm_data` 负责对话文件；应用层负责 Riverpod、设置和钥匙串组合。依赖固定为 `dart_agent_core 2.1.8`。

## UI 接入

GUL-530 起由 `AssistantScope`（`features/assistant/widgets/assistant_panel.dart`）在学习集窗口外层建立 ProviderScope，override `assistantDependenciesProvider` 与 `assistantControllerProvider`；窗口存在期间对话一直存活，关闭面板或切换文档不中断生成（切换对话仍按控制器契约先停止旧运行）。依赖由 `assistantDependenciesForProvider(studySetId)` 组合：对话存储 `assistantArchiveProvider`（文件仓库用 `ConversationStorage`，内存仓库用 `MemoryConversationArchive`）、GUL-531 的 executor / NoteSaver、`assistantNetworkProvider`（可选测试覆盖；生产通过 `assistantNetworkFor` 按本轮模型创建）；revision 与 parents 取自同一个 content 快照（`assistantMapRevision`、`mapParents`，根节点为 mapId）。读取端口为 `WorkspaceReader`：选区原文来自本轮问题的 ContextItem（`displayText` 即原句），重启后也能重读；上下文与读取里的脑图根节点 ID 为 `__root__`，与画布一致。对话列表首次加载前执行一次 `LegacyConversationMigration`；只读对话不显示输入区，回答只保留复制。

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

`AssistantNetwork` 的三个方法：search(keywords)、papers(keywords)、fetch(url)，均带取消令牌。GUL-532 的 `SnapshotAssistantNetwork` 实现真实后端：

- Claude/Responses 复用现有 mm_research 供应商内置搜索，仅转换为标题、URL、摘要；丢弃其结论与引用。
- compatible/Ollama 使用设置中的 SearXNG endpoint；未配置时明确 unavailable。
- fetch 必须再次使用独立网页 UrlPolicy、安全传输、快照持久化和段落编号，成功提交后才返回 kind=snapshot 的 AssistantSource。OpenAlex 返回 kind=openAlex 的元数据，不假称全文。
- 内存实现只供测试。生产网络每轮新建，搜索最多 3 次、抓取最多 5 次；公共与供应商传输共享 2 MiB 原始响应和 90 秒期限，外层运行预算仍限制工具、输出和总时限。公共网页不享有本机或供应商 API 的地址例外。
- 网页与 OpenAlex 元数据均先提交学习集中的内容寻址快照，再返回来源。来源 ID 为快照路径，版本固定为 1；内容变化会产生新 ID，不覆盖旧快照。引用携带 title/kind/snapshotFile/fetchedAt 及实际段落，随对话持久化，来源抽屉显示标题、站点、版本、快照时间和被引段落。失败或取消后不会登记来源。

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

兼容服务和 Ollama 的地址支持基础地址（如 `https://example.com/v1`）或完整的 `/chat/completions` 地址，忽略首尾空格和末尾斜杠；仅填写域名时使用 `/v1/chat/completions`，自定义路径前缀保留。连接检查与实际对话共用解析与传输，仍将请求限制在解析后的单一接口，禁止重定向、携带用户信息或查询参数的地址；远程仍要求 HTTPS，本机仍须显式启用且仅允许 loopback。连接卡分别提示配置无效、Key 无效、超时和限流，不展示供应商原始响应或凭据。

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


## GUL-532 接入与清理

设置和首次连接支持 Ollama 的 `/v1/chat/completions`，无需 API Key；仅允许显式启用的 loopback 地址。设置可保存 SearXNG JSON 搜索 endpoint。云端不可用时“改用本机模型”切换至已配置且启用的 Ollama，并关闭联网后重新请求。未安装 / 未启动 Ollama 时仍如实显示连接失败，不隐式回退到云端。

旧研究启动卡、三标签面板、保存表单、生成控制器、session_engine、兼容模型适配器及废弃功能开关已移除。保留两种供应商的内置搜索协议、公共安全传输与正文提取；保留旧会话文件和只读迁移、研究笔记查看 / 编辑 / 复习，不删除历史内容。

## 第二轮运行时可靠性（GUL-536）

`assistantFailureKind` 供运行时与控制器共用：连接/TLS 故障为 `network`，服务或未知异常为
`unavailable`，错误工具协议为 `toolProtocol`，循环检测及工具次数上限为 `loop`。
未知工具和参数错误会以具体、安全的拒绝原因回传模型；工具匹配前去除命名空间、统一大小写及连字符，
整数参数接受整数字符串。连续三次同原因失败后，本轮请求不再发送工具定义，要求根据附带上下文直接回答；
成功工具会重置连续失败计数，联网开关、读取授权及提议确认仍逐次生效。

最小数据层接口为 `AssistantModel.supportsTools`（旧数据默认 true）；false 时从首次请求开始移除工具。
后续模型目录只需传入该字段。标题候选通过 `assistantTitleModel` 从同服务可用模型中选取小模型；
当前设置每服务只有一个模型，因此无候选时使用当前模型，不硬编码未配置的模型 ID。
标题请求独立、无工具、最多 64 tokens / 10 秒，失败保留 24 字问题占位；手动改名优先。

`Message.traces` 按发生顺序存说明与动作，说明使用 `TraceStep.narration`，正文仅保留最后一次工具调用后的输出。
中文问题的纯英文工具前元话语不展示；系统和每个 Skill 均要求说明、正文跟随提问语言。
`Message.activity` 合并相邻同类、同状态、同原因动作并提供 count；原始 traces 保留完整事件。
`startedAt`、`endedAt`、`elapsedSeconds` 供过程时间线使用。

每轮 `metadata['assistant.diagnostics'][requestId]` 只保存请求 ID、模型、服务主机、工具原始名称、结果、
拒绝原因、是否兜底和分类后的失败原因；`Message.diagnostics` 提供不可变的详情/复制视图。
不保存 Key、工具参数、请求正文、选区或供应商原始错误。工具名称限 100 个 ASCII 标识字符。
界面完整的时间线视觉和详情/复制交互由第二轮消息 UI 任务消费上述数据；本任务为现有过程列表补上说明、计数与拒绝原因。

录制回归使用确定性假模型及兼容接口响应样本（`coding/auto`），不代表真实服务账号联调。

## 多服务与独立搜索设置（GUL-535）

`mm_assistant/src/services.dart` 是新设置页的数据契约：`AssistantServices` 包含有序服务、模型和默认 `(serviceId, modelId)`；服务协议为 `openai / anthropic / gemini / ollama`。OpenAI 的 `responses` 标记保留旧 Responses 调用方式。服务 ID 创建后不可更换，协议不支持原地切换。集合不可变，重复 ID 拒绝；默认失效时按服务顺序、模型顺序选择首个启用项，没有则为空。Ollama 必须另有显式本机授权。

应用层 `features/assistant/assistant_services.dart` 提供：

- `assistantServicesProvider`（AsyncNotifier）：`upsert/remove/setEnabled/setDefault/saveKey`；模型编辑 `upsertModel/removeModel/setModelEnabled`；从列表或手动 ID 新增均使用 `addDiscoveredModel`，它先探测工具能力再保存。
- `enabledAssistantModelsProvider`：按服务 ID 分组的已启用模型；显示名和服务名从 `AssistantServices` 获取。
- `serviceCatalogProvider`：`list(service, key)`、`probe(service, model, key)`、`check(service, key)`；支持 CancellationToken。检查返回 `ok/authFailed/unreachable`，取消抛 cancelled；UI 负责 0.7 秒防抖、取消前一次及丢弃过时结果。
- `webSearchSettingsProvider`：`configure` 和 `saveKey`；`checkWebSearch(webSearchProvider(...))` 检查当前选定后端。测试查询只发送固定关键词，不含文档内容。
- `quickModelFor(service, current)`：仅在同服务已启用模型内选择已知小模型名称（haiku/mini/flash/small），否则使用当前模型。标题生成也校验服务 ID，不能跨同地址的两个账号借用模型。

持久化键为 `assistant.services.v1` 和 `assistant.search.v1`，不含凭据。服务 Key 使用 `assistant.service.<id>`；搜索 Key 使用 `assistant.search.<backend>`，Cloudflare 账户 ID 单独使用 `assistant.search.cloudflare.account`。服务操作串行化，失败不阻塞后续操作。删除服务同时删除新 Key；迁移服务另清理其旧供应商 Key，其他服务只引用自己的独立 Key。Keychain 与 preferences 无跨存储事务：删除若中途失败，保留服务配置并向调用方报错，可重试，可能需要重新输入已删除的 Key。

首次读取只迁移旧服务配置，包括未选中但已配置的服务，不读写钥匙串。迁移服务需要凭据时，优先读取新服务 Key，缺失时读取原供应商 Key；自建服务不回退到其他服务的 Key。清空迁移服务 Key 时同时清理旧账户，避免清空后又恢复旧 Key。新配置存在时不再重迁移，因此删除服务不会被旧偏好恢复。旧对话不改写：缺少 serviceId 时按 `legacy-<provider>` 解析；发送及标题生成重新检查服务/模型启用状态。删除、停用或移除模型后旧内容仍可阅读，发送失败要求重新选择模型。

打开学习集只加载模型配置，助手面板打开或实际提问时才检查凭据。macOS 钥匙串读写使用串行后台队列，结果回到主线程；同时禁止传统 login 钥匙串和 LAContext 的认证弹窗，操作完成后恢复原有交互策略。钥匙串锁定或拒绝访问会返回认证错误，保留已存 Key，不阻塞阅读；助手显示连接入口，设置表单仍可编辑。不会把凭据转存到普通文件或 preferences。

系统账号密码和修改钥匙串权限均不是应用的使用或迁移步骤。旧条目拒绝更新时，用户显式填写的新 API Key 存入新的钥匙串条目，成功后才切换逻辑账户的引用；旧条目保持不动。UserDefaults 的 `marginmind.secret-store.reference.v1.<account>` 只保存随机条目 ID，不含密钥。删除当前条目后保留引用，避免读回旧密钥；如果整个钥匙串锁定而无法保存，则返回错误，不弹系统密码框，也不改成明文存储。

旧 `AssistantSettingsController` 适配层已在 GUL-537 删除（见下文）。GUL-537 应在设置/模型菜单初始化时订阅 `assistantServicesProvider`，新对话使用其 `configuration`，无模型时展示未配置状态。旧会话文件格式不升级。

模型列表按协议使用 models/tags，Anthropic/Gemini 支持分页（最多 20 页并拒绝重复游标）。过滤明确非对话 ID 和能力字段；未知兼容模型保留，允许手动添加。工具能力 `unknown/supported/unsupported`：优先用能力字段，否则一次最小带工具请求；不执行返回的工具，不把鉴权、超时、限流和其他参数错误当作不支持。仅明确工具不支持的 400 错误记为 unsupported。unknown 在运行时按支持处理，由 GUL-536 的连续错误兜底。

搜索后端独立选择 model/Cloudflare/SearXNG/Tavily/Brave。model 复用 Claude/Responses 搜索并增加 Gemini grounding URL 解析；不支持原生搜索的兼容服务明确 unavailable，无隐式回退。迁移时若旧 SearXNG 地址非空则选它，否则默认 model。该选择只迁移一次，后续不随模型切换。所有答案、原始网页内容和供应商引用均不作为证据；仅提取 URL、标题、摘要，后续由 fetch_source 抓取快照。

API 依据：[Cloudflare](https://developers.cloudflare.com/web-search/how-to-use/)、[Tavily](https://docs.tavily.com/documentation/api-reference/endpoint/search)、[Brave](https://api-dashboard.search.brave.com/app/documentation/web-search/get-started)、[Gemini Models](https://ai.google.dev/api/models)、[Ollama](https://docs.ollama.com/api/tags)。Cloudflare Token 需 Workers AI 与 AI Gateway 读取权限，gateway 固定 default。未进行真实账号计费调用，验证使用 fake HTTP 与已有本机测试服务。

列表操作的所有分页及 Ollama `/api/show` 能力查询共享一份 90 秒/2 MiB 预算，最多 1000 条候选；Ollama tags 未返回能力时通过 show 过滤非 completion 模型并取得 tools 能力。服务探测期间地址改变则拒绝保存过时结果。旧设置页暂不新增 Gemini 选项，以避免旧的四段控件溢出；新设置页直接使用四种 ServiceProtocol（包含 Gemini），不使用旧 connectableServices。

翻译回合通过 `AssistantServicesStore.resolve(..., quick: true)` 选择同服务小模型；普通对话仍使用选中的模型，对话菜单中的选择不被翻译临时改写。缺省 Claude 模型的空字符串按旧设置规则恢复，避免迁移后原本可用的缺省配置变为空清单。

## 第二轮界面（GUL-537）

- **设置**：`settings/settings_window.dart` 的 `showSettings(context, tab:)`（通用 / 阅读 / 模型 / 网页搜索）取代旧的设置面板和助手设置面板。“模型”页 `features/assistant/settings/model_settings.dart` 只通过 `assistantServicesProvider` 读写；“网页搜索”页 `web_search_settings.dart` 只通过 `webSearchSettingsProvider`，检查走可替换的 `webSearchCheckerProvider`（默认 `checkWebSearch`）。服务卡片在名称、地址、Key 停顿 0.7 秒后保存，地址或 Key 保存后用 `serviceCatalogProvider.check` 检查，新的输入会取消上一次检查并丢弃过时结果。
- **适配层已删除**：`assistantSettingsProvider`、`AssistantSettings`、`assistantConnectionTesterProvider` 不再存在。`assistant_settings.dart` 只保留钥匙串、`legacyAssistantAccount/legacyAssistantModel`（迁移和无 serviceId 的旧对话用）、`assistantDefaultModelProvider`（`AssistantServices.configuration`）、`assistantConfiguredProvider`（有默认模型，且其服务有 Key 或为已授权的 Ollama）和 `assistantRunFactory`。服务 Key 变化通过 `assistantKeysProvider` 通知。
- **默认模型与对话模型**：`AssistantDependencies.defaultModel` 是读取当前默认模型的回调；控制器创建首个对话和 `newConversation` 时使用它（没有时退回 `model`，即未配置占位）。窗口宿主订阅 `assistantDefaultModelProvider`：服务异步加载完成或默认模型改变时，只让**还没有消息**的对话跟随；用过的对话保留自己的模型。模型菜单（`widgets/assistant_model_menu.dart`）只调用 `switchModel`，不改默认模型。
- **联网开关按学习集记住**：输入框的开关写入 `assistant.online.<studySetId>`，新窗口的第一个对话由 `assistantOnlineDefault` 读取（旧的全局 `assistant.online` 作后备）。
- **不用工具重答**：`AssistantController.retry(id, tools: false)` 把本轮传给 runFactory 的对话模型设为 `supportsTools: false`（不持久化）；`assistantRunFactory` 以 `config.supportsTools && conversation.model.supportsTools` 决定是否发送工具。
- **消息**：过程时间线 `ActivityTimeline` 直接用 `Message.activity`、`elapsedSeconds`；错误块的“详情 / 复制诊断信息”只用 `Message.diagnostics` 的白名单字段（模型、服务名、主机、HTTP 状态码、失败工具与次数、停止原因、请求 ID）。正文用 `markdown` 包解析（GitHub 扩展 + 引用语法），流式时以代码块外最后一个空行为界：之前的块解析一次后缓存，之后的未完成块只解析行内格式。中文里以全角标点结尾的 `**…**`（如 `**一句话：**这句…`）在 CommonMark 下不闭合，`_CjkStrongSyntax` 通过 markdown 包的扩展接口只处理这一种情况。
