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
| 全屏往返 | 全屏下 Flutter 顶部工具栏保持可见；通过系统 AX 接口退出后原生工具栏和按钮恢复 |
| 侧栏 | 收起后顶部预留按钮位置，重新展开后恢复侧栏；顶部开关仍可点击 |
| 空白区域 | 侧栏顶端拖动使窗口位置变化；双击缩放到 1512×864，再次双击恢复 |
| 浅色 / 深色 / 失焦 | 两种外观下按钮可见；系统浅色下切换至 Finder 后，按钮变灰 |

真实坐标点击通过 CGEvent 注入，按钮状态通过系统 AX 属性读取；没有用 AXPress 代替按钮点击。
修改前后点击录屏随 Multica 交付评论附上。全屏顶缘悬停唤出按钮的自动化操作受系统菜单跟踪影响，
请评审时再人工复核一次全屏下的悬停图标及绿色按钮退出动作；不将这部分计为完整人工验收。

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
- `python3 tool/coverage.py`：七个测试套件全部通过，总行覆盖率 90.64%。
- `desktop_window.dart`：27/27 行覆盖；`mm_platform`：82/82 行覆盖。
- `xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=macOS' -enableCodeCoverage YES`（应用目录）：通过。
- 新增 Swift 工具栏外观、全屏通知和资源清理方法及闭包：行覆盖率均为 100%。
- `flutter build macos --release`：通过。

原生测试覆盖三个系统按钮在窗口调整大小后的命中、保持系统布局、工具栏背景移除、
全屏往返、原本隐藏的工具栏、无工具栏和未配对退出通知。macOS CI 已加入同一原生测试命令。
