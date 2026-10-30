# 标注工具栏：颜色与工具分离

按用户确认的设计实现：颜色圆圈、荧光笔、画线笔依次排列。两种笔共用当前颜色，打开或更改颜色均不切换工具。荧光笔面板只有颜色及“选择更多颜色”；画线笔面板额外显示实线、虚线、点线和波浪线。

选区应用标记后保留工具栏及已打开的设置面板。切换两种笔修改同一条标记，保留关联卡片，支持撤销；选择颜色本身不会给尚未标记的选区创建标记。已有标记的颜色可直接修改。共用颜色及画线样式可在重启后恢复。

窄屏保留三个标注按钮，将导图和翻译入口收进“更多”；320pt 手机和 768pt 平板的工具栏、颜色面板通过边界检查。Esc 先关闭颜色面板，保留当前工具和选区。

截图均由实际 Flutter 组件导出，像素密度为 2 倍。`highlight-settings-*` 和 `underline-settings-*` 同时包含工具栏和对应面板；`toolbar-*`、`highlight-palette-*` 和 `underline-palette-*` 为各组件局部。

验证：13 个相关测试文件共 127 项通过；隔离导出的提交内容同样通过 127 项测试及 `flutter analyze --no-pub`。本地 `flutter build macos --release --no-pub` 成功。实际 PDF 拖选画线通过测试后端验证，未替换已安装应用，也未宣称完成真实窗口的人工验收。

复现截图：在 `apps/marginmind` 目录，将 `MM_SCREENSHOTS` 指向本目录绝对路径后运行 `flutter test --no-pub test/annotation_toolbar_test.dart`。
