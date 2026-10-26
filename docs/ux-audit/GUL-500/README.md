# GUL-500 渲染验证（复审版）

2026-10-26，Mac mini / macOS 26.6.2，Flutter 3.47.2
（framework `d3b14c8769`，engine `a804b26164`），pdfrx 2.10.1。
U-G1 的运行时采样与压力证据来自上一轮 `3c5b0c0`，已经评审通过，本轮不重复压测。
本轮 U-R1 的两个候选基于 `e427db3`（已集成 main `049e1e3`）构建。
所有对比均为 Release，保留发布沙盒 entitlements，测试 bundle ID 为
`io.github.mylxsw.marginmind.gul500`，使用仓库示例 PDF 第 1 页。

## U-R1：精确 2:1 采样（已通过评审）

评审确认旧 1× 的 3:1 双线性缩小会跳过源像素，不能保留该策略。
本轮分别构建精确 1:1、精确 2:1，最终代码选择 **精确 2:1**。
两者都不再依赖 `zoom × max(3, 2 × DPR)`。候选一构建时仅临时把
`pdfPreviewPlan` 的 `samples` 默认值设为 1，其余代码和渲染器相同；提交保留默认值 2。

`pdfPreviewPlan` 同时计算 PDFium 渲染倍率与绘制的物理尺寸；两个回调共用它。
pdfrx 只支持一个渲染倍率，PDFium 分别截断宽高，因此 2:1 方案寻找宽高都为偶数的
倍率区间，绘制矩形宽高严格为位图的一半。只对宽度反推倍率仍可能使高度出现相位漂移，
本实现与测试同时检查两个方向。1:1 候选直接用原生倍率，矩形取实际位图宽高，
避免降低倍率触发 pdfrx 的额外 tile 覆盖。

整页最长边上限仍为 4000；超过预算使用 pdfrx 分块，不对分块施加页面对齐。
页面原点每轴最多移动半个物理像素；为满足两个整数尺寸，页面边缘可能收缩数个物理像素
（测试覆盖 A4/Letter/横向页面、DPR 1/2 与 zoom .31/.8273/1.26，差值小于 3 像素）。
文档坐标、导航和独立 widget 命中区域不变，边缘存在相应的小偏差。

### 同条件原图

Skia Release、1280×820 逻辑窗口、同一示例 PDF / 分栏 / 页位置。真实显示模式
分别为 1512×949（1×）和 3024×1898（2×）；截图没有缩放，结束恢复 2×。
基线沿用原始采样的 Skia 构建；旧 `skia-after-*` 保留作被评审版本的历史。

| 条件 | 原图 |
| --- | --- |
| 1× 原始 Skia 基线 | [原图](skia-before-1x.png) |
| 1× 候选一：精确 1:1 | [原图](exact1-1x.png) |
| 1× 候选二：精确 2:1（选择） | [原图](exact2-1x.png) |
| 1× Preview 参照 | [原图](preview-1x.png) |
| 2× 原始 Skia 基线 | [原图](skia-before-2x.png) |
| 2× 精确 2:1 | [原图](exact2-2x.png) |
| 2× Preview 参照 | [原图](preview-2x.png) |

Preview 同为 1280×820 窗口，但适合窗口时页面宽约 523 逻辑像素，应用约 492，
只比较字形观感，不把两个不同尺寸的正文区域作数值等同比较。

正文 ROI 为逻辑 `(300,170)-(700,700)`；2× 坐标加倍。灰度计数含白底，原始统计见 [JSON](exact-screenshot-metrics.json)：

| 条件 | 深色 ≤60 | 中间灰 61–200 |
| --- | ---: | ---: |
| 1× 基线 | 2.23% | 5.56% |
| 1× 旧 3:1 | 1.74% | 6.48% |
| 1× 精确 1:1 | 0.16% | 10.64% |
| 1× 精确 2:1 | 0.26% | 9.80% |
| 2× 基线 | 2.24% | 5.47% |
| 2× 精确 2:1 | 2.15% | 5.71% |

精确 2:1 的“间”“重”横笔不再因跳采样而消失；相比 1:1 候选，正文略深，
因此选择候选二。Arch/Opus (Ora) 对 `2c95773` 的像素级复审确认两个候选均完整保留细笔画，
2× 与基线没有可见差别，U-R1 的采样修复已批准。

深色像素占比不能单独判断 1× 清晰度：评审对同一 ROI 计算的平均墨量
（`255 − 灰度` 的均值）为基线 12.54、精确 1:1 为 13.12、精确 2:1 为 12.70。
墨量基本相等；基线的深色占比高来自锯齿化抽样，新策略将墨迹分布为连续的抗锯齿灰。
**1× 与 Preview 的剩余差异来自笔画主干加粗（CoreText stem darkening）和显示字号不同，
不属于采样问题，不再阻塞本 PR。** Preview 页面更宽，字形约大 6%；其平均墨量为 15.48。
评审和合并由 Arch/Opus (Ora) 负责；真实 1× 屏幕的人眼验收保留在最终验收清单。
若真实 1× 显示器上仍希望加深，可另行评估 gamma 调整；
这也会加深图片和高亮，需要所有者权衡，不纳入本 PR。

### 防止再次漏线的测试

逐一在源位图每一行画 1 像素黑线，使用实际 `FilterQuality.low` 缩至计划的设备尺寸，
断言每行都留有可见像素，覆盖两种候选和 DPR 1/2。负向对照证明旧 3:1 会让黑线完全消失。
另检查分数页面尺寸时宽高都严格为 1:1 / 2:1，以及 viewer 实际发给 PDF 后端的尺寸。
原来的半像素位置、退化矩形测试保留。

### 长文档基准

本轮结果见 [基准记录](benchmark.md)。同一 300 页 / 6000 标注基准入口，
除了帧耗时与 RSS，还在跳页后读取真实绘制结果，测量首次出现正文墨迹的时间。
该时间包含 GPU readback，是可观察出图时间的上界，不冒充 PDFium 纯渲染耗时。

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

**回退跟进负责人：Arch/GPT-Astra（本 issue 负责人）；合并由 Arch/Opus (Ora) 负责。**
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
| Skia 回退（最终构建） | 30 | 150 / 120 | 60 | 无崩溃，103.49 秒：[JSONL](fixed-fullscreen.jsonl) |

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

第三轮：format、analyze、七套 Dart/Flutter 测试、11 项 Python 测试通过；
总行覆盖率 **8039/8735 = 92.03%**，PDF 包 **704/727 = 96.84%**。

- 集成 `19fa24f` 后 format、analyze、七套 Dart/Flutter 测试通过；该轮总行覆盖率 **91.88%**，PDF 包 **96.01%**。
- 集成 `049e1e3` 后 PDF 包重测 **52 项通过**，该包覆盖率 **96.88%**；最终提交由 CI 重跑全部套件。
- 新增像素绘制/几何回归测试通过，Python 工具 **11 项测试**通过，压力脚本行覆盖率 100%。
- Release 构建通过；4 项原生窗口测试（包含打包配置断言）此前通过，CI 再次执行。
- 物理输入的人工回归项见 `docs/macos-acceptance.md`。视觉验收与这些自动测试分开。
