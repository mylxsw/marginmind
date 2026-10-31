# 验证记录

基线：6dacccc（本运行检查时 origin/main 同一提交）。

通过：flutter analyze；dart format --set-exit-if-changed apps packages；flutter gen-l10n；mm_design 材质测试；应用 Gallery 测试；393×852 浅深色截图生成；git diff --check；原型与附件逐字节一致。

全仓 `python3 tool/coverage.py` 的应用测试共 1187 通过、34 跳过、10 失败。在独立、未修改的基线 worktree 中执行 `flutter test test/workspace_chrome_test.dart test/study_notes_ai_ui_test.dart` 复现其中相同 5 个失败：

- study_notes_ai_ui_test：Android compact AI setup 找不到 note-preview-outline。
- workspace_chrome_test：phone reader/map dock 在 393/402 宽度的 items 保持断言失败（4 项）。

这些页面和测试未由本任务修改。PR 保持草稿，不能把本次交付描述为全仓检查通过。

另在同一基线执行 `flutter test test/note_rich_export_test.dart`，复现纸张/简洁/夜读分享卡的 3 个 golden 尺寸不匹配；执行 `flutter test test/liquid_glass_test.dart` 复现 iPhone/Android 标签栏 2 个断言失败。全仓共 10 个失败均在未修改基线复现。

`python3 tool/coverage.py --report-only` 汇总现有报告为 91.57%（46872/51185），mm_design 为 89.06%。这只表示覆盖率达标，不抵消测试失败。按 git diff 新增行与 LCOV 交集统计，变更可执行行 72/72（100%，含本地化生成行；不含生成行 64/64）。

最终针对性复跑：mm_design 的 `flutter test test/phone_glass_test.dart test/liquid_glass_test.dart` 27 项通过；应用 `flutter test test/gallery_test.dart` 2 项通过。
