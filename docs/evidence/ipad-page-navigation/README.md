# iPad PDF 悬浮页码条

依据用户选中的第2版设计稿，实现300×44pt横向半透明玻璃胶囊。页码、进度和翻页按钮处于同一行，位于阅读区底部安全区上方16pt；取消原52pt底栏占位。

- `design.png`：选中的设计稿。
- `reader-dark.png`：最终iPad模拟器实际截图，2388×1668px、1194×834pt、2×。
- `comparison.png`：裁去设计稿设备边框后，与实现按相同宽度并排比较。
- `comparison-detail-before.png`：第一轮局部对照，滑条偏长。
- `comparison-detail.png`：最终局部对照，已收窄胶囊并稳定页码区域宽度。

完整验收记录见仓库根目录`design-qa.md`的“iPad PDF 悬浮页码条”章节。44项相关测试及静态检查通过；模拟器确认翻页、进度拖动和页码输入，未做本轮实体iPad验收。
