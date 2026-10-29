# 文本下划线（2026-10-29）

采用用户确认的第三版交互及随后确认的组件细化稿。只增加下划线工具和设置栏，不调整阅读器其他布局。设置栏无“下划线 / 颜色 / 线型”标题，线型名称只通过提示与无障碍标签提供。

顶部 U 进入连续划线，已有选区则立即应用。划词工具条的 U 只处理当前选区，不改变当前阅读工具。设置栏选择颜色和线型后保持展开；点击空白或 × 收起，Esc 退出下划线。自定义色盘沿用现有实现。默认蓝色实线，颜色和线型独立持久化，不改变高亮笔设置；连续模式遵循现有“同步到导图”开关。

组件复用：

- `MMToolbarGroup` / `MMFloatingToolbar`、`MMToolbarButton`、色点、分隔线及 `HighlightCustomColorPicker` 沿用现有组件。
- 新增 `MMToolbarPreviewButton`，为设计系统提供带视觉预览的工具栏按钮。
- `AnnotationLineStylePicker` 与 `UnderlineStyleToolbar` 独立组合；不依赖具体文档或保存逻辑。
- `AnnotationMoreColorsButton` 和 `AnnotationPalettePlacement` 从原高亮入口提取，供两个工具共用。
- `MMPdfAnnotationLinePainter` 同时绘制文档下划线与线型预览，实线、虚线、点线和波浪线保持一致。

标注保存类型、线型、颜色及各页文字矩形。旧数据缺少新字段时继续按高亮读取。同一区域重复划线更新已有下划线，保留导图关联；复制粘贴保留样式。下划线关联导图时用页边标记表示，不额外叠加状态线。

证据：`design-reference.png` 为确认稿；`underline-toolbar-*`、`underline-entry-*` 和 `underline-component-*` 为真实 Flutter 组件导出，2 倍密度；`comparison-toolbar.png` 上方为确认稿局部，下方为实现。截图通过 `MM_SCREENSHOTS` 运行 `test/underline_tool_test.dart` 生成。

验证覆盖选区及连续划线、非模态弹层下直接拖选 PDF、四种线型、跨行跨页、改色、自定义色、撤销重做、磁盘重开、旧高亮兼容和剪贴板复制。PDF 交互测试运行实际 pdfrx 视图，但使用可控 PDF 后端；不等同于已安装应用的原生鼠标验收。本次未替换日常安装版。

最终验证：核心层 201 项、数据层 44 项、PDF 视图 25 项、阅读器相关 58 项、设计组件 24 项，共 352 项测试通过；工作区 `flutter analyze --no-pub` 无问题；最终 `flutter build macos --release --no-pub` 成功。
