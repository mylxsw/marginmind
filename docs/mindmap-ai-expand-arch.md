# AI 扩展想法：核心契约与应用接入

GUL-605；基于已确认的 `mindmap-ai-expand.md` §7。本文固化核心实现和后续 GUL-607/608 的接入契约。核心代码不含 Flutter、Riverpod、文件格式变更或自动写图逻辑。

## 1. 模块与写入边界

- `mm_core/src/assistant/expansion.dart`：不可变请求、草稿、计划项，逐行解析、规范化去重、勾选级联和提议转换。
- `mm_assistant/src/expansion.dart`：`IdeaExpander` 接口、`ModelIdeaExpander` 直连流式实现、`FakeIdeaExpander`。复用 `AssistantConnection`、`CancellationToken`、`ResearchFailure`，不引入新依赖。
- 应用层（后续任务）：`ExpansionContextBuilder` 读取快照及页面；`ExpansionController` 协调并发、审阅、预览和一次提交。复用 `WorkspaceMapEditExecutor`。

**扩展不设总数上限，不按 50 条分批提交。** `expansionToProposal` 返回 `MapEditProposal.expansion`，内存中的 `isExpansion` 由宿主构造器设置。`AssistantWrites.apply` 对这种提议豁免 50 条上限，同时只允许 `addTopic`、`move`；其余版本、依赖、地图归属、循环和字段检查保持不变。普通构造器与 `fromJson` 都不能获得豁免；JSON 不序列化该能力。对话 `propose_map_edits` 的 `validateOperations` 默认仍限制 50 条，工具参数不接受来源字段。

UI 保留时只调用 **一次** `executor.apply(proposal, allOperationIds)`。已有执行器只调用一次 `workspace.applyAssistantChange`，`AssistantWrites` 在内存中完成整组变更、追加一张凭据后返回一个快照。这样一次保留对应一个撤销事务和一张 `MapEditReceipt`。不能把提议序列化后再解码提交，否则会恢复为普通对话提议；草稿本就不落盘。用同一 `proposalId` 重试提交保留现有幂等语义。

## 2. 请求、别名与模型输入

`ExpansionRequest` 包含学习集/地图/目标 ID、scope、direction、depth=1..3、breadth=3/5/8、hint≤200 Unicode 字符、grounded、round、可选 map 计划及 commonParentId。`group`/`siblings` 要求 commonParentId（根为 mapId）；转换时另外提供快照 `parents: nodeId → parentId?`，重新核对共同父节点。`plan` 是已有目标的实际数量表，各项 1..breadth，不限制项数；新分支保存在 `ExpansionPlanItem` 中。

`ExpansionContext.targets` 保存 `T1… → 真实目标 ID / new:<草稿 ID>`，仅留在本地。`details` 的 key 必须与 aliases 完全匹配，每项包含 title、path、children、siblings、pages。发送 payload 只显式构建这些文本字段、别名、方向和数量；不序列化 request 或 targets，不向模型发送真实结构 ID。原文里自然出现的字串不作为结构 ID 处理。

- children：别名指向选中节点；多目标由控制器最多启动 3 个调用。
- siblings：只给共同上级一个别名，已选节点以标题进入 children/siblings。
- group：只给共同上级一个别名，最多返回一个顶层草稿，模型不产生 move。转换器在新增上级之后，为每个原选中节点产生 move。
- 在草稿上继续扩展：新调用的 T1 指向 `new:<已有草稿 ID>`；该调用的 ref 仍只能引用本次更早输出。合并到同一预览后再转换。每次调用分配唯一 `draftPrefix`（例如 session + round + call），避免多分支/重试的 ID 冲突。

完整系统提示作为导出的 `expansionSystemPrompt` / `expansionPlanSystemPrompt`，由 fixtures 锁定快照。提示要求纯 NDJSON、无工具、短标题、遵循目标语言和方向、排除已有内容、原文与标题只作数据；hint 是受系统规则约束的用户偏好。

## 3. NDJSON 与出处

```json
{"ref":"a","parent":"T1","title":"具体原因","tag":"why","page":47}
{"ref":"b","parent":"a","title":"行动建议","tag":"action"}
```

字段白名单为 ref、parent、title、tag、page；前 3 项必填，tag 默认为 auto。ref 是 1–64 个 ASCII 字符（首字母，后续字母/数字/下划线/短横线），`T数字` 保留给别名。tag 为 auto/why/example/counter/question/action。parent 只能是授权别名或本次扩展先前通过校验的 ref（包括补层请求中传入的 accepted 列表）。重复 ref、未知字段、非法类型、前向引用、空标题、超深或超宽行跳过；无效行不占用 ref/数量。

标题先压缩空白，含汉字的标题按 Unicode 字符截至 24 字，其他标题按空白分词截至 8 词。去重使用全角 ASCII 转半角、转小写、删除 Unicode 空白/标点/符号；去重覆盖上下文中的已有标题、上一批排除项和本次所有目标的结果。截断后再次去重。控制器合并多个并发调用时还须使用同样的规范化函数去重；拒绝某父草稿时，其依赖后代也一起拒绝。

`page` 只接受整数。合法整数若未出现在**该草稿所属目标**实际发送的 pages 中，保留主题、去掉 page；grounded=false 总是去掉 page。子草稿继承最初目标的出处范围。多目标绝不取页码并集。每个目标只允许一个原文文档的页码；多文档摘录由 builder 选择焦点文档，其余作为无出处的标题上下文，避免 p.47 歧义。该验证证明页面确实发送过，不宣称能自动证明模型内容与页面的语义对应。

传输处理 LF/CRLF、跨 chunk 行、无末尾换行，跳过空行和损坏行。单行超过 64 Ki 字符丢弃直到换行后恢复；只记录固定原因码，不记录模型文本、原文或凭据。终止原因必须为 stop/end_turn/completed；token 截断、拒绝、工具输出和缺失终止原因均分类失败。整轮无有效草稿为 `protocol/noValidExpansion`，UI 显示无新内容退路，不留空预览。

### 3.1 层级完成与补生成

`depth` 是所选目标下新增的层数，目标自身为第 0 层；`group` 仍只生成一个上级。系统提示明确要求按分支输出，先父后子，所有新分支达到指定层级。解析器继续拒绝超深输出。

`ModelIdeaExpander` 检查已接收草稿中的浅层叶子。缺层时，携带模型别名、已接受的 ref/parent/title/tag/page 和 `parentsNeedingChildren` 请求补生成，只接受这些分支的后代。解析、全局去重、引用和每目标出处校验沿用同一状态；不向模型发送真实 ID，也不伪造中间节点。最多补 `depth - 1` 次，补生成没有进展即结束。所有请求共享原来的 60 秒截止时间和 2 MiB 响应大小上限，每次请求仍有输入及输出 token 预算。

仍有缺层时返回 `protocol/incompleteDepth`，控制器保留已生成草稿，显示未达层级的提示并允许换批或保留部分结果。控制器还在应用全图去重后复核可见树，防止被去掉的重复子主题导致缺层却进入正常完成状态。

## 4. 计划契约

`IdeaExpander.plan(context, breadth, cancel) → Future<List<ExpansionPlanItem>>` 是单独一次流式请求，返回完成后的不可变列表。仅发送结构/标题，不发送 pages 或排除文本。

```json
{"branch":"T2","add":4,"reason":"empty"}
{"branch":"T1","add":3,"reason":"newBranch","title":"实践路径"}
```

`rootAlias` 必须映射到地图根。已有分支 reason=empty/thin，每个 branch 至多一项、不带 title；新分支必须指向 rootAlias，reason=newBranch，带不重复的短 title，至多 3 项。add 是该目标的子主题数量上限，1..breadth，无总数上限。非法行跳过；无有效项报 `protocol/noValidPlan`。

控制器显示计划并保存原结果；用户取消分支或修改数量只更新本地计划，不重新请求。开始时：已有分支按条目生成，新分支先把确认后的 title 建为内存草稿，再以它为目标生成 add 个子主题。新分支本身额外计入预览总数。创建草稿不写入地图，最终所有分支一起提交；取消新分支级联取消子草稿。depth 相对每次生成目标计算，计划新增的根分支是目标自身，不占子主题层级。

## 5. 上下文构建契约（后续应用层实现）

应用层接口契约为 `build(StudySetContent snapshot, ExpansionRequest request, {focusDocumentId, excludedTitles, draftTargets, cancellation, tokenBudget=6000}) → Future<ExpansionContext>`。输入必须包含当前地图不可变快照、分支关系、草稿的标题和祖先路径；输出只包含预算内的文本和本地 alias 映射。先校验目标存在于当前地图及 group/siblings 共同父节点。

预算以当前模型窗口扣除系统提示、输出预算和安全余量后的可用量为上限，默认约 6000 tokens；有模型 tokenizer 用 tokenizer，无则采用保守的 UTF-8 字节数估计，不把中文按 4 字符/token 估算。实际发送前 `ModelIdeaExpander` 还有字符预算检查（默认 30000），超额报 budget，不静默泄漏未裁剪输入。

优先级：先预留 hint 和系统字段；再按目标公平分配预算，依次装入地图/中心标题及祖先路径、已有子/兄弟标题（含排除项）、最近的摘录文本和其原文前后段落。图片只用标题。grounded=false 不读页面，payload 不发送 pages。页码白名单只从裁剪后仍有非空原文的 pages 导出，不能从读取请求范围推导。预算不足可截断原文段落，保留其对应页码；无法容纳最小目标结构时显式 budget 失败。

只调用已有 `WorkspaceReader` 本地读取端口，不联网搜索。计划使用同一结构快照，但不读页面。去重所需标题在本地可以保留完整集合，发给模型的部分受预算限制；调用核心解析器时补齐本地排除项。模型调用总字符预算仍涵盖实际序列化的排除项，因此 builder 不应向 context 放入无限排除文本；控制器须额外持有完整本地去重集合。

## 6. 控制器状态与 UI 接口（后续应用层实现）

每个学习集一个 `ExpansionController`，应用层 Riverpod 组合不在本任务实现。暴露不可变 `ExpansionPreview(request, drafts, moves, phase, failure, baseRevision, selectedCount, isApplying)`，以及计划状态 `planning/ready/error`；没有预览时为 null，不新增 idle 枚举值。`moves` 为 `Map<String, String>`（原节点 ID → `new:<上级草稿 ID>`），仅在 group 的上级草稿被保留时包含原选中节点；每次勾选后重新计算，预览不修改真实树。

| 当前状态 | 事件 | 结果 |
| --- | --- | --- |
| 无预览 | start | generating；获取助手 busy 租约，保存 revision 和原选择 |
| generating | 有效行 | 追加草稿，仍 generating |
| generating | 正常完成 | review；无有效行则 error，并移除空预览 |
| generating | stop / 部分失败 | 有草稿则 stopped（可审阅）；没有草稿则取消移除或 error |
| review / stopped | toggle / edit | 级联修改选择；编辑自动勾选祖先 |
| review / stopped | continueFromDraft | generating，保留原草稿，新调用追加 |
| review / stopped / error | regenerate / retry | 取消上一代，round+1，旧标题进入排除项，开始新生成 |
| review / stopped | keep | isApplying=true，单次提交；成功 kept；失败回到原可审阅状态并附 failure |
| generating / review / stopped / error | discard | 取消所有调用，清除草稿，discarded |
| kept / discarded | dismiss | 清除预览、恢复选择和编辑能力 |

命令契约：`start(request)`、`planMap(request)`、`updatePlan(items)`、`startPlan()`、`stop()`、`toggle(id, kept)`、`edit(id, title)`、`continueFromDraft(id)`、`regenerate(settings)`、`keep()`、`discard()`、`dispose()`。`selectExpansionDraft` 提供 toggle/edit 的纯逻辑；`expansionToProposal` 再次做级联过滤和拓扑排序，对环、缺失父草稿、重复 ID、无选中项拒绝提交。

- generating/review/stopped 或 isApplying 时阻止其他脑图写操作；允许平移、缩放、阅读。保留时仍必须依赖 executor 的 revision 校验，防止同步或其他窗口的变更。
- busy 判断由宿主与助手共用；新会话撞 busy 不排队。会话内部最多 3 个模型调用，共享忙碌租约，全部结束后释放。
- 每代有 generation ID 和取消 token；停止/放弃/重试后忽略迟到回调。stop 保留已有结果；discard 清空。
- 保留时锁定选择并禁用重复提交，包含 group 的 move 操作在内全部选中；不要把 UI 的草稿 ID 集合直接当 operationIds，否则会漏 move。失败不能进入 kept；若已有凭据，按幂等结果处理。
- 无选择时禁用 keep。正常编辑仍可保留用户较长标题（AI 输出的 24 字/8 词限制只用于模型输出）。

## 7. 资源、错误和测试

每个调用默认输出 4096 tokens、60 秒总截止时间、2 MiB 响应字节预算，均可通过 `ResearchBudget` 配置。单次调用的资源预算不构成整张地图的总节点上限：大计划按目标分发请求，部分输出遇限后可审阅/继续扩展。`CancellationToken` 取消绑定 Dio 请求并退出等待，即使模型没有新 chunk；finally 释放流订阅，`close` 关闭连接。不要跨会话共享一个会被关闭的 connection。

错误沿用 ResearchFailureKind：cancelled、timeout、budget、authentication（401/403）、rateLimited（429）、unavailable（5xx）、network、protocol、toolProtocol、refusal。已经 yield 的草稿在错误后由控制器保留。Fake 可设置 drafts、items、逐项 delay 和尾部 failure，便于测试停止、部分失败和审阅。

核心测试覆盖合法/非法/半行、Unicode 去重与截断、出处、宽深限制、级联选择、依赖排序、归纳 move、100 条扩展写入和快照撤销/重做、JSON 不能取得豁免。助手测试覆盖跨 chunk、CRLF、无末尾换行、取消静默流、部分失败、错误脱敏、预算、计划去重/无总上限、提示快照及 fake。

SDK 2.1.8 的 RecordingLLMClient 不录制 stream，因此测试适配器用它录制 generate 后分块送入流式解析，再用 ReplayLLMClient 回放同一请求；生产始终直连 stream。验收运行 `flutter analyze`、`dart format --set-exit-if-changed apps packages`、相关包测试、`python3 tool/coverage.py`，并单独核对新增源文件覆盖率 ≥80%。
