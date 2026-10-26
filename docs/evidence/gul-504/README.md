# GUL-504 阅读器界面验证记录（2026-10-26）

Mac mini（Apple 芯片），macOS 26.6.2，Flutter 3.47.2。修改前为 `main`（`ff231c1` 之后的最新提交）、修改后为本分支，
均为 `flutter build macos --release`，ad-hoc 重签并保留 `Release.entitlements`，独立 bundle ID
`io.github.mylxsw.marginmind.review504before` / `review504after`。资料库为同一份种子（1 个学习集、1 份 2 页 PDF、已有 3 条摘录）。
窗口大小由 `set_window_frame` 设定，点击与拖选由桌面事件注入。

| 编号 | 修改前 | 修改后 |
| --- | --- | --- |
| U-R5 标题与标签栏 | [副标题“学习的科学 · Page 1”，单标签栏重复文档名](before-wide.jpg) | [标题是文档名，副标题只有“Page 1”，一份文档没有标签栏](after-wide.jpg) |
| U-X5 颜色菜单 | [工具栏常驻 6 个颜色点](before-wide.jpg) | [工具栏只留一个当前颜色的按钮](after-wide.jpg)；[点开后弹出六色菜单](after-color-menu.jpg) |
| U-R6 窄窗口（960 pt） | [侧栏仍占位，布局按钮仍选“分栏”，脑图消失](before-narrow.jpg) | [侧栏自动收起，分栏保留，布局按钮选“分栏”](after-narrow.jpg) |
| U-X4 添加笔记 | [居中的模态对话框](../../ux-audit/06-add-note-dialog.jpg) | [选字](after-selection.jpg)后点“添加笔记”：[没有对话框，脑图里直接出现摘录卡片和聚焦的空笔记，可原地输入](after-add-note.jpg) |

## 自动化没覆盖的部分

- U-R4（浮动工具条避开页码胶囊）：种子 PDF 的页面里没有能同时让选区和页码胶囊相邻的位置，真机上未能复现“叠在一起”；
  布局算法由 `floating_toolbar_test`（含两侧都被占用的情形）和 `selection_toolbar_test` 覆盖，列入
  [macOS 验收清单](../../macos-acceptance.md) 的人工项。
- 物理拖动窗口边缘、触控板选字等人工项见同一清单。

## 检查命令

- `dart format --set-exit-if-changed apps packages`：通过（176 个文件，无改动）。
- `flutter analyze`：无问题。
- `python3 tool/coverage.py`：七个套件全部通过，总行覆盖率 92.73%（要求 80%）。
- `flutter build macos --release`：通过（修改前、修改后各一份）。
