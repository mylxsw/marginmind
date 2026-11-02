# iOS 系统 Sheet 参考样板

这是独立的 UIKit 参考 App，用来观察系统面板，不连接 Foliarc 的业务、文档和账号，也不会更新正式 Foliarc。

使用系统 `UISheetPresentationController` 的 medium / large 高度与拖动柄，标准导航操作、URL 输入框、键盘和未保存确认。没有自绘面板高度动画或玻璃效果。源码最低系统版本为 iOS 26，仅为观察新设计；不代表正式应用需要提高最低系统版本。

在 Apple Silicon Mac、安装对应 iOS Simulator 和 Xcode SDK 的环境运行：

```sh
python3 docs/prototypes/ios-native-sheet-reference/run.py SIMULATOR_UDID --capture
```

运行后可在模拟器中手动拖动、展开、输入、取消和保存。保存只关闭参考面板，不实际导入网页。

采集脚本使用样板自身模拟器容器内的命令文件切换展示状态，再用 `simctl` 保存系统原图。自动采集不等于手指拖动测试。首次使用模拟器键盘可能出现系统输入教程，应先处理后重新核对键盘截图。

[规范与接入方案](../../ios-native-presentation-review-2026-11-02.md) · [原图目录](../../evidence/ios-native-sheet-reference-2026-11-02/)
