# 底部弹窗移除关闭图标

此记录替代上一轮仍有右上角 × 的设置截图。

新增公共 `MMModalCloseButton`：在 `MMBottomSheet` 内不绘制关闭控件，保留其他呈现方式原有行为。`MMPhoneSheetHeader` 默认不显示关闭按钮。设置、阅读设置、全文翻译、选区翻译、查词、图片预览、脑图生成/更新/样式、阅读目录及助手扩展标题统一接入；阅读更多与外观面板在共享底部容器内同样移除 ×。iPhone 原生目录和操作面板的系统关闭图标改为现有本地化文字，不再使用 ×。

删除标签、移除词形、取消任务等内容操作保持原意，没有按图标全局隐藏。桌面独立窗口仍保留需要的关闭入口。

## 最新运行截图

| 场景 | 浅色 | 深色 |
| --- | --- | --- |
| 设置主页 | [截图](iphone/light-settings.png) | [截图](iphone/dark-settings.png) |
| 通用详情 | [截图](iphone/light-settings-general.png) | [截图](iphone/dark-settings-general.png) |
| 导入 | [截图](iphone/light-share-import.png) | [截图](iphone/dark-share-import.png) |

专用 iPhone 17 Pro / iOS 26.5 模拟器运行，已检查最新浅深色设置主页截图。集成测试断言设置和导入内容内没有关闭图标，同时验证设置默认展开、详情返回和系统返回关闭。没有安装到真机。

## 验证

- 应用相关测试 86 项通过：[日志](validation/app.log)。覆盖设置、320/390 宽度与大字号、遮罩关闭、草稿保护、阅读目录下拉关闭、更多菜单返回关闭、脑图表单、查词及翻译。小屏设置用空资料库隔离背景示例卡片的布局，不将背景卡片排版混入设置检查。
- 公共组件测试 13 项通过：[日志](validation/components.log)。涵盖三种弹窗入口自动隐藏关闭控件、拖动/返回/键盘行为及子菜单。
- 修改文件静态分析无问题：[日志](validation/analyze.log)。
- iPhone Flutter 运行验收通过：[日志](iphone/run.log)。本次使用 `modal_no_close_acceptance_test.dart`，不重复前一轮原生表单的 XCTest；原生 Reader 的文字关闭入口完成 iOS 编译，没有另行实机交互验证。
- 格式及 `git diff --check` 通过。[源码校验](source-verification.json)确认截图场景代码未再改动；截图后又将脑图调整标题接入同一公共关闭控件，该单一入口完成静态检查，没有重复截取其运行画面。

专用模拟器在验证后删除。原先下拉、遮罩、返回、Escape 和无障碍关闭入口继续有效；涉及未保存内容仍通过原有 PopScope 与草稿确认。
