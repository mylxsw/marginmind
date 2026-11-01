# 文档导图 Heavy Runtime 接入（GUL-652）

扩写 `map_expand` 和生成/更新 `map_generate` 的生产调用通过 `MapTaskSession` / `createMapTaskExecutor` → `PersistentTaskAssembly` → `SdkAgentRuntime`。每个阶段使用真实功能路由、凭据读取与磁盘 RunStore，不读取旧默认模型。首次阶段冻结配置；规划、章节、分层归并与局部修复的 child context 继承模型、额度、知识版本与权限范围。未知能力继续拒绝，不降级到裸模型请求。离线限制仍由宿主执行。

导出的契约为 `mapExpandSpec`、`mapGenerateSpec`、`mapTaskKnowledgeBundles`（mindmap.expand/document v2）、`registerMapTaskDefinition`、`MapTaskSession` 与 `createMapTaskExecutor`。注册函数接收阶段指令和领域校验函数；宿主为每次阶段建立独立 registry，避免并发章节共享解析状态。父负责人聚合两个实际 TaskSpec 到 `aiTaskRoutingSpecsProvider`，并在公共知识装配中纳入 v2 包。公共 provider 与公共 assembly 未在本领域覆盖。

整任务没有累计 token 或文档长度配额。单请求保守限制为 24,000 个编码输入字符、8,192 输出 tokens（同时受能力档案的更小额度约束）、256,000 响应字符；Runtime 还校验实际模型容量与完整编码请求。大章节继续拆到页内 10,000 字符片段，保留完整正文和标注/批注，不截断丢弃。长标注独立分块。分块来源仅允许实际发送页，逐字引文仅在该片段验证。超大指令或现有结构不能安全拆分时明确报容量失败。

最终合成前按编码大小分组，将章节要点分层归并。每个批次都有独立运行记录；若归并不能缩小输入，明确失败，不无限递归或把全部原始要点塞入最后请求。模型语义保真度仍需真实模型评测，确定性校验不能证明摘要无遗漏。

Runtime 响应保留 NDJSON，并要求末尾 `{"coverage":["id",...]}` 覆盖记录。章节覆盖页/标注片段；归并和最终构图覆盖输入要点 ID。覆盖元数据不是图编辑，不进入提议。完整性校验分别检查范围声明、合法内容、父子依赖、无环、深度、来源别名与保护节点；只有合法行而缺少覆盖声明仍是 partial。覆盖声明证明可追踪性，不单独证明语义质量。

坏行最多局部修复两次：保留已经接受的 refs，仅发送拒绝项及缺失覆盖范围；已接受内容不重新生成。耗尽修复仍保留草稿并显式 partial。结果、遗漏 IDs、失败原因通过 RunStore 持久化。生成器生命周期内还复用已完成片段；显式章节重试只继续失败片段。已完整章节继续使用磁盘章节缓存；缓存键在读取缓存前使用实际冻结的模型身份、服务修订、调用策略、知识和提示版本生成；不使用可能发生变化的全局设置快照。失败流不写成完整章节缓存。进程重启后的恢复以完整章节磁盘缓存和 Runtime 的 partial 记录为依据；未提供跨进程的导图预览自动复原 UI。

`DocumentDigestBuilder` 保留既有目录、OCR、Book IR、来源 fingerprint 与增量读取逻辑。EPUB/MOBI/Markdown/网页仍使用 canonical spine 单元；它们不是物理页码，因此不伪造页码来源。精确文本出处跳转仍需要 TextAnchor 契约扩展。

三个章节 worker、提议预览、revision 冲突、用户确认、依赖闭包、原子提交与撤销保持既有链路。失败章节 ID 会进入最终构图的 Runtime validation，最终 run 保持 partial，不会因局部构图成功被显示为完整任务；扩写为失败目标保存明确原因，并审计实际可见树深度。设置与开始入口使用真实 TaskSpec 的 resolver；功能内复用 ModelRoutePicker、RoutingIssueLine、RunStatusCapsule。旧的直连构造器仅供已有离线协议回放和 smoke 工具使用，不是生产 fallback。
