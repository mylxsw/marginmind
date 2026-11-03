# 移动端侧滑目录与菜单设计稿

这是用于确认方向的图像设计稿，不是实际运行截图；本轮未修改应用代码。图像中的屏幕比例和细节经过概念排版，实际尺寸以实现后的设备验证为准。

采用内置 image_gen 工具生成，第二轮校正专用助手图标和添加菜单宽度。最终文件：[preview.png](preview.png)。

- 目录从左侧滑出，约占屏宽 85%，右侧露出当前内容，并允许点击外部或向左滑动收起。
- 顶部保留资料库入口及学习集名称，移除返回脑图、返回阅读和关闭叉号。
- 目录文档标题单行省略；需要完整名称时使用长按预览。
- 根级添加、更多菜单不显示重复标题；子菜单保留具体标题和返回按钮。
- 两列三行：目录、添加菜单、更多菜单，各显示深浅色。

## 最终编辑提示词

```text
Use case: precise-object-edit / ui-mockup.
Edit image 1, the Chinese six-screen mobile design board. Image 2 is a supporting reference ONLY for the app's dedicated assistant emblem at the top left of its "AI 助手" header: a flat indigo-blue circle with TWO small white slanted rounded vertical bars inside, like a slightly tilted pause mark. This is NOT a star or sparkle.

Make only these targeted fidelity corrections to image 1, keeping its six screens, layout, all Chinese labels, 85% drawers, single-line truncated document titles, dark/light pairings and overall visual design intact:
1. Replace EVERY purple-blue sparkle/star assistant button in ALL SIX screens with that exact dedicated blue circle + two white slanted short rounded bars from reference image 2. Keep each button in its current position and size. No stars, sparkles, magic-wand marks, or glow; simple flat brand emblem.
2. In the first row's deep/light directory learning list, the "卡片" row should use the brain-shaped line icon as in the app reference, and "生词本" should keep the vocabulary/book line icon. Avoid duplicate identical icons for these two distinct rows.
3. In the second row, the floating ADD bottom sheet must span the ENTIRE phone artboard width with equal small left and right margins, covering both the drawer and its exposed workspace strip. It must not stop at the drawer's 85% edge. It has no title and no X, only handle and two action rows "导入文档…" / "添加网页…". Preserve its opaque neutral surface and restrained corners.
Do not add "返回脑图", "返回阅读", or a close X to any drawer. Do not wrap the document title. Preserve all other content. Output one complete 2-column 3-row board.
```
