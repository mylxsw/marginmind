# GUL-510 复习范围验证

2026-10-26，Mac mini（arm64），macOS 26.6.2，Flutter 3.47.2。修改前为 main `787cc5c`，修改后为本 PR（rebase 前的 `b6def57`，与最终提交只差 main 上 GUL-507 / GUL-508 的改动）。

## Release 对照

两版均由 `flutter build macos --release` 构建，临时 bundle ID 分别为 `io.github.mylxsw.marginmind.review510before` / `review510after`（只在验证用的副本里改，未提交）。数据来自 v0.6 体验审查的格式 5 学习集（82 张卡片、3 张摘录），给前两张摘录加了标签 `memory`。

**验证限制**：与 [GUL-511](../gul-511/README.md) 相同，保留沙盒 entitlement 的应用卡在 `_libsecinit_appsandbox`（本次 main 基线同样复现），GUI 对照使用去掉沙盒签名的临时 Release 副本和独立 Application Support 目录。

| 验证 | 结果 |
| --- | --- |
| 修改前节点菜单 | 没有复习或暂停入口 [截图](before-node-menu.jpg) |
| 摘录节点菜单 | 只多出“Suspend Card”；叶子节点不显示“Review Branch” [截图](after-node-menu.jpg) |
| 暂停 | 卡片内容半透明，侧栏 Review 3 → 2 [截图](after-suspended.jpg)；大纲中以次级文字色显示 [截图](after-outline.jpg) |
| 分支复习 | 章节主题菜单只有“Review Branch”（主题不显示暂停）；进入后副标题“第 1 章 遗忘曲线 · 2 left”，跳过暂停的卡片 [截图](after-branch-review.jpg) |
| 标签复习 | 侧栏标签右键“Review Tag” [截图](after-tag-menu.jpg)；进入后“memory · 1 left”，带标签但已暂停的卡片不出现 [截图](after-tag-review.jpg) |
| 持久化 | 写盘为 format 6，被暂停的卡片 `suspended: true`；退出重开后资料库 2 张待复习 [修改前](before-library.jpg) · [修改后](after-library-relaunch.jpg) |

## 自动检查

- `dart format --set-exit-if-changed apps packages`：188 个文件，无变化。
- `flutter analyze`：无问题。
- `python3 tool/coverage.py`：七个套件全部通过，总覆盖率 93.00%。
- 对照 `git diff -U0 origin/main` 与合并 LCOV，新/改动可执行行 114/115（99%）。
- `xcodebuild test`（Mac mini）：通过。
