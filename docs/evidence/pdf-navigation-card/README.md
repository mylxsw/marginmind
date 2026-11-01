# PDF 页面侧栏独立卡片

- `design-selected.png`：用户选定的第 1 版设计稿。
- `annotations-dark.png`：真实 PDF、深色标注卡片与居中标题。
- `bookmarks-dark.png`：书签跳转至第 2 页。
- `outline-light.png`：浅色目录卡片。
- `narrow-light.png`：900×820 逻辑视口。
- `comparison.png`／`comparison-detail.png`：设计与实现的整体／局部对照，左侧为设计，右侧为实际界面；局部标题上下依次为设计、实现。
- `design-qa.md`：视觉、功能检查与已确认的基线失败。

运行验证：在 `apps/marginmind` 中执行 `flutter test --no-pub integration_test/pdf_navigation_card_test.dart -d macos --reporter expanded`。测试使用独立内存库和临时示例 PDF，不修改用户学习库。可用 `PDF_CARD_SHOT_SERVER` 编译参数指定 localhost PNG 接收器；请求为 `POST /capture/{name}`，含 PNG 请求体与 Content-Length，接收器返回 200。
