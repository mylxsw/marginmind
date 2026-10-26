# GUL-500 长文档滚动与出图基准

2026-10-26，Mac mini / macOS 26.6.2，Flutter 3.47.2，Skia Release，真实 2× 显示模式。
两组同为 `e427db3` 应用代码和本轮新增出图探针的基准入口；唯一渲染差异：

- before：恢复原始 200 DPI 预览，不施加页面对齐。
- after：精确 2:1 预览 / 页面对齐，最长边 4000 像素上限。

使用 `tool/sample/make_benchmark_pdf.swift` 的 300 页确定性 PDF、6000 个高亮，
1000×700 窗口；两轮滚动、跳页、惯性轨迹与缩放，各 360 帧。
两次正式测量期间没有并行构建/测试；最初与构建同时运行的一次 after 只作试跑，未计入结果。
原始数据：[before](benchmark-before.json)、[after](benchmark-after.json)。

| 场景 | RSS MiB 前 → 后 | total p95 ms 前 → 后 |
| --- | ---: | ---: |
| cold-scroll | 259.3 → 304.1 | 0.993 → 1.357 |
| cold-jump | 266.0 → 308.9 | 1.020 → 1.159 |
| cold-inertia | 279.0 → 310.9 | 1.198 → 1.225 |
| cold-zoom | 287.7 → 312.8 | 0.774 → 1.087 |
| warm-scroll | 263.8 → 314.7 | 0.882 → 1.016 |
| warm-jump | 260.6 → 312.4 | 1.299 → 1.015 |
| warm-inertia | 270.1 → 312.5 | 1.068 → 1.125 |
| warm-zoom | 261.2 → 311.2 | 0.872 → 1.038 |

RSS 是各场景结束时的 `ProcessInfo.currentRss`，不是进程全程峰值，也不等于 pdfrx 的缓存预算。
观测到的场景末尾最大 RSS 从 **287.7 增至 314.7 MiB（+27.0 MiB / 9.4%）**；
after 第二轮稳定在 311–315 MiB，没有随跳页持续累积。最坏 total p95 为 1.357 ms。
100 MiB 缓存是图像软预算，文本、GPU 和其他对象不计入，不能用它断言应用总内存上限。

## 可观察出图时间

两轮场景结束后，依次瞬时跳到 299、279、259、239、219、199、179、159、139、119 页。
每帧读取真实 RepaintBoundary 图像，中央 40% 宽、60% 高区域至少有 100 个 RGB 均小于 100
的墨迹像素时记录时间，5 秒超时则失败；黄标注和白页不满足条件。
`endOfFrame` 确保跳页后的页面已绘制，避免读旧画面。读取图像的 GPU 回传开销计入时间。
该指标是“首次可见正文”，不是完整高清图块完成、也不是纯 PDFium 耗时；未清空 OS 缓存。

| 10 次跳页 | before | after |
| --- | ---: | ---: |
| 最小值 | 27.022 ms | 47.372 ms |
| 中位数 | 31.798 ms | 47.619 ms |
| 最大值 | 51.097 ms | 49.876 ms |

两组均成功出图，没有 5 秒超时；新策略中位数增加 **15.821 ms**，约一帧 60 Hz。
这是更大预览位图的可测开销，不能说性能完全没有变化；本次小样本没有出现明显卡顿或持续白页，
也不足以推断大扫描件、复杂矢量文件或其他机器的尾延迟。

## 复现

```sh
swift tool/sample/make_benchmark_pdf.swift apps/marginmind/assets/sample/benchmark.pdf
(cd apps/marginmind && flutter build macos --release --target ../../packages/mm_pdf/benchmark/main.dart)
python3 tool/run_pdf_benchmark.py after
```

before 使用相同基准入口，仅把 `getPageRenderingScale` 恢复为 `200 / 72`，
`_beginPagePaint` 只保留 `canvas.save()`，与成对 restore 匹配；保持 Skia 配置不变。
分别构建后通过 `--source <app.bundle>` 指定测试包。不要在测量期间并行构建或运行测试。
原始 JSON 保存逐帧微秒值、RSS 和逐次出图延迟，录制脚本保留固定窗口录屏。
生成的 benchmark.pdf 不提交，测量结束从发布资源目录移走。
