# ADR 0002：受控客户端助手工具

状态：按 GUL-528 已确认方案实施。日期：2026-10-27。替代 ADR 0001 中“不打包 Agent SDK / 一律拒绝客户端工具”的条款；GUL-532 已移除旧研究会话引擎，保留内置搜索协议、安全传输、正文提取与历史数据。

## 决策

新增纯 Dart mm_assistant，固定 dart_agent_core 2.1.8（MIT）。允许白名单读工具、受限制的内存 Skill 激活和只生成待确认提议的 propose_map_edits。未知工具、删除、改原文拒绝；不启用 MCP、脚本、文件系统 Skills、规划、子 Agent。DefaultLoopDetector 不注入 LLM，避免隐式诊断请求。

Policy → Proposal → Citation。框架 defer 仅合成结果，因此 afterToolCall 显式 stop。图修改必须由 UI 确认后经 MapEditExecutor 事务执行，baseRevision、proposalId 幂等和持久执行凭据是接口硬约束。真实写操作/撤销及笔记双位置保存由 GUL-531 接入。

框架三个供应商的 maxRetries=0；受控 Dio 仅重试收到的 429/5xx 两次，遵守同一总期限，取消退避立即结束。网络异常、流后失败、空响应、无终止标记不重发。CheckedLLMClient 在框架重试空响应之前失败；SDK 命名日志器关闭，避免原始正文/工具参数进入日志。Responses store=false、autoPreviousResponseId=false；无远端响应链隐式恢复。

API 使用 UrlPolicy 的已验证数值 IP 连接、原主机 TLS 校验、禁用代理和重定向，路径必须与配置的完整 endpoint 一致。Ollama 仅保留显式启用的 loopback endpoint；网页策略不共享该例外。GUL-532 已接入 Ollama 配置与本机重试路径；真实传输用 loopback 假服务验证，不声称已测试实际安装的模型。

## 联网与证据

统一客户端 web_search 只发现候选 URL：Claude/Responses 的真实后端将复用 mm_research 的供应商搜索，仅取标题/URL/摘要，丢弃结论和供应商引用；compatible/Ollama 走可配置 SearXNG，没配置则 unavailable。第一批正式接入必须提供前两者的默认可用路径，不能把“服务未配置”作为其默认产品行为。

用户显式配置的 SearXNG 仅对同一 origin（scheme、host、port）放行本机与局域网地址；该例外不传给 fetch_source、OpenAlex 或其他请求，搜索结果仍按公网地址策略校验并丢弃内网 URL。

证据独立来自 fetch_source 的本地安全抓取、已提交快照及段落编号；OpenAlex 元数据也可引用，但不得假称全文。接口与 MemoryAssistantNetwork 由 GUL-528 提供；GUL-532 接入真实搜索、抓取和快照后端。联网关闭不注册联网工具且 Policy 二次拒绝，无隐式供应商回退。

page 标记绑定本轮主文档；其他文档为本地 source。只接受本轮真实读过的页/快照登记，流式缓冲未闭合标记，最终再次校验。外部内容是数据，不得扩大读取授权。

## 持久化与应用契约

见 [assistant-architecture.md](../assistant-architecture.md)。每学习集独立 ConversationStorage，原子替换和串行写；running 恢复成 interrupted，不重发。ResearchNote 新增可空 conversationId，不升级文件格式。UI 订阅 Riverpod 不可变 Conversation；本阶段不接 UI、不删除旧研究功能。

## 包体积与验证

测量口径：同机 Flutter Release macOS；递归累计 .app 所有文件的 st_size（包含框架版本符号链接对应文件），同时单列 App.framework；不是压缩下载大小。基线 main e13a264。三组结果见下表，测量入口为正常 lib/main.dart 和 benchmark/assistant_size.dart；探针保留真实供应商工厂并执行一个假 LLM 的离线 StatefulAgent 回合，不联系模型服务。

| 组 | .app 字节 | App.framework 字节 |
| --- | ---: | ---: |
| 无新依赖基线 | 134423152 | 45811874 |
| 声明依赖，正常入口未使用 Agent | 139868952 | 45844567 |
| 真实 Agent/供应商工厂可达的离线探针 | 140787352 | 46762967 |

实际可达探针相对基线 .app 增加 6,364,200 字节（4.73%），App.framework 增加 951,093 字节（2.08%）；相对依赖组 AOT 增加 918,400 字节。当前增量可接受，保留上游固定版本，不引入 third_party 裁剪维护成本。不能把第二组的 tree shaking 结果当作完整接入成本。

真实账号联调未执行；确定性录制来自假客户端。框架录制器不支持 stream 录制，因此 record/replay 用 generate 模式，流式路径另测。继承 ADR 0001 的远端计费、TLS 握手取消限制。完整命令和覆盖率在 PR 与交付评论记录。
