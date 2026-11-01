# 语音输入工具条

2026-11-01。截图来自 Flutter 组件测试中的真实组件渲染，语音服务和麦克风使用测试替身。桌面为深色、手机为浅色；测试截图使用 Arial Unicode 字体，系统实际字体可能略有不同。

- `desktop-recording.png` / `phone-recording.png`：输入框外部工具条、计时和按钮间距。
- `desktop-connecting.png` / `desktop-transcribing.png`：连接和最终转写等待。
- `desktop-empty.png` / `phone-empty.png`：未听到声音的普通提示、重试和关闭。
- `desktop-interrupted.png`：连接中断，识别文字保留且可编辑、发送。

生成方式，在 `apps/marginmind` 下运行（Flutter 3.47.6）：

```sh
MM_VOICE_SCREENSHOTS="$PWD/../../docs/evidence/voice-toolbar" flutter test --no-pub test/voice_ui_test.dart
```

验证：语音相关 25 项测试通过；新增断言覆盖外部等宽工具条、8 px 间距、输入框高度、桌面与手机布局、计时、取消恢复草稿和失败重试。助手与手机布局扩大回归中 58 项通过、1 项失败；失败项 `assistant_ui_test.dart` 的 `each failure kind has its reason and its one next step` 期望重试后有 7 条消息，实际为 2 条。临时恢复修改前的 composer 后，单独运行同一测试也得到相同失败，已恢复当前实现。

静态分析和 macOS Debug 构建通过。没有验证真实麦克风、云端识别或已安装应用的运行效果。
