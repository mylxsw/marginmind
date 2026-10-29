# GUL-552 逐段对照验证

AI 对照复用 CompareView、布局快照、标题条与栏缝。目标语言随当前文档在中文 / English 间切换；模型未配置、离线云模型、未识别扫描件显示禁用原因。已有完整段落缓存可离线查看，无需重新连接模型。识别结果变化会更新菜单判断，封面无文字时继续检查正文。

段落切分版本为 1。指纹包含文档身份、整份提取内容与原始字符框的摘要、页码、段落序号、规范化文本与版本。零大小空格框不参与换行判定，避免 PDFium 把单词拆成段落；实际字形的纵向范围用于识别视觉行。标题 / 行距 / 缩进 / 页界决定段落边界。

TranslationSession 使用两路并发、可见段落优先、阅读线附近预取与缓存键去重。所有请求共享 ResearchBudget 的输入、输出、响应字节与截止时间；输出额度在发送前预留，失败请求仍计账。直接模型调用使用助手默认服务与钥匙串，工具列表为空，沿用安全端点和有界重试适配器。未完成、截断、取消和写盘失败的结果不会成为成功缓存。退出、换文档、换语言和销毁使旧 generation 失效，仓储原子 update 内再次检查，避免迟到写入。

缓存只标记一个模型来源。改默认模型不会丢弃已保存译文；部分缓存与新模型不一致时，显式点“重试”才删除旧缓存并重新翻译，避免把不同来源混在同一个 model 下。离线时不执行该删除。

译文按页重排，跟随阅读配色；占位微光、进度、已保存、失败重试及双侧悬停均由生产界面呈现。完成不弹 HUD。同步按段落及段内比例，使用原始 PDF 坐标；用户接管使旧滚动驱动失效。占位替换保留阅读线所在段落的位置。译文可选中后摘录或高亮，正文保留所选译文，出处使用原文文档、页码和段落矩形；不提供批注入口。

## 原生复现

在 `apps/marginmind` 运行：

```sh
flutter run -d macos -t example/translation_acceptance.dart
```

该入口使用生产 ReaderPane、PDFium 与真实原创 PDF；只有模型替换为延迟返回的确定性测试替身。不访问网络、钥匙串、用户文档或用户偏好，学习集与缓存存于内存。截图通过 Mac mini 的真实窗口捕获，覆盖翻译中、已保存和悬停联动。

## 自审

检查了菜单到保存 / 离线重开 / 退出恢复的完整链路，空文档与扫描件、模型和存储失败、预算与取消、迟到结果、滚动回环、PDF 句柄及网络连接释放、工具执行与敏感信息、文案及数据模型一致性。

实机发现并修复零大小空格框引起的按词切段；全量回归发现并修复段落覆盖层破坏已有高亮 LRU 列表复用。另修复切换左栏后的目标语言、重试时进度状态、可见范围内按阅读线距离排序、原文主动输入接管，以及 OCR 副本与图片封面的菜单判断。相关回归覆盖段落、调度、缓存和实际界面交互。凭证检查只在 AI 菜单打开后执行，保留“打开 / 重开学习集不读钥匙串”的既有隐私边界；标题识别与页脚去重也补有测试。

## 最终验证

- `dart format --set-exit-if-changed apps packages`：445 个文件，0 改动，退出码 0。
- `flutter analyze --no-pub`：无问题，退出码 0。
- `python3 -m unittest discover -s tool/tests`：17 项通过。
- 纯 Dart 包 `dart test --coverage=coverage` 后以 `coverage:format_coverage` 生成 LCOV：mm_core 190、mm_research 62（另跳过 1）、mm_assistant 165、mm_layout 21、mm_data 41，全部通过。
- Flutter 包 `flutter test --no-pub --coverage`：mm_design 139、mm_platform 29、mm_pdf 105，全部通过。
- 应用完整复跑：按 `app-test-groups.json` 把全部 80 个测试文件分成不重叠的两组，逐组运行 `flutter test --no-pub --no-test-assets --coverage --coverage-path=coverage/group-N.info --concurrency=4 <该组文件>`。第 0 组 338 项通过、9 项按条件跳过；第 1 组 317 项通过；两组均退出 0，合并 LCOV 后覆盖完整应用。
- `python3 tool/coverage.py --report-only --minimum 80`：整体 91.27%；改动可执行行 630 / 707，89.11%。详见 `coverage.md`、`changed-coverage.json`。
- macOS `flutter build macos --debug --no-pub -t example/translation_acceptance.dart`：退出 0；真实 PDFium 渲染，输出 `NATIVE_TRANSLATION_SAVED paragraphs=27`。

单次应用全量曾显示 655 项通过、9 项跳过并生成覆盖率后由执行器返回 143；最终用上述文件分组复跑，取得两组明确的退出码 0。测试内容没有放宽或删减。

## macOS 截图

- [翻译中 8/27，保留占位](01-translating.png)
- [27 段全部完成，已保存](02-saved.png)
- [悬停译文，原文对应段落同时高亮](03-hover.png)

截图为 Mac mini / Flutter 3.47.2 Debug 的真实窗口捕获（1568 × 975），没有图片合成。已停止本次验收进程。
