# 更新脑图对话框

2026-11-01

菜单文案改为“更新脑图”。对话框采用 560pt 宽度、圆角和分区布局，展示资料列表、更新摘要、更新范围与补充要求。标题栏和底部操作区固定，正文和长资料列表可滚动；提供关闭、取消和 Esc 退出。回看较早页时显示上次更新页码，不再显示倒退的页码箭头。

验证：

- Flutter 3.47.6 下，`map_update_test.dart`、`map_generation_ui_test.dart`、`map_update_screenshots_test.dart` 共 31 项通过。
- 更新预览、选择资料、切换范围、填写要求、应用与撤销、关闭和取消已检查。
- 覆盖 320×640、402×874、900×390，长标题、多资料和手机键盘遮挡；静态分析与格式检查通过。
- 六张截图为内存测试数据，覆盖桌面、手机和手机键盘下的浅色／深色界面；未调用真实模型，未替换已安装应用。

复现截图：在 `apps/marginmind` 运行以下命令（输出路径请设为绝对路径）。

```sh
MM_SCREENSHOTS=/absolute/output/path MM_FONT='/System/Library/Fonts/Hiragino Sans GB.ttc' flutter test --no-pub test/map_update_screenshots_test.dart
```
