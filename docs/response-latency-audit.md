# 交互响应延迟排查

日期：2026-11-01。基线：`46448c7`。Flutter 3.47.6 / Dart 3.13.5。

状态：确认 5 类单击等待仍待处理；另发现的页边笔记菜单动画已修复。

## 实测结果

这里的 300ms 指 Flutter 可控测试时钟中，松开指针后到业务回调发生的等待，不是实际机器的完整响应耗时。测量按 1ms 推进；网络、磁盘、模型、PDF 渲染耗时不在这个数字内。

| 编号 | 用户操作 | 测量结果 | 来源与状态 |
| --- | --- | --- | --- |
| RL-01 | 点击 PDF 正文上的高亮、划线、研究笔记原文标记、词汇标记 | 鼠标/触摸回调均等待 300ms；研究笔记页边图标鼠标 0ms、触摸 300ms | `packages/mm_pdf/lib/src/pdf_view.dart:1965` 的 `PdfOverlayInteractionRegion` 和 `:2691` 附近的 `onGeneralTap` 均由 pdfrx 的单击/双击识别分发。**待处理**；上一次修复只让桌面页边图标独立响应。 |
| RL-02 | 可重排文档中点击已有标记、脚注/内部链接 | 鼠标/触摸均等待 300ms | `apps/marginmind/lib/features/workspace/widgets/reflow_reader.dart:1063`、`:1086`：`onTapUp` 和双击选词共享手势。**待处理**。同一 `_tap` 还承担词汇提示、外部链接、关闭当前选择、分页边缘翻页，均有同源风险；这次直接测量的是已有标记和脚注跳转。 |
| RL-03 | AI 脑图草稿点击保留/排除、点击草稿的来源页码 | 两项均等待 300ms | `apps/marginmind/lib/features/assistant/widgets/expansion_widgets.dart:494`：整卡 `onTap` 与 `onDoubleTap` 并存，来源按钮也被父级双击识别拖住。**待处理**；`MapGhostNode` 被生成脑图/扩展预览复用。 |
| RL-04 | 学习笔记中点击内部引用文字跳到对应章节 | 等待 300ms | `apps/marginmind/lib/features/study_notes/note_view.dart:1673`：外层双击编辑包着内层单击跳转。**待处理**；调用来自 `:1189` 的 `XrefBlock`，普通笔记文字不走这个双击分支。 |
| RL-05 | 点击脑图展开附注的文字，选中所属节点 | 等待 300ms | `apps/marginmind/lib/features/workspace/widgets/mind_map_canvas.dart:1982`：附注文字的双击编辑手势拖住所属节点的单击选择。**待处理**；不是附注区域所有按钮都慢。 |
| RL-06 | 页边笔记卡片右上角“更多”菜单 | 原动画 300ms：首帧进度 0、299ms 为 0.9967、300ms 完成；修改后首帧进度 1、过渡时长 0ms | `apps/marginmind/lib/features/workspace/widgets/reader_margin_notes.dart:559`：这一个 `PopupMenuButton` 漏掉了即时展示设置。**已修复**，与通用下拉菜单保持一致；回归验证菜单第一帧可点击“复制”。 |

PDF 探针复用同一种矩形和分发回调，分别验证普通标记、`note:`、`vocabulary:` 和页边图标。真实弹窗的后续工作不计入回调等待。可重排阅读探针使用内存 Markdown/HTML 章节；EPUB、Word 等格式复用该阅读器，但本轮没有逐个导入真实文件验收。

17 个诊断场景包括 16 个单击场景和 1 个菜单动画场景：基线中 15 个单击为 300ms，桌面研究笔记图标为 0ms；菜单动画为 300ms。结果见 [基线数据](evidence/response-latency-audit/baseline-timings.txt) 和 [菜单修复后数据](evidence/response-latency-audit/after-menu-fix.txt)。

## 另外发现的 300ms 通知

pdfrx 2.10.1 的 `pdf_viewer.dart:1638` 在 `_onSelectionChange` 中对 `onTextSelectionChange` 做 300ms 防抖；`MMPdfView` 将它转为 `onSelectionChanged`。这会延后“选区状态发生变化”的通知。

当前摘录工具条走 `_commitSelection` 的帧结束后提交路径（`pdf_view.dart:1713`、`:1791`），不以这个防抖回调作为打开前提。因此不把它写成“摘录工具条固定延迟 300ms”。后续排查阅读栏显隐与选区状态联动时需要覆盖它。

## 已排除的同类误报

- 学习集网格/列表、普通脑图节点、概要/关联线标签使用 `MMInteractive.immediateTap`；首击不等双击计时。学习集和节点行为回归 30 项通过。
- 工具栏、侧栏标题区把窗口双击手势放在按钮后方的独立区域；按钮不再被标题栏双击拖住。通用工具栏/下拉菜单即时展示回归 5 项通过。
- 普通 `MMDropdownButton` 已使用无动画弹出；级联菜单在当前 Flutter SDK 中 `MenuAnchor.animated` 和 `SubmenuButton.animated` 默认均为 `false`。没有把 SDK 内未启用的 500ms 动画算成产品问题。
- 模型名称双击改名、分隔线/节点宽度双击重置，没有同一位置的单击业务动作；拖动也有独立处理，不能仅凭 `onDoubleTap` 判定存在单击卡顿。
- `MMSidebarItem` 允许同时传入单击和双击，底层默认手势存在潜在等待；当前生产调用没有配置该双击入口，未计入已发生的问题。
- `MMMotion.layout` 的 320ms、手机抽屉/更多面板的 320–380ms 是显式布局/过渡动画；不是先空等再执行单击。工具提示的 700ms、笔记预览移出的 500ms、阅读页码后台保存的 800ms 也分别是提示、关闭缓冲、后台写入策略。
- 应用自身未发现 UI 点击链路中主动 `Future.delayed(300ms)` 再执行操作的代码。主要来源是手势识别和漏配的菜单动画。

## 后续处理顺序

1. 先处理 RL-01 / RL-02：覆盖面最大，需要让标记/链接立即响应，同时保留双击选词、拖选、触屏长按/缩放、脚注优先级，以及同一次点击只派发一次回调。
2. 处理 RL-03：先让来源按钮脱离整卡双击识别；保留/排除与双击编辑是两个不同动作，编辑入口需要独立处理，避免为了立即响应而在编辑前先改动保留状态。
3. 处理 RL-04 / RL-05：单独处理编辑入口，保留单击跳转/选择的即时响应。RL-04 还需避免首击跳转后重建内容，导致第二击落到另一段文字。

本轮代码修复仅为 RL-06；RL-01～RL-05 的定位、测量和建议已记录，交互行为保持当前实现。

## 复跑与验收边界

```bash
# 在 apps/marginmind 中：9 个诊断场景（不以 300ms 为必须维持的正确结果）
flutter test --no-pub test/probes/response_latency_probe.dart --reporter expanded

# 在 packages/mm_pdf 中：8 个诊断场景
flutter test --no-pub test/probes/response_latency_probe.dart --reporter expanded
```

探针按当前结果打印时延，允许后续修复后变为 0ms；文件名不以 `_test.dart` 结尾，常规测试不会把尚未修复的延迟固化为预期行为。全程使用内存工作区和可控 PDF 后端，不访问用户学习集或真实模型。

本轮验证：应用探针与页边笔记/概要相关回归共 23 项通过；PDF 探针 8 项通过；学习集/普通节点回归 30 项通过；工具栏/下拉菜单回归 5 项通过；全仓静态检查、本次文件格式检查、macOS Debug 构建通过。触摸结果来自注入触摸事件，本轮未做手机/iPad 实机或新的原生窗口交互验收。
