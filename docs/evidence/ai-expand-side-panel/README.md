# AI 扩展想法：侧开设置

用户选定的第 2 版设计为 `reference.png`。实现保留原有生成与草稿审阅链路。

- `native-options-dark.png`：真实 macOS 测试窗口中的展开态，使用隔离的演示数据，没有调用真实模型或修改用户学习集。
- `options-dark.png` / `options-light.png` / `options-english.png`：Flutter 全应用测试中的深浅色、英文展开态。
- `options-narrow.png`：600pt 窗口的原位设置与返回入口；测试同时检查放大到800pt后设置值和输入保持。
- `comparison.png` / `comparison-settings.png`：选定设计与原生渲染放在同一画布上的整体及局部对比，等比缩放，没有纵向拉伸。
- `iteration-1.png` / `comparison-iteration-1.png`：早期原生截图及其与设计稿的对比；输入框底色、输入框圆角和回车字符的视觉问题已修正。

验证覆盖：主菜单入口、悬停与点击、右方向键、Esc逐层退出、独立关闭、主菜单其他操作、输入法相关的原生文本快捷键、窄窗口返回与草稿保留、窗口调整大小、中英文完整显示、两层补生成与预览写入、一次撤销。53项相关测试及1项macOS原生窗口测试通过，静态检查和macOS Release构建通过。

原生窗口使用自动注入的鼠标/键盘事件，未单独做真实硬件鼠标操作验收。当前已安装应用没有被替换。详细视觉复核在仓库根目录 `design-qa.md` 本功能章节。
