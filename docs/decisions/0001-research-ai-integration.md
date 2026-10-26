# ADR 0001：研究 AI 接入与安全边界

状态：按 GUL-513 已批准的方案实施；真实服务验证待补。日期：2026-10-27。

## 决策与模块

直接使用 HTTP API，不打包 Agent SDK、Node/Python 运行时或客户端工具执行器。
`mm_core/src/research/ports.dart` 定义纯 Dart 端口和不可变传输值类型；
`mm_research` 依赖 `mm_core`、`http`，负责请求构造、SSE、引用候选、安全 HTTP 和预算；
`mm_platform/KeychainSecretStore` 经 `marginmind/secret_store` 方法通道调用 macOS Security。
应用组合根负责读密钥并注入适配器，界面不接触 HTTP、供应商 JSON 或平台插件。

本任务不定义第二套持久化实体，不升级文件格式。会话持久化统一使用 P2-A2 的 `ResearchSessionRepository`（`mm_core` content），
本任务的临时泛型端口已在合并时移除。SearchProvider / ContentExtractor 仅定义端口，
OpenAlex、WKWebView / Readability 与会话调度不在本次实现范围。

## 请求与事件合同

`AiProvider.generate(AiRequest, CancellationToken) → Stream<AiEvent>`。
请求含 sessionId、requestId、问题、已确认上下文、方式、所选文档段落和预算。
每个事件携带原请求的两个 ID；控制器写入前仍须校验最新 requestId，适配器不改写会话状态。
事件分为文本增量、来源、引用候选、工具错误、用量、完成。
没有供应商终止信号、格式错误或输出到达上限都不能发 completed。
取消令牌可贯穿检索、提取和 AI 请求；流订阅取消也释放 HTTP 客户端。

| 方式 | Anthropic Messages | OpenAI Responses | OpenAI 兼容 Chat Completions |
| --- | --- | --- | --- |
| 联网研究 | `web_search_20260209` / `web_fetch_20260209`，各设 `max_uses`；`allowed_callers: [direct]` 禁用动态过滤代码执行 | `tools: [{type: web_search}]`、`max_tool_calls`、`include: [web_search_call.action.sources]` | 请求发送前拒绝 |
| 不联网 | 不含 tools，不接受资料列表 | 不含 tools，`store: false` | 不含 tools |
| 基于资料 | 所选段落作为 text/plain document，`citations.enabled: true`，不含 tools | JSON 分隔的资料段落，要求 `[source:N]`，不含 tools | 同 Responses 的段落标记方式，不含 tools |

Anthropic 默认 `claude-opus-5-5`，调用方可覆盖。OpenAI 与兼容端要求显式模型名，避免静默猜测
用户账号可用模型。三个适配器均流式输出。不联网不是本机推理：使用远端服务仍会上传已确认的上下文。
基于资料的 Responses/兼容模式没有假造“原生 citations 开关”；客户端仅接受已发送段落的合法索引。

## 预算与错误

默认每请求搜索 3 次、读取 5 页、输出 4096 tokens、输入 60000 字符（含系统说明）、
响应 2 MiB、总时限 90 秒。Anthropic fetch 另设 `max_content_tokens: 10000`。
OpenAI 的 `max_tool_calls = searches` 限制所有内置工具调用总数，不能承诺独立的页面上限；
本地 pages 计数用于 Anthropic fetch / 后续提取调度。预算不是金额估计。

本地计数器独立校验字节和工具使用。供应商侧上限先约束远端行为；客户端取消只能停止接收，
不能保证已提交的远端计算立即停止或免除费用。只对收到的 HTTP 429 / 5xx 最多重试两次，
退避默认 0.5 / 1 秒，整数 Retry-After 上限 30 秒，所有尝试共用总时限。
收到流后、网络异常、超时和用户取消不自动重发。pause_turn 不自动续接，避免隐藏增加预算。

| 情况 | ResearchFailureKind / 事件 |
| --- | --- |
| 用户取消、总超时、字节/输入/输出/工具预算耗尽 | cancelled / timeout / budget |
| 401、403 / 重试耗尽的 429 / 5xx | authentication / rateLimited / unavailable |
| 其他非 200 / 非法 SSE、截断 | invalidRequest / protocol |
| HTTP 200 中工具错误块 | toolError，可保留已有回答，但不能据此生成证据 |
| Anthropic stop_reason refusal、Responses refusal、兼容 refusal/content_filter | refusal，终止且不发 completed |
| 客户端 tool_use/function_call、兼容联网、pause_turn | unsupported；不执行、不自动回传结果 |

不暴露原始错误响应、密钥、请求正文或供应商诊断文字到异常/日志。重试可能再次计费，
不是 exactly-once 协议；应用恢复中断会话时必须由用户显式重试。

## 引用到持久化实体

`ResearchCitation` 是候选，不等同于 `Evidence`；其字段允许表达能力差异。

1. web_search/web_fetch 结果与 URL citation 按规范 URL 去重后创建/关联 P2-A2 的
   `ResearchSource`，保留标题和真实获取方式。URL 注解只有回答中的 start/end，
   不是原文偏移；不得据此生成 quote、段落定位或“已提取正文”状态。
2. Anthropic `cited_text` 保留为候选原文。网页来源需要本地快照验证文本后，才能生成
   `Evidence(sourceId, sourceVersion, quote, locator, acquisition, capturedAt)`。
   供应商返回 fetch 文档不等于本地已保存快照；web-fetch document_index 映射回 fetch URL。
3. 输入文档的引用必须存在于对应段落。Anthropic 原生引用要求 cited_text 确为原文子串；
   Responses/兼容标记只接受现有段落索引，定位整段，quote 为未改写的原段落，不能声称更精细定位。
   sourceId/version/paragraphId 直接来自调用方选定的不可变快照。
4. 未知索引、编造摘录被丢弃；不联网模式丢弃全部引用。URL 候选不自动抓取，
   读取前重新经过 URL 安全策略。后续来源归档及 Evidence 写入由 P2-A2 模型和研究保存流程完成。

## 地址、密钥与提示注入

网页只允许 HTTP(S)，拒绝凭据 URL、回环、私网、链路本地、元数据地址、共享地址段、
非全局 IPv6、IPv4-mapped/NAT64/6to4 等转译地址。DNS 结果中出现一个不可用地址就拒绝；
连接使用已验证的数值 IP（TLS 主机名不变），关闭环境代理，避免校验与连接之间的 DNS 重绑定。
每次重定向重新校验，最多 5 次。API 非 GET 请求或携带 authorization、proxy-authorization、x-api-key、api-key、cookie/cookie2 时拒绝重定向，避免泄露密钥。

本机 Ollama 例外仅用于用户显式启用的兼容 API 完整 endpoint：同 origin、同 path 且 DNS
全部为 loopback；不放行局域网。远端 API 必须 HTTPS。此例外不共享给网页读取。

网页/资料始终为数据，不执行客户端工具，不读取文件，不扩大上下文；收到任何客户端工具请求
直接拒绝。联网模式本来就授权了有预算的供应商搜索/读取，不能承诺提示注入完全不影响其查询选择。
确定性测试保证的是应用不因此执行客户端工具、追加请求或增加本地上下文。

密钥仅存固定 service 下的 Keychain generic password；不同供应商使用不同 account，
不启用 iCloud 同步，设备解锁时可用。read/write/delete 错误脱敏；缺失键返回 null。
DebugProfile 与 Release 均开启 network.client；Release 签名产物检查该权限为 true。

## 验证与限制

环境没有 ANTHROPIC_API_KEY / OPENAI_API_KEY，**真实服务验证待补**，不宣称已接通。
fixtures 是官方协议示例衍生的脱敏固定响应，并非真实账号录制；需补充真实录制响应回归。
确定性测试覆盖三协议成功、单字节 UTF-8/SSE 分片、引用、拒答、200 工具错误、
HTTP 重试、取消、超时、大小上限、危险地址/重定向及提示注入。新增包纳入覆盖率门禁。

参考：[Anthropic search](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool)、
[fetch](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-fetch-tool)、
[OpenAI web search](https://developers.openai.com/api/docs/guides/tools-web-search)、
[Responses 参数](https://developers.openai.com/api/reference/resources/responses/methods/create)。

本地验证：`flutter analyze`、全仓 `dart format` 检查、11 项 Python 工具测试、
八包覆盖率测试均通过；mm_research 97.12%（43 项确定性测试）。
macOS Debug 构建通过，5 项 Xcode 原生测试通过，含真实 Keychain 临时测试账号的读写/覆盖/删除。
无界面改动，不需要截图。以上验证不等同于真实模型服务接通。

### PR #45 HTTPS Review 修复

自定义 connectionFactory 必须显式升级 TLS；HttpClient 不会自动升级普通 Socket。
现在先连接校验后的 IP，再通过 `SecureSocket.secure(host: url.host)` 使用原始域名完成
SNI 和证书校验，通过 ConnectionTask 返回连接并在取消时清理已建立的 Socket。
普通 accept/user-agent 请求头可以跟随重定向，每一跳仍重新校验 URL；凭据头匹配不区分大小写。

默认测试使用本地自签名 TLS 服务，证书仅包含 research.test，验证成功握手及错误域名被拒绝。
可选 network 标签测试走真实 ResearchHttp，请求 OpenAlex（无需 Key）：2026-10-27 已通过。
这只验证公网 HTTPS 传输，不代表 Anthropic/OpenAI 真实模型服务已验证。

取消边界：TCP 建连及已完成握手的 Socket 可被关闭；`SecureSocket.secure` 开始后会从原 Socket
分离底层连接，Dart 未暴露握手中的 Socket。因而握手期间取消只能由请求总超时结束调用，
并在握手返回时销毁 TLS Socket，不能保证恶意服务器停滞握手时立即释放底层连接。
本地停滞握手探针未通过即时关闭断言；此项仍需后续收紧，不能把普通流取消测试当作该场景已覆盖。
