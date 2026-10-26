# GUL-512 v0.7 验收

2026-10-26，Mac mini（Apple 芯片），macOS 26.6.2，Xcode 27.1，Flutter 3.47.2。`v0.6.0` 标签与 v0.7.0（7）各自
`flutter build macos --release`，先后以同一个临时 bundle ID `io.github.mylxsw.marginmind.review512` 启动，数据目录相同。
逐项结论见 [Mac 真机验收清单](../../macos-acceptance.md) 的“v0.7.0”一节。

沙盒签名的包在这台机器上卡在 `secinit_appsandbox`（已发布的 v0.6.0 同样如此），所以 GUI 用去掉沙盒签名的 Release 副本，
与 [GUL-511](../gul-511/README.md) 相同。

## 数据

- “学习的科学”：体验审查的 format 5 学习集（1 份 PDF、3 张摘录），在 v0.6.0 里复习一张、评“良好”。
- “FSRS migration cohort”：`packages/mm_data/test/fixtures/fsrs-cohort.json`，360 张带 SM-2 排期的旧卡（逾期、成熟、重学、不同难度系数）。

## 迁移前后

| | v0.6.0 | v0.7.0 首次打开 |
| --- | --- | --- |
| 格式 | 5 | 6，旁边多出 `studyset.json.format-5.bak`（SHA-1 与 v0.6.0 写出的文件相同） |
| 待复习 | 54（评分前，3 + 51）；评分后的那张明天到期 | 53（2 + 51） |
| `reviews` | — | 两个学习集逐项相同 |
| 未来 30 天到期（旧卡集） | 51、3、3、5、3、4、3、4、3、2… | 逐日相同 |
| 其他字段 | — | 文档、卡片、节点、高亮、书签等不变，只新增空的 `reviewLogs` / `memoryStates` |

v0.6.0 的评分预览是 10 分钟 / 12 小时 / 1 天 / 4 天（SM-2），v0.7.0 新卡片是 1 分钟 / 5 分钟 / 10 分钟 / 16 天（FSRS-5）。

## v0.7.0 功能

| 验证 | 结果 |
| --- | --- |
| 暂停 | 摘录节点菜单“暂停复习”，卡片半透明，侧栏复习数 2 → 1 |
| 分支复习 | 章节主题菜单“复习此分支”，副标题“第 1 章 遗忘曲线 · 1 left”，暂停的卡片不出现 |
| FSRS 评分 | 评“简单”：一条日志（间隔 0 → 16 天），记忆状态 S ≈ 15.69、D ≈ 3.22；v0.6 评过的卡片补出 S = 1、D = 5，到期时间不变 |
| 统计 | 评分前没有入口；评分后学习集和资料库侧栏都有“统计”：1 次复习、记住率 100%、未来 30 天 2 张 |
| 重开 | 待复习 51（暂停和已评分的卡片不计入）；没有再迁移，两个 `studyset.json` 与两个备份的 SHA-1 都不变 |

## 截图

| 截图 | 内容 |
| --- | --- |
| [v06-library-seed](v06-library-seed.png) | v0.6.0 资料库，54 张待复习 |
| [v06-rating](v06-rating.png) | v0.6.0 评分预览（SM-2） |
| [v07-library-migrated](v07-library-migrated.png) | v0.7.0 迁移后的资料库，53 张待复习 |
| [v07-suspended](v07-suspended.png) | 暂停后卡片半透明，复习数 1 |
| [v07-branch-review](v07-branch-review.png) | 分支复习 |
| [v07-fsrs-rating](v07-fsrs-rating.png) | v0.7.0 评分预览（FSRS-5） |
| [v07-stats](v07-stats.png) | 学习集统计 |
| [v07-library-relaunch](v07-library-relaunch.png) | 重开后的资料库，侧栏有“统计” |
