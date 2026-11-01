# 工作区 Tab 实际界面

[设计验收](design-qa.md) · [测试与基线](regression.md)

| 文件 | 内容 |
| --- | --- |
| source-approved.png | 用户确认的最终设计稿 |
| comparison-final-full.png | 确认稿与实际窗口同画布比较 |
| comparison-final-chrome.png | 顶部 Tab、主阅读器与 AI 入口局部比较 |
| states-final.png | 五种实际状态总览 |
| document-reference-light.png | 共用文档/脑图 Tab 与笔记参考 |
| document-tags-light.png | 标签右侧内容栏 |
| document-assistant-light.png | 浅色 AI 内容栏 |
| document-assistant-dark.png | 深色 AI 内容栏 |
| note-reference-dark.png | 独立笔记 Tab 与原文参考 |

截图由原生 Flutter 集成测试输出；资料、笔记、标注和脑图使用本地临时场景，AI 使用脚本回答。

复现：在 `apps/marginmind` 下运行 `flutter test --no-pub integration_test/workspace_tabs_visual_test.dart -d macos --reporter expanded`。设置 `WORKSPACE_TAB_SHOT_SERVER` 编译参数可将 PNG 上传到本地接收器；未设置时只验证流程，不输出截图。
