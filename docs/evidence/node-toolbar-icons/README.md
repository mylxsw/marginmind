# iPad 脑图节点工具栏

2026-10-31：节点操作改为直接显示图标，长按显示完整说明。保留至少 44×44 pt 的点击区域；空间不足时沿用画布工具栏的横向滚动。根节点只保留适用操作。

- `tablet-dark.png`、`tablet-light.png`：1024×700 pt 的组件渲染截图，使用内存示例数据。
- `tablet-dark-tip.png`、`tablet-light-tip.png`：长按“同级节点”图标时的说明。
- 42 项相关组件测试通过：全部图标的点击与长按、无障碍名称、根节点操作、节点操作回归，以及 180–960 pt 宽度下的布局和可达性。
- `flutter analyze --no-pub` 和 `flutter build ios --simulator --debug --no-pub` 通过。

截图来自组件测试；尚未完成实体 iPad 的交互验证。
