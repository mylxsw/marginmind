# GUL-530 助手面板截图

由 `apps/marginmind/test/assistant_screenshots_test.dart` 生成（Linux 上用 Noto Sans SC 渲染；widget 测试不渲染 PDF，原文栏为空）：

```
MM_SCREENSHOTS=docs/evidence/gul-530 MM_FONT=~/.fonts/NotoSansSC.otf flutter test test/assistant_screenshots_test.dart
```

- `assistant-light.png`：浅色，1440×900，对话含步骤条、`p.24` 引用、提议卡，输入区有选区 chip、自动附带页 chip 与快捷操作。
- `assistant-dark.png`：深色，同一状态。
- `assistant-narrow.png`：1000×760 窄窗口，侧栏自动收起，面板 360。

“改标题”条目的 `✎` 在该 Linux 字体中缺字显示为方框，macOS 系统字体有此字形。
