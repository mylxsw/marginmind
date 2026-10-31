# GUL-621：全文翻译 UI 验收与打磨

基线：`9a4ed5ed`（main，含 GUL-618/619/620）。环境：Linux aarch64，Flutter 3.47.2。macOS 真机：两台 Mac worker 当日对所有工作目录返回 `path_denied`，未能构建运行；真机项列在 `docs/macos-acceptance.md` 的 GUL-621 一节，尚未执行。

## 方法

1. 原型：用 Chrome 无头模式依次点击 `design/prototype/full-translation.html` 的 16 个场景，浅色 / 深色各截一张（1440×900）。原型图可随时复现，未提交。
2. 实现：widget 测试的证据模式，加载真实中文字体渲染 2× 截图（`impl/`）：

```sh
cd apps/marginmind
TRANSLATION_EVIDENCE_DIR="$PWD/../../docs/evidence/gul-621/impl" \
TRANSLATION_EVIDENCE_FONT=/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc \
flutter test --no-pub test/full_translation_test.dart test/translation_paragraph_test.dart
```

截图中统计格里的“/ 20”“token”显示为方块，是测试字体回退的问题（嵌套 span 不继承证据字体）；macOS 上使用系统字体，不受影响。玻璃顶部的白色条是测试环境中模糊背景的渲染效果。

## 场景对照与修正

| 场景 | 结论 | 修正 / 说明 |
| --- | --- | --- |
| 1 入口：对照菜单 | ✅ 组件测试 | `translation_entry_points_test`：三个入口、任务中改为“全文翻译任务… n%”、compact 无入口 |
| 2–4 设置面板 | ✅ 已修正 | 标题图标块与副标题、语言弹出菜单（完整语言名，源语言可指定）、页码框禁用样式、“不发送”总是显示、底栏说明与按钮同行、“已是{目标语言}” |
| 5 翻译中 + 任务面板 | ✅ 已修正 | “停止”critical 文字；统计 15pt、圆角 10、间距 8；明细数值右对齐不挤压标签；批次分界线改为次级色，当前页圆点改为 label 色；标题行完整语言名；胶囊进度环加底轨、0% 不再转圈 |
| 6–7 检查点 | ✅ 已修正 | 徽标改为 22pt `accentTint` 圆底；“n 段 · 复用 n · n 段未译 [重试]” |
| 8 段落失败与重试 | ✅ | 与原型一致（GUL-620 `paragraph-*.png`） |
| 9–11 错误 / 断网 / 超出预估横条 | ✅ | 与原型一致（`strip-*.png`） |
| 12 重新打开 | ✅ 组件测试 | 暂停胶囊与 HUD“全文翻译已暂停在第 n 页 [继续]” |
| 13 段落修改与重译 | ✅ | 与原型一致（GUL-620） |
| 14 全部完成 | ✅ 组件测试 | 胶囊、HUD、面板“重试 n 段 / 移除译文…”；系统通知需真机 |
| 15 原文变化 | ✅ 组件测试 | 预估区“原文已重新识别”行 |
| 16 不可用 | ✅ | `sheet-blocked.png`；主按钮禁用 |

保留的偏差及原因写在 `docs/full-translation.md` 第 19 节。

## 第 11 节验收标准

| # | 结论 | 依据 |
| --- | --- | --- |
| 1 分批 review 期间 0 请求 | 🧪 | `translation_scheduler_test`「two workers, visible priority inside batch, review gate…」；真机 300 页待测 |
| 2 一次完成无检查点、150% 暂停一次 | 🧪 | 「budget pauses once after saving both workers…」 |
| 3 暂停后 0 新请求、在途结果保存 | 🧪 | 「pause and stop issue zero new requests but durably save paid in-flight results」 |
| 4 不重复请求、相同文字一次、页眉页码不发送 | 🧪 | 「no-send rules, identical content fanout…」「cached-only batches advance automatically…」 |
| 5 临时错误重试不显示失败；任务级错误整体暂停 | 🧪 | 「transient delays, jitter…」「paragraph failures persist, retry recovers; task errors halt…」 |
| 6 强退重开保留、paused、只补缺 | 🧪 | 「offline auto resume, manual pause and process recovery never auto-spend」；真机强退待测 |
| 7 改要求不影响已译段落 | 🧪 | 「two workers, visible priority inside batch, review gate…」：`continueBatch(note:)` 后新段落带新 `profile`，已译段落不重发 |
| 8 手动修改不被批量覆盖 | 🧪 | 「cached-only batches … edited values are never overwritten」、`translation_paragraph_test` |
| 9 删除文档删除译文目录；旧版兼容 | 🧪 | `file_translation_store_test`「remove pair, document and orphans…」；`studyset.json` 格式未变 |
| 10 浅色 / 深色、减弱动态效果、VoiceOver | 🧪 / ⏳ | 浅 / 深 golden 与截图、减弱动态效果与读屏标签组件测试；VoiceOver 真机待测 |

🧪：自动化测试覆盖；⏳：需要 macOS 真机。
