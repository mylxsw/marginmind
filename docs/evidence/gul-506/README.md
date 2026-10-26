# GUL-506 v0.6 整体复验截图

2026-10-26，Mac mini（Apple 芯片），macOS 26.6.2，Flutter 3.47.2。v0.6.0（6）Release 构建，按 `Release` 工作流签名，
临时 bundle ID `io.github.mylxsw.marginmind.review506`。结论和逐节说明见 [体验审查第 8 节](../../ux-audit.md#8-v06-整体复验)。

测试文档是体验审查用的 301 页中英文 PDF。原文件没有目录，用 [`outline.swift`](outline.swift) 从每页开头找出“第 N 章”和“N.M”标题，
再用 [`add_outline.py`](add_outline.py)（pypdf）写入 64 章、94 节的 PDF 大纲：

```sh
swift outline.swift book.pdf > outline.json
python3 add_outline.py book.pdf outline.json book-toc.pdf
```

| 截图 | 内容 |
| --- | --- |
| [reader-toc-jump](reader-toc-jump.jpg) | 页面侧栏目录，跳到第 7 章 |
| [reader-2x](reader-2x.png)、[reader-1x](reader-1x.png)、[reader-1x-crop](reader-1x-crop.png) | 同一页在 2× 与 1× 下的原始截图（未缩放） |
| [excerpt](excerpt.jpg) | 摘录后的行高亮与卡片 |
| [excerpt-cross-page](excerpt-cross-page.jpg) | 跨页摘录 |
| [reveal-zoomed](reveal-zoomed.jpg) | 放大后回原文，缩放不变 |
| [locate-card](locate-card.jpg) | 定位卡片 |
| [library-after-reopen](library-after-reopen.jpg) | 退出重开后的资料库 |
| [review-en-dark-front](review-en-dark-front.jpg)、[review-en-dark-back](review-en-dark-back.jpg) | 复习卡，英文深色 |
| [review-zh-light-front](review-zh-light-front.jpg)、[review-zh-light-back](review-zh-light-back.jpg) | 复习卡，中文浅色 |
| [review-cross-page-before](review-cross-page-before.jpg)、[review-cross-page-after](review-cross-page-after.jpg) | 跨页摘录正面，修复前后 |
| [review-cross-page-zh-light-back](review-cross-page-zh-light-back.jpg)、[review-cross-page-en-dark-back](review-cross-page-en-dark-back.jpg) | 跨页摘录背面，中文浅色 / 英文深色 |
