# GUL-498 摘录文本与高亮验证

2026-10-26，Mac mini（Apple 芯片），macOS 26.6.2，Flutter 3.47.2 / Dart 3.13.2，Xcode 27.1。
修改前为 main `8bb4d8a`，修改后为首次交付提交 `7d98c0c`。两者均为 `flutter build macos --release` 构建，
使用独立 bundle ID `io.github.mylxsw.marginmind.review498before` / `review498after`，
重签保留 Release.entitlements，未使用日常资料库。

## 对照

使用同一份三页 PDF，从第 1 页的 “This sentence” 拖到第 2 页的 “中文内容”。
PDF 有日期页眉、路径与变化页码的页脚，中英文硬换行、连字符断行和较大的段间距。
生成方法：`swift fixture.swift fixture.pdf`（在本目录运行）。

| 检查 | 修改前 | 修改后 |
| --- | --- | --- |
| 跨页选区 | 页脚和下页页眉蓝色选中 | 松开后仅正文选中，页眉页脚无选区 |
| 高亮 | 单词矩形，连页眉页脚一起保存 | 第 1 页 3 个行矩形、第 2 页 2 个；页眉页脚不高亮 |
| 引文 | 夹带日期、路径、页码；硬换行原样保留；断词有方框字符 | 只有正文，段内连接，保留段落空行；international 不再含 U+0002 |
| 脑图卡片 | 原文按 PDF 行宽断开 | 按卡片宽度自然排版，保留段落分隔 |

真实选区与点击经桌面事件注入完成，截图由系统窗口截图取得。截图和实际落盘的引文及矩形如下：

- [修改前选区](before-selection.png) / [修改后选区](after-selection.png)
- [修改前高亮和卡片](before-highlight-card.png) / [修改后高亮和卡片](after-highlight-card.png)
- [修改前完整引文](before-quote.png) / [修改后完整引文](after-quote.png)
- [实际落盘结果](excerpts.json)

## 首次交付验证

- `dart format --set-exit-if-changed apps packages`：161 个文件，无改动。
- `flutter analyze`：无问题。
- `python3 -m unittest discover -s tool/tests`：3 项通过。
- `python3 tool/coverage.py`：七个套件全部通过，总覆盖率 91.42%；新纯函数 107/107 行，选区接入新增可执行行 45/45，共 152/152。
- `xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=macOS' -enableCodeCoverage YES`（应用目录）：3 项原生测试通过。
- `flutter build macos --release`：通过；上述截图来自独立签名的 Release 应用。

自审覆盖选区→引文→高亮→卡片→复习完整链路、空选区、无文本/几何无效、反向跨页选择、
邻页失败、异步过期与卸载、旧数据、正文误判和多栏间隙。修复了两项真机发现：PDFium 的 U+0002
断词标记，以及主题改变后 PDF 画布缓存仍显示原始选区的问题（下一帧显式重绘）。
空白/纯页眉选区会清掉原生选区并关闭旧工具条，已补真实选区委托回归测试，并在最终 Release 构建中拖选页眉复验：不出现工具条或卡片。

## 识别边界与人工项

只认完整页面按矩形位置取出的最上/最下行（不依赖 PDF 文本流顺序）：位于上下 8% 内，与正文有明显间隔，并且在至少两页上内容及位置重复。
日期单独归一化；书眉或 HTTP(S)/文件路径页脚中的行首/行尾页码，要求数字差等于 PDF 页码差，保留页码偏移，支持非相邻页。其他标题和 URL 中的数字不替换，包括“第 1 章 / 第 2 章”和“Chapter N”；中文页码匹配“第 N 页”。证据不足、只有一页证据、短页、位置不一致或
文字几何不匹配时无法建立安全的高亮，取消该页摘录；其余证据不足时保留可疑行；不是通用版面语义识别。
原始空行和明显几何间距保留为段落分隔；页边界本身按段内换行处理。
拖动过程中仍使用 PDF 引擎的临时预览，松开后以清理结果替换。
只处理新选区，不改旧引文或旧高亮矩形，不变更文件格式。拉丁断词规则会将 `well-` 换行 `known` 合并为 `wellknown`；没有词典时无法可靠区别断词和复合词，此处保留该取舍。

物理触控板跨页拖选、触控板滚动中取消、物理 ⌘C 待人工验收，见 `docs/macos-acceptance.md`；
本次不把自动化事件注入等同于物理设备验收。


## 复审修订（2026-10-26）

分支已 rebase 到 main `19fa24f`，包含 #26 和 #32。保留 #26 的按页高亮索引、16 页 overlay LRU、
缩略图缓存与翻页隔离；工作区相关代码相对 main 没有差异。持久行高亮经过原索引与 LRU，
临时选区在缓存之外组合。回归测试检查：选区出现及清除不替换原有高亮组件，未选中页继续返回同一缓存列表。

候选行改为按矩形位置取最上/最下行，输出引文仍保留原来的阅读顺序。
新增行首/行尾页码比较：模板一致且数字差等于 PDF 页码差才匹配，支持 `12 Book Title`、`Book Title 13`、
`https?://… 3/12`，页码偏移与非相邻页同样适用。测试还覆盖数字跳变、URL 内数字或总页数不同、
中英文章节标题和页眉页脚插在文本流中间的情况；不满足约束时保留原文。

Mac mini Release 使用独立 bundle ID `io.github.mylxsw.marginmind.review498revision`、Release 沙盒签名。
[补测 PDF](review-fixture.pdf) 由 [Swift 脚本](review-fixture.swift) 生成：先画正文，再画 HTTPS 页脚，最后画带变化页码的书眉。
真机 PDF 文本层也确认这个顺序。跨页拖选后，书眉与页脚没有选区或持久高亮，落盘引文没有 `Book Title`、
`https:` 或 U+0002，两页分别保存 3 和 2 个正文行矩形；断言通过。

- [复审选区截图](review-selection.png)
- [复审高亮与脑图卡片](review-highlight-card.png)
- [复审落盘引文与矩形](review-excerpt.json)

修订后实际运行：`dart format --set-exit-if-changed apps packages`（171 个文件）、`flutter analyze`、
`python3 -m unittest discover -s tool/tests`（3 项）、`python3 tool/coverage.py`（七个套件，PDF 48 项、应用 227 项）、
macOS `xcodebuild test`（3 项）、`flutter build macos --release`，均通过。
总体覆盖率 **92.00%**，相对 main 新增可执行行 **170/170**（纯函数 120/120、选区接入 50/50）。

自审核对了文本/几何顺序分离、页码差的正反方向、错误数字回退、章节标题保护、缓存复用和 LRU 容量、
翻页不重建、原生渲染资源释放及文档一致性。几何不匹配和复合词断行的现有限制已在上文写明。
