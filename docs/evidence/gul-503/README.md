# GUL-503 脑图视图验证记录（2026-10-26）

修改前的截图来自体验审查（`b24198e`，v0.5.0）；修改后使用本分支的 Release 构建（按 `Release` 工作流签名，临时 bundle ID `io.github.mylxsw.marginmind.review503`），在 Mac mini（Apple 芯片）上运行。资料库预先写入一个学习集：8 章、约 60 个节点，第 1 章下挂 3 张没有标题的摘录（两张超过四行）。

| 编号 | 修改前 | 修改后 |
| --- | --- | --- |
| U-M1 滚轮平移 | [滚轮把比例从 60% 缩放到 150%](../../ux-audit/08-map-wheel-zoom.jpg) | [滚轮向下滚 10 行：画布上移，比例仍为 60%，图的底部进入视野后停住](after-wheel-pan.jpg)；[录屏](wheel-pan.mp4)：滚轮上下、横向平移，比例始终 60% |
| U-M2 平衡布局与适应窗口 | [适应窗口缩到 10%，一条细长竖列](../../ux-audit/07-map-fit-large.jpg) | [第 1～3 章在右，第 5～8 章在左](after-balanced-cards.jpg)；[适应窗口：放不下时停在 60%，以中心主题为中心](after-fit.jpg) |
| U-M3 精简摘录卡片 | [三层：标题、正文、来源](../../ux-audit/17-map-cards.jpg) | [只有摘录文字](after-balanced-cards.jpg)；[选中后来源显示在卡片右侧](after-source-selected.jpg) |
| U-M4 省略号 | [第四行直接截断](../../ux-audit/17-map-cards.jpg) | [超过四行的两张卡片末尾有“…”](after-balanced-cards.jpg) |
| U-M5 插入位置 | 面板标题下一行“新摘录 → …” | [面板标题下没有说明文字；选中“第 2 章”后插入标记移到它的右上角](after-excerpt-target.jpg)；[选中摘录时标记在它的父主题上](after-source-selected.jpg) |

## 真机上发现并修复的问题

- 最初把悬停 / 选中时的来源放在卡片下方，真机上压住了下一张兄弟卡片的上沿；改为放在卡片外侧（右侧分支在右，左侧分支在左，避开折叠按钮）。

## 自动化做不到的部分

桌面自动化发出的是合成滚轮事件，没有物理触控板手势，也收不到修饰键，所以 ⌘ + 滚轮缩放、触控板捏合与双指滑动、⇧ + 滚轮由 `map_view_test` 覆盖，并列为 [macOS 验收清单](../../macos-acceptance.md) 中“GUL-503：脑图视图人工验收”的人工项。

## 检查命令

- `flutter analyze`、`dart format --set-exit-if-changed apps packages`：通过。
- `python3 tool/coverage.py`：七个测试套件全部通过，总行覆盖率 92.00%；本次改动的行覆盖率 98.89%（356 / 360）。
- E-12 基准：`mm_layout` 500 节点布局 p95 约 0.4～0.5 ms（右向与平衡布局相同，修改前约 0.5 ms，上限 16 ms）；`mind_map_cache_test` 500 节点编辑重排基准通过。
- `flutter build macos --release`：通过。
