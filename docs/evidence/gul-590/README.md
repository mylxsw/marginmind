# GUL-590：AI 整理流程验收

四张 PNG 来自 macOS 原生应用窗口（按应用 PID 捕获），由假的 `NoteOrganizer` 驱动，无需模型 Key：

- [确认提纲](outline.png)
- [生成中](generating.png)
- [AI 标记开](ai-on.png)
- [AI 标记关](ai-off.png)

复现：`python3 tool/study_notes_evidence.py --ai --output docs/evidence/gul-590`。
集成测试导入临时 Markdown、建立两条划线，然后完成提纲确认、逐节生成与标记切换。

`test/study_notes_ai_ui_test.dart` 覆盖默认档位与记忆、提纲移动与排序、批注随划线移动、
停止后的迟到结果、断点续写、失败回退、解释与改写、三种声音、加锁、跨节跳转、复习卡出处与重新整理。
`mm_assistant` 的续写测试核验跳过已完成节时保留全局关联索引。

生成预览逐节展示已校验的结构化结果，不发布未校验的 JSON 片段。
停止时笔记正文落盘；断点与素材字典保留在当前应用会话，可从提示条或笔记继续。
真实模型质量与真实 Key 的端到端验收留到最终验收，符合任务讨论中的授权。

原生窗口测试在截图测试之后运行时，需覆盖截图测试留下的临时 Flutter 入口：

```bash
cd apps/marginmind
xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Debug -destination 'platform=macOS' \
  -enableCodeCoverage YES FLUTTER_TARGET=lib/main.dart
```
