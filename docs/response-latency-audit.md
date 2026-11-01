# 交互响应延迟排查与修复

日期：2026-11-01。测量基线：`46448c7`；菜单修复：`5689d16`。Flutter 3.47.6 / Dart 3.13.5。

RL-01～RL-06 均已修复。保留双击识别所需的时间窗口，但首击业务动作不再等待该窗口结束。

## 实测结果

这里的 0ms / 300ms 指 Flutter 可控测试时钟中，松开指针后到业务回调发生的等待。0ms 表示同步派发，无人为等待；不代表真实机器的完整渲染、磁盘、网络或模型响应为零。

| 编号 | 用户操作 | 修复前 | 修复后及处理方式 |
| --- | --- | --- | --- |
| RL-01 | PDF 正文高亮、划线、研究笔记与词汇标记；研究笔记页边图标 | 鼠标/触摸均 300ms；此前已修复的桌面页边图标为 0ms | 全部 0ms。指针抬起且确认没有拖动时立即派发；识别并吸收 PDF 后端随后送来的同次点击，避免重复打开。 |
| RL-02 | 可重排文档的已有标记、脚注/内部链接 | 鼠标/触摸均 300ms | 全部 0ms。首击立即分发，第二击仍用于选词；跳章节/翻页后重置上一页的双击序列。词汇提示、外部链接、关闭选择和边缘翻页也复用这条即时分发路径。 |
| RL-03 | AI 脑图草稿的保留/排除、来源页码 | 两项均 300ms | 两项均 0ms。来源按钮独立响应；首击立即切换，双击进入编辑前精确恢复首击改动的保留状态，包括子草稿原有选择。生成脑图和扩展预览均覆盖。 |
| RL-04 | 学习笔记内部引用文字跳章节 | 300ms | 0ms。引用文字点击跳转，右侧铅笔按钮编辑；普通笔记文字的编辑方式保持原样。 |
| RL-05 | 脑图展开附注文字选中所属节点 | 300ms | 0ms。首击立即选择所属节点，双击仍编辑附注；保留连接模式和组合键选择行为。 |
| RL-06 | 页边笔记“更多”菜单 | 300ms 渐入动画 | 0ms 无动画，第一帧菜单可操作；已在 `5689d16` 修复。 |

共 17 个诊断场景：16 个单击场景现均为 0ms，1 个菜单动画场景首帧进度为 1。对照数据：[原始基线](evidence/response-latency-audit/baseline-timings.txt)、[仅修复菜单](evidence/response-latency-audit/after-menu-fix.txt)、[全部修复后](evidence/response-latency-audit/after-fixes.txt)。常规测试现在会断言立即响应，并验证 PDF 经过原先等待窗口后也只有一次回调。

## 兼容性保护

- PDF 保留双击选词、拖选、长按、滚动、双指缩放。多指、移动超过阈值和长按不会作为首击派发；真实链接所在区域不使用“附近标记”的扩大命中范围。链接信息随可见标记页预先准备，点击时不等待加载。
- 可重排阅读保留鼠标拖选、触摸长按选词和双击选词，原有手机固定版面双击缩放回归通过。
- 草稿双击编辑前只恢复本次点击实际改动的保留状态，不覆盖其他字段，也不把原本排除的子草稿重新保留。第二击即使发生在下一帧之前，也使用最新状态。编辑器显式取得焦点，Esc 仅取消当前编辑。
- 引用跳转与编辑采用独立入口，避免第一击跳章节后，第二击误落到另一段内容。
- 原生 macOS 集成验证真实 PDF 的悬停、点击固定、弹窗按钮、Esc，以及触摸点击原文立即打开、等待后不重复打开；触摸事件为程序注入，未做本轮手机/iPad 实机验收。

## 保留的时间窗口与排除项

pdfrx 2.10.1 对 `onTextSelectionChange` 通知保留 300ms 防抖。摘录工具条走应用 `_commitSelection` 的帧结束后提交路径，并不等该通知；本次未改变后端通知策略，也不把它说成工具条固定等待 300ms。

以下时间设置不属于本次首击等待，保留原意：

- 双击时间窗口用于判定第二击；首击现在立即执行。
- `MMMotion.layout` 的 320ms，以及手机抽屉/更多面板的 320–380ms，是可见的布局/过渡动画。
- 工具提示 700ms、笔记预览移出后 500ms，是提示出现和离开缓冲；阅读页码 800ms 是后台保存策略。
- 模型名称双击改名、分隔线/节点宽度双击重置，同位置没有单击业务动作。
- `MMSidebarItem` 可配置单击和双击，但当前生产调用没有传双击入口。

学习集、普通脑图节点、概要/关联线标签已使用即时首击；工具栏双击窗口手势位于独立背景区域。通用下拉菜单和当前 SDK 默认的级联菜单无需重复修改。

## 复跑与验收边界

在 `apps/marginmind` 中：

```bash
flutter test --no-pub test/response_latency_test.dart test/immediate_gestures_test.dart test/expansion_test.dart test/map_generation_ui_test.dart --reporter expanded
flutter test integration_test/response_latency_test.dart -d macos --no-pub --dart-define=MM_NOTE_PREVIEW_EVIDENCE=1 --reporter expanded
```

在 `packages/mm_pdf` 中：

```bash
flutter test --no-pub test/response_latency_test.dart test/immediate_annotation_test.dart --reporter expanded
```

在 `packages/mm_design` 中：

```bash
flutter test --no-pub test/immediate_tap_test.dart test/reader_tap_recognizer_test.dart --reporter expanded
```

诊断探针仍保留在两个包的 `test/probes/response_latency_probe.dart` 中，可独立打印计时结果。单元测试使用内存工作区和可控 PDF 后端；原生测试使用临时真实 PDF，不访问用户学习集或真实模型。EPUB、Word 等复用可重排阅读器，本轮未逐个导入真实文件。

完整验证结果和已知基线失败见 [验收记录](evidence/response-latency-audit/README.md)。构建通过不代表用户已经运行新版本；本轮不重启用户原有应用窗口。
