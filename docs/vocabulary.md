# 生词本：查词、全文生词提示与生词本（GUL-582）

交互原型：`design/prototype/vocabulary.html`（单文件，浏览器直接打开；演示控制台 12 个场景）。原型里的释义、译文是演示数据，界面文案以原型为准。

## 1. 目标

1. 阅读时选中单词或短语，查词或翻译之后可以一键**加入生词本**。
2. 加入后，**整份文档**里这个词（包括它的屈折变化，如 plateau / plateaus）都会被标出来；点按就能看到释义，不需要再次选中。
3. 提示可以**随时关闭**：全局关闭、只在当前文档隐藏，或者在下划线和行间释义之间切换。
4. 生词本可以集中查看：释义、自己的笔记、例句，**每条例句都能回到原文**（延续“原文是锚点”的原则）。

不在本期：生词复习（FSRS）、导出 Anki / CSV、离线系统词典。见第 8 节。

## 2. 交互方案

### 2.0 文案原则（所有界面强制）

- 不加不必要的二级标签和说明，让布局本身说明含义。
- 不加不必要的辅助文字、描述性文案和重复的界面微文案。
- 能用图标 + tooltip 表达的不写文字；状态用胶囊或颜色表达，不用句子解释；HUD 只写结果（“已加入生词本”），不附带数量或解释。
- 原型 `design/prototype/vocabulary.html` 是文案的唯一依据：原型里没有的说明文字，实现时不要加。

### 2.1 入口：浮动工具条上的「翻译 / 查词」

不新增按钮。现有的「翻译」按钮（Lucide `languages`）按选区类型变化：

| 选区 | tooltip | 打开 | 加入生词本 |
| --- | --- | --- | --- |
| 单个词（字母，可带撇号，去掉首尾标点） | 查词（T） | 查词卡片 | 能 |
| 短语：≤ 8 个词、≤ 64 个字符，中间没有 `. ! ? ; : —` | 翻译（T） | 翻译卡片 | 能 |
| 更长的句子或段落 | 翻译（T） | 翻译卡片 | 按钮置灰，原因只在 tooltip 里 |

已收录的词：按钮右上角 6pt 生词色圆点。新增选区快捷键 **T**（与 E / H / C / A 相同机制）。

### 2.2 查词卡片

沿用划词翻译弹层（`QuickActionsPlacement` + `MMGlass`，圆角 16，宽 360）。从上到下：

1. 原形（选中 `meticulously` 显示 `meticulous`）、英 / 美音标与朗读按钮（系统 TTS）；无音标时整行不显示。
2. 右上角主按钮「☆ 加入生词本」（生词色实心胶囊，快捷键 S）；已收录时显示状态胶囊「★ 学习中 / 已掌握」，点击弹出菜单：在生词本中查看 / 标为已掌握 / 移出生词本。
3. 义项：词性标签 + 释义，最多 4 条。
4. 生词色浅底块：本句释义、原句（宋体，目标词加粗着色）、整句译文；已收录且本句未收录时右上角一个 `+` 图标按钮（tooltip“收录为例句”）。不加区块标题。
5. 底栏：翻译整句 / 问助手 /（已收录时）详情 ›。

加载中为骨架屏；Esc 或点外部关闭。

### 2.3 翻译卡片

现有翻译弹层底栏右侧增加同一个「加入生词本」按钮；长句时置灰，原因写在 tooltip。不加词形提示、不加说明行。

### 2.4 加入之后

- HUD：“已加入生词本　撤销”。
- 本文所有命中处做一次 `MMMotion.flash` 生词色底闪烁。
- 侧栏「生词本」计数 +1。

### 2.5 全文生词提示

| 模式 | 外观 |
| --- | --- |
| 关闭 | 无 |
| **下划线**（默认） | 1.5pt 点状下划线，生词色 |
| 释义 | 下划线 + 词上方行距空隙里 10pt 的简短释义（≤ 8 字）；只叠加不重排，空隙不够的行退回只画下划线 |

- **生词色**：固定青绿 `#0E8A86`（深色 `#40C8C0`），底色 12% / 16%。新令牌 `MMColors.vocabulary` / `vocabularyTint`，需通过 `tokens_test` 4.5:1 检查。实现时浅色微调为 `#0D8480`（白底 4.54:1）：原型值在白底只有 4.20:1；色底上的正文使用 `label`。
- **点按命中处**：轻量卡片（宽 300）：词、音标、状态胶囊、前两条义项、笔记（如有，不加前缀）；底栏 `‹ 1 / 4 ›` 切换并滚动、掌握（✓ 图标）、移出（垃圾桶图标）、详情 ›。拖选优先，拖动不弹卡片。
- 已掌握的词默认不提示。
- 不显示底部统计胶囊；开关状态由工具栏按钮表达。

### 2.6 关闭与切换

| 位置 | 控件 |
| --- | --- |
| 阅读工具栏 | 生词提示图标按钮（开时生词色底，tooltip“生词提示（⇧⌘U）”），一键开关，记住上次模式；菜单“显示 › 生词提示 ⇧⌘U” |
| 阅读设置（Aa） | 分组“生词提示”：分段 关闭 / 下划线 / 释义；开关“本文档隐藏”“标出已掌握” |
| 设置 › 阅读 | 默认提示模式 |

“本文档隐藏”按文档 ID 存偏好。提示只叠加绘制，不写入标注、不进撤销历史、不影响导出。

### 2.7 生词本页面

入口：工作区侧栏“学习”分组「生词本」（计数 = 学习中数量）、卡片里的“详情 ›”；资料库侧栏也有「生词本」，默认“全部”。

- **左栏（340）**：搜索；分段“本学习集 / 全部”和“学习中 / 已掌握 / 全部”；按“今天 / 更早”分组；行：词、释义摘要、状态点、本文出现次数（纯数字，tooltip 说明）。不加页内标题（窗口标题已是“生词本”）、不加总数副标题。
- **右栏详情**：词头、音标与朗读、状态胶囊；“释义”（右侧重新生成图标）；“行间释义”（≤ 8 字输入框）；“笔记”；“词形”（chip 可删，末尾“添加”输入）；“例句”（宋体原句 + 译文 + “学习集 · 文档”，当前学习集为“回到原文”，其他为“打开学习集 ›”，右侧删除图标；来源已删除时去掉跳转按钮）；底部“标为已掌握”“从生词本删除”。各区只有一个小标题，不加说明文字；空值显示“—”。
- 删除、改状态、删例句带 HUD 撤销。

### 2.8 异常状态

与划词翻译一致：未设置模型、联网关闭（非 Ollama）、认证失败、超时显示一行问题标题 +“打开设置”。仍可“加入生词本”：只存词与例句，释义留空，之后“重新生成”或手写。重复加入不新增记录，只追加例句。

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

- `mm_assistant` 新增 `WordLookup`，复用划词翻译的模型选择、联网判断、`CancellationToken` 和 90s 超时；请求带上单词、所在句子、源 / 目标语言，要求模型返回 JSON：`lemma, phonetics{uk,us}, senses[{pos,meaning}], contextMeaning, sentenceTranslation, gloss, forms[]`。
- 解析允许 Markdown 代码块或少量前后说明文字，提取第一个完整 JSON 对象，响应仍限 64 KB。
- 字段降级：`gloss` 按 rune 截到 8 字，可为空；`senses` 仅检查前 6 项，丢弃不合法项，无合法义项时失败；`forms` 仅检查前 16 项，丢弃非字符串、空串及超过 64 字符的项，小写去重并保证包含小写 `lemma`（总数不超过 16，优先保留原形）；`phonetics` 缺失或不是对象时，英美音标为空，缺失或非字符串的单项也为空，超长音标截到 128 字符。缺失或非字符串的 `gloss` 按空串处理，缺失或非列表的 `forms` 仅保留原形。
- 非 JSON、缺少合法 `lemma`、无合法义项、缺少 `contextMeaning` 或 `sentenceTranslation` 时按失败处理，不写入生词本；原形、词性、释义和译文的既有长度限制仍保留。
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

## 9. 已确认（2026-10-30）

按本文建议执行：生词本为应用级（可按学习集筛选）；短语上限 8 个词 / 64 个字符；默认提示模式“下划线”；生词色为固定青绿。本期范围为第 8 节 P1 + P1.1。
