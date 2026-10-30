# 生词本：查词、全文生词提示与生词本（GUL-582）

交互原型：`design/prototype/vocabulary.html`（单文件，浏览器直接打开；演示控制台有 12 个场景，可切换深色、AI 模型状态和提示模式）。原型里的释义、译文都是演示数据。

## 1. 目标

1. 阅读时选中单词或短语，查词或翻译之后可以一键**加入生词本**。
2. 加入后，**整份文档**里这个词（包括它的屈折变化，如 plateau / plateaus）都会被标出来；点按就能看到释义，不需要再次选中。
3. 提示可以**随时关闭**：全局关闭、只在当前文档隐藏，或者在下划线和行间释义之间切换。
4. 生词本可以集中查看：释义、自己的笔记、例句，**每条例句都能回到原文**（延续“原文是锚点”的原则）。

不在本期：生词复习（FSRS）、导出 Anki / CSV、离线系统词典。见第 8 节。

## 2. 交互方案

### 2.1 入口：浮动工具条上的「翻译 / 查词」

不新增按钮。现有的「翻译」按钮（Lucide `languages`）按选区类型变化：

| 选区 | 按钮提示 | 打开 | 能否加入生词本 |
| --- | --- | --- | --- |
| 单个词（字母，可带撇号，去掉首尾标点） | 查词（T） | **查词卡片** | 能 |
| 短语：≤ 8 个词、≤ 64 个字符，中间没有句子 / 分句标点（`. ! ? ; : —`） | 翻译（T） | 翻译卡片 | 能 |
| 更长的句子或段落 | 翻译（T） | 翻译卡片（与现在一致） | 不能：按钮置灰，提示“生词本收录单词和 8 个词以内的短语” |

选中的词已在生词本里时，按钮右上角有一个 6pt 的生词色小圆点，提示写“· 已在生词本”。新增单字母快捷键 **T**（工具条打开时生效，与 E / H / C / A 相同的机制）。

### 2.2 查词卡片

位置、尺寸、材质沿用划词翻译的弹层（`QuickActionsPlacement` + `MMGlass`，圆角 16，宽 360）。从上到下：

1. **词头**：原形（选中 `meticulously` 时显示 `meticulous`，下面一行注明“原形 meticulous · 选中的是 meticulously”）、英 / 美音标和朗读按钮（系统 TTS）。
2. 右上角主按钮 **「☆ 加入生词本」**（生词色实心胶囊，快捷键 S）；已收录时变成「★ 已在生词本」（浅色底），点击弹出菜单：在生词本中查看 / 标为已掌握 / 移出生词本。
3. **义项**：词性标签 + 释义，最多 4 条。
4. **在本句中**（生词色浅底块）：结合本句的释义、原句（宋体，目标词加粗着色）、整句译文。已收录的词这里有“+ 收录此例句”；同一句已收录则显示“已收录此例句”。
5. 未收录时显示“加入后全文也会标出：deliberately · deliberated …”，让用户知道为什么会多标出几处；已收录时显示状态、例句数和来源学习集数。
6. 底栏：翻译整句 / 问助手 / 在生词本中查看。

加载中显示骨架屏，不阻塞其他操作；Esc 或点外部关闭。

### 2.3 翻译卡片里的「加入生词本」

在现有翻译弹层底栏右侧增加同一个「加入生词本」按钮，以及“加入后全文也会标出：took for granted …”的词形提示。长句只翻译，按钮置灰，卡片里多一行说明：“选中了 16 个词的句子，只翻译、不收录。可以只选其中的短语再加入生词本。”

### 2.4 加入之后

- 底部 HUD：“已加入生词本 · 本文标出 4 处　撤销”。撤销即删除这条记录。
- 本文所有命中处做一次 `MMMotion.flash`（1600ms）的生词色底闪烁，让用户立刻看到“全文都标出来了”。
- 侧栏“学习”分组的「生词本」计数 +1。

### 2.5 全文生词提示

| 模式 | 外观 | 说明 |
| --- | --- | --- |
| 关闭 | 无 | |
| **下划线**（默认） | 1.5pt 点状下划线，生词色 | 与用户的标注（实线 / 虚线 / 波浪下划线、高亮）在形态和颜色上都能区分 |
| 行间释义 | 下划线 + 词上方行距空隙里一条 10pt 的简短释义（≤ 8 个字） | 只叠加绘制，不重排正文；行距放不下（空隙 < 释义高度）时这一行自动退回只画下划线 |

- **生词色**：固定青绿 `#0E8A86`（深色 `#40C8C0`），底色 12% / 16%。不使用六种标注色和系统强调色，避免和“自己画的线”“当前选择”混淆。作为新令牌 `MMColors.vocabulary` / `vocabularyTint` 加入，需通过 `tokens_test` 的 4.5:1 对比度检查。
- **点按命中处**：弹出轻量卡片（宽 300）：词、音标、状态、前两条义项、我的笔记；底栏“本文第 1 / 4 处”可上下切换并滚动到对应位置，另有“标为已掌握”“移出生词本”“详情 · N 条例句 ›”。拖选仍然优先：按下后拖动就是选文字，不弹卡片。
- **已掌握的词不再提示**；阅读设置里可以打开“也标出已掌握的词”（灰色点线）。
- 阅读区底部的小胶囊显示“本文出现 4 个生词 · 9 处　查看”，点击打开生词本并筛选到本学习集；提示关闭时改为“生词提示已关闭　显示”。胶囊放在页码导航上方，浮动工具条和提示照常避开整个底部区域。

### 2.6 关闭与切换

| 位置 | 控件 |
| --- | --- |
| 阅读工具栏 | 「生词提示」图标按钮（开时为生词色底），一键开关，记住上次的模式；快捷键 **⇧⌘U**（菜单“显示 › 生词提示”） |
| 阅读设置（Aa） | “生词提示”分组：关闭 / 下划线 / 行间释义；“在本文档中隐藏”；“也标出已掌握的词” |
| 设置 › 阅读 | 新文档的默认提示模式 |

“在本文档中隐藏”只对这份文档生效（按文档 ID 存在偏好里），其他文档照常提示。提示只在阅读时叠加绘制，不写入标注、不进入撤销历史、不影响导出。

### 2.7 生词本页面

入口：工作区侧栏“学习”分组的「生词本」（计数为学习中的数量）、命中卡片的“详情”、阅读底部胶囊的“查看”。资料库窗口侧栏也有「生词本」，默认“全部”范围。

- **左栏（340）**：搜索（单词、释义、词形）；范围“本学习集 / 全部”；状态“学习中 / 已掌握 / 全部”；按加入日期分组（今天 / 更早），每行显示词、释义摘要、状态点和“本文 N”。
- **右栏详情**：词头、音标与朗读、状态、加入日期、当前文档出现次数；释义（“重新生成”结合全部例句重写）；行间释义（≤ 8 字，可手改）；我的笔记；**识别的词形**（可删、可加；正文按这些形式匹配）；**例句与出处**（宋体原句 + 译文 + “学习集 · 文档”，当前学习集的例句点“回到原文”跳到出处并闪烁，其他学习集的是“打开学习集 ›”；来源文档已删除时保留句子并注明“原文已删除”）；底部“标为已掌握 / 加入复习（P2）/ 从生词本删除”。
- 删除、改状态、删例句都带 HUD 撤销。

### 2.8 异常状态

与划词翻译一致：未设置模型、联网关闭（非 Ollama）、认证失败、超时都显示同样的问题卡片和“打开设置”。查词卡片额外提供“仅记下单词”：只存词和例句，释义留空，之后在生词本里“重新生成”或手写。重复加入不产生重复记录，只追加例句。

## 3. 数据模型

生词本是**应用级**数据，不属于某个学习集：同一个词在不同书里反复出现，只有跨学习集才能看出“又遇到了”。学习集文件包（`.mmset`）保持不变，导出 / 复制学习集不带生词本。

```dart
// mm_core/src/vocabulary/vocabulary.dart（纯 Dart）
enum VocabularyStatus { learning, known }
enum VocabularyKind { word, phrase }

class VocabularyEntry {
  final String id;
  final String term;            // 原形，显示用
  final String key;             // 规范化键：小写、合并空白，去重依据（term + language 唯一）
  final String language;        // 'en' 等 TranslationLanguage.code
  final VocabularyKind kind;
  final List<String> forms;     // 匹配用词形（含 term），小写、去重，最多 16 个
  final String? ukPhonetic, usPhonetic;
  final List<VocabularySense> senses;   // (partOfSpeech, meaning)，≤ 6
  final String gloss;           // 行间释义，≤ 8 个字符
  final String note;            // 我的笔记
  final VocabularyStatus status;
  final List<VocabularyContext> contexts; // 新的在前，≤ 20 条
  final DateTime createdAt, updatedAt;
}

class VocabularyContext {
  final String id, studySetId, documentId;
  final String studySetTitle, documentTitle; // 快照，来源删除后仍可显示
  final String sentence, hit;                 // 原句与命中的词形
  final String? sentenceTranslation;
  final TextAnchor? textAnchor;               // 流式文档
  final int? page; final List<PageRect> rects; // PDF（与 PdfTarget 同样的定位方式）
  final DateTime addedAt;
}
```

- 端口 `VocabularyRepository`（`load()` / `save(entries)` / `watch()`），内存实现放 `testing.dart`。
- 编辑走纯函数 `VocabularyEditor`：`add`（按 `key` 去重，已存在则合并例句）、`addContext`（同句去重、超 20 条丢最旧）、`setStatus`、`updateForms`、`remove`、`removeContext`，全部返回新的不可变列表，便于测试和撤销。
- `mm_data` 的 `FileVocabularyStore` 写 `Library/vocabulary.json`（与 `sets/` 同级），`{"format":1,"entries":[…]}`；沿用学习集的“写临时文件 → flush → rename”和串行写入；未知 `format` 不载入也不改写。
- 偏好（`SharedPreferences`）：`vocabulary.hintMode`（off / underline / gloss）、`vocabulary.lastHintMode`、`vocabulary.showKnown`、`vocabulary.hiddenDocuments`（文档 ID 列表）。

## 4. 查词

- `mm_assistant` 新增 `WordLookup`，复用划词翻译的模型选择、联网判断、`CancellationToken` 和 90s 超时；请求带上单词、所在句子、源 / 目标语言，要求模型返回 JSON：`lemma, phonetics{uk,us}, senses[{pos,meaning}], contextMeaning, sentenceTranslation, gloss, forms[]`。解析失败按“失败”处理，不写入生词本。
- 结果按 `(lemma, 目标语言, 句子指纹)` 缓存在内存；已收录的词直接用生词本里的释义，只为新句子请求 `contextMeaning` / `sentenceTranslation`。
- **词形**：以模型返回的 `forms` 为主；本地再用一份很小的英文规则（-s/-es/-ies、-ed/-d/-ied、-ing、比较级、-ly）补全，并保证包含选中时的原词。用户可以在生词本里增删。
- 隐私：发送给模型的只有单词和所在句子，与划词翻译相同。

## 5. 全文匹配与绘制

- `VocabularyMatcher`（`mm_core`，纯函数）：把所有学习中（及“显示已掌握”时的已掌握）条目的词形建成“首词 → 候选词序列”的索引，候选按长度降序；对段落做一次分词（拉丁字母词按词边界，大小写不敏感），**最长短语优先**、命中后跳过已覆盖的词；短语的词之间只允许空白，不跨句。中文 / 日文短语按子串匹配。复杂度与段落长度线性相关。
- 结果按 `(段落指纹, 生词本版本号)` 缓存；生词本变化只重算可见页及前后各一页，其余页在滚动到附近时计算。
- **流式文档**（EPUB / MOBI / Markdown / 网页）：`mm_reflow` 的段落文本 → 命中区间 → 布局里的行框，绘制在标注装饰层，点状下划线复用 `MMPdfAnnotationLinePainter` 的 `AnnotationLineStyle.dotted`。
- **PDF**：用划词翻译已有的每页文字与字符框（`TranslationPage`），命中区间转成 PDF 坐标矩形，交给 `MMPdfView` 的高亮叠加层画点状下划线；行间释义的可用高度取上一行底边到本行顶边的距离，不够就不画。扫描版需先识别文字（OCR 后才有字符框）。
- 点按命中：命中层只在“按下 → 抬起且没有拖动”时响应，拖选照常交给选字。

## 6. 架构落点

| 层 | 新增 |
| --- | --- |
| `mm_core` | `vocabulary/`：实体、`VocabularyEditor`、`VocabularyMatcher`、`VocabularyRepository` 端口、英文词形规则 |
| `mm_data` | `FileVocabularyStore`（`Library/vocabulary.json`） |
| `mm_assistant` | `WordLookup`（结构化输出与解析） |
| `mm_design` | `MMColors.vocabulary` / `vocabularyTint`；`MMIcons.vocabulary`（Lucide `book-a`） |
| `apps/marginmind` | `vocabularyProvider`、`vocabularyHintProvider`；`WordLookupCard`（与 `SelectionTranslation` 并列）；翻译卡片的加入按钮；阅读器叠加层；命中卡片；`features/vocabulary/` 生词本页面；侧栏入口、菜单“显示 › 生词提示 ⇧⌘U”、选区快捷键 T；中英文案 |

依赖方向不变：`apps → mm_assistant / mm_data / mm_design → mm_core`。

## 7. 测试计划

- `mm_core`：分词与大小写；最长短语优先、短语不跨句；屈折词形规则；`VocabularyEditor` 去重合并、例句上限与去重、状态切换、删除；JSON 往返与未知字段。
- `mm_data`：原子写入、并发串行、未知 `format` 拒绝、损坏文件不覆盖。
- `mm_assistant`：结构化结果解析、缺字段 / 非 JSON / 取消 / 超时。
- Widget：选区分类（单词 / 短语 / 长句）与按钮提示；查词卡片的加载、结果、已收录、问题状态；加入后 HUD 与撤销；命中卡片的上一处 / 下一处；工具栏开关与 ⇧⌘U；“在本文档中隐藏”；生词本筛选、搜索、回到原文；深色主题截图。
- 新增代码行覆盖率 ≥ 80%（`tool/coverage.py`）。

## 8. 分期

| 期 | 内容 |
| --- | --- |
| P1（本期） | 查词卡片、翻译卡片加入、应用级生词本存储、下划线提示与命中卡片、开关（工具栏 / 阅读设置 / 本文档）、生词本页面 |
| P1.1 | 行间释义模式（依赖行距检测，PDF 与流式各自实现） |
| P2 | 生词复习：生词作为独立的 FSRS 卡组（不计入学习集的待复习数），正面为例句挖空，背面为释义；导出 CSV / Anki；macOS 系统词典作为离线查词兜底 |

## 9. 待确认

1. 生词本放在应用级（跨学习集共用、可按学习集筛选）——还是希望每个学习集各自一本？
2. 短语上限定为 8 个词 / 64 个字符是否合适？
3. 默认提示模式是“下划线”；新用户是否希望默认关闭？
4. 生词色选了固定青绿，是否接受？
