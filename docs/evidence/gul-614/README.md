# GUL-614 验证记录

触屏正文下滑累计 24pt 隐藏表头与底部控件，上滑 8pt 或轻点正文恢复。手机学习集改为 50pt 顶栏和 56pt 拇指工具条；资料库、复习、生词本及整理笔记从侧栏或更多进入。Mac 保持工具栏常显。

## 截图

每组对照图从左到右依次为原型、应用初始显示、下滑隐藏、上滑恢复。单独的 PNG 保留原始尺寸；`*-map.png` 展示示例学习集的脑图，iPad 使用查看全图，检查节点文字没有换行裁切。

| 场景 | 应用逻辑尺寸 | 浅色 | 深色 |
| --- | --- | --- | --- |
| iPhone | 402 × 874 | [对照](phone-light-comparison.png) | [对照](phone-dark-comparison.png) |
| iPad 横屏 | 1194 × 834 | [对照](ipad-light-comparison.png) | [对照](ipad-dark-comparison.png) |
| iPad 竖屏 | 834 × 1194 | [对照](ipad-portrait-light-comparison.png) | [对照](ipad-portrait-dark-comparison.png) |
| iPad 紧凑 Split View | 500 × 1000 | [显隐](ipad-compact-light-comparison.png) | [显隐](ipad-compact-dark-comparison.png) |

应用图来自 Flutter Web release 构建，使用应用内“打开示例学习集”创建的资料与真实 PDF。浏览器注入触屏平台并通过 Chrome DevTools 发送触摸手势；临时截图入口未提交到产品代码。原型为 `design/prototype/layout-density.html` 的新方案。浏览器没有系统状态栏，原型保留了 iPhone 54pt / iPad 24pt 的状态栏；手机原型尺寸为 393 × 852。应用默认白纸阅读配色，不跟随深色 chrome 反转 PDF。Web 平台能力隐藏原生助手入口。对照用于检查结构和显隐状态，不作像素金图。

紧凑 Split View 的附加图按显示／下滑隐藏／上滑恢复排列，复用 iPad 表头，不显示手机工具条或标签栏。

本机 `xcrun simctl list devices booted` 未返回，已终止该子进程。没有声称完成原生 iPhone / iPad 截图与真机验收；这些仍需在设备上复核。`browser-errors.json` 记录浏览器页面异常。

## 测试与自审

新增测试覆盖方向阈值与换向、顶部回弹、无效输入、多个独立 hold、用户滚动与程序跳页的区分、隐藏后的命中/语义移除、PDF 视口稳定、菜单锚点、Mac 常显、无障碍、减少动态效果、键盘、画笔、旋转，以及生词本返回保留当前 pane。手机既有导航测试同步到新入口。

自审检查入口闭环、空学习集和窄窗口、文档与布局切换、手势和程序滚动、键盘与选区、监听/动画释放、菜单及弹窗锚点、扁平化材质和敏感信息。修复了桌面浮层被表头遮挡、换文档后选区 hold 未释放、手机画笔工具条溢出、上下文控件遮挡，手机工具条边框被背景覆盖，以及紧凑 iPad 仍走旧工具栏分支的问题。

最终命令、覆盖率和 CI 结果见本 issue 与 PR 的交付说明。
