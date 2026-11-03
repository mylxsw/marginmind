# iPhone 阅读菜单统一原生弹窗

“更多”此前使用 Flutter Cupertino Sheet，目录使用 UIKit 系统 Sheet，导致高度、圆角、背景材质和关闭方式不同。现在“更多”及“阅读外观”改用与目录相同的 UIKit medium/large 呈现配置，业务状态仍由 Dart 管理。其他平台沿用现有入口。

同时为系统呈现容器同步深浅色，避免深色文字与背景材质使用不同的外观。此公共配置也用于已有的目录和表单。

## 画面

| 状态 | 浅色 | 深色 |
| --- | --- | --- |
| 默认半屏 | [菜单](light-reader-actions-medium.png) | [菜单](dark-reader-actions-medium.png) |
| 拖动展开 | [菜单](light-reader-actions-expanded.png) | [菜单](dark-reader-actions-expanded.png) |
| 阅读外观 | [外观](light-reader-actions-appearance.png) | [外观](dark-reader-actions-appearance.png) |
| 跳转目录入口 | [导航](light-reader-actions-to-outline.png) | [导航](dark-reader-actions-to-outline.png) |

上述是正式应用代码在 iPhone 17 Pro / iOS 26.5 模拟器中的系统截图，使用应用自带 PDF 示例；示例默认导航类别是缩略图。截图已逐类复核。没有安装到用户真机。

## 验证

- [完整运行记录](run.log)：最终源码编译及 Flutter 集成测试通过。
- [浅色 UIKit 验收](native-ReaderActions-summary.json)、[深色 UIKit 验收](native-ReaderActionsDark-summary.json)、[关闭验收](native-ReaderActionsClose-summary.json)：3 项 XCTest 通过。检查真实 medium→large 拖动、外观选中、生词/批注开关往返、关闭菜单后打开原生导航、关闭按钮；Dart 另核对外观确实保存及导航关闭状态。
- [静态分析](analyze.log)：无问题。[阅读器相关测试](reader-tests.log)：17 项通过。[原生通道专项](native-channel-tests.log)：3 项通过，包含内联操作刷新及关闭后的回调释放。
- [设计组件完整测试](design-tests.log)：248 项通过、1 项跳过、5 项失败。用未修改 HEAD 的 mm_design 独立副本运行相关的四个测试文件，[复现相同 5 项失败](baseline-design-tests.log)：图标断言、手机控件尺寸、桌面浅/深色截图各一项、侧栏安全区一项。[基线来源](baseline.json)。本次没有修改这些组件或放宽断言。
- [最终源码哈希](build-source.json)、[截图哈希](screenshots.json)。保存时已重新计算 Dart/Swift 哈希并与构建记录核对一致。

复跑：

```sh
PATH=/Users/mylxsw/fvm/versions/3.47.2/bin:/usr/bin:/bin:/opt/homebrew/bin:$PATH \
  /opt/homebrew/bin/python3 tool/capture_mobile_redesign.py SIMULATOR_UDID iphone \
  --test phone_native_actions_test.dart --output /tmp/phone-native-actions
```

XCTest runner 使用安装了 xcodeproj 的系统 Ruby；不要由未安装该 gem 的 Homebrew Ruby 运行。集成脚本等待 XCTest 时持续刷新 Flutter，以验证菜单关闭后的业务页面跳转。早期脚本暂停 Flutter 刷新导致跳转断言失败；修正后在最终源码完整重跑通过。原始 xcresult 留在本机临时目录，不加入仓库。
