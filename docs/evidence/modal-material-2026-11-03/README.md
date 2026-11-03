# 弹窗公共材质验证

此记录保留初次实现结果；其中设置半屏高度及深色亮灰底已被后续修正替代，当前效果见 [设置高度与配色修正](../settings-correction-2026-11-03/README.md)。

2026-11-03，在本地主分支同步分享导入功能 `bf8480bc` 后进行。保留工作区已有的手机界面修改。

本次新增 `MMModalSurface` / `MMModalStyle`，手机底部面板和普通表单共用底板、细边框及内部 flat 样式，分享导入自动继承。iPhone 原生表单、目录、操作与确认从同一个 Dart 配置读取颜色和几何值；确认选项使用真实按钮，未保存草稿确认也共用原生面板配置。去掉玻璃按钮背景后，标题栏文字显式使用公共前景色，保证浅色“保存”可见。

## 实际运行

[浅深色四类弹窗对照](comparison.jpg)。每张原始截图都已打开检查；拼图仅缩小和排版截图。

| 场景 | 浅色 | 深色 |
| --- | --- | --- |
| 分享导入 | [截图](iphone/light-share-import.png) | [截图](iphone/dark-share-import.png) |
| 设置 | [截图](iphone/light-settings.png) | [截图](iphone/dark-settings.png) |
| 原生重命名 | [截图](iphone/light-native-form.png) | [截图](iphone/dark-native-form.png) |
| 原生确认 | [截图](iphone/light-native-confirmation.png) | [截图](iphone/dark-native-confirmation.png) |
| 键盘输入 | [截图](iphone/light-native-keyboard.png) | [截图](iphone/dark-native-keyboard.png) |
| 未保存草稿确认 | [截图](iphone/light-native-discard.png) | [截图](iphone/dark-native-discard.png) |

在专用 iPhone 17 Pro / iOS 26.5 模拟器运行生产组件与真实本地资料库。验证导入选择面板取消、设置关闭、原生重命名输入、继续编辑保留草稿、放弃草稿和确认取消；另通过实际点击浅色“保存”，确认修改后的值回到 Dart。分享面板使用真实 `ShareImportSheet` 与相同底部路由，但此次未重复 Safari 分享扩展交接，也未抓取网页或请求 AI。

八张核心截图的面板留白处采样全部一致：浅色 `(255,255,255)`、深色 `(50,50,53)`，记录见 [颜色采样](surface-samples.json)。这证明检查位置的底色一致，不代表所有控件或系统呈现的阴影、遮罩、布局像素完全相同。系统文件、分享与颜色选择器仍由系统呈现。未安装到真机；Android 由组件及手机布局测试覆盖，此次未补 Android 运行截图。

## 检查结果

| 检查 | 结果 |
| --- | --- |
| 公共弹窗、材质继承、嵌套菜单、原生通道、拖动与键盘回归 | 37 通过，见 [日志](validation/components.log) |
| 分享导入、手机布局、脑图表单、更多菜单 | 43 通过，见 [日志](validation/app.log) |
| iPhone 运行集成 | 1 通过，见 [日志](iphone/run.log) |
| XCTest 原生浅深色重命名、确认及浅色保存 | 5 通过，`iphone/native-*-summary.json` 保留结果 |
| 完整设计库 | 269 通过、1 跳过、6 失败，见 [日志](validation/design-full.log) |
| 6 项失败的干净基线复现 | 同样失败，见 [基线日志](validation/baseline.log) |
| 静态分析 | 无新增诊断；未修改的 `workspace_sidebar.dart` 有一条无用 import 提示，见 [日志](validation/analyze.log) |
| 本次 Dart 文件格式 / `git diff --check` | 通过 |

完整设计库的失败为图标关系、手机几何、抽屉安全区、手机菜单勾选及 macOS 深浅色工具条快照。没有改动这些断言或更新快照。

[源码校验](source-verification.json)确认最终 Dart / iOS Runner Swift 源码与运行截图构建一致。`iphone/build-source.json` 记录构建来源。

复现：在仓库根目录执行 `python3 tool/capture_mobile_redesign.py <专用模拟器 ID> iphone --test modal_material_acceptance_test.dart --output <空的验证目录>`。本机需将 `/usr/bin` 放在 Homebrew 前，并将 Flutter 加入 PATH，以使用已安装 xcodeproj 的系统 Ruby。
