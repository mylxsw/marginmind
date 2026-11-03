# 手机弹窗统一验收（2026-11-03）

后续针对节点长按菜单的对齐、快捷键和长菜单高度又做了修正，最新截图及验证见[节点菜单专项记录](../node-context-menu-2026-11-03/README.md)。本文保留该次全面审查的源码与截图记录。

应用内独立弹窗统一使用底部悬浮面板：四周留边、圆角、拖动条，长内容可展开，短菜单按内容高度显示。iPhone 的简单菜单与表单使用原生呈现，复杂内容使用同一套悬浮布局和原生玻璃材质；Android 使用实色面板，保留平台合适的圆角与系统返回行为。

## 检查范围

检查了应用、设计组件库和平台层的弹窗、对话框、菜单、树内浮层及原生宿主入口。[完整入口清单](inventory.md)记录了 366 个源码匹配位置，包含组件定义和调用点，**并非 366 个独立弹窗**。22 个底层路由与桌面回退位置均已检查手机分支，没有未分类项。

覆盖设置、阅读外观、目录与书签管理、文档切换、查词与翻译、生词卡、助手及模型/技能选项、脑图生成与调整、笔记设置、导出、重命名、确认及颜色选择。补齐了最后一轮发现的目录管理全屏容器和脑图调整锚定表单。

贴着原文的选区、划线、节点和研究笔记工具条保留原位置；关闭它们时优先处理返回键。输入建议、短暂提示继续使用对应组件。资料库抽屉属于页面导航。文件、分享、权限和系统颜色面板继续由操作系统呈现。

## 两端交互

- iPhone：原生菜单、目录、简单表单共用原生 sheet 配置；深浅色外观同步到呈现层；复杂内容统一悬浮容器。
- Android：菜单、二级菜单、目录管理和表单共用悬浮容器；系统返回先退子页或关闭浮层，再返回阅读页面。
- 两端：点击遮罩、下拉和系统返回遵守未保存草稿保护。键盘弹出和旋转时保留编辑状态；安卓横屏会滚动到当前输入框，保存按钮可滚动到达。横屏菜单继续使用手机容器。

## 运行截图

在 iPhone 17 Pro / iOS 26.5 模拟器与 Android 16 / API 36 模拟器中，以真实应用和内置示例文档运行，共收集 60 张截图。两端均覆盖深浅色。没有安装到实体手机，也没有触发付费 AI 请求。

| 场景 | iPhone | Android |
| --- | --- | --- |
| 设置半屏 | [截图](iphone/general/dark-01-settings-medium.png) | [截图](android/general/dark-01-settings-medium.png) |
| 二级菜单 | [截图](iphone/general/dark-04-submenu.png) | [截图](android/general/dark-04-submenu.png) |
| 目录管理最终补测 | [截图](iphone/navigation/dark-navigation-sheet.png) | [截图](android/navigation/dark-navigation-sheet.png) |
| 脑图调整最终补测 | [截图](iphone/adjustment/dark-map-adjustment-sheet.png) | [截图](android/adjustment/dark-map-adjustment-sheet.png) |
| 横屏输入及保存 | 原生表单由 UIKit 用例验证 | [输入框](android/general/android-10-rename-landscape-keyboard.png)、[保存按钮](android/general/android-10a-landscape-save.png) |

运行记录位于各平台的 general、navigation、adjustment 目录。iPhone 的原生表单、确认、颜色及目录管理另有 XCTest 结果；Android 通过 adb 实际发送系统返回键。

截图分三阶段采集：通用弹窗验收后，修改了目录管理容器与阅读页返回处理两个文件；目录专项验收后，又修改了脑图调整入口一个文件并完成两端专项验收。[coverage.json](coverage.json)记录每阶段源码指纹、截图校验值和三个文件的差异证明，其余业务源码在这些阶段完全相同。最终脑图调整验收使用最终业务源码，不能将较早截图当作同一构建的截图。

## 自动检查

| 检查 | 结果 |
| --- | --- |
| Flutter analyze | 无问题 |
| 修改的 48 个 Dart 文件格式 | 无需修改 |
| 设计库完整测试 | 253 通过、1 跳过、5 个已有失败 |
| 应用相关测试 | 142 通过、1 个已有失败 |
| 目录与手机布局专项 | 22 通过 |
| 手机脑图调整专项 | 2 通过 |
| 桌面脑图调整回归 | 1 通过 |
| iPhone / Android 运行验收 | 两端三个阶段均通过 |

[验证日志](validation/)保留完整输出。六个失败已在未修改的基线提交 `531b11ecdf621a53e63d84c25f09fcd89dd550de` 单独复现：设计库的图标尺寸关系、手机几何常量、抽屉遮罩安全区，以及 macOS 深浅色工具条快照；应用中未配置 AI 的旧用例查找不到 `assistant-configure-models`。这些失败仍存在，没有通过删测或改断言隐藏。

## 复现入口

运行组件与应用测试时分别进入 `packages/mm_design`、`apps/marginmind`。运行截图使用 `tool/capture_mobile_redesign.py`，三个集成入口为：

- `mobile_modal_acceptance_test.dart`
- `mobile_navigation_sheet_acceptance_test.dart`
- `mobile_map_adjust_sheet_acceptance_test.dart`

Android 构建使用 Homebrew OpenJDK 21，避免本机 Java 26 与当前 Android 构建链不兼容。iOS 原生自动化将 `/usr/bin` 放在 Homebrew 前，使用已具备 xcodeproj 的系统 Ruby。每批目录中的构建记录保留实际命令及源码信息。
