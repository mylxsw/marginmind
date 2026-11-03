# 手机导图交互重做（2026-11-03）

轻点节点显示固定底部操作栏；长按只用于拾起和拖动，拖动时隐藏操作栏；完整菜单由“更多”按钮打开。节点工具栏与导图视图工具占用同一个底部位置，避免叠放或遮挡节点。详见[交互规则](../../../design/phone-map-interactions.md)。

同时调整了缩小画布后的触控落点容差、抓取偏移和定位行为：拖动时不会因选中节点自动平移，底部文字提示与父节点高亮／同级插入线对应同一个最终落点。无有效目标、只长按未移动或系统取消手势时都不改结构。

## 最终版本截图

| 状态 | iPhone | Android |
| --- | --- | --- |
| 选中并显示底部操作 | [浅色](iphone/light-selected-dock.png) / [深色](iphone/dark-selected-dock.png) | [浅色](android/light-selected-dock.png) / [深色](android/dark-selected-dock.png) |
| 长按，工具栏隐藏且没有菜单 | [截图](iphone/light-hold-to-move.png) | [截图](android/light-hold-to-move.png) |
| 移到父节点，显示预览与文字 | [截图](iphone/light-child-drop-preview.png) | [截图](android/light-child-drop-preview.png) |
| 松手后结构生效 | [截图](iphone/light-after-drop.png) | [截图](android/light-after-drop.png) |
| 主动点“更多”打开菜单 | [截图](iphone/light-explicit-more.png) | [截图](android/light-explicit-more.png) |

截图中的绿色触点和十字线来自 Flutter 自动化测试指针，不是应用界面。两端的浅色、深色均实际完成选中、静止长按后松手、长按拖动改父节点、撤销恢复，以及主动打开菜单和返回关闭。每端 10 张图，实际记录和源码指纹见各自 run.log、build-source.json；source-proof.json 将本次最终截图与当前业务源码对应。

## 检查结果

- `flutter analyze`：无问题。
- 5 个相关测试文件：61 项全部通过。覆盖触控拖动／取消、菜单与拖动分离、双指缩放、固定工具栏、常用操作、放大触控区域、循环结构保护、同级落点、手机布局，以及桌面／平板原有行为。
- 本次修改的 9 个 Dart 文件：格式检查通过；`git diff --check` 通过。
- iPhone 17 Pro / iOS 26.5、Android 16 / API 36 模拟器：最终业务源码下的深浅色运行验收通过。

使用内置示例学习集；没有触发付费 AI 请求，没有安装到实体手机。触感及真实手指遮挡的体验仍需真机检查。

## 复现

应用目录运行 `flutter test test/map_drag_test.dart test/map_drop_test.dart test/map_node_bar_touch_test.dart test/map_node_bar_test.dart test/phone_layout_test.dart`。通过 `tool/capture_mobile_redesign.py` 运行 `mobile_map_gestures_acceptance_test.dart` 可重新采集两端截图；Android 使用 OpenJDK 21。
