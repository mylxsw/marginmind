# GUL-547 验证记录

基线：`1b2c78e`。pdfrx 锁定版本：2.10.1。

| 验证 | 结果 |
| --- | --- |
| `dart format --output=none --set-exit-if-changed apps packages` | 410 文件，无格式变化 |
| `flutter analyze --no-pub` | No issues found |
| `python3 tool/coverage.py --minimum 80` | 全部包测试通过（含原有平台跳过项）；整体 90.99% |
| 新增/修改可执行 lib 行，按 diff 与 package LCOV 相交 | 420 / 421，99.76%；详见 changed-coverage.json |
| `dart test --platform chrome test/browser_library_store_test.dart`（mm_data） | 7 项通过，含阅读数据 IndexedDB 关闭/重开与并发缓存合并 |
| `python3 -m unittest discover -s tool/tests` | 17 项通过 |
| Chrome 打开产品 HTML 原型前 9 个场景 | 9 场景均激活，无 pageerror |
| `flutter test packages/mm_pdf/test/reading_probe_test.dart packages/mm_pdf/test/reading_geometry_test.dart` | 6 项通过 |

核心模型/编辑器后补共享卡片删除场景后重新执行 mm_core 全部测试：182 项通过。覆盖率文件也随之更新，改动行报告使用更新后的 LCOV。

PDF widget 测试使用仓库现有可控 PDF 后端，实际执行 PdfViewer 的布局、MMPdfView 导航与探针交互，不宣称这些测试覆盖 PDFium 的字形栅格化。

裁边探针验证单页、非对称裁边、矩形选择命中、高亮和笔迹几何。完整多页选区和产品性能验收由批次 A 完成；路线与边界见 ADR 0004。页边跨页排布属于 B，空间切换和用户布局恢复属于 C。

原生 PDFium 自检已通过：2 页示例，裁剪输出 523×786，首页读取 585 个字符（`NATIVE_PROBE_OK`）。直接读取工作区文件受 macOS 沙箱限制，因此自检读取打包资产；交互探针默认也使用打包示例。

原生探针可通过以下命令读取打包示例并执行裁剪渲染后退出（无需绕过 macOS 文件沙箱）：

```sh
cd apps/marginmind
flutter run -d macos -t ../../packages/mm_pdf/example/reading_probe.dart --dart-define=PROBE_SELF_CHECK=true
```
