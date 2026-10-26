# GUL-511 格式 6 验证

2026-10-26，Mac mini（arm64），macOS 26.6.2，Flutter 3.47.2。修改前为 main `09c588f`，修改后为本 PR。

## Release 对照

两版均由 `flutter build macos --release` 构建。使用独立 bundle ID
`io.github.mylxsw.marginmind.review511fresh`，数据来自 `packages/mm_data/test/fixtures/format-5.json`，
PDF 为项目示例 PDF 复制到 120 页，仅用来验证阅读位置与资源引用。

**验证限制**：保留沙盒 entitlement 的临时重签名应用在系统 `_libsecinit_appsandbox` 初始化等待，
main 基线也可复现。此次 GUI 使用去掉沙盒签名的临时 Release 副本、独立 Application Support 目录完成；
仓库的 Release entitlements 和发布签名流程均未修改。以下结果不代表已验证正式沙盒包启动。

| 验证 | 结果 |
| --- | --- |
| 格式 5→6 | 所有旧 content 字段逐项一致，新增空 `reviewLogs` / `memoryStates` |
| 原始备份 | `studyset.json.format-5.bak` 与固定格式 5 JSON 字节一致 |
| 资料库 | 修改前后均 2 张待复习、阅读到第 42 页，卡片与星标保留 |
| 实际评分 | 进入复习→显示答案→Good，追加唯一日志，间隔 3→7.5 天；SM-2 结果不变 |
| 退出重开 | 评分后的 JSON 字节、日志、文件及备份修改时间均不变，无再次迁移 |

[修改前](before.png) · [迁移后](after.png) · [评分后](after-rating.png)

原始落盘证据：[迁移后 JSON](after-migration.json)、[评分后 JSON](after-rating.json)。

## 自动检查

- `dart format --set-exit-if-changed apps packages`：182 个文件，无变化。
- `flutter analyze`：无问题。
- `python3 -m unittest discover -s tool/tests`：11 项通过。
- `python3 tool/coverage.py`：七个套件全部通过，总覆盖率 92.85%；mm_core 96.54%，mm_data 96.81%。
- 对照 `git diff --unified=0` 与合并 LCOV，新/改动可执行行 70/70（100%）。
- `xcodebuild test`：4 项原生测试通过。
- 修改前后的 `flutter build macos --release` 均成功。

领域测试覆盖所有评分、重复评分、首评、未知卡片、记忆状态替换、三种 phase、暂停/恢复、
序列化、删除/撤销保留日志与记忆状态。迁移测试覆盖固定格式 5 的全部字段、30 天到期队列不变、
字节备份、连续两次重开不改写、中断恢复、备份冲突及新数据写盘重开。
