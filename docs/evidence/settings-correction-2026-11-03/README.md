# 设置高度与深色配色修正

后续已移除标题区 ×；本页截图保留当时状态，当前界面见 [无关闭图标验证](../modal-no-close-2026-11-03/README.md)。

此记录替代上一轮弹窗材质验收中关于“设置半屏”和深色 `#323235` 底板的设计结论。上一轮仅验证技术一致性，没有充分判断实际使用效果。

- 设置打开时默认展开到安全区内最大高度，分类无需先上拉；进入通用等详情页、返回分类时保持展开。
- `MMModalStyle` 底板改用 `MMColors.windowBackground`，深色为 `#1E1E1F`，不再使用悬浮控件玻璃的不透明退化色。
- 设置分类分组使用 `card`，图标、文字、箭头和分隔线显式读取公共配色。深色下底板较暗、分组略亮，修正之前相反的明暗层次。
- 导入、普通表单、iPhone 原生表单和确认同步继承公共底色；公共材质与各场景的合理高度分别配置。

[设置深色前后对照](settings-before-after.jpg) · [设置主页、通用、导入的浅深色对照](comparison.jpg)

## 运行检查

专用 iPhone 17 Pro / iOS 26.5 模拟器，真实本地资料库及生产组件。已打开检查浅深色设置主页、通用详情页和导入截图；设置主页七个分类均显示，自动化断言打开高度超过屏幕 80%、网页搜索可直接点击，并验证从详情返回、关闭设置。通用页更长内容仍正常滚动。

| 场景 | 浅色 | 深色 |
| --- | --- | --- |
| 设置主页 | [截图](iphone/light-settings.png) | [截图](iphone/dark-settings.png) |
| 通用详情 | [截图](iphone/light-settings-general.png) | [截图](iphone/dark-settings-general.png) |
| 导入 | [截图](iphone/light-share-import.png) | [截图](iphone/dark-share-import.png) |
| 原生表单 | [截图](iphone/light-native-form.png) | [截图](iphone/dark-native-form.png) |
| 原生确认 | [截图](iphone/light-native-confirmation.png) | [截图](iphone/dark-native-confirmation.png) |

六张 Flutter 截图的底板留白采样与页面背景一致：浅色白、深色 `(30,30,31)`，见 [采样](surface-samples.json)。这只是指定位置的颜色验证；实际层次和可读性另经截图检查。

## 验证结果

- 设置、手机布局及分享导入：47 项通过，[日志](validation/app.log)。其中手机设置高度断言覆盖 iPhone 和 Android。
- 公共弹窗及原生通道：12 项通过，[日志](validation/components.log)。
- 本次修改文件静态分析：无问题，[日志](validation/analyze.log)。
- iPhone 集成运行：通过，[运行日志](iphone/run.log)。包括设置展开、详情返回、取消导入、原生草稿保留、放弃、确认取消及实际保存。
- 原生 XCTest：5 项通过，结果保留于 `iphone/native-*-summary.json`。
- 格式及 `git diff --check`：通过。

[源码校验](source-verification.json)确认最终 Dart 和 iOS Runner Swift 与截图构建完全一致。未安装到真机，此次未补 Android 运行截图；没有网页抓取、付费 AI 请求或业务数据删除。专用模拟器在验证后移除。
