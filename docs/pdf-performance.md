# PDF 性能与缩略图接口（GUL-495）

## 结构

`mm_pdf` 继续封装 pdfrx / PDFium；应用层不引用渲染插件。页面图像由 pdfrx 管理：保留默认 100 MiB 目标预算、横纵方向各一个视口的预渲染范围和默认渐进预览策略，缩放期间复用预览，静止后由 pdfrx 补齐详细图块。预算是 pdfrx 的软上限，不包含文字层和 GPU 内存。曾试验 1200 像素低分辨率预览与 128 MiB 预算，缩放后 RSS 反而上升且帧耗时无稳定收益，已撤回。

高亮按页建立索引，每页仅遍历自己的矩形。等价标注列表保留身份，未变化页面复用 overlay widget；缓存最多保存 16 页最近一次缩放尺寸。改色、几何变化、强调状态和文档切换使相应缓存失效。框选矩形通过独立 notifier 更新，拖动不重建整个 PDF 视图。

## GUL-496 可复用接口

```dart
final controller = MMPdfViewController();
// 传给 MMPdfView(controller: controller, ...)，onReady 后请求。
final png = await controller.renderPreview(page, pixelWidth: 320);
// 调用方确认当前文档、页码仍匹配后，用 Image.memory(png) 显示。
```

- `page` 从 1 开始；`pixelWidth` 为物理像素，由调用方把逻辑宽度乘 DPR，合法范围 1–1024，向上取整至 64 像素桶。
- 预览只包含原始 PDF 页面，不绘制应用高亮叠加层。
- 返回 `Future<Uint8List?>`；成功是只读 PNG 字节，不需要调用方释放。文档未就绪、页面不存在、原生渲染未返回图像、请求期间文档失效时返回 null。非法参数抛 `RangeError`，渲染异常传播给调用方处理。
- 每个视图有独立 16 MiB PNG LRU；同页同桶请求合并，原生渲染串行执行；超过预算的单张图片会返回但不保留。
- 文档切换和视图销毁清空缓存、取消活动缩略图渲染、跳过过期排队任务、丢弃过期结果。侧栏只请求可见缩略图，不要一次排队数百页；切换文档时也须清理自身显示状态。
- 复用阅读器已打开的文档，**不再打开一份 PDF**。pdfrx 的主阅读器图像缓存是私有实现，此接口不访问其内部缓存；缩略图 PNG 与阅读器图块有独立预算。
- `actualSize()` 使用 PDF 点与逻辑像素 1:1（100%），`fitWidth()` / `fitPage()` 作用于当前页。菜单与键盘通过焦点分发；阅读器 ⌘0 是实际大小，脑图 ⌘0 仍是适应窗口。

## 可复现基准

```sh
swift tool/sample/make_benchmark_pdf.swift apps/marginmind/assets/sample/benchmark.pdf
(cd apps/marginmind && flutter build macos --release --target ../../packages/mm_pdf/benchmark/main.dart)
python3 tool/run_pdf_benchmark.py after
```

基准使用真正的 PDFium、300 页确定性文字 PDF、6000 个高亮，运行两轮滚动、跳页、减速滚动轨迹与缩放。每场景 360 次逐帧变换；导出每帧 build / raster / totalSpan 微秒原始值、p50/p95/p99、超过 16.67ms 比例与进程 RSS。输出在 `performance-artifacts/`。`cold`/`warm` 标签指第一轮与第二轮；不表示每场景都清空 OS/PDFium 缓存。

脚本使用当前已构建的二进制；对照组必须由基线代码构建，同样的基准入口、PDF 和窗口条件。录屏需要 ffmpeg、系统屏幕录制和辅助功能权限，按测试窗口的屏幕区域裁剪，进程与录制均在前台调用内等待结束。录制时须保持窗口在前台且无遮挡；此脚本按主显示器的缩放比例换算坐标。测试入口不进入正常应用构建；生成的 PDF 不提交，完成后移走，避免进入发布包。

这是渲染管线基准：跳页与惯性轨迹通过控制器驱动，并非注入真实滚动条拖拽或物理触控板输入。组件测试另验证 PointerPanZoom 的缩放锚点。真实触控板手感仍需结合真机人工交互验收，不能仅凭低帧耗时宣称完成。

## 工作区通知隔离

即时阅读位置由独立的 `readingPagesProvider` 提供，只有页码显示订阅。工作区展示内容通过 `workspaceContentProvider` 过滤仅阅读元数据变化的保存通知；原始仓库和资料库继续收到完整更新。GUL-496 的缩略图请求接口没有变化。工作区回归证据及尚缺的真实触控板验收见 [评审修订记录](performance/gul-495-revision.md)。

完整工作区的原生滚轮事件基准入口为 `apps/marginmind/benchmark/workspace.dart`，生成器为 `tool/sample/make_image_pdf.swift`，录制与输入脚本为 `tool/run_workspace_benchmark.py` / `tool/workspace_wheel.swift`。MMPdfThumbnail 统一调用上述 renderPreview 缓存，不再使用 PdfPageView。物理手势与原生按键匹配由项目所有者按 `docs/macos-acceptance.md` 最终验收。
