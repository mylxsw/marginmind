# GUL-498 摘录文本与高亮验证

2026-10-26，Mac mini（Apple 芯片），macOS 26.6.2，Flutter 3.47.2 / Dart 3.13.2，Xcode 27.1。
修改前为 main `8bb4d8a`，修改后为本分支。两者均为 `flutter build macos --release` 构建，
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

## 验证

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

只认完整页面首行/末行：位于上下 8% 内，与正文有明显间隔，并且在至少两页上内容及位置重复。
日期、路径、页码允许数字变化，其他正文标题不归一化数字，包括“第 1 章 / 第 2 章”；中文页码只匹配“第 N 页”。证据不足、只有一页证据、短页、位置不一致或
文字几何不匹配时不推断页眉页脚。宁可保留可疑行；不是通用版面语义识别。
原始空行和明显几何间距保留为段落分隔；页边界本身按段内换行处理。
拖动过程中仍使用 PDF 引擎的临时预览，松开后以清理结果替换。
只处理新选区，不改旧引文或旧高亮矩形，不变更文件格式。

物理触控板跨页拖选、触控板滚动中取消、物理 ⌘C 待人工验收，见 `docs/macos-acceptance.md`；
本次不把自动化事件注入等同于物理设备验收。
