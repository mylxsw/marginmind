# GUL-495：完整工作区原生滚轮基准

## 环境与输入

- 修改前：最新 main `8bb4d8a`，已包含 GUL-496。修改后：本 PR rebase 后的工作区通知隔离与共享缩略图缓存实现。
- Mac mini M4、16 GB、macOS 26.6.2、Flutter 3.47.2 / Dart 3.13.2；两组均为 macOS Release，Metal Impeller。
- 真实 MarginMindApp、FileLibraryStore、原生 PlatformMenuBar；分屏模式，资料库侧栏显示，PDF 页缩略图侧栏保持默认关闭。窗口最大化，3024×1728 物理像素，DPR 2。不是先前的独立 MMPdfView 窗口。
- 300 个脑图节点（10 个主题，每个 29 个子节点）；120 页图片型 PDF，每页是一张独立的 1800×2400 栅格图。文字也烘焙在图片内。它是可生成的合成图片样本，不是真实扫描书籍。
- PDF SHA-256：`b9e559cd3cbd620e2e2dc06238076785775127b3ed52ab3c15f9da801c38d4ee`。两组使用同一文件、同一窗口条件和输入脚本。
- CGEvent 系统事件队列发送像素滚轮，应用正常接收 PointerScrollEvent：10 秒连续向下、10 秒间歇阅读（每秒 150 ms 滚动，850 ms 停顿，覆盖 800 ms 保存防抖）、10 秒连续向上。每组实际收到 **1290** 个事件；结束都在第 **2** 页。视频第 18 秒都显示第 12 页附近。
- 从第一个滚轮事件开始收集 32 秒 FrameTiming；未通过 PDF 控制器驱动滚动。就绪前的加载不计入；记录期间没有运行本任务的构建或测试。机器属于共享开发环境，其他进程的负载未完全隔离。

## 数据

单位：毫秒。分位数为排序后 `floor((n - 1) × p)` 对应的观测值。UI 是 buildDuration，raster 是 rasterDuration，总耗时是 totalSpan。

| 指标 | 修改前 p95 | 修改前 p99 | 修改后 p95 | 修改后 p99 |
| --- | ---: | ---: | ---: | ---: |
| UI | 0.903 | 2.477 | 0.790 | 0.982 |
| Raster | 1.699 | 1.852 | 1.727 | 1.844 |
| 总耗时 | 2.622 | 4.128 | 2.535 | 2.784 |

修改前采集 1305 帧，修改后 1304 帧；两组均没有 totalSpan 超过 16.67 ms 的帧。采样结束 RSS 分别约 295.3 MiB / 293.1 MiB。总耗时 p50 为 2.134 / 2.173 ms，未见整体中位帧时改善；主要变化在 UI 尾部。单组前后结果不足以证明所有 PDF 都流畅，本样本也未复现原始严重卡顿。

原始逐帧微秒数据和输入事件时间/位移：[修改前](gul-495-workspace-before.json)、[修改后](gul-495-workspace-after.json)。`frames_us` 每行依次是 UI、raster、total；`events` 的 ms 从首个滚轮事件计时。FrameTiming 不衡量异步光栅化完成前的白页/模糊页延迟，因此还需结合录屏。录屏以 60 fps 采集，上传版压缩至 1280 像素宽，不改变帧率；两段作为 PR 描述中的附件链接提供。

此前重建回归测试证明，每次翻页对工作区、阅读器、脑图、侧栏、菜单的无关重建已隔离，保存阅读元数据也不重建。这里补足的是完整应用、图片型 PDF 和原生事件输入下的量化佐证，而不是将自动化滚轮称作物理触控板。

## 复现

```sh
swift tool/sample/make_image_pdf.swift apps/marginmind/assets/sample/workspace-images.pdf
(cd apps/marginmind && flutter build macos --release --target benchmark/workspace.dart --dart-define=BENCH_LABEL=after)
python3 tool/run_workspace_benchmark.py workspace-after --source apps/marginmind/build/macos/Build/Products/Release/MarginMind.app
```

对照组将同一个 benchmark/workspace.dart、window_manager 开发依赖和 PDF 复制到 main 的独立 checkout，构建同样的 Release 入口，再以 workspace-before 运行脚本。生成的文件与运行产物不提交；采样结束将 PDF 移出 assets/sample，再用 lib/main.dart 构建正常应用。

该入口使用临时目录内的专用资料库，不改用户资料库。脚本只启动/终止自己创建的进程，激活测试窗口，暂时移动指针到 PDF 区域并在结束后复位；运行时避免同时操作桌面。需要屏幕录制和辅助功能权限。脚本拒绝启动失败、未收到足够输入或未生成足够帧的运行；失败重试的数据未纳入上表。

物理触控板手感和物理 ⌘0 的原生菜单匹配已按评审决定列入 [所有者最终验收](../macos-acceptance.md)，不再作为本 PR 的合并条件。
