# GUL-500 渲染验证

## 环境与结论

2026-10-26，Mac mini / Apple Silicon，macOS 26.6.2，Flutter 3.47.2
（framework `d3b14c8769`，engine `a804b26164`），pdfrx 2.10.1。
基线为 `8bb4d8a`，两组都是 `flutter build macos --release`，保留发布沙盒
entitlements，以临时 bundle ID `io.github.mylxsw.marginmind.gul500` 运行，
使用仓库自带的双语示例 PDF 第 1 页、分栏视图、1280×820 窗口。

U-G1：采用 macOS `FLTEnableImpeller=false` 的临时规避，不升级 Flutter。
基线未复现原崩溃，不能据有限循环排除偶发问题；此改动也不是修复上游引擎。
此外，显示模式切换期间，同机先前运行的 Debug 实例产生了同栈崩溃，见
[去除路径的栈摘录](display-switch-crash.txt)。这不是本分支 Release 基线，不能混入下表计数。
原审查的栈与 [Flutter #192522](https://github.com/flutter/flutter/pull/192522)
描述的错尺寸 back-buffer / 空纹理问题一致；未验证上游补丁本身，仍不能证明同一根因。
截至查询时该 PR 仍为 OPEN、`mergedAt=null`，没有已确认包含该修复的稳定版本。
回退方式来自 [Flutter 官方 macOS Impeller 文档](https://docs.flutter.dev/perf/impeller#macos)。
后续仅在稳定版包含该修复、同样的压力测试及截图验证通过后移除此配置；升级需另开 PR
并同步 `.fvmrc`、CI 和发布工作流。

U-R1：不是遗漏 DPR。pdfrx 的 `_paintPages` 已使用 `currentZoom * devicePixelRatio`，
但普通倍率未触发精细分块时，绘制的是固定 `200 / 72` 倍的整页预览，且
`drawImageRect` 使用 `FilterQuality.low`（双线性采样）。例如当前约 492 逻辑像素宽
的 PDF 页面，1× 实际仍在缩小约 1654 像素宽的预览，细笔画出现采样不均。
通过公开的 `getPageRenderingScale` 回调让整页预览采用当前缩放 × max(2, DPR)：
1× 使用两倍超采样，避免单倍位图再经亚像素定位 / 双线性采样造成柔化；2× 保持
原生物理像素密度，3× 及以上继续跟随实际 DPR。
最长边最多 2000 像素且不超过引擎建议值；超过上限后仍由 pdfrx 的可见区域分块
保证实际像素分辨率。页面布局、选区和高亮的 PDF 坐标不变。

## 窗口缩放

先打开 Release 应用和示例 PDF，用其实际 PID 执行：

```sh
python3 tool/resize_stress.py --pid <PID> --cycles 250 --delay 0.02 > resize.jsonl
```

每轮尺寸：1280×820 → 1279×819 → 1280×820 → 960×640 → 1280×820。
当前原生工具栏会把 600 高的请求约束为 634，因此小窗口使用 640 高。
脚本通过 macOS Accessibility 写尺寸、等待 20ms 并记录每次读回的实际尺寸。
AppKit 可能合并快速请求或约束窗口大小，因此分别报告请求数和观察到的尺寸变化数，
不把被约束的请求当成崩溃；退出、读写错误、超时、无效尺寸或整轮尺寸始终不变均返回非零。
目标 PID 固定，失败不会重启应用、换进程或把中断轮计为完成。
这是进程外 AX 压力测试，不等同于上游在同一 AppKit 调用栈中同步 shrink/restore 的
确定性复现程序，也不覆盖全屏、显示器热插拔等全部触发路径。

| 构建 | 轮数 / 缩放请求数 | 结果 | 记录 |
| --- | ---: | --- | --- |
| 基线，Impeller | 250 / 1250 | 无崩溃；1000 次实际尺寸变化，125.51 秒 | [JSONL](baseline-resize.jsonl) |
| 修改后，Skia | 250 / 1250 | 无崩溃；1000 次实际尺寸变化，119.47 秒 | [JSONL](fixed-resize.jsonl) |

早期 960×600 的直接读回脚本曾在修改后第 137 轮中断（[记录](interrupted-resize.jsonl)）：
应用仍存活，后续独立读回为 960×634，确认是原生窗口最小高度约束。
另一次并发试跑也遇到尺寸读回不一致（[记录](interrupted-concurrent-resize.jsonl)）。
这些中断不计作崩溃或通过；表内两组均使用最终记录实际尺寸的同一脚本重新跑满。

## 原始截图

同一台 Mac 的显示模式分别为 1512×949 逻辑像素 / 1512×949 物理像素（1×），
以及 1512×949 逻辑像素 / 3024×1898 物理像素（2×）。使用系统显示模式切换，
没有用截图缩放模拟 DPR；完成后恢复 2×。截图是窗口原始 PNG，不含阴影。
请打开原图以 100% 查看；浏览器把 2× 图缩小会掩盖区别。

| 显示倍率 | 修改前 | 修改后 |
| --- | --- | --- |
| 1× | [原图](before-1x.png) | [原图](after-1x.png) |
| 2× | [原图](before-2x.png) | [原图](after-2x.png) |

## 自动化验证

- `dart format --set-exit-if-changed apps packages`、`flutter analyze` 通过。
- 七个 Dart / Flutter 测试套件全部通过，汇总行覆盖率 **91.33%**，`mm_pdf` **93.13%**。
- 新回调的 3 个可执行行全部覆盖；测试观察真实 viewer 发给测试 PDF 后端的像素尺寸，
  覆盖 1× → 2× → 3× → 1×、缩放与整页分配上限。
- Python 工具测试通过；`python3 -m trace --count --summary --module unittest discover -s tool/tests`
  的脚本行覆盖率为 100%。测试覆盖计数、错误中断、尺寸校验、超时和参数校验。
- `xcodebuild test ... -enableCodeCoverage YES` 的 4 项原生窗口测试通过，包含打包后
  `FLTEnableImpeller` 的配置断言。Release 构建通过。

物理触控板、跨显示器拖动和原生全屏的人工回归项见 `docs/macos-acceptance.md`。
