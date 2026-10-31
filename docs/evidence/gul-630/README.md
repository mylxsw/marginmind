# GUL-630 材质证据

393×852 逻辑像素，Flutter widget renderer。CoreSimulator 查询在本运行未返回，因此使用 golden 截图，不宣称真机渲染结果。每张图从上到下：regular、regular 降低透明度、thick、thick 降低透明度、50pt 工具球材质样本。

复现：在 packages/mm_design 中执行 `MM_SCREENSHOTS=1 flutter test test/phone_glass_test.dart --plain-name '393x852' --update-goldens`。默认读取 macOS Arial Unicode；可用 MM_FONT 指定本地字体。截图启用真实阴影；常规 golden 使用测试默认字体及阴影设置，以保持可移植。

本 PR 仅基础材质，具体阅读页面由后续任务实现。顶部径向高光近似原型的椭圆光斑。
