# Foliarc 名称与图标切换验收

2026-10-31。默认图标为 B「翻页」，A「书叶」和 C「折纸 F」可选，应用名称统一为 Foliarc。

## 已完成验证

- `flutter test test/app_icon_test.dart test/settings_test.dart test/window_title_test.dart test/reader_chrome_test.dart`：43 项通过（Flutter 3.47.6）。
- 使用仓库固定的 Flutter 3.47.2 运行 `test/app_icon_test.dart`：13 项通过。覆盖默认值、保存与重建、系统失败、设置写入失败及内存缓存恢复、连续点击、启动时与原生图标对齐、失败后重试，以及四种设置布局。
- 使用 Flutter 3.47.2 执行静态分析：无问题。
- macOS `RunnerTests.testFoliarcIconAssetsAndBrandIdentity` 通过：三款真实资产均能加载到 `NSApplication.applicationIconImage`，Bundle 名称为 Foliarc，原 Bundle ID 保持不变。
- macOS 实际运行检查：选择 A、C、B 成功；选择 C 后退出并重新启动，设置仍选中 C；最后恢复默认 B。窗口标题和菜单显示 Foliarc，原有学习集仍可见。
- macOS Debug、Release 构建通过，最终 Release 为 `Foliarc.app`；`codesign --verify --deep --strict` 通过，签名内的应用沙盒和网络客户端权限均为 true。
- iOS 模拟器 Debug 构建通过。生成的 Info.plist 在 iPhone 和 iPad 两组图标配置中均包含 `AppIconLeaf` 与 `AppIconF`。57 个图标条目的像素尺寸和无透明 RGB 格式校验通过。

- iPad 模拟器原生 UI 测试 `iPadAcceptance.testAppIcons` 通过（83.524 秒，0 失败）：逐一切换 A、C、B，处理 SpringBoard 的系统确认弹窗，并在每次退出重启后确认选择仍然保持。应用启动会读取 iOS 实际备用图标，所以此项同时验证了系统状态与设置一致；最终恢复默认 B。

复现原生 iPad 测试：先安装正常的 iOS 构建，再运行 `xcodebuild test -project tool/ipad_acceptance/iPadAcceptance.xcodeproj -scheme iPadAcceptance -destination "platform=iOS Simulator,id=<device>" -only-testing:iPadAcceptance/iPadAcceptance/testAppIcons CODE_SIGNING_ALLOWED=NO`。结果摘要见 `ipad-native-result.txt`。

## 设置界面精简

按用户截图去掉常驻的 Dock / 主屏幕说明、选中图标下方的对勾及对应留白，以及设置页中的组件库入口。选中状态由边框、背景和辅助功能状态表达；切换中和失败时仍显示必要反馈。四张布局截图已更新。使用 Flutter 3.47.2 运行图标与设置测试：24 项通过；静态分析无问题。

## 界面证据

以下 PNG 使用内存中的示例资料在 Flutter widget 测试中生成，供版式检查；原生切换结果由上面的实际运行检查与原生测试验证。

- `icons-desktop-light-zh.png`：桌面，中文浅色。
- `icons-desktop-dark-en.png`：桌面，英文深色。
- `icons-ipad-zh.png`：iPad 竖屏，中文。
- `icons-phone-en.png`：320pt 手机窄屏，英文。

## 平台边界

macOS 使用 AppKit 的 Dock 图标接口，不改动签名应用包；访达保留默认 B。iOS / iPadOS 使用系统备用图标，系统可能弹出确认；启动只读取系统实际状态，不自动触发换图标弹窗。Android、Windows 和 Web 已更新默认图标与展示名称；其他平台暂不提供运行时切换入口。Windows 保留内部 ProductName 以继续使用旧的数据与偏好设置目录。

尚未进行物理 iPad / iPhone 验证，也未构建验证 Android、Windows、Linux 或 Web。此次不改变应用标识、数据结构、钥匙串条目、文件格式或存储位置。

原生接口参考：[AppKit applicationIconImage](https://developer.apple.com/documentation/appkit/nsapplication/applicationiconimage)、[Xcode 备用图标配置](https://developer.apple.com/documentation/xcode/configuring-your-app-to-use-alternate-app-icons)。
