# GUL-524：研究扩展验收

2026-10-27，macOS 本机 Flutter 3.47.2 Debug。`macrun` 不在 PATH 中；使用本机构建、桌面自动化和窗口截图完成验证。
可复现入口：`flutter run -d macos -t benchmark/research_extensions.dart`。它运行真实应用界面，使用隔离的内存学习集、固定论文/视频资料与快照，不读写个人资料。截图中的来源数据是验收 fixture，不是在线搜索结果截图。

- `note-review.png`：研究笔记详情与加入复习开关。
- `review-front.png` / `review-back.png`：通过菜单进入真实复习界面，题面为问题，答案为正文、引用版本和原链接；复用 FSRS 评分按钮。
- `sources.png` / `sources-narrow.png`：作者、年份、DOI、仅摘要/需订阅状态；无字幕视频、链接保存与两个站点的外部搜索入口。

OpenAlex 单独用生产 `OpenAlexSearch` 做匿名真实调用：`retrieval practice` 返回
“Covert retrieval practice benefits retention as much as overt retrieval practice.”，作者 Megan A. Smith / Henry Lederer Roediger III / Jeffrey D. Karpicke，2013，DOI `10.1037/a0033569`，开放获取且有摘要。
这不代表已读取论文全文。协议参考：[OpenAlex 认证](https://help.openalex.org/api/authentication/)。

视频通过外部站点搜索结果页发现，具体链接由用户保存；没有在应用内调用 YouTube/B 站搜索 API，未取得授权字幕，不生成视频总结或时间戳摘录。

本地全量检查：`dart format`、`flutter analyze`、8 个测试套件及覆盖率脚本通过，
总体行覆盖率 **92.33%**，本次变更可执行行覆盖率 **90.68%**（基于 git diff 新行与 LCOV 交集，含新增视频表单）。
测试覆盖隐藏载体、去重排期、关闭保留历史、撤销、原选区恢复、重复启动、视频链接校验、禁止无字幕总结、重复抓取及历史快照定位。

macOS：Debug 构建与 `xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=macOS' -enableCodeCoverage YES` 通过（`TEST SUCCEEDED`）。
