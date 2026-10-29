# GUL-576 流式阅读验收

Linux ARM64 桌面应用，Flutter 3.47.2 / Dart 3.13.2，Xvfb 1280×720。图片来自真实 GTK/Flutter 窗口；使用测试生成的 Markdown，无用户文档或凭据。

| 步骤 | 截图 |
| --- | --- |
| 导入入口 | [01-import.png](01-import.png) |
| 导入后阅读 | [02-read.png](02-read.png) |
| 原文选区与浮动工具条 | [03-selection.png](03-selection.png) |
| 摘录到脑图 | [04-excerpt.png](04-excerpt.png) |
| 即时增大字号 | [05-font-size.png](05-font-size.png) |
| 字号改变后标注仍对齐 | [06-annotation-alignment.png](06-annotation-alignment.png) |
| 卡片回原文 | [07-back-to-source.png](07-back-to-source.png) |

原生集成测试通过测试文件选择器导入临时 Markdown，使用内存仓库隔离数据；工作区、解析器、排版和选区工具条使用生产实现，最后验证卡片回原文。它同时断言改字号前后存储的 revision/chapterId/UTF-16 锚点完全相同，且新布局仍能获取标注文本框。

在 `apps/marginmind` 运行：

```bash
xvfb-run -a -s '-screen 0 1280x720x24' flutter test integration_test/reflow_reader_test.dart -d linux --no-pub --reporter expanded
```

设置 `--dart-define=GUL576_SHOTS=<已存在的输出目录>` 可同时保存七张 X11 窗口截图（需要 Python Pillow）。CI 的 macOS 集成测试不设置此选项，因此不依赖 X11/Pillow。

macOS 构建、Xcode 原生窗口测试及同一阅读集成测试已接入 `.github/workflows/ci.yml`。本机没有执行 macOS 测试；根据任务 owner 的决定，macOS 实机截图由 owner 验收时补充。

自审覆盖入口到持久化、跨章节/失效/Unicode 锚点、异步加载取消、段落与图片释放、字体注册、版本目录隔离、摘要验证，以及命令、令牌和中英文文案。固定 EPUB 的纯图拖动、缩放和逐页预览跳转也有 Widget 回归覆盖。修复了字体重复注册、重复划线目标校验绕过、部分失效锚点仍可点击、旧分页几何在新视口溢出、加载中搜索丢失和返回后键盘焦点丢失。

截图主机未安装 emoji 字体，emoji 显示为缺字方框；组合字符与 emoji 的 UTF-16/字素边界由自动测试验证。

## 最终验证

- `flutter analyze --no-pub`：无问题。
- `dart format --set-exit-if-changed apps packages`：576 个文件，0 变更。
- 全部包的测试套件通过；应用在最终修复后完整重跑 `flutter test --coverage --no-pub`：811 通过、21 项按默认条件跳过。
- `python3 -m unittest discover -s tool/tests`：17 通过。
- `python3 tool/coverage.py --report-only`：32615 / 35640 行，总覆盖率 **91.51%**；应用覆盖率 **88.92%**。
- 将 Git diff 的新增 / 修改行与 LCOV 可执行行相交：1595 / 1807 行，**88.27%**（包含生成的本地化代码）。
- Xvfb Linux 桌面 debug 构建及阅读集成测试：1 通过，七张原生窗口截图已保存。
