# 手机框选与多选验收（2026-11-03）

已实现独立的手机多选模式。入口是导图工具里的“多选”、单个节点“更多”中的“多选”，以及批量操作栏中的补选按钮。选择过程中只修改临时选择，完成后才提交给工作区；取消和安卓返回恢复原来的选择。

## 交互

- 点选：点节点加入或移除，单指平移、双指缩放。
- 框选：单指画矩形，可从节点上开始；松手后保留四角与边框，可继续缩放范围或平移整个框。
- 连续框选：保留前几轮选择；缩小当前矩形只撤回本轮新增节点。切回点选后可逐个排除。
- 导航：双指移动／缩放画布，矩形保存在导图坐标中；加入第二根手指时撤回未完成的一笔。
- 跨屏：在画布边缘停留后自动平移，可将原屏幕外的节点纳入范围。
- 完成：提交临时选择并显示批量操作；取消：保持原工作区选择。

选择模式屏蔽底层节点的长按移动、菜单、编辑和宽度拖动。读屏用户通过单独的节点选择操作修改同一份临时选择。顶部保留取消、计数和完成；底部只放点选／框选和清空，批量操作在完成之后出现。

四角采用 44 点触控范围；框选手势使用较小的移动门槛，允许 iPhone 上的小幅微调。控制栏避开横屏刘海与手势区域。选择状态由工作区范围内的临时控制器保存，屏幕旋转、画布重新挂载后保留。

## 真实应用模拟器截图

| 状态 | iPhone | Android |
| --- | --- | --- |
| 进入多选 | [浅色](iphone/light-01-selection-mode.png) | [浅色](android/light-01-selection-mode.png) |
| 松手保留选择框 | [浅色](iphone/light-02-box-with-handles.png) / [深色](iphone/dark-02-box-with-handles.png) | [浅色](android/light-02-box-with-handles.png) / [深色](android/dark-02-box-with-handles.png) |
| 缩放后保留范围 | [截图](iphone/light-03-zoom-preserves-frame.png) | [截图](android/light-03-zoom-preserves-frame.png) |
| 点选排除 | [截图](iphone/light-04-refine-by-tapping.png) | [截图](android/light-04-refine-by-tapping.png) |
| 完成并进入批量操作 | [截图](iphone/light-05-completed-selection.png) | [截图](android/light-05-completed-selection.png) |
| 横屏继续选择 | [截图](iphone/landscape-selection-controls.png) | [截图](android/landscape-selection-controls.png) |

两端每种主题均实际执行了从节点上开始画框、小幅拖动右下角扩大范围、双指缩放、点选排除、返回取消、重新进入后完成，以及从批量操作栏继续补选。横屏额外验证取消、完成和清空按钮均可点击，并能退出选择。iPhone 的横竖屏切换由原生 XCTest 完成；Android 返回由 adb 实际发送系统按键。

`source-proof.json` 保存最终业务源码指纹和截图校验值。每个平台的 `run.log` 与 `build-source.json` 记录实际构建及运行结果。截图中的测试触点若出现，属于自动化指针，不是应用控件。

## 自动检查

- Flutter analyze：无问题。
- 9 个相关测试文件：86 项全部通过。覆盖临时选择与取消、画框与修正、连续累加、点选、50%／100%／200% 缩放、双指打断、系统取消、跨屏自动平移并选中远处节点、读屏选择、320 点窄屏与横屏深浅色布局，以及完成后恢复拖动。
- 工作区用例同时验证原有选择不会被临时操作覆盖、屏幕旋转保留选择控制器、混合摘录选择可以再次进入多选。
- 回归包含节点拖动、落点、节点工具栏、原有鼠标框选、批量拖动、剪贴板与单步撤销，以及手机／平板／桌面布局。
- 修改文件格式及 `git diff --check` 通过。

未安装到实体手机；触感及真实手指遮挡体验仍需真机确认。验收使用内置示例文档，没有调用付费 AI。

## 复现

在 `apps/marginmind` 运行：

```sh
flutter test test/phone_map_selection_test.dart test/phone_map_selection_workspace_test.dart test/map_drag_test.dart test/map_drop_test.dart test/map_node_bar_touch_test.dart test/map_node_bar_test.dart test/phone_layout_test.dart test/mind_map_canvas_test.dart test/map_selection_clipboard_test.dart
```

两端截图由 `tool/capture_mobile_redesign.py` 运行 `mobile_map_selection_acceptance_test.dart` 采集。Android 使用 OpenJDK 21；iOS 原生横屏自动化使用系统 Ruby。详细交互规则见[手机导图选择方案](../../../design/phone-map-selection.md)。
