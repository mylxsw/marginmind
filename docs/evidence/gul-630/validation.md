# 验证记录

基线：6dacccc（本运行检查时 origin/main 同一提交）。

通过：flutter analyze；dart format --set-exit-if-changed apps packages；flutter gen-l10n；mm_design 材质测试；应用 Gallery 测试；393×852 浅深色截图生成；git diff --check；原型与附件逐字节一致。

全仓 `python3 tool/coverage.py` 的应用测试共 1187 通过、34 跳过、10 失败。在独立、未修改的基线 worktree 中执行 `flutter test test/workspace_chrome_test.dart test/study_notes_ai_ui_test.dart` 复现其中相同 5 个失败：

- study_notes_ai_ui_test：Android compact AI setup 找不到 note-preview-outline。
- workspace_chrome_test：phone reader/map dock 在 393/402 宽度的 items 保持断言失败（4 项）。

这些页面和测试未由本任务修改。初次交付时 PR 保持草稿；后续验收确认这 10 项基线失败不阻塞本任务，但仍不能描述为全仓检查通过。

另在同一基线执行 `flutter test test/note_rich_export_test.dart`，复现纸张/简洁/夜读分享卡的 3 个 golden 尺寸不匹配；执行 `flutter test test/liquid_glass_test.dart` 复现 iPhone/Android 标签栏 2 个断言失败。全仓共 10 个失败均在未修改基线复现。

`python3 tool/coverage.py --report-only` 汇总现有报告为 91.57%（46872/51185），mm_design 为 89.06%。这只表示覆盖率达标，不抵消测试失败。按 git diff 新增行与 LCOV 交集统计，变更可执行行 72/72（100%，含本地化生成行；不含生成行 64/64）。

最终针对性复跑：mm_design 的 `flutter test test/phone_glass_test.dart test/liquid_glass_test.dart` 27 项通过；应用 `flutter test test/gallery_test.dart` 2 项通过。

## Review 后 Linux golden 修正

Ubuntu 24.04.5 x86_64 容器、Flutter 3.47.2（d3b14c876900e553bc736ca19295fc09e3853e8e）、Dart 3.13.2：修复前精确复现浅色 1875px、深色 1797px 差异。差异集中在默认测试字体与圆角边缘。改为按宿主选择 `goldens/linux` / `goldens`，在上述 Linux 环境重新生成基线；保留 macOS 基线和严格比较容差。

容器内工作目录为 `packages/mm_design`，执行：

```sh
flutter test --no-pub test/phone_glass_test.dart --update-goldens
flutter test --no-pub test/phone_glass_test.dart test/liquid_glass_test.dart --coverage
```

验收负责人确认既有基线失败不阻塞交付；本次修复仅调整测试基线和文档，不修改产品代码。PR 转为 Ready for review，任务进入 in_review，不等待 CI。

复验结果：Linux 上述严格比较与兼容性测试 27 项通过（exit 0），macOS `flutter test test/phone_glass_test.dart` 8 项通过；`flutter analyze`、`dart format --set-exit-if-changed apps packages` 和 `git diff --check` 均通过。
