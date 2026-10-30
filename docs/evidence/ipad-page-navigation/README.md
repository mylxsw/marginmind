# iPad PDF 悬浮页码条

依据用户选中的第2版布局及随后明确的扁平化要求，实现300×44pt横向半透明胶囊。使用应用现有工具组底色，无背景模糊、渐变、高光描边或阴影。页码、进度和翻页按钮处于同一行，位于阅读区底部安全区上方16pt；取消原52pt底栏占位。

- `reader-flat-dark.png`：当前最终iPad模拟器实际截图，2388×1668px、1194×834pt、2×。
- `comparison-flat.png`：上一版玻璃与当前扁平材质的原尺寸局部对比。
- `design.png`：最初选中的布局设计稿，材质已按用户后续要求修正。
- `reader-dark.png`、`comparison.png`、`comparison-detail-before.png`、`comparison-detail.png`：上一版实现与布局比例调整的历史证据。

完整记录见仓库根目录`design-qa.md`的“iPad PDF 悬浮页码条”及“扁平材质修正”章节。布局版本的44项相关测试及模拟器翻页、进度拖动、页码输入通过；材质修正后15项iPad测试及静态检查通过，未做本轮实体iPad验收。
