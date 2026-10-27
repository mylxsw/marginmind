# GUL-526 二期最终验收（v0.8.0）

2026-10-27，Mac mini（Apple 芯片），macOS 26.6.2，Flutter 3.47.2。`v0.7.0` 标签与 `main`（`6228314`）、修复分支（`83dbe46`）各自
`flutter build macos --release`，按 `Release` 工作流签名，临时 bundle ID `io.github.mylxsw.marginmind.review526`。逐项结论见
[Mac 真机验收清单](../../macos-acceptance.md) 的“v0.8.0”一节。

## 环境与限制

- **沙盒签名包这次能正常启动**：修复分支的沙盒签名构建打开后得到独立的空容器（`p2-sandbox-empty`），P-2 通过。此前 GUL-511/512 记录的
  `secinit` 卡住没有复现；早期判断“0 个窗口”是 `osascript` 没有辅助功能权限导致的误报。迁移与场景 1～13 仍在去掉沙盒签名的副本上做，
  以便直接读写数据目录核对。
- **没有真实 AI 服务的 Key**：两台机器的环境变量里都没有 `ANTHROPIC_API_KEY` / `OPENAI_API_KEY`。AI 用 GUL-520 的本机替身
  （OpenAI 兼容接口，回答是按请求拼的模板）；论文搜索、正文读取和视频标题是真实网络。
- **钥匙串**：设置里填测试 Key 后，`security` 看到 `io.github.mylxsw.marginmind.research / anthropic` 一项，偏好文件只有 `key.anthropic = true`，
  不含 Key 本身；“移除”后该项被删除。
- 自动化可以在 PDF 上拖选文字（本次已验证），但注入的按键不带修饰键，⌘I / ⌥空格 / ⇧⌘M / ⇧⌘E / ⌃⌘R / ⌘B 仍待物理键盘。
- 系统询问 macrun 访问“其他 App 的数据”和“文稿”时选了“不允许”，所以导出的 PNG 没有回读核对内容。

## 数据迁移（format 6 → 7）

`v0.7.0` 打开 format 5 种子（“学习的科学” 82 张卡、FSRS 旧卡集 360 张）升到 format 6，复习一张卡（简单，16 天后到期）后退出；
换成 `main` 打开：

| | v0.7.0（format 6） | main 首次打开（format 7） |
| --- | --- | --- |
| 待复习 | 评分前资料库显示 56；评分后那张卡 16 天后到期 | 55（`m2-library-migrated`），与评分后一致 |
| `reviews` / `reviewLogs` / `memoryStates` | 1 / 1 / 1；360 / 0 / 0 | 逐项相同（SHA-1 一致） |
| 未来 30 天到期 | 0…第 16 天 1；54、3、5、3、4… | 逐日相同 |
| 文档、卡片、节点、高亮、阅读页码 | — | 相同；只新增空的 `evidence`、`inkStrokes`、`noteAttachments`、`researchNotes`、`researchSources` |
| 备份 | — | 两个学习集都多出 `studyset.json.format-6.bak`，与 v0.7.0 写出的文件逐字节相同 |

## 截图

| 截图 | 内容 |
| --- | --- |
| `m2-library-migrated` | 迁移后的资料库 |
| `13-research-settings` | 研究设置：AI 服务、论文检索、上限、隐私、网页缓存 |
| `01a-launcher` ～ `01g-relaunch` | 场景 1：选区 → 查证 → 真实论文搜索 → 基于资料回答 → 保存到原文和脑图 → 详情改标题，原文浮层同步 → 重启后仍在 |
| `02a-offline-answer`、`02b-node-save` | 场景 2：节点解释标“未联网 · 不附引用”，保存只能加入脑图，默认不进复习 |
| `03a-switch-choice`、`03c-followup-own-session` | 场景 3：进行中再发起时可选“作为新研究 / 加入当前问题”；慢请求的追问落在原会话 |
| `05-image-paste` | C02：粘贴图片成为节点下的图片卡 |
| `07-ink` | C04：画笔工具条与自由线 |
| `08-export-dialog` | C05：PNG / PDF / Markdown / OPML、范围、外观、清晰度 |
| `11a-no-ai-launcher` | 场景 11：未设置 AI 时只能“只搜索”，提示去设置 |
| `12a-review-image`、`12b-review-research-note` | 场景 12：图片卡背面显示图片；研究笔记卡以问题为题面 |
| `p2-sandbox-empty` | 沙盒签名包首次启动，独立容器为空 |
| `fix-video-title` | 修复后：B 站链接显示视频标题；YouTube 在这台机器的网络下直连不通，退回显示网址 |
