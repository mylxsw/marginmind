# GUL-494 原生窗口按钮验证

2026-10-26，远程 Mac mini（Apple 芯片），macOS 26.6.2、Xcode 27.1、Flutter 3.47.2。
修改前基于 `b24198e`，修改后使用本分支的 Release 构建；验证应用使用独立 bundle ID
`io.github.mylxsw.marginmind.review494`，重签时保留 Release 沙盒 entitlements。

## 结果

| 检查 | 实测结果 |
| --- | --- |
| 修改前三个按钮 | 真实坐标点击关闭、最小化、绿色按钮，窗口仍为 1200×800，未最小化或进入全屏，进程仍在 |
| 最小化 | 点击黄色按钮，系统 `AXMinimized` 从 0 变为 1；恢复后为 0 |
| 关闭 | 点击红色按钮后，独立验收进程退出 |
| ⌥ 点击绿色按钮 | 从 1200×800 缩放到 1512×864，保持非全屏；再次点击恢复原尺寸 |
| 绿色按钮 | 坐标点击进入全屏，系统 `AXFullScreen` 从 0 变为 1 |
| 全屏往返 | 顶缘唤出系统按钮并悬停显示关闭 / 退出图标；真实点击绿色按钮退出，位置与尺寸恢复；复审时已补齐录屏 |
| 侧栏 | 收起后顶部预留按钮位置，重新展开后恢复侧栏；顶部开关仍可点击 |
| 空白区域 | 侧栏顶端拖动使窗口位置变化；双击缩放到 1512×864，再次双击恢复 |
| 浅色 / 深色 / 失焦 | 两种外观下按钮可见；系统浅色下切换至 Finder 后，按钮变灰 |

真实坐标点击通过 CGEvent 注入，按钮状态通过系统 AX 属性读取；没有用 AXPress 代替按钮点击。
修改前后点击录屏随 Multica 交付评论附上。复审时补齐了全屏顶缘悬停、绿色按钮退出和进入动画验证，见下节。

## 截图

- [修改前](before.png)
- [修改后深色](after-dark.png)
- [修改后浅色](after-light.png)
- [浅色失焦](after-inactive.png)
- [全屏内容](after-fullscreen.png)

## 自动化检查

- `dart format --set-exit-if-changed apps packages`：通过。
- `flutter analyze`：通过，无问题。
- `python3 -m unittest discover -s tool/tests`：3 个测试通过。
- `python3 tool/coverage.py`：七个测试套件全部通过，总行覆盖率 90.62%。
- `desktop_window.dart`：25/25 行覆盖；`mm_platform`：80/80 行覆盖。
- `xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=macOS' -enableCodeCoverage YES`（应用目录）：通过。
- 新增 Swift 工具栏外观、全屏通知和资源清理方法及闭包：行覆盖率均为 100%。
- `flutter build macos --release`：通过。

原生测试覆盖三个系统按钮在窗口调整大小后的命中、保持系统布局、工具栏背景移除、
全屏往返、原本隐藏的工具栏、无工具栏和未配对退出通知。macOS CI 已加入同一原生测试命令。


## 复审补测与修复（2026-10-26）

在 GUL-497 基准进程结束后使用独立名称的 Release 应用做对照，避免切换 Space 干扰基准。

| 项目 | 实测与修复 |
| --- | --- |
| 搜索框拖选 | 旧版从 (116, 52) 移到 (232, 52)，选区不连续。修复后同一路径选出连续文字，窗口仍在 (116, 52) |
| 搜索框右键 | 旧版可弹出 Cut / Copy / Paste；新版仍可弹出，不显示 AppKit 工具栏的显示模式菜单 |
| 滚轮与其他控件 | 单行搜索框在两版中对横向滚轮均没有可见滚动效果，窗口不移动；现有顶栏没有其他依赖拖动 / 右键 / 滚轮的控件（空白区窗口拖动除外）。原生测试验证滚轮及完整指针序列原样到达 Flutter 的事件接收者 |
| 空白区拖动 / 双击 | 修复后从 (116, 52) 拖到 (174, 73)；双击缩放到 1512×864，再次双击恢复 1280×820 |
| 全屏悬停 | 向屏幕顶缘移动后系统标题栏滑出；悬停绿色按钮，截图可见关闭 × 与退出全屏图标。黄色按钮由 AppKit 按全屏规则置灰禁用 |
| 绿色按钮退出 | 全程真实坐标点击，AXFullScreen 0→1→0；窗口从 (116, 52)、1280×820 恢复到相同位置与尺寸，没有使用 AX 接口退出 |
| 进入动画 | 旧实现录屏中有短暂不透明横条。改为 willEnterFullScreen 时隐藏后，抽帧可见 Flutter 顶栏持续显示，横条消失 |

使用自己的 `FlutterWindowToolbar` 替代插件的 `BlockingToolbar`，显式转发拖动、左右 / 中键及滚轮。
按下事件转发期间暂时关闭 AppKit 窗口移动，返回时恢复原状态；窗口空白区的拖动仍交给 Flutter 命令判断。
转发目标为弱引用；原生工具栏保持不可自定义、无玻璃背景。

提前隐藏工具栏后，进入失败需要额外恢复。`WindowChromeDelegate` 只增加失败恢复，其他可选委托方法转发给原窗口插件；
不替换插件行为、不持有窗口或原委托。新增 XCTest 验证失败恢复、委托方法透传、弱引用和完整事件序列。
三个 XCTest 全部通过，新增 Swift 方法 / 闭包覆盖率均为 100%；最新七套 Dart/Flutter 测试总覆盖率为 90.62%。
分支已 rebase 到包含 GUL-493 的 main。

- [拖选连续选区](search-drag.png)
- [搜索框右键菜单](search-menu.png)
- [全屏悬停图标](fullscreen-hover.png)
- [进入动画修复前抽帧](entry-before.png) / [修复后抽帧](entry-after.png)

复审的全屏前后录屏附在 Multica 回复中。本轮已补齐上次列出的全屏验证项。
