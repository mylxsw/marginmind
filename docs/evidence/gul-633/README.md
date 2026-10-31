# GUL-633 手机端“更多”底部面板与阅读外观二级面板验收证据

环境：Flutter 3.47.2 / Dart 3.13.2，macOS arm64。在已合并 GUL-631 (#153) 与 GUL-632 (#152) 的基础上完成 Stage 3 交付。

## 功能实现说明

1. **手机端“更多”浮动 Liquid Glass 底部面板 (`PhoneMoreSheet`)**：
   - 在手机紧凑屏（`MMInput.of(context).phone && sizeClass == MMSizeClass.compact`）下，工作区顶部“更多”按钮点击弹出基于 `MMLiquidGlass(phoneStyle: MMPhoneGlass.thick)` 的浮动底部面板，内边距 8，圆角 38，高度自适应内容。
   - **标题区**：当前激活文档标题（如“学习的底层逻辑”）+ 右侧圆形半透明关闭按钮（×）。
   - **第一层（3 个磁贴）**：
     - **阅读外观**：带有 26×26 的“Aa”实时纸色色块（反映当前 paperColor 与 inkColor）；点击平滑横向滑动进入二级面板。
     - **页边批注**：点击切换当前文档页边批注状态；开启时仅通过强调色背景高亮表达，无多余说明文本。
     - **生词提示**：点击切换词汇提示开关；开启时仅通过强调色背景高亮表达。
   - **第二层（组 1，文档操作）**：
     - **目录与书签**：唤起底部目录、缩略图与书签面板。
     - **切换文档**：右侧展示“1 / N”文档序号及切换箭头，点击切换到学习集下一篇文档。
     - **裁掉白边**：触发 PDF 白边裁切。
   - **第三层（组 2，学习操作）**：
     - **整理笔记**：唤起笔记整理与卡片化面板。
     - **复习**：右侧显示待复习卡片数量，点击直达复习会话。
     - **生词本**：唤起生词本。
   - **入口精简**：“资料库”入口已移入全高侧边抽屉，底部面板中不再重复；彻底移除了原桌面版长下拉菜单、小字和缩放滑块。

2. **阅读外观二级面板 (`PhoneReaderAppearanceSheet`)**：
   - 点击“阅读外观”后，面板以水平滑动动画推入；左上角圆形返回按钮，右上角圆形关闭按钮。
   - 提供 4 张纸样卡片：白底 (`white`)、羊皮纸 (`paper`)、护眼绿 (`green`)、深色 (`dark`)。
   - 卡片直观展示真实纸色、墨色线条与选中勾选标志，点击后立即通过 `settingsProvider` 生效。
   - 遮罩采用极淡半透明遮罩（`Color(0x14000000)`，8% 透明度），用户可直接看到背后阅读器正文的实时纸色效果再做决定。

3. **双击缩放与手势交互 (`pdf_view.dart`)**：
   - 移除了手机端缩放滑块及“实际大小 / 适合宽度 / 适合页面”文字菜单。
   - 保留原生双指捏合缩放（Pinch-to-zoom）。
   - 在手机滚动配置（`scrollProfile == MMPdfScrollProfile.phone`）下，双击正文在“适合宽度”（fitWidth）与放大（1.5× widthZoom）之间无缝切换。

4. **资料库头部收尾（Stage 2 补充）**：
   - 手机紧凑屏下，资料库页面顶部 toolbar 改为原型场景 1 的大标题“资料库”（`l.librarySection`），右侧为圆形玻璃“+”按钮，搜索框置于下方。
   - 移除了“x 个学习集 · y 张卡片待复习”副标题，学习集卡片本身的徽章保留。

## 视觉证据（393×852 浅深色截图）

所有截图均严格按照 393×852 逻辑像素规格生成：

| 场景 | 浅色 | 深色 |
| --- | --- | --- |
| 原型场景 1 资料库头部收尾 | [01-library-light.png](01-library-light.png) | [01-library-dark.png](01-library-dark.png) |
| 原型场景 6 更多底部面板 | [06-more-light.png](06-more-light.png) | [06-more-dark.png](06-more-dark.png) |
| 原型场景 7 阅读外观二级面板 | [07-appearance-light.png](07-appearance-light.png) | [07-appearance-dark.png](07-appearance-dark.png) |

## 验证与覆盖率

1. **静态代码分析**：
   - `flutter analyze`: **No issues found!**（0 warnings, 0 errors）
   - `dart format`: 全部改动文件 100% 格式规范检查通过。
   - `flutter gen-l10n`: 中英文多语言配置同步更新并通过。

2. **自动化测试**：
   - `phone_more_sheet_test.dart`: 2 项测试全部通过（测试浮动面板布局、磁贴切换、二级外观推入、文档切换与复习直达）。
   - `phone_reader_appearance_sheet_test.dart`: 4 种纸色卡片渲染、实时切换与返回/关闭测试通过。
   - `phone_pdf_double_tap_test.dart`: 手机端双击在适合宽度与 1.5 倍缩放间切换测试通过；非手机模式隔离测试通过。
   - `phone_gul633_screenshots_test.dart`: 浅深色 393×852 截图生成测试通过。
   - `phone_layout_test.dart`: 21 项既有手机布局与设置底层测试全部通过。
   - `phone_reader_controls_test.dart`: 14 项既有手机浮控、标注与交互测试全部通过。
   - `phone_navigation_redesign_test.dart`: 8 项既有导航、抽屉与复习测试全部通过。

3. **改动代码执行行覆盖率**：
   - 相对 `origin/main` 差异行及新增文件的实际可执行代码行：
     - `apps/marginmind/lib/features/library/library_screen.dart`: 20/21 (95.2%)
     - `apps/marginmind/lib/features/workspace/widgets/phone_more_sheet.dart`: 218/232 (94.0%)
     - `apps/marginmind/lib/features/workspace/widgets/phone_reader_appearance_sheet.dart`: 88/88 (100.0%)
     - `apps/marginmind/lib/features/workspace/workspace_screen.dart`: 8/8 (100.0%)
     - `packages/mm_pdf/lib/src/pdf_view.dart`: 6/6 (100.0%)
   - **整体变更代码覆盖率：94.74%（342 / 361 行）**，显著高于任务要求的 80% 门槛。

## 平台隔离与自审结论

- **平台隔离**：所有新交互与视图结构均通过 `MMInput.of(context).phone && sizeClass == MMSizeClass.compact` 和 `scrollProfile == MMPdfScrollProfile.phone` 进行严格门禁。iPad、macOS 及桌面端保持原样，没有任何代码行为或视觉受影响。
- **文案约束**：完全去除多余说明文本（如“已开启/已关闭”字样），开关状态仅依赖强调色背景表达；资料库副标题已去除。
- **资源与内存安全**：没有长驻孤儿定时器，弹层关闭与路由切换均妥善释放监听；无第三方依赖增加，无密钥敏感信息。
