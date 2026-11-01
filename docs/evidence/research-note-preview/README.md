# 研究笔记页边图标响应优化

日期：2026-11-01。工具链：Flutter 3.47.6 / Dart 3.13.5，macOS。

## 原因与改动

笔记内容已在工作区内存中。原图标通过 `PdfOverlayInteractionRegion` 交给 PDF 阅读器的通用单击/双击识别处理：在未修改的 `dfc055e7` 上，用可控测试时钟确认，松开鼠标后 0ms、299ms 均未回调，300ms 时才回调。

桌面图标现在独立处理点击，松开鼠标即回调，下一帧显示卡片；真实墙钟延迟还取决于机器负载，不将测试时钟当作帧率或生产性能基准。图标的滚轮事件转交 PDF，触屏保持原有点击、长按、滑动手势路径。

鼠标进入图标立即显示本地笔记预览。预览只更新自己的区域，不写工作区的 pending 状态，不抢键盘焦点。移出后保留 500ms，移入卡片取消关闭；滚动、切文档、点击外部、Esc 关闭；点击图标固定展示。卡片保留查看全文、脑图定位、继续问入口。

## 验证

- 新交互及相关应用回归：15 项通过，含悬停首帧、焦点/工作区状态保持、卡片按钮、离开/外部/Esc/滚动/切文档关闭、点击固定、旧标注与阅读位置回归。
- `mm_pdf`：136 项通过，含新图标首帧回调、避免重复派发、原文定位边界、图标上滚轮、触屏点击、原有缩放/选字/手势。
- `mm_core` 323、`mm_research` 62（跳过 1）、`mm_data` 77、`mm_layout` 44、`mm_platform` 63 项通过。
- 全仓 `flutter analyze --no-pub` 通过；本次 7 个 Dart 文件格式与 `git diff --check` 通过。
- macOS 原生窗口 + 原生 PDFium + 真实示例 PDF 集成测试通过：悬停首帧显示，移入卡片保持、移出关闭，点击即时固定、Esc 关闭；截图见 [native-hover.png](native-hover.png)。Esc 由弹窗自身监听，避免依赖当前焦点。
- 正常 Debug 应用构建通过（已恢复 `lib/main.dart` 入口）；`xcodebuild test` 原生测试 28 项通过。

原生测试复跑（在 `apps/marginmind` 目录）：

```bash
flutter test --no-pub -d macos integration_test/research_note_preview_test.dart --dart-define=MM_NOTE_PREVIEW_EVIDENCE=1
```

测试使用内存工作区和临时 PDF，不读写真实学习集；截图先写应用沙盒临时目录，控制台输出路径，再从宿主复制到本证据目录。

## 全量检查的已有失败

应用全量：1462 通过、58 跳过、31 失败。设计组件全量：228 通过、1 跳过、4 失败。全部失败均在独立、未修改的 `dfc055e7` 工作树上复现，未扩大本次修复范围。

全仓格式检查另报 6 个已有文件不符合格式，本次未改动它们：`phone_more_sheet.dart`、`beta_features_test.dart`、`study_notes_ui_test.dart`、`adaptive.dart`、`menu.dart`、`sidebar.dart`。

应用全量的 31 项已有失败：

- `adaptive_layout_test.dart: touch windows iPad portrait: source above map, sidebar drawer and companion panel`
- `adaptive_layout_test.dart: touch windows iPhone: one pane at a time with a top switch and thumb dock`
- `full_translation_test.dart: FullTranslation Widgets & Visual Evidence FullTranslationCheckpoint renders expanded and collapsed and captures screenshots`
- `full_translation_test.dart: FullTranslation Widgets & Visual Evidence FullTranslationPanel renders running and review states and captures screenshots`
- `full_translation_test.dart: FullTranslation Widgets & Visual Evidence FullTranslationStrip renders key, no-model, offline, budget strips, actions, and goldens`
- `ipad_adaptation_test.dart: tablet split grip and compact tools dark`
- `ipad_adaptation_test.dart: tablet split grip and compact tools light`
- `map_node_bar_touch_test.dart: tablet icons expose every action and long press only explains (dark: false)`
- `map_node_bar_touch_test.dart: tablet icons expose every action and long press only explains (dark: true)`
- `map_node_bar_touch_test.dart: tablet root shows only applicable icons`
- `map_update_test.dart: current source fingerprint is shared and detects text and reading changes`
- `map_update_test.dart: phone review leaves canvas visible above a bottom panel`
- `map_updates_reading_test.dart: sidebar update dot stays clear when revisiting pages and still detects changed material`
- `mobile_polish_test.dart: Android portrait: library title fits and search still filters`
- `mobile_polish_test.dart: iPhone 402×874: library title fits and search still filters`
- `multiple_maps_test.dart: sidebar creates renames switches deletes and undoes maps`
- `note_rich_export_test.dart: share night widget golden and 2x PNG`
- `note_rich_export_test.dart: share paper widget golden and 2x PNG`
- `note_rich_export_test.dart: share plain widget golden and 2x PNG`
- `phone_more_sheet_test.dart: PhoneMoreSheet capabilities, switch document picker, reading settings and organize notes`
- `phone_sidebar_regression_test.dart: phone drawer preserves imported document flash and scene 8 learning hierarchy`
- `popover_response_test.dart: reading, translation, AI and service popovers are complete in their first frame`
- `reader_chrome_test.dart: reader buttons share foreground colors in dark`
- `reader_chrome_test.dart: reader buttons share foreground colors in light`
- `reader_chrome_test.dart: window title (U-R5) reader tools control the sidebar and appearance separately`
- `reader_sidebar_notes_test.dart: sidebar reveals quote and line notes with the margin collapsed`
- `reader_sidebar_notes_test.dart: sidebar reveals quote and line notes with the margin expanded`
- `selection_translation_test.dart: palette, translation and preserved selection in dark`
- `selection_translation_test.dart: palette, translation and preserved selection in light`
- `workspace_chrome_test.dart: phone map dock preserves items through hide and reveal at 393.0`
- `workspace_chrome_test.dart: phone map dock preserves items through hide and reveal at 402.0`

设计组件已有失败：`settings_form_test.dart` 的菜单勾选、`tokens_test.dart` 的脑图生成几何、`toolbar_density_test.dart` 的 mac light/dark 截图。

未做 Windows/Linux 原生运行或手机/iPad 实机验收；触屏结论来自回归测试。
