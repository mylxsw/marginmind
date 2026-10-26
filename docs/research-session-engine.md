# P2-R2 研究会话引擎

无界面实现；沿用格式 7，不引入新迁移。入口在
`apps/marginmind/lib/features/research/research_providers.dart`，领域调度在
`packages/mm_research/lib/src/session_engine.dart`。AI 协议与引用可信度遵循 ADR 0001。

## P2-R3 接口

| 接口 | 用途 |
| --- | --- |
| `researchReadyProvider.future` | 全库启动恢复屏障；恢复失败时阻止请求并暴露错误 |
| `researchSessionsProvider(studySetId)` | 侧栏列表，按更新时间倒序；引擎保存后失效重载 |
| `createResearchSession(ref, studySetId:, question:, origin:, …)` | 从应用命令/provider 创建 draft，返回 `ResearchSessionKey` |
| `researchSessionProvider((studySetId: …, sessionId: …))` | 持续存活的 AsyncNotifier；隐藏面板不销毁工作 |
| `.notifier.answer(provider:, question:, mode:, …)` | 三种 AI 方式；`followUp: true` 携带本会话已保存问答 |
| `.notifier.search(query)` | 仅 OpenAlex 检索，不调用 AI |
| `.notifier.readSources(ids)` | 显式读取；可仅重试一个失败来源 |
| `.notifier.cancel()` / `updateDrafts(drafts)` | 保留已接收结果；保存勾选/编辑草稿 |
| `researchCacheProvider` | 可选原始 HTML 缓存；设置清理调用 `clear()` |
| `externalSearchLink(query)` | 浏览器搜索动作；不是资料，不读取结果、不进入引用 |

`ResearchSessionState` 暴露 session、sources、evidence、metadata、answer、error。
创建方法的 Ref 属于 provider：UI 应通过命令/应用 provider 调用，不将 WidgetRef 传入。
AI provider 由调用方在已配置密钥后注入，控制器不读密钥、不挑选模型。
`answer` 的再次调用就是显式重试；不存在恢复后自动调用逻辑。
资料模式需要 `ResearchDocument(sourceId, version, paragraphId, title, text)`，
引擎会读取现有快照验证 text，不能用临时字符串冒充资料。

保存笔记仍通过 P2-A2 的 `StudySetEditor.saveResearchNote` 和工作区更新流程：
传入 `state.sources`、`state.evidence` 中实际使用的项，复用同一个笔记 ID 即为重复保存。
本任务不添加菜单入口，也不绕过工作区撤销历史直接写正式笔记。

## 状态、归属与恢复

- draft → running → done / failed / cancelled；启动发现 running → interrupted。
  兼容已有 `idle` 默认值为 draft。终态只能由显式操作重进 running。
- `main` 在 runApp 前完成一次全库恢复，并把同一 ResearchRecovery 实例注入 provider。
  恢复失败仍允许打开普通工作区，但研究 provider 保留错误并禁止请求。
  非生产组合根也通过 provider 屏障恢复。列表、创建与引擎都等待该屏障。
- 每请求冻结问题、上下文、选中段落及请求 ID；原点锚点属于会话，后续选区变化不会修改它。
  每个事件检查 sessionId/requestId；每个排队写入检查取消令牌。当前 AI 端口无事件序号，
  同一请求的文本增量按传输顺序追加；跨请求乱序丢弃，不凭空重排文字。
- 每会话串行原子写入，文本增量、检索和读取完成后立即保存。先落盘再发布新状态。
  取消先使旧令牌失效，再排队保存终态；已在写入的已接收结果保留。
- 会话文件的 history 保存各次问答；drafts 中保留一个 `type: engine` 的类型化封装，
  其中存来源、证据草稿、错误、摘要/开放获取与转载元数据。其余 drafts 归 UI 所有。
  不升级格式，不把未保存研究加入 undo 栈。来源 ID 包含会话命名空间，防止两个会话
  把不同正文同时写成同一个 sourceId/version；会话内按 URL/DOI 去重。
- 网络/平台异常暴露稳定原因码；磁盘写入失败可通过 Future 报错，不虚报 done。
  单来源失败不取消其他来源；引擎顺序读取，原生并发固定为一。

## 时限与取消

默认 AI 总阶段 90 秒，搜索 30 秒，每个来源 30 秒，原生解析 20 秒。
会话层在整个阶段外设置 deadline，包含静默流和 TLS 握手停滞；阶段超时会失效令牌，
后续回调不可更新会话。HTTP/平台取消分别关闭客户端和停止/释放 WebView。

**P2-A1 已知限制仍存在**：Dart `SecureSocket.secure` 握手中的底层 socket 无法可靠立即释放。
会话层超时保证 UI/状态不被无限挂住，不宣称远端计算立即停止，也不宣称该 socket 立即回收。
流的 cancel Future 同样不能阻塞终态；已失效响应没有写入权限。

## 提取与安全

1. `ResearchHttp` 获取文档，逐跳验证 URL/DNS、固定目标 IP，拒绝非 HTTP(S)、私网和凭据 URL。
   正文提取禁止启用本地 API endpoint 例外；最终响应 URL 用于相对链接解析。
2. Dart 把有上限的 HTML 和打包的 Readability 0.6.0 交给方法通道。
   WKWebView 仅加载本地空文档，使用非持久化数据存储、全请求 content blocker 和 CSP。
   页面在 detached DOMParser 文档中解析，网页脚本不执行，子资源全部禁用，远程导航全部拒绝。
   即使文档请求了私网图片、样式、iframe、视频或 meta refresh，也不能发出请求。
3. Readability 返回正文 HTML；`mm_research` 转换为 Markdown，保留标题、列表、表格、代码、链接和
   图片说明（不保存远程图片 URL）。危险 HTML/协议不进入阅读正文。
4. 段落 ID 为内容 SHA-256 + 重复序号。快照用带长度的 Markdown 注释标记定位段落，
   不把代码中伪造的段落标记当成结构。快照仍写入 `research/snapshots/<sha256>.md`。
   相同内容复用版本，新内容增加版本，旧证据永远引用旧版本。
5. 相同 URL / DOI 合并；显式 canonical 转载候选合并到已知来源并保留 aliases。
   已有快照版本的来源不重写 ID，避免破坏已保存证据。仅标题相近不合并。
6. URL 引用只产生来源。网页候选摘录必须在本地快照中逐字匹配才生成 Evidence；
   资料引用验证固定版本与段落，编造摘录、未知索引丢弃，不联网丢弃全部引用。

保守模式不执行站点 JS，因此脚本生成正文、登录后正文、PDF 下载地址可能无法提取。
登录页只有检测到密码表单且缺少足够正文才标记 login_required；其他解析失败不猜测登录限制。
支持 UTF-8/ASCII HTML；其他明确编码和无效 UTF-8 返回 unsupported_encoding，避免把乱码当原文。
错误包括 timeout、unavailable、login_required、unparseable、unsafeUrl、unsupported_content、unsupported_encoding。
UI 负责 ARB 映射与“打开原网页/粘贴正文/保存链接”操作。

## 来源与缓存

读取状态固定为 `unread / snippet / abstractOnly / fullText / transcript / failed / noTranscript`。
字幕采集不在本任务范围。OpenAlex 恢复摘要倒排索引，记录作者、DOI、日期及开放获取信息；
开放获取不代表已读全文。论文摘要也保存为快照，可用于资料回答，但状态始终是 abstractOnly；
读取全文后才提升为 fullText，旧摘要证据仍引用旧版本。API 支持可选 Bearer key；默认匿名，服务拒绝时明确报错。
搜索协议测试使用固定响应，不声称已验证模型服务账号。

原始 HTML 可写入应用支持目录 `research-cache/<url-sha256>.html`；显式读取仍重新联网。
缓存失败不阻断正文阅读。`ResearchWebCache.clear()` 只删除该目录，不遍历 Library 包，
绝不删除会话、已保存笔记或正文快照。WebView 临时数据随任务释放。
目前不做保留快照垃圾回收；因此失败/取消时留下未引用快照也不会误删已有引用。

## 验证

- 替身：过期事件、冻结原点、取消、无终止信号、静默超时、断网、单来源失败、启动屏障、
  重复保存、快照校验、引用验证、追问、URL/DOI/canonical 去重、缓存清理。
- 20 个 Mozilla 上游录制 HTML：4 中文、16 英文。实际 WKWebView 输出与上游 expected.html
  的正文逐字比对（忽略空白）。manifest 记录源地址、校验值和导入日期；原始录制日期未知。
- 原生私网 trap 验证子资源无连接、网页脚本未执行；原生/Flutter 通道覆盖取消和错误路径。
- Dart 负责 Markdown 结构、危险链接清理、稳定段落编号及伪造标记回归。

协议依据：[OpenAlex API](https://help.openalex.org/api/)、
[认证](https://help.openalex.org/api/authentication/)、
[Readability 0.6.0](https://github.com/mozilla/readability/tree/0.6.0)。

本地实测（2026-10-27）：匿名 OpenAlex `machine learning` 检索返回 2 篇论文，
其中 1 篇有摘要、2 篇有开放获取状态；使用生产安全 HTTP 与搜索实现。
这不代表真实 Anthropic/OpenAI 模型服务已验证。
