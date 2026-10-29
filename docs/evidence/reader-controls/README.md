# 阅读器菜单与贴线浮控

2026-10-29：菜单与按钮按设计稿1，中间分隔按用户随后选择的稿2。

- `design-reference.png`：菜单、缩放/裁边分组。
- `divider-reference.png`：细分隔线与贴线浮控。
- `comparison-menus.png` / `comparison-divider.png`：源图与实际Flutter组件的同画布对照。
- `*-dark.png` / `*-light.png`：原生组件样式导出，2倍密度；`*-full.png`保留展开位置，`workspace-*-narrow.png`检查窄窗口。

完整复核记录见仓库根目录 `design-qa.md`。导出使用 `apps/marginmind/test/reader_controls_screenshots_test.dart`，环境变量 `MM_READER_SHOTS` 指定绝对输出目录，`MM_FONT`指定中文字体；`MM_LATIN_FONT`、`MM_SYMBOL_FONT`可补充系统字体与快捷键符号。

测试后端不绘制PDF正文，原生Release另用已有真实PDF核验；用户文档截图没有保存至本目录。
