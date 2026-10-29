# GUL-549 裁边验证

macOS 实机运行生产 ReaderPane、工具栏、菜单与 PDFium，使用应用自带的两页 PDF。截图为系统窗口捕获：

- [裁边前](01-before.png)：一次性胶囊、既有高亮。
- [裁边后](02-cropped.png)：真实裁去白边，标题和段落保持原阅读位置。
- [调整模式](03-adjust.png)：完整页面、四边手柄、范围工具条；既有高亮与笔迹可见。

原生重现（在 `apps/marginmind`）：

```sh
flutter run -d macos -t example/crop_acceptance.dart
flutter run -d macos -t example/crop_acceptance.dart --dart-define=CROP_SELF_CHECK=true
```

原生自检结果：`NATIVE_CROP_OK`。开启裁边、调整后取消的阅读线均为 `{page: 1, y: 727.6428571428571}`；原始文本相同，同一区域导出的 PNG 字节相同。运行使用 Flutter 3.47.2、pdfrx 2.10.1。构建出现现有 Keychain 弃用警告，构建成功。

验证命令：

```sh
dart format --set-exit-if-changed apps packages
flutter analyze
python3 tool/coverage.py --minimum 80
python3 -m unittest discover -s tool/tests
(cd packages/mm_data && dart test --platform chrome test/browser_library_store_test.dart)
```

全部包测试通过；浏览器存储 7 项、Python 工具 17 项通过。平台限定用例在常规测试中跳过 9 项。整体与改动覆盖率见 [coverage.md](coverage.md)。

单元及 widget 覆盖：扫描页像素框和检测缓存、14pt 余量、笔迹扩展、三种范围、文件迁移与重开、开关和阅读位置、四边手柄与键盘 1/10pt、取消草稿、完成一次撤销、提交时重复取消、隐藏标注计数、真实正反向跨三页选区、触控长按、搜索、链接目标、框选及画笔坐标。

自审修复了阅读元数据过滤器漏掉裁边变化、菜单文字溢出、首页滚动边界限制、调整时隐藏原有标注、慢拖动小数丢失、文档重载就绪状态及过期异步结果。检测和渲染可取消；原始文档、图片句柄在 finally 释放。未改写 PDF、OCR 或导出坐标。

本批次提供每个 MMPdfView 独立的裁边参数及原始阅读线。原型场景 9 的双栏入口与界面编排属于后续批次 C，本批次的截图没有将单栏冒充双栏验收。
