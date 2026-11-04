# 手机 UI 一致性修复

对应用户提供的七张页面截图，重点修复材质、圆角、边框、字号、图标、间距与裁切。沿用现有深浅色主题与功能入口。

本轮补齐用户指出的五处遗漏：搜索分割线与“继续学习”之间的留白；可下拉面板冗余关闭按钮（包括完整 AI 对话）；AI 输入框的过大内缩；脑图“问助手”的通用图标；手机快捷输入旁无意义的侧边栏入口。

同时修复复查发现的问题：快捷输入在展开后悬在中间、完整助手底部控件占两行、推荐操作与输入区不对齐、节点和列表工具栏材质不一致、定位后直接子节点超出画布，以及列表滚动时文字进入顶部导航区域。下拉关闭后重开保留输入草稿。

第四轮按用户指出的目录叉号和菜单小标题继续修复：目录右侧用“返回阅读 / 返回脑图”等明确文字代替叉号，点按或左滑仅收起目录，左侧“资料库”才离开工作区；导航文字在大字号下自然换行。根级操作菜单去掉标题和分割线，子菜单仍保留返回和具体标题，AI 助手标题不变。表单及需要说明任务的内容面板不套用无标题菜单规则。

[七页可切换前后对照](review.html) · [深色总览](overview-dark.jpg) · [浅色总览](overview-light.jpg)

两列三行拼图：[深色六页](pages-two-columns-1.jpg) · [第七页与展开/列表末尾](pages-two-columns-2.jpg) · [半屏与键盘状态](pages-two-columns-3.jpg) · [浅色六页](pages-two-columns-4.jpg)

本轮重点：[目录返回、无标题短菜单与子菜单](pages-two-columns-5.jpg)。

## 实际截图

以下是最终修改代码在专用 iPhone 17 Pro / iOS 26.5 模拟器中的系统原图（1206 × 2622）。应用通过真实导入和持久化建立本地示例，以截图中可见的文字复现页面结构；这不是原设备资料的复制，正文、模型显示名、脑图结构和相机位置与用户截图有差别。未安装到实体手机，未保存密钥，未发送 AI 请求。

| 对应原图 | 页面 | 深色 | 浅色 | 修复重点 |
| --- | --- | --- | --- | --- |
| 1 | 资料库 | [原图](final-iphone/dark-01-library.png) | [原图](final-iphone/light-01-library.png) | 首分区前置留白 28 点，验证实际标题间距；标题两行 |
| 2 | 资料目录与添加 | [原图](final-iphone/dark-02-resources-add.png) | [原图](final-iphone/light-02-resources-add.png) | 目录返回文字明确目的地，添加菜单直接显示操作，无重复标题、分割线或关闭按钮 |
| 3 | 完整 AI 助手 | [原图](final-iphone/dark-03-assistant.png) | [原图](final-iphone/light-03-assistant.png) | 输入区及推荐操作内缩 8 点、底部单行控件、移除重复关闭按钮 |
| 4 | 选中脑图节点 | [原图](final-iphone/dark-04-map-selection.png) | [原图](final-iphone/light-04-map-selection.png) | 专用助手图标及用户配色、实色工具栏及 24 点圆角、定位容纳直接子节点 |
| 5 | AI 快捷操作 | [原图](final-iphone/dark-05-assistant-actions.png) | [原图](final-iphone/light-05-assistant-actions.png) | 去掉重复外框、关闭及侧边栏按钮；输入区内缩 8 点 |
| 6 | 列表更多菜单 | [原图](final-iphone/dark-06-outline-more.png) | [原图](final-iphone/light-06-outline-more.png) | 根级无标题，子菜单保留返回与具体标题；叶子与子菜单的字号、图标、行高、对齐一致 |
| 7 | 脑图列表 | [原图](final-iphone/dark-07-outline.png) | [原图](final-iphone/light-07-outline.png) | 来源下移去重、正文优先、缩进限宽、紧凑工具栏、视口避开上下操作区 |

另验证完整助手[半屏](final-iphone/dark-03a-assistant-medium.png)与[系统键盘](final-iphone/dark-03b-assistant-keyboard.png)、快捷操作[展开](final-iphone/dark-05a-assistant-actions-expanded.png)与[系统键盘](final-iphone/dark-05b-assistant-actions-keyboard.png)，以及[列表末尾](final-iphone/dark-07a-outline-bottom.png)。第四轮增加[目录返回脑图](final-iphone/dark-02a-resources.png)、[目录返回阅读](final-iphone/dark-02b-resources-reading.png)与[子菜单](final-iphone/dark-06a-map-submenu.png)，深浅色各 15 张，共 30 张。`compare-01.jpg` 至 `compare-07.jpg` 将用户原图和修改后原图排在一起复核，未修改系统截图本身。

## 共用组件

- `MMBottomSheet`：手机面板统一实色 `surface` 背景，外边距 12，圆角 28，细边框 0.5，不再由原生玻璃和内层自绘背景叠加。原生系统表单等入口保留平台呈现。
- `MMPhoneSheetHeader`：子菜单及两种 AI 面板使用共用标题栏，不显示重复关闭按钮；根级操作菜单省略标题栏，菜单名称仍作为无障碍标签。容器提供无障碍关闭动作。
- 手机下拉菜单：统一最小行高 52、图标 20、正文样式；保留禁用、子菜单、返回和选中动作。
- 手机 AI 输入框：单层 16 点圆角边框，左右内缩 8 点，手机不显示“展开到侧边栏”入口；引用不再套底色，更多、模型、语音、发送合成一行，提及和联网在更多选项中。快捷操作滚动区占满剩余高度，输入框保持在面板底部。
- 手机列表：最多三层视觉缩进、每层 16；连续相同来源不重复绘制，正文预览最多三行。列表视口避开上下工具栏，末尾内容可以完整滚动到达。
- 手机脑图：节点、多选和列表工具栏统一实色、24 点圆角；定位选中节点时优先容纳直接可见子节点，缩放下限 0.6，超过时退回当前缩放居中选中节点。

设计说明已同步至 [design-system.md](../../design-system.md#手机弹窗统一2026-11-03) 与 [design/README.md](../../../design/README.md)。

## 验证

| 检查 | 结果 |
| --- | --- |
| Flutter analyze | [无问题](validation/current-analyze.log) |
| 修改/新增 Dart 文件格式 | 0 个需要格式化 |
| 菜单、子菜单、关闭/返回、尺寸与对齐专项 | [27 项通过](validation/design-focused.log)，包括 320/390 点、深浅色及 130% 字号 |
| 上轮手机菜单、拖动关闭、子菜单与样式专项（本轮未改相关实现） | [28 项通过](validation/followup-design.log)，下拉关闭时面板整体移动，不压缩标题和输入区 |
| 第四轮根级菜单、子菜单返回/选择、拖动关闭及共用导航专项 | [24 项通过](validation/current-design.log) |
| 第四轮目录返回、搜索、菜单动作、大字号、键盘、导航及助手草稿专项 | [18 项通过](validation/current-app.log)；320 点、150% 中英文检查限定在目录组件 |
| 第三轮助手专用图标、关闭与草稿保留、手机导航、脑图和布局专项 | [59 项通过](validation/final-app.log)，本轮按上述范围复验 |
| 上轮设计组件完整测试（本轮未全量重跑） | [264 通过、1 跳过、6 个既有失败](validation/design-full.log) |
| 上轮应用相关 9 个测试文件（本轮按上述范围复验） | [76 通过、6 个既有失败](validation/app-related.log) |
| 桌面脑图快捷键测试 | 8 通过、1 个既有失败，原代码亦复现同一失败，见[基线日志](validation/baseline-map-keyboard.log) |
| iPhone 编译及七页与补充状态运行 | [通过](final-iphone/run.log)，30 张截图；断言目录点按及滑动返回、两种返回目的地、无重复菜单标题、子菜单返回保留选择，并复验输入区、键盘、节点定位及草稿保留 |
| 截图与源码一致性 | [screenshots.json](screenshots.json) 校验原图 SHA256；采集时的全部 Dart 业务/组件源码与 [构建记录](final-iphone/build-source.json) 一致。原生 Swift 文件在截图期间另有更新，保留采集构建与当前源码的两个指纹，并明确记录 `native_source_matches: false` |

原代码 `cac2ef0dbbebe293a046df8881a7736c929b3d62` 在独立 worktree 中复现了上轮全部 12 个失败：

- 设计库：图标断言、手机几何常量、macOS 深浅色快照，见[基线日志](validation/baseline-design.log)；菜单选择勾图标，见[基线日志](validation/baseline-menu-icons.log)；抽屉遮罩安全区，见[基线日志](validation/baseline-adaptive.log)。
- 应用：桌面模型菜单定位两项、凭据丢失的旧预期、未配置助手的旧入口，见[基线日志](validation/baseline-assistant.log)；横屏资料库旧标题查找两项，见[基线日志](validation/baseline-mobile.log)。

本轮另复现桌面脑图菜单快捷键的既有失败。手机助手关闭测试随新交互更新为拖动关闭及草稿保留；没有把这些既有失败改成通过。

没有运行整个应用全部测试，也没有进行 Android 真实模拟器截图；Android 的菜单行为在组件专项中验证。

本轮七页及补充状态均为 Flutter 页面/面板，没有打开 UIKit 原生表单、确认或目录。原生弹窗文件在两轮已通过的采集中继续被更新，未回退或覆盖这些修改；本轮截图对应已通过验收的完整应用构建，其 Flutter 源码与采集当时的工作区一致，原生弹窗的最新改动不在本截图验收范围内。未将原生源码差异算作验证通过。

探索全应用 320 点、150% 字号时另外观察到资料库继续学习卡片及阅读底部控件溢出；本轮目录组件的大字号通过不代表整个应用已完成无障碍字号验收。这些额外问题仍待独立修复。

## 提交前独立验证

日志入库时仅移除行尾空白，保留原有测试结果及失败内容。

本提交只包含本轮移动端 UI 修复、相关检查、截图记录及设计稿，共享文件仅纳入本轮改动；工作区独立的统一原生弹窗、设置高度/配色及关闭按钮框架改动未包含在此提交中。

- 独立检出静态检查：[通过](validation/submit-analyze.log)。
- 应用相关检查：[65 项通过](validation/submit-app.log)。
- 设计组件检查：[24 项通过](validation/submit-design.log)。
- 独立检出的源码指纹及父提交：[submit-source.json](validation/submit-source.json)。

截图采集构建含采集当时的并行弹窗改动，其完整源码指纹与本次聚焦提交不同；原图作为该构建的布局/交互验证记录保留，不能视作本提交整个源码树逐字节一致的截图。提交内容的独立检查以上述三份日志为准。

新的 85% 侧滑目录及目录文档单行标题方案仅保存为[设计稿](../../../design/proposals/2026-11-03-mobile-drawer/README.md)，没有作为已实现功能纳入此提交。

## 复现

使用专用 iPhone 模拟器，每次截图前卸载其中的测试应用，避免示例累积和覆盖日常数据。该集成脚本会创建两份本地示例资料，使用内置 PDF 和从截图整理的 Markdown 文字。

```sh
PATH=/Users/mylxsw/fvm/versions/3.47.2/bin:$PATH \
  python3 tool/capture_mobile_redesign.py SIMULATOR_UDID iphone \
  --test phone_visual_polish_acceptance_test.dart \
  --output docs/evidence/phone-visual-polish-2026-11-03/final-iphone
```

重新生成总览和前后对照：在带 Pillow 的 Python 环境中执行 `tool/build_phone_visual_review.py --reference-dir 原始附件目录`。脚本保留系统原图，另生成排版预览；要求采集运行通过、全部图片在本次构建后生成，且待比较的 Dart 源码一致。默认也要求 Swift 一致；本轮针对上述独立原生变更使用 `--allow-native-drift`，同时在清单和画廊显式记录差异，不放宽 Dart 或截图校验。


## 后续修复（2026-11-04）

上述记录保留当时验证范围。后续已实现侧滑 Drawer 与目录文档单行标题，并修复继续学习卡片、数量角标及阅读页码在 320 点、150% 中英文字号下的溢出；原生阅读目录与 Flutter 面板也完成层级和初始高度调整。最新运行截图与检查结果见[本轮验证](../mobile-surface-hierarchy-2026-11-04/README.md)。
