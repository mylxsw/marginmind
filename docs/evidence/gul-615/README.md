# GUL-615 验证记录

手机 dock 中的普通按钮使用 `MMThumbDockScope` 的 46×44pt 尺寸，但 `MMDropdownButton` 在最近输入为鼠标时绕过了这个 scope，使用 30×26pt。触摸滚动会把下拉按钮切换到 46×44pt，触发工具条重新计算溢出项。reader 的 sync 和 map 的 fit 因此被移进菜单，与显隐动画是否完成无关。

下拉按钮现在始终遵循 dock 尺寸；手机 dock 的按钮间距改为已有的 `MMSpacing.xs`（4pt）。393pt 窗口下，可用宽度为 357pt，七个 46pt 按钮加六个间距占 346pt。较窄窗口仍通过既有溢出菜单访问命令。

## 截图

- [初始](reported-before.png)、[滚动后丢失 sync](reported-after-scroll.png)：任务附件中的修复前截图，后者的 sync 已消失。
- [初始](reader-initial.png)、[鼠标输入](reader-pointer.png)：修复后的初始状态与鼠标输入状态。
- [隐藏](reader-hidden.png)、[恢复](reader-revealed.png)：触摸下滑隐藏、上滑恢复，七个入口保持一致。
- [脑图](map.png)：修复后的脑图 dock。

修复后截图来自 Flutter Web release 构建，Chrome 模拟 393×852、DPR 2 的手机触屏，使用真实示例 PDF。临时截图入口仅覆盖触屏平台与手机布局、语言，并打开示例学习集，没有提交到产品代码。手势通过 Chrome DevTools 的触摸事件发送。`browser-errors.json` 记录浏览器页面异常。这些证据不代表原生 iPhone 真机验收。

## 回归与自审

`workspace_chrome_test.dart` 在 393pt、402pt 下分别验证 reader 与 map，连续三轮鼠标输入 → 隐藏 → 触摸输入 → 上滑恢复，比较所有可命中的工具项，并检查菜单按钮尺寸与隐藏时不可命中。修复前 reader 测试丢失 sync、map 测试丢失 fit；修复后保持一致。既有 PDF 滚动测试覆盖真实阅读手势与显隐链路。

自审检查了溢出菜单可达性、触控命中尺寸、窄窗口退化、手机与 iPad/桌面分支、显隐时输入与语义移除，以及监听/动画生命周期。改动没有新增异步任务、资源或持久化状态。最终检查命令与覆盖率见 PR 和任务交付评论。
