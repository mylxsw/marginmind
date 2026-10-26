# GUL-500 渲染验证（复审版）

2026-10-26，Mac mini / macOS 26.6.2，Flutter 3.47.2
（framework `d3b14c8769`，engine `a804b26164`），pdfrx 2.10.1。
所有对比均为 Release，保留发布沙盒 entitlements，测试 bundle ID 为
`io.github.mylxsw.marginmind.gul500`，使用仓库示例 PDF 第 1 页。

## U-R1：候选修正与验收边界

撤回上一版“2× 原生像素预览足够清晰”的结论。上一版 `max(2, DPR)` 在 2×
退化为一份物理像素采样，再叠加非整数页面位置和双线性过滤，会让细笔画发灰。
仅把页面绘制对齐到物理像素，也没有解决本 PDF 在 1× 下的细笔画问题。

本次采用 `zoom × max(3, 2 × DPR)`：1× 三倍采样，2× 两倍物理像素采样。
整页最长边上限从 2000 提高到 4000 像素（正方形 RGBA 位图最坏 64 MB），
超过预算后继续使用 pdfrx 的可见区域分块；不再用固定 200 DPI 限制 Retina 超采样。
在预算内，用背景/前景绘制回调成对 save/restore，把每页内容和同层选区、搜索标记
对齐设备像素网格；坐标换算使用 `documentToGlobal`，不假设 Canvas 包含祖先层变换。
页面原点位移每轴不超过半个物理像素，宽高收缩小于一个物理像素。
PDF 文档坐标和导航不变；独立 widget 高亮/命中区域可能存在上述亚像素偏差。
高倍率分块不套用该变换，避免改变 tile 的坐标系。

### 控制变量原图

同一 Skia 渲染器、同一 1280×820 逻辑窗口、同一示例 PDF / 分栏 / 页位置。
基线是 `8bb4d8a` 的原始采样，仅在测试 app 的 Info.plist 关闭 Impeller；
新图使用本次采样和对齐策略。显示模式为 1512×949 逻辑像素，分别真实输出
1512×949（1×）和 3024×1898（2×），没有缩放截图冒充 DPR；最后恢复 2×。

| 倍率 | Skia 原始采样 | Skia 新策略 | Preview.app 参照 |
| --- | --- | --- | --- |
| 1× | [原图](skia-before-1x.png) | [原图](skia-after-1x.png) | [原图](preview-1x.png) |
| 2× | [原图](skia-before-2x.png) | [原图](skia-after-2x.png) | [原图](preview-2x.png) |

Preview 同样是 1280×820 窗口，单页适合窗口模式；其页面宽度与应用分栏不同，
只作原生文本观感参照，不把它与应用的 ROI 做数值比较。请在 100% 原图下查看。
旧 `before-*.png` / `after-*.png` 保留为第一次评审历史，不作为本次控制变量证据。

同一正文 ROI：逻辑坐标 `(300,170)-(700,700)`，2× 即 `(600,340)-(1400,1400)`。
精确计数见 [JSON](screenshot-metrics.json)。灰度用 Pillow `convert('L')`；比例以整个 ROI（包括白底）为分母。

| 倍率 / 采样 | 深色 ≤60 | 中间灰 >60 且 ≤200 |
| --- | ---: | ---: |
| 1× Skia 基线 | 2.23% | 5.56% |
| 1× 新策略 | 1.74% | 6.48% |
| 2× Skia 基线 | 2.24% | 5.47% |
| 2× 上次被退回版本 | 0.28% | 9.62% |
| 2× 新策略 | 2.19% | 5.68% |

2× 大幅发灰的回归已消除，接近基线；1× 部分细笔画更连续，但整体仍略淡。
**这些数值不能证明 1× 已达到“与 Preview 一样清晰”或“明显更清楚”。U-R1 保留待复审，
不把自动化测试通过当成视觉验收，也不建议在视觉标准未确认前合并。**

像素回归测试实际用 `FilterQuality.low` 绘制一像素黑线：半像素偏移时成为两条灰线，
对齐后必须是一条黑线且没有灰色邻行。另测 1×/2×/3×、负坐标、不同亚像素偏移、
退化小矩形，并观察 viewer 发给 PDF 后端的尺寸，断言 Retina 不再回落为 1:1 采样。

## U-G1：Skia 是实际运行后端，仍属预防性规避

`FLTEnableImpeller=false` 未升级引擎。Release 进程活动渲染时运行 `sample <pid> 10 1`：

- [Skia 栈摘录](skia-runtime.txt)：光栅线程出现 `DlSkCanvasAdapter::Flush`、
  `GrMtlOpsRenderPass`、`GrMtlCommandBuffer`，证明实际运行 Skia/Ganesh Metal 后端。
- [Impeller 基线摘录](impeller-runtime.txt)：出现 `impeller::RenderPassMTL::Draw` 等帧。
- Skia 栈的共享 DisplayList 函数签名仍带 `impeller::TRect/Matrix/AiksContext` 类型；
  因此不能用全文搜索“没有 impeller::”判断后端。关键是实际光栅调用链的正向证据。

[Flutter #192522](https://github.com/flutter/flutter/pull/192522) 查询仍为 OPEN、未合并。
不能证明原崩溃与该补丁完全同源；配置依据为
[Flutter 官方文档](https://docs.flutter.dev/perf/impeller#macos)。

**回退跟进负责人：Arch/GPT-Astra（本 issue 负责人）；合并确认由 mylxsw 负责。**
重新开启条件：稳定版明确包含 #192522 或等价修复；单独升级 PR 同步 `.fvmrc`、CI、
发布工作流；去掉开关后补运行时后端证据，并通过同一缩放/全屏压力、1×/2×截图回归。
在这些条件满足前保留回退，不因测试若干轮没崩就自行开启。

### 固定 PID 的窗口 / 原生全屏压力

```sh
python3 tool/resize_stress.py --pid <PID> --cycles 30 --fullscreen > fullscreen.jsonl
```

每轮先请求 1280×820 → 1279×819 → 1280×820 → 960×640 → 1280×820，
记录每次实际尺寸；再通过原生 AX 对象写 `AXFullScreen=true/false`，有限等待状态到达，
等待动画并再次读回。辅助 Swift 进程保留同一 AX 窗口引用，避免 System Events 在全屏
时按应用名称重新解析窗口。失败、超时、窗口消失返回非零，不重启目标、不换 PID，
未完成的轮次不计入成功。需要终端辅助功能权限和 Xcode Command Line Tools。

| 构建 | 完整轮数 | resize 请求 / 实际变化 | 全屏状态变化 | 结果 |
| --- | ---: | ---: | ---: | --- |
| Impeller 基线 | 28（目标 30） | 140 / 112（仅完整轮） | 56（仅完整轮） | 第 29 轮 AX 读回失败：[JSONL](baseline-fullscreen.jsonl) |
| Skia 回退（最终构建） | 30 | 150 / 120 | 60 | 无崩溃，103.48 秒：[JSONL](fixed-fullscreen.jsonl) |

基线第 29 轮发生 AX `cannotComplete (-25204)`，进程仍在、CGWindow 窗口仍在，
`sample` 的主线程和光栅线程都处于事件循环等待；没有对应新崩溃报告。
因此是未完成的压力测试，**不能把它说成已复现 Impeller 崩溃，也不能声称基线通过 30 轮**。
Skia 与基线的目标次数均为 30；目前仍不足以建立“基线崩溃、修改后不崩”的因果证据，
结论继续是预防性规避。

失败日志中的工作区绝对路径已脱敏；轮次和错误内容保留。

最初仅用 AppleScript 的全屏尝试分别完成 1 / 2 轮后发生 AX 查询错误，进程仍存活且
CGWindow 中窗口仍存在；不是已确认的引擎崩溃，也不算通过，保留
[基线中断](interrupted-baseline-fullscreen.jsonl) / [Skia 中断](interrupted-fixed-fullscreen.jsonl)。
此前仅窗口尺寸的 250 轮结果保留在 [基线](baseline-resize.jsonl) / [Skia](fixed-resize.jsonl)。
此前同机 Debug 实例显示模式切换的 [同栈崩溃](display-switch-crash.txt) 也不是本次受控
Release 基线，不能混入计数。没有做物理热插拔；显示模式切换用于截图，不当作压力轮次。

## 自动化验证

- format、analyze、七套 Dart/Flutter 测试通过；总行覆盖率 **91.34%**，PDF 包 **93.54%**。
- 新增像素绘制/几何回归测试通过，Python 工具 **11 项测试**通过，压力脚本行覆盖率 100%。
- Release 构建通过；4 项原生窗口测试（包含打包配置断言）此前通过，CI 再次执行。
- 物理输入的人工回归项见 `docs/macos-acceptance.md`。视觉验收与这些自动测试分开。
