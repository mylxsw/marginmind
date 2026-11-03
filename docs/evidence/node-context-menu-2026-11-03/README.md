# 导图节点长按菜单修正

后续交互已调整：手机长按仅用于拖动，完整菜单改由底部“更多”打开。最新行为见[手机导图交互验收](../phone-map-interactions-2026-11-03/README.md)。此处保留菜单布局修正时的记录。

截图中的菜单有两个问题：逐行居中排版时，快捷键挤占右侧空间，导致每行文字起点不同；动作很多时菜单按内容高度展开，接近占满整屏。

共享长按菜单现已改为固定图标列、文字左对齐，保留操作分组，普通文字使用正文色，移除操作用红色。手机隐藏桌面快捷键，模型说明等真正的辅助信息单独保留。超过 8 个操作的手机菜单默认半屏，可上拉展开并滚动；取消按钮固定在底部。短菜单仍按内容高度显示，桌面保留快捷键。

| 场景 | iPhone | Android |
| --- | --- | --- |
| 浅色半屏 | [截图](iphone/light-node-menu-medium.png) | [截图](android/light-node-menu-medium.png) |
| 深色半屏 | [截图](iphone/dark-node-menu-medium.png) | [截图](android/dark-node-menu-medium.png) |
| 上拉并滚到底部 | [截图](iphone/dark-node-menu-last-actions.png) | [截图](android/dark-node-menu-last-actions.png) |

在真实应用的内置示例中长按导图节点，验证半屏、展开、滚动到底部和返回关闭。iPhone 17 Pro / iOS 26.5 与 Android 16 / API 36 模拟器均通过，截图对应的源码指纹与当前业务源码一致，见各目录 build-source.json。未安装实体手机。

组件相关测试 23 项通过，覆盖深浅色、iOS/Android、路由/页面浮层、图标与文字对齐、隐藏快捷键但保留模型说明、横屏、展开、滚动和选择，以及已有菜单行为。

应用相关测试 68 项通过；另有笔记路由的 2 个既有用例失败，已在未修改的基线提交 531b11ecdf621a53e63d84c25f09fcd89dd550de 复现，详情见 app-tests.log 和 baseline-note-tests.log。导图拖动、合并以及助手路由回归通过。静态分析无问题。

复现运行入口：`tool/capture_mobile_redesign.py` 配合 `mobile_node_menu_acceptance_test.dart`。Android 构建使用 OpenJDK 21。
