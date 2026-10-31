# 手机适配截图验收 · 2026-10-31

本次以现有 iPad 组件为参照，修复手机的字号、按钮、输入框、菜单、分段控件、侧栏选中态和底部弹层的一致性。手机仍使用单栏阅读和底部工具栏。

## 发现和修复

| 截图或检查 | 原问题 | 修复后的行为 |
| --- | --- | --- |
| `before/02-settings-general.png`、`before/02-settings-reading.png` | 设置分类被截成“网页…”和“语音…”，没有直接关闭入口 | 分类按内容宽度显示，可横向滚动，当前分类自动露出；常显标题和关闭按钮 |
| `before/03-reader.png` | 裁边建议覆盖章节标题，页码和进度分占两行 | 裁边从菜单进入；页码、进度与前后页合并为 iPad 同款单行胶囊 |
| `before/05-assistant.png` | 手机助手缺少关闭按钮，控件沿用较小的旧规格 | 使用共享字号、44pt 触摸区域与明确关闭入口 |
| 窄屏和大字号检查 | 设置标签挤占输入区，模型服务状态换行超高，继续学习卡片的进度条被徽标挤压 | 设置行按空间上下排列；服务标题随字号增高；手机徽标移入标题行，保留进度可用空间 |
| 阅读器目录栏打开时 | 页码胶囊在剩余窄栏中溢出 | 胶囊小于 240pt 时隐藏进度条，保留页码输入及前后页按钮；目录按钮可横向滚动 |
| `before/06c-map-style-clipped.png` | 脑图样式弹窗按右边缘对齐，超出手机左边界 | 根据脑图区域的实际坐标限制左右边界，横屏时限制高度并允许滚动 |
| 原生辅助功能检查 | 整个助手面板被错误标记成输入框 | 将标注范围限制在输入区域，由真实文本输入控件暴露输入角色 |
| 横屏助手、复习答案 | 空状态和评分按钮在短屏或较长英文下溢出 | 空状态可滚动；评分标签和时间间隔保持单行 |

## 设备与边界

- iPhone 16e：iOS 26.2，390×844pt。主流程截图由 `simctl io screenshot` 保存，每张保存成功后才允许测试继续，避免日志延迟导致截到下一页；样式弹窗、系统键盘和补充横屏截图由 XCTest 保存。
- iPad mini：同版本 iOS，作为共享组件样式的模拟器对照。
- 组件和布局检查还包含 320×568pt、小屏英文/中文、1.3 倍字号、手机横屏、iPad 多种尺寸及桌面。
- 样例 PDF 为仓库自带内容；摘录、生词、笔记和复习数据只写入模拟器。助手输入界面使用本机模型配置展示，不发送模型请求，不写入 API Key。
- 这次验证 UI、布局和基本交互；不代表完成真实模型回答、真实服务连接、系统分享或实体设备触控验收，也不宣称完整的屏幕阅读器适配。

## 检查记录

- 应用相关测试（含手机弹窗）：110 项通过，2 项按现有截图开关跳过。
- 共享组件重点检查：42 项通过。
- 全部共享组件检查：197 项通过；两张旧 Mac 图像基准分别差 12 / 10 像素。使用未经修改的源码副本重跑，同样出现相同差异，未重写旧基准。
- 脑图样式修复回归：21 项通过，包含 320pt、390pt 和手机横屏的实际弹窗边界检查。
- 助手和弹窗最终交互检查：12 项通过。
- 原生 iPhone 检查：1 项通过；真实键盘高度与输入框位置断言通过，完成输入、关闭和横屏切换。
- `flutter analyze --no-pub` 与 iOS 模拟器 Debug 构建：通过。
- 最终 iPhone 原生检查直接使用 `lib/main.dart` 普通版本；iPhone 和 iPad 均已安装并启动该版本。
- 原始输出保存在 `validation/`；模拟器截图原图见 `iphone/`、`ipad/`。

## 截图目录

共 38 张手机截图、6 张 iPad 对照截图。所有图片均来自实际运行的模拟器。浅色、深色、横屏和键盘状态分别保留原图。

| 检查流程 | 手机截图 |
| --- | --- |
| 资料库：空状态、已有学习集与继续学习 | [01-library](iphone/01-library.png)、[01a-library-populated](iphone/01a-library-populated.png) |
| 设置：通用、模型、阅读、语音、网页搜索、服务详情 | [02-settings-general](iphone/02-settings-general.png)、[02-settings-models](iphone/02-settings-models.png)、[02-settings-reading](iphone/02-settings-reading.png)、[02-settings-voice](iphone/02-settings-voice.png)、[02-settings-webSearch](iphone/02-settings-webSearch.png)、[02a-model-service](iphone/02a-model-service.png) |
| 阅读器、菜单、文本选择、目录、书签 | [03-reader](iphone/03-reader.png)、[03a-reader-menu](iphone/03a-reader-menu.png)、[03b-reader-selection](iphone/03b-reader-selection.png)、[04-reader-outline](iphone/04-reader-outline.png)、[04a-reader-bookmarks](iphone/04a-reader-bookmarks.png) |
| 助手、输入区、草稿 | [05-assistant](iphone/05-assistant.png)、[05a-assistant-composer](iphone/05a-assistant-composer.png)、[05b-assistant-draft](iphone/05b-assistant-draft.png) |
| 脑图、选中节点、卡片详情、样式、列表、导出 | [06-map](iphone/06-map.png)、[06a-map-selection](iphone/06a-map-selection.png)、[06b-card-details](iphone/06b-card-details.png)、[06c-map-style](iphone/06c-map-style.png)、[06d-map-outline](iphone/06d-map-outline.png)、[06e-map-export](iphone/06e-map-export.png) |
| 工作区侧栏 | [07-workspace-sidebar](iphone/07-workspace-sidebar.png) |
| 笔记设置、编辑、导出 | [08-note-setup](iphone/08-note-setup.png)、[08a-study-note](iphone/08a-study-note.png)、[08b-note-export](iphone/08b-note-export.png) |
| 生词列表与详情 | [09-vocabulary](iphone/09-vocabulary.png)、[09a-vocabulary-detail](iphone/09a-vocabulary-detail.png) |
| 复习问题与答案 | [10-review](iphone/10-review.png)、[10a-review-answer](iphone/10a-review-answer.png) |
| 统计、内置浏览器、网页转换 | [11-statistics](iphone/11-statistics.png)、[11a-web-browser](iphone/11a-web-browser.png)、[11b-web-conversion](iphone/11b-web-conversion.png) |
| 深色阅读与脑图 | [12-reader-dark](iphone/12-reader-dark.png)、[13-map-dark](iphone/13-map-dark.png) |
| 横屏阅读 | [14-reader-landscape](iphone/14-reader-landscape.png) |
| 系统键盘与原生横屏检查 | [15-native-keyboard](iphone/15-native-keyboard.png)、[16-native-landscape](iphone/16-native-landscape.png) |

iPad 对照：[资料库](ipad/01-library.png)、[通用设置](ipad/02-settings-general.png)、[阅读设置](ipad/02-settings-reading.png)、[阅读器](ipad/03-reader.png)、[助手](ipad/05-assistant.png)、[脑图](ipad/06-map.png)。

## 复现

使用专门的模拟器运行；`flutter test` 会安装测试版本。

```sh
python3 tool/capture_mobile_ui.py IPHONE_UDID iphone
python3 tool/capture_mobile_ui.py IPAD_UDID ipad --reference
```

后半段复查可追加 `--from-screen 06c`，前面的界面仍会正常运行，只跳过已检查画面的重复截图。不设置 `CAPTURE_PHONE_UI` 时，集成测试不依赖截图脚本。

原生键盘验收先用 `apps/marginmind/tool/phone_ui_probe.dart` 构建模拟器测试入口（仅设置中文、浅色和无密钥本机模型配置），再运行 `tool/ipad_acceptance` 的 `testPhoneKeyboardAndRotation`。该用例通过系统输入控件弹出真实键盘，并截图检查脑图样式和横屏阅读。验收后重新安装 `lib/main.dart` 的普通启动版本。

原生检查应使用新的 DerivedData 目录，并加上 `-parallel-testing-enabled NO`，避免沿用旧测试运行器。
