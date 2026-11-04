# 网页转文档的 AI 整理

把网页保存为文档时，可以选择让模型整理抓取到的正文，再保存为阅读模式、PDF 或 Markdown。需求和取舍见 GUL-660，交互原型见 [prototypes/web-ai-format](prototypes/web-ai-format/index.html)。

## 行为

- “保存到资料库”里的 **AI 整理** 开关默认关闭；关闭时流程与原来一致。
- 模型路由不可用时开关置灰并指向设置。任务 `TaskType.webFormat` 属于重型任务，出现在“设置 › AI 功能”。
- 打开开关不会发送内容；点“开始整理”才会。开关下方说明字数、段数和内容的去向。
- 整理时逐段流式显示，可以停止。已完成的段落保留，未完成的保留原始内容。
- 单段失败不影响其他段，可重试或用原始内容。连接、密钥或配置错误会停止整轮，可以继续或直接保存。
- 完成后可预览、编辑、对照原文。手动编辑后不能再按段重新整理，可以还原。
- 有整理内容时关闭弹窗需要确认。第一版整理不转入后台。
- 用户没改过名称时，采用模型给出的干净标题。

## 内容边界

- 只恢复结构，只删除页面杂质（导航、广告、推广等），不改写正文。被删内容在“对照原文”里划线显示。
- URL 换成占位符后才发给模型。校验拒绝未知占位符和输入里没有的链接目标；被一起删掉的链接和图片只提示，不算失败。
- 网页内容按不可信数据处理，任务不开放工具。打印前的 HTML 再过一遍 `WebBookParser.sanitizeHtml`。
- 某段可见文字比原文少 20% 以上或多 30% 以上时提示确认，不阻止保存。

## 保存

- 阅读模式和 Markdown 都由整理后的 Markdown 解析。PDF 文稿打印同一份 Markdown，字体用宋体。
- 打印复用当前标签页的原生打印通道：内容放在只对打印可见的 closed shadow root 里，所以没有新增原生代码，页面显示也不变。
- 文档包额外保存 `web/<id>/<version>/formatted.md`，原网页快照照常保存。`DocumentOrigin.formatting` 记录模型、提示词版本、是否编辑过、未整理段数。
- 重新抓取 AI 整理过的文档时不走静默更新，而是打开弹窗并默认打开开关，由用户决定是否调用模型。

## 代码位置

| 内容 | 位置 |
| --- | --- |
| 任务契约、分段、占位符、校验、对照 | `packages/mm_assistant/lib/src/web_formatting.dart` |
| 整轮状态 | `apps/marginmind/lib/features/workspace/web_format_session.dart` |
| 路由与执行 | `apps/marginmind/lib/features/workspace/web_format_runtime.dart` |
| 界面 | `apps/marginmind/lib/features/workspace/widgets/web_format_panel.dart`、`web_conversion.dart` |
| 打印 | `packages/mm_platform/lib/src/browser_document.dart`（`printDocument`） |

原生验收（macOS）：

```sh
MM_WEB_FORMAT_EVIDENCE=1 flutter test integration_test/web_format_test.dart -d macos --no-pub
```

逐屏走查（真实应用、真实抓取和打印，只有模型回复是脚本）：`integration_test/web_format_screens_test.dart`。加 `--dart-define=CAPTURE_UI=true` 后，每个状态会打印 `PHONE_SHOT`，由宿主进程截取真实窗口并回写标记文件。手机上的确认框在正式应用里是系统弹窗，这个测试不初始化原生呈现，所以截到的是共用的 Flutter 弹窗。结果见 [evidence/web-ai-format-review](evidence/web-ai-format-review/README.md)。
