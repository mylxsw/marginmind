# GUL-521 扫描 PDF 文字识别

2026-10-27，Mac mini / macOS 26.6.2，Flutter Debug，使用自动生成的中英文扫描讲义与隔离学习集。原 PDF 和用户资料库不参与写入。

## 实现

`VisionPdfOcr` 通过 `marginmind/pdf_ocr` 调用 Vision。后台串行队列逐页绘制原矢量内容、识别扫描页并写入不可见 Core Text 文字；已含文字的页面跳过。副本为 `documents/<hash>.ocr.pdf`，写完后原子替换，原 PDF 不变，不升级 format 7。

文档检测使用独立队列，打开其他文档不排在识别批次后面。识别位图最长边限制为 2048 像素。取消在当前页识别完成后生效，其余页仍复制进副本；重试从已有副本接续。取消不会中断正在执行的 Vision 请求，因而响应时间最多包含一个页面的识别时间和剩余页面的复制时间。错误时保留旧副本并清理临时文件。

页面旋转、裁剪统一转换到 PDFium 显示坐标；页面尺寸及原有应用标注的显示位置保持一致。识别副本复用 pdfrx 选字、查找、摘录和高亮。

## 验证

- `dart format --set-exit-if-changed apps packages`、`flutter analyze`。
- 八包测试通过，汇总覆盖率 93.88%（11213/11944 行）；应用 325 项测试、Python 工具 11 项测试通过。新增 Dart OCR 文件覆盖率超过 95%；原生 `PdfOcr.swift` 为 254/258 行（98.45%）。
- `xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=macOS' -enableCodeCoverage YES`：10 项原生测试通过，含实际 Vision 中英文识别、像素不变、文本选择坐标、旋转裁剪、取消续跑、重复任务、错误清理，以及识别队列阻塞时仍可检测另一份文档。
- 300 页真实 Vision 回归：27.01 秒，主线程 20 ms 定时器响应 1324 次；第 30 页 RSS 543.70 MiB，后续采样峰值 682.28 MiB（增长 138.58 MiB）。测试限制预热后增长小于 256 MiB。指标来自 XCTest activity `OCR_STRESS`；不同硬件、图像质量和布局会影响速度。
- 回归测试覆盖：翻页不重建阅读面板，切换文档恢复页码，副本重新打开后清理旧选区并重跑已有搜索。

## 真机界面

| 截图 | 内容 |
| --- | --- |
| [scan.png](scan.png) | 扫描页提示与识别入口 |
| [options.png](options.png) | 范围与中英文选项 |
| [progress.png](progress.png) | 300 页后台识别与工具栏进度胶囊 |
| [recognized.png](recognized.png) | 副本载入，页面与文档行显示已识别 |
| [search.png](search.png) | 中文“学习”命中 300 页，文字高亮与扫描图像对齐 |

本机 macrun 默认 socket 不存在，已有备用 socket 无响应；截图通过本机窗口捕获获得。此处为自动化输入验证，未声称物理鼠标和键盘验收。

复现：

```sh
swift tool/sample/make_ocr_pdf.swift apps/marginmind/assets/sample/benchmark.pdf 300
cd apps/marginmind
flutter build macos --debug -t benchmark/ocr.dart
./build/macos/Build/Products/Debug/MarginMind.app/Contents/MacOS/MarginMind
```

生成的 `benchmark.pdf` 已在仓库忽略规则内。测试入口创建独立临时资料库，不覆盖用户学习集。
