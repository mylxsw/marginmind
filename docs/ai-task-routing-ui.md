# AI 功能模型配置与任务状态：界面规格

> 建立日期：2026-11-01（GUL-645，父任务 GUL-643）。上位文档：《AI Agent 改造实施方案》v1.1（S0 将其提交为 `docs/ai-agent-refactor-plan.md`），本文对应其中 §2 任务目录、§3 配置页面、§10 重答/会话覆盖、§11 生命周期。数据契约、解析顺序、能力判定以上位文档为准；本文只规定界面。
> 交互原型：[`design/prototype/ai-task-routing.html`](../design/prototype/ai-task-routing.html)，17 个场景（地址栏 `#scene-N`）。对应画面：[`docs/evidence/ai-task-routing-ui/`](evidence/ai-task-routing-ui/) 中的 `scene-N.png`。
> **这些图片是用 HTML 原型通过 headless Chrome 渲染的设计稿，不是运行中应用的截图。** 本任务环境没有 Flutter SDK，未运行应用，也未在应用中核对。视觉以 `mm_design` 令牌和现有设置页为准，原型中的 CSS 数值只作参考。未写到的细节沿用 [`design-system.md`](design-system.md)、[`phase-3-assistant-ui.md`](phase-3-assistant-ui.md) 和 [`full-translation.md`](full-translation.md)。

本文写给 S1（路由与设置）和 S3/S4（各功能接入）的界面实现者。本任务不修改生产 Dart 代码。

**界面原则（必须遵守）。** 不加多余的次级标签和说明文字，让布局表达含义；不加多余的辅助文字、描述性文案和重复的界面微文案。落到本页：

- 正常状态每行只有“功能名 + 选择器”。不显示来源徽章，不显示“跟随默认”文字，不写说明句。
- 继承还是显式绑定，由选择器文字颜色区分（见 §2.3），不另加标签。
- 只有在需要用户做决定或处理异常时，才在该行下方显示一行短状态和一个操作（§3）。
- 不向普通用户暴露 taskType、prompt、knowledge 包名、协议参数（`reasoning_effort`、`thinking.type` 等）或 HTTP 字段。

---

## 1. 入口与导航

| 项 | 规格 |
| --- | --- |
| 设置分区 | `SettingsTab` 新增 `aiTasks`，位于 `models` 之后、`webSearch` 之前。标题“AI 功能”。图标新增 `MMIcons.aiTasks`，从已打包的 Lucide 中选择分流类图标（如 `split` / `workflow`）；不要复用 `MMIcons.ai`，避免与“模型”分区重复 |
| 显示条件 | 与“模型”分区相同：`MMPlatformCapabilities.current.externalCredentials`。不借此扩大平台支持范围 |
| 窄窗口 | 沿用 `SettingsWindow` 在 `MMBottomSheet` 中的分段控件，“AI 功能”是其中一段（场景 11） |
| 定位入口 | `showSettings(context, tab: SettingsTab.aiTasks, focus: AiTaskFocus)`。`focus` 可以是某个 taskType 或某个模型引用 `(serviceId, modelId)`，见 §5.2 |

## 2. AI 功能页（场景 1–3、9、12）

### 2.1 结构

页面使用 `SettingsPage`（最大宽 540）。从上到下：

```
快速任务                               ← MMSettingsHeader
┌ 默认模型                 [Haiku 4.5 ⇕] ┐  ← 默认组
└ 思考                             关闭  ┘
┌ 选区翻译                 [Haiku 4.5 ⇕] ┐  ← 功能组（3 行）
│ 单词释义                 [Haiku 4.5 ⇕] │
└ 标题生成                [GPT-5 mini ⇕] ┘
重型任务
┌ 默认模型   [Anthropic · Claude Opus 4.5 ⇕] ┐
└ 思考                             [自动 ⇕] ┘
┌ 助手对话与解释 … 复习卡与问题生成（9 行）    ┐
────────────────────────────────────────────── ← 固定在页面底部
未保存                    [恢复跟随默认] [保存]
```

- 两个类别，每类两个 `MMSettingsGroup`（默认组、功能组），组间距 8；类别之间用 `MMSettingsHeader` 分隔。页面上只有这两个分组标题，没有其他副标题。
- 12 个功能的行顺序和名称固定，与上位文档 §2 的表格一致：
  - 快速：选区翻译、单词释义、标题生成。
  - 重型：助手对话与解释、对话总结、文档归纳、全文翻译、思维导图扩写、思维导图生成与更新、调研与查证、学习笔记整理与改写、复习卡与问题生成。
  - 行由注册表的 `TaskSpec` 列表生成（名称走 l10n），不在界面硬编码第二份列表。注册表新增功能时自动出现。
- 底部操作条在滚动区外，固定在页面底部：上方 1pt `separator`，内边距 10×18。内容复用 `SettingsSaveActions`：左侧状态文字，`secondaryAction` 放“恢复跟随默认”，右侧主按钮“保存”。

### 2.2 行

| 行 | 右侧控件 | 规则 |
| --- | --- | --- |
| 快速 · 默认模型 | 模型选择器（§2.4） | 未设置时显示占位“选择模型”（`caution` 色） |
| 快速 · 思考 | 只读文字“关闭”（`secondaryLabel`），不可点 | quick 固定 off。界面不提供任何切换。用与重型“思考”行相同的位置，让布局本身说明两类的差别，不另写解释 |
| 重型 · 默认模型 | 模型选择器 | 同上 |
| 重型 · 思考 | `MMPopUpButton`：自动 / 关闭 / 标准 / 深入 | 只列出重型默认模型支持的选项（来自能力档案），默认“自动”。能力未知时只列“自动”；默认模型未设置时禁用 |
| 功能行 | 模型选择器 | 第一项是“跟随默认”。重型行的菜单附带思考分节（§2.4） |

行高 40（触屏 52），左右内边距 14，与 `MMSettingsRow` 一致。

### 2.3 继承与显式的视觉区分

- **继承**（`mode: inherit`）：选择器显示**实际生效的模型名**，文字用 `secondaryLabel`。
- **显式**（`mode: explicit`）：选择器显示绑定的模型名，文字用 `label`。
- 不加“默认”“继承”等徽章。用户关心的是实际生效的模型，所以界面直接显示它；颜色深浅只用来区分来源。读屏用 `semanticValue` 读出完整来源（§7）。
- 继承行在默认模型改变时立即更新显示（草稿态也一样），让用户在保存前看到影响范围。

### 2.4 模型选择器（场景 2、3）

新增 `ModelRoutePicker`，放在 `features/assistant/settings/`。外观与 `MMPopUpButton` 一致（高 22，圆角 6，`quaternaryFill`，⇕ 图标，最大宽 260），菜单用 `showMMMenu` + `MMMenuHeader`。现有 `MMPopUpButton` 不支持分组和右侧附注，因此不能直接复用。菜单项右侧的灰色附注（生效模型、不可用原因、“需验证”）放在 `MMMenuItem.shortcut` 的右对齐次要文字位置。禁用项右侧显示原因短语，同时设置 `disabledReason`，悬停时给出相同的 tooltip，读屏也能读到。如果 `mm_design` 维护者认为借用 `shortcut` 字段语义不当，可以给 `MMMenuItem` 新增 `detail` 字段，渲染方式与 `shortcut` 相同。这是本功能唯一需要改动的设计系统组件。

菜单内容：

```
✓ 跟随默认                    Claude Haiku 4.5      ← 仅功能行；右侧附注为当前生效模型
───────────
  Anthropic                                         ← MMMenuHeader = 服务名
  Claude Haiku 4.5
  Claude Opus 4.5             无法关闭思考          ← 已知不兼容：禁用 + 原因
  公司代理
  Claude Opus 4.5             需验证                ← 能力未知：可选 + 附注
  Ollama
  Qwen3 8B                    需验证
───────────                                         ← 仅重型功能行，且已显式选择模型时
  思考
✓ 自动 / 关闭 / 标准 / 深入                           ← 只列出所选模型支持的值
```

- **绑定值**是 `(serviceId, modelId)`；`ModelRoutePicker` 的值类型是 `ModelReference`，不用显示名或下标。复用现有 `modelKey()` 时只作为菜单项的内部键。
- **列出的模型**：已启用服务中已启用的模型，按服务分组，服务顺序与“模型”页一致。不按“是否思考模型”过滤。
- **不兼容项**（能力档案明确不满足本功能 `TaskSpec` 所需能力时）：置灰，右侧附注写具体原因，只用下列短语：
  - “无法关闭思考”：quick，`ThinkingCapability.alwaysOn`。
  - “不支持工具调用”：heavy 且 `TaskSpec` 需要工具。
  - “不支持结构化输出”：功能要求结构化输出而模型确认不支持。
  - “上下文不足”：模型容量低于该功能最小语义单元。
  - 能力未知的模型一律可选，标“需验证”，不根据名字推断。
- **当前值失效时**（已删除或已停用）：菜单顶部不再勾选任何项；按钮显示原名并加删除线（§3）。
- **同名区分**：任一处显示的模型名，只要它的显示名在两个以上服务中出现，就写成“服务名 · 模型显示名”。规则对按钮、菜单附注、任务面板、删除确认一致生效。没有同名时只显示模型名。菜单项本身位于服务标题下，所以菜单项不重复服务名。这是对上位文档“服务名 · 模型显示名”的精简：歧义时必定显示服务，不歧义时不重复。若父负责人要求始终显示服务名，只需改 `routeModelLabel()` 一处。
- 按钮 tooltip：`服务名 · 模型 ID`（与“模型”页模型行的 tooltip 一致，ID 只在 tooltip 中出现）。
- 选择后立即进入草稿（§2.5），不立即写盘。

### 2.5 草稿、保存与恢复（场景 3、7）

整页是**一份草稿**（`AiTaskRoutingDraft`）。与 `ServiceCard` 一样，必须显式“保存”。

| 状态 | 底部条 |
| --- | --- |
| 无改动 | 状态为空，“保存”禁用 |
| 有改动 | “未保存”；“保存”可用 |
| 保存中 | “正在保存…”；所有选择器和按钮禁用 |
| 已保存 | “已保存”（沿用 `voiceSaved`）。若有正在运行或可恢复的任务使用了被改动的功能，改为“已保存，进行中的任务不受影响” |
| 保存失败 | `critical`“保存失败，请重试”；草稿保留，“保存”可再次点击 |
| 版本冲突 | `critical`“设置已在其他窗口更改”；secondaryAction 换成“重新载入”（丢弃草稿并读取最新值）；“保存”禁用。不提供强制覆盖 |

- 保存携带读取时的 `revision`。被拒绝时进入“版本冲突”，不重试覆盖（上位文档 §4）。
- **恢复跟随默认**：把草稿中全部 12 个功能改为继承，并清除功能级思考设置；不改两个默认模型和重型默认思考。没有显式绑定时禁用。不弹确认（这是草稿操作，可以不保存）。
- 草稿存在于设置窗口生命周期内：切换分区后回来草稿仍在。关闭设置窗口时，若有未保存改动，弹 `showConfirmSheet`：标题“保存对 AI 功能的更改？”，按钮“不保存”/“保存”。
- 快捷键：⌘S（Windows/Linux 为 Ctrl+S）在本页等于“保存”。
- 保存只影响新任务；运行中的任务已冻结配置（上位文档 §11），界面不需要为此改动任务面板。

## 3. 异常状态（场景 4、5、6、12）

异常只在受影响的行上显示：行下方一行 `footnote`，左侧 11pt 图标 + 短语，右侧最多一个 plain 链接按钮。该行高度随之增加，不弹窗。颜色：需要用户动作才能运行的用 `critical`，可以尝试/待验证的用 `caution`。下表是完整清单，不得新增解释句。

| 状态 | 判定（来自 Resolver / 能力档案） | 选择器 | 行下状态 | 操作 |
| --- | --- | --- | --- | --- |
| 尚未创建任何模型 | 从未配置模型，且路由无任何默认/显式引用 | 整页替换为居中的主按钮“添加模型”（场景 6） | — | “添加模型”切到“模型”分区并打开 `showServiceList` |
| 某类默认未设置 | `defaults.quick/heavy == null` | 默认行占位“选择模型”（`caution`）；该类继承行显示“需配置”（`caution`） | 无（默认行已经说明问题，继承行不重复） | 点选择器 |
| quick 模型无法关闭思考 | `alwaysOn` | 正常显示模型名；继承它的快速功能行文字用 `caution` | 在“思考”行（默认）或该功能行（显式）下：⚠“此模型无法关闭思考” | “更换模型”（打开该行选择器） |
| 能力未知 | `unknown`，或缺少本功能所需能力的证据 | 正常 | ⚠ `caution`“需验证兼容性” | “测试”：运行 `capability_probe`。运行中把链接换成 12pt 转圈，可取消（离开页面时取消）。结束后按结果刷新本行：通过则消失；不支持则变为对应状态；连接失败则显示“连接不可用” |
| 重型模型能力不足 | 确认不支持 `TaskSpec` 必需能力 | 正常 | ⚠“此模型不支持工具调用”或其他 §2.4 原因 | “重新选择” |
| 模型已删除 | 引用的 modelId 不在服务中 | 保留**原显示名**并加删除线，`secondaryLabel` | ⚠“模型已删除” | “重新选择” |
| 模型已停用 / 服务已停用 / 服务已删除 | 对应开关为 off 或 serviceId 不存在 | 同上 | ⚠“模型已停用”/“服务已停用”/“服务已删除” | “重新选择” |
| 密钥暂不可访问 | Keychain 读取失败或 `secret_store` | 正常（**不**标为能力不支持） | ⚠ `caution`“连接不可用” | “打开模型设置”（定位到该服务卡片） |

- 失效引用**不清空、不改为继承、不换成列表第一项**。默认行失效时，继承它的功能行显示“需配置”，不悄悄回退到另一个服务。
- 全部模型停用/删除但仍有路由引用时，保留完整设置页和失效项；没有启用模型不能被当作首次使用空态。提供打开模型设置的入口以启用或添加模型。
- 同一行同时有多个问题时，只显示优先级最高的一个：删除/停用 > 密钥不可用 > 能力不足/无法关闭思考 > 能力未知。
- 本页只用于配置，可以保存含异常的草稿（上位文档 §3 允许保存未就绪配置），只是在开始任务时拦截（§6）。
- 迁移后首次打开：quick 默认若由旧默认模型预填但能力未确认，按“能力未知”显示，不加引导横幅。

## 4. 与“模型”页的衔接（场景 8–10）

### 4.1 移除旧“默认模型”

迁移后旧默认模型成为重型默认，旧字段不能继续作为第二个默认来源（上位文档 §12）。因此“模型”页：

- 删除顶部“默认模型”组（`settings-default-model`）。
- 模型行删除“默认”勾选标记和悬停“设为默认”（`model-default`、`model-set-default-*`）。
- 原位置改为悬停时显示 plain 按钮 **“分配…”**（`model-assign-<id>`），只对已启用服务中的已启用模型显示。点按后打开 `showSettings(tab: aiTasks, focus: model)`。

### 4.2 添加或保存后的分配入口

- `AddModelsSheet` 成功添加后，在设置窗口显示 HUD“已添加 n 个模型”，附操作“分配给功能”。
- 服务卡片保存且连接检查通过后，若该服务有已启用模型，但没有任何默认或功能引用它，则同样显示 HUD“已保存”+“分配给功能”。
- 不强制弹窗，不改动密钥保存流程。

### 4.3 定位（场景 9）

`focus: model` 打开 AI 功能页时：

- 所有当前选用该模型的选择器（默认和功能，继承或显式）用 `accentTint` 底高亮 1.6s 后淡出；滚动到第一个；焦点放在快速默认选择器（尚未设置时）或第一个高亮项。
- 没有任何行使用它时，焦点放在快速默认选择器，不额外提示。
- `focus: taskType` 时只高亮该行并聚焦其选择器（由 §6 的“AI 功能设置”按钮使用）。
- “减弱动态效果”开启时不淡出：高亮保持到焦点离开该行。

### 4.4 删除被使用的模型或服务（场景 10）

`_ModelRow` 的“−”和服务卡片的“移除服务”在执行前检查引用。来源包括两类默认、功能绑定、会话级 assistant_chat 覆盖，以及可恢复的长任务。

- 没有引用：行为不变（模型直接移除，服务仍弹原确认）。
- 有引用：弹 `showConfirmSheet`，标题“移除“{模型名}”？”。正文是受影响项的列表（`quaternaryFill` 圆角 8 列表，每行一项，最多 6 行，超出时最后一行为“另有 n 项”），条目文字：
  - “快速任务默认模型”/“重型任务默认模型”
  - 功能名
  - “当前对话”或“n 个对话”
  - 任务名，如“全文翻译 · Deep Work.pdf”
- 按钮“取消”/“移除”（critical）。不写说明句。
- 移除后这些位置进入 §3 的失效状态，不自动改派。
- 关闭模型或服务开关不弹确认，受影响行直接显示“已停用”。

## 5. 对话中的模型选择（场景 16）

- 输入框上的模型 chip 始终显示当前会话 `assistant_chat` **实际生效**的模型名。规则与 §2.4 相同，有歧义时加服务名。
- `showModelMenu` 第一项新增“跟随设置”，右侧附注为 AI 功能页中 assistant_chat 的生效模型。会话无覆盖时它被勾选。
- 选择具体模型 = 设置会话级覆盖（行为与现有 `switchModel` 相同）；选择“跟随设置” = 清除覆盖。
- 菜单底部“管理模型…”改为“AI 功能设置…”（快捷键仍为 ⌘,），打开 `aiTasks` 并 `focus: assistant_chat`。
- 旧会话迁移后带有覆盖：显示原模型，“跟随设置”未勾选。
- **专用功能不受 chip 影响**：在助手中触发的“总结”“调研”等使用各自功能的模型。其回答在现有元信息位置（回答下方 `footnote`，`tertiaryLabel`）显示实际模型名。只有当它与 chip 不同时才显示，相同时不重复。
- 其余输入框布局不变（参考 `docs/evidence/assistant-configuration-scope/README.md` 的范围纠正，不借此改版助手侧栏）。

## 6. 开始任务前的拦截与“本次模型”（场景 13、17）

模型解析顺序：本次显式选择 → 功能绑定 → 类别默认 → 未配置。界面按以下规则对应。

### 6.1 带设置面板的重型任务

全文翻译、文档归纳、思维导图生成/更新、学习笔记整理、复习卡、调研等，在开始前都有设置面板或确认面板：

- 面板中的“模型”行统一使用 `ModelRoutePicker`，但第一项为“跟随设置”（右侧附注为功能设置的生效模型），其余为模型列表。改选具体模型 = **本次任务显式选择**，只写入本次 run 的配置快照，不改设置。
- 全文翻译沿用现有“模型”行位置，原文案“模型名 · 预计 t token”中的模型名部分改为该选择器。
- 解析失败时（§3 中除“能力未知”外的状态）：选择器下方显示同一短语（如 ⚠“模型已删除”），主按钮禁用。左下角 plain 按钮“AI 功能设置”打开 `focus: taskType`。用户在选择器中改选可用模型后可直接开始。
- “能力未知”时主按钮可用。开始时先运行一次能力测试（按钮显示转圈）：通过则开始；不通过则停在面板，显示具体原因。

### 6.2 无设置面板的快速任务

选区翻译、单词释义：在原结果卡片位置显示错误卡（场景 17）。

- 一行 ⚠ 原因（同 §3 短语），右侧两个按钮：“更换本次模型”（打开模型菜单，选择后立即用该模型重试本次请求，不改设置）、“AI 功能设置”（主按钮）。
- 密钥问题时第二个按钮为“打开模型设置”。
- 标题生成失败不弹任何界面，保留本地占位标题（上位文档 §7）；问题只在 AI 功能页的对应行显示。

### 6.3 不做的事

- 不隐式跨服务回退，不在 quick 不能关闭思考时以开启思考的方式运行。
- 不显示“已切换到其他模型”之类的提示，因为这种切换不会发生。

## 7. 长任务状态（场景 14、15）

沿用 `full-translation.md` §3、§9 的胶囊、任务面板、横条与配色。本节把 Run 生命周期状态映射到现有组件，并规定模型显示。其他重型长任务（文档归纳、导图生成、学习笔记、复习卡、调研）复用同一胶囊与面板骨架，内容区保留各自现有设计。

### 7.1 状态映射

| Run 状态 | 胶囊（高 24） | 面板标题行右侧 | 面板横条 | 主操作 |
| --- | --- | --- | --- | --- |
| running | 进度环 + `{p}%` + 进度 | 进度 | — | 暂停 |
| awaiting_user | `accentTint`“待确认” | 待确认 | — | 沿用各功能的确认操作 |
| paused（用户） | `quaternaryFill`“已暂停 {x}/{y}” | 已暂停 | — | 继续 |
| paused（任务级错误） | critical 8%“已暂停” | 已暂停 | critical：原因短语 + 一个操作（“打开模型设置”/“AI 功能设置”/“重试”） | 继续 |
| interrupted | caution 9%“已中断 {x}/{y}” | `caution`“已中断” | caution：“上次运行未完成” | 继续 |
| partial | caution 9%“部分完成 · {n} {单位}未完成” | 同胶囊 | — | “重试 {n} {单位}”；次要“查看结果” |
| failed | critical 8%“失败” | 失败 | critical：原因短语 + 操作 | 重试 |
| cancelled | `quaternaryFill`“已停止 {x}/{y}” | 已停止 | — | — |
| completed | positive 10%“✓ 已完成” | — | — | — |

- `{单位}` 按功能：段、节、章、条、个子问题。
- interrupted 的“继续”只重发缺失或未确认的部分，已校验结果不重算（上位文档 §11）。
- 应用重新打开后存在 interrupted 任务时，沿用全文翻译的 HUD 规则：“{任务名}已中断 [继续]”，不自动继续。
- 领域原有的 `review` 等状态照旧显示，由适配层映射，不改现有文案。

### 7.2 模型行与本次模型

任务面板固定有一行“模型”（标签宽 44，`secondaryLabel`）：

- 显示 run 冻结的模型（不是设置页当前值）。设置在任务开始后被修改时，面板仍显示冻结值，不提示差异。
- run 有多个模型阶段时，按顺序用“→”连接显示，如“Claude Opus 4.5 → GPT-5”。tooltip 列出每段的完成范围。
- 模型行是 `ModelRoutePicker`，状态为 paused、interrupted、partial、failed 时可点；running 时禁用，tooltip“先暂停”。菜单中没有“跟随设置”项，因为这里只更改本次 run。
- 选择另一个模型后弹 `MMSheet`（场景 15）：标题“后续使用 {模型}？”，列表两行：“已完成 {x} {单位} · {原模型}”和“剩余 {y} {单位} · {新模型}”。按钮“取消”/“后续使用”。确认后创建新配置阶段，已有结果的归属不变。
- 冻结模型已失效（删除或停用）时，模型行显示删除线原名，横条 critical 显示对应短语。横条中的操作改为“更换后续模型”，打开上述菜单。

## 8. 窄屏（场景 11）

- 在 `MMBottomSheet` 中，页面内边距 16；底部操作条加上安全区底部内边距，按钮高 30。
- 行宽不足以并排放下“功能名 + 选择器”时（`MMSettingsRow` 现有规则：触屏且宽度 < 300，大字号时 < 480），功能名单独一行，选择器在下一行右对齐。异常行状态在选择器下方。
- 此外：内容宽度 < 460 时，选择器标签若会被截断（同名带服务前缀时常见），该行同样改为两行；不截断模型名中的服务部分。
- 菜单在紧凑尺寸下由 `showMMMenu` 自动变为操作表；分组标题、禁用原因、勾选状态保持不变。
- 不得水平溢出；在 320pt 宽、最大动态字体下所有行可读。

## 9. 键盘与无障碍

| 项 | 规格 |
| --- | --- |
| Tab 顺序 | 每行依次：选择器 → 行内异常操作；然后底部“恢复跟随默认”→“保存”。快速“思考”只读行不可聚焦 |
| 选择器 | Space / Enter / ↓ 打开菜单；菜单中 ↑↓ 移动（跳过分组标题与禁用项）、Enter 选择、Esc 关闭并把焦点还给按钮 |
| 页面 | ⌘S / Ctrl+S 保存；Esc 关闭设置窗口（未保存时走 §2.5 的确认） |
| 读屏 | 选择器 `semanticLabel` = 功能名；`semanticValue` = 继承时“跟随默认，{服务} · {模型}”，显式时“{服务} · {模型}”，失效时“{服务} · {原名}，已删除”。读屏始终读出服务名，不受 §2.4 的歧义规则影响 |
| 异常 | 状态行用 `Semantics(liveRegion: true)`，出现或变化时朗读；不抢焦点 |
| 颜色 | 所有状态都有图标或文字，不只靠颜色（继承/显式的颜色差异另由 `semanticValue` 说明） |
| 禁用项 | 菜单中的禁用项读出原因（附注文字 + `disabledReason`） |
| 动效 | 定位高亮遵守“减弱动态效果”（§4.3） |

## 10. 文案

| 场合 | 中文 | English |
| --- | --- | --- |
| 分区 | AI 功能 | AI Features |
| 分组 | 快速任务 / 重型任务 | Quick Tasks / Heavy Tasks |
| 行 | 默认模型 / 思考 | Default Model / Thinking |
| 思考值 | 自动 / 关闭 / 标准 / 深入 | Auto / Off / Standard / Deep |
| 选择器 | 跟随默认 / 跟随设置 / 选择模型 / 需配置 | Use Default / Use Setting / Choose Model / Not Set |
| 菜单原因 | 无法关闭思考 / 不支持工具调用 / 不支持结构化输出 / 上下文不足 / 需验证 | Can't turn off thinking / No tool use / No structured output / Context too small / Unverified |
| 行状态 | 此模型无法关闭思考 / 需验证兼容性 / 此模型不支持工具调用 / 模型已删除 / 模型已停用 / 服务已停用 / 服务已删除 / 连接不可用 | This model can't turn off thinking / Compatibility not verified / This model doesn't support tool use / Model removed / Model off / Service off / Service removed / Connection unavailable |
| 行操作 | 更换模型 / 测试 / 重新选择 / 打开模型设置 | Change Model / Test / Choose Again / Open Model Settings |
| 底部 | 恢复跟随默认 / 保存 / 已保存，进行中的任务不受影响 / 设置已在其他窗口更改 / 重新载入 | Reset to Defaults / Save / Saved. Running tasks are unchanged / Changed in another window / Reload |
| 空态 | 添加模型 | Add Model |
| 关闭确认 | 保存对 AI 功能的更改？ / 不保存 / 保存 | Save changes to AI Features? / Don't Save / Save |
| 模型页 | 分配… / 已添加 n 个模型 / 分配给功能 | Assign… / Added n models / Assign to Features |
| 删除确认 | 移除“{模型}”？ / 快速任务默认模型 / 重型任务默认模型 / 当前对话 / n 个对话 / 另有 n 项 | Remove “{model}”? / Quick default / Heavy default / This conversation / n conversations / n more |
| 对话菜单 | 跟随设置 / AI 功能设置… | Use Setting / AI Features Settings… |
| 拦截 | 更换本次模型 / AI 功能设置 | Use Another Model / AI Features Settings |
| 任务 | 已中断 / 上次运行未完成 / 部分完成 · n {单位}未完成 / 重试 n {单位} / 查看结果 / 先暂停 / 后续使用 {模型}？ / 后续使用 / 更换后续模型 | Interrupted / Last run didn't finish / Partially complete · n {unit} unfinished / Retry n {unit} / View Results / Pause first / Use {model} from here? / Use from Here / Change Model for Remaining |

已有可复用的 key：`settingsSaveFailed`、`settingsUnsaved`、`settingsSaving`、`voiceSaved`、`save`、`cancel`、`assistantCannotConnect`。新增 key 统一以 `aiTasks` 前缀命名。

## 11. 场景清单

| 场景 | 内容 | 画面 |
| --- | --- | --- |
| 1 | 正常态：12 个功能全部可见，继承与显式区分，同名模型带服务名 | `scene-1.png` |
| 2 | 快速功能行菜单：跟随默认、按服务分组、不可用原因、需验证 | `scene-2.png` |
| 3 | 重型功能行菜单：显式选择 + 思考分节；未保存 | `scene-3.png` |
| 4 | 异常集合：无法关闭思考、需验证、已删除、连接不可用、不支持工具、服务已停用 | `scene-4.png` |
| 5 | 快速默认未设置；显式绑定的标题生成不受影响 | `scene-5.png` |
| 6 | 没有任何模型 | `scene-6.png` |
| 7 | 保存失败；版本冲突 | `scene-7.png` |
| 8 | 模型页“分配…”与添加后的 HUD | `scene-8.png` |
| 9 | 按模型定位并高亮 | `scene-9.png` |
| 10 | 删除被使用的模型 | `scene-10.png` |
| 11 | 窄屏（底部表单，两行布局） | `scene-11.png` |
| 12 | 深色 | `scene-12.png` |
| 13 | 全文翻译开始前：模型失效，选择本次模型 | `scene-13.png` |
| 14 | 长任务：interrupted / partial（多模型阶段）/ 任务级错误暂停 | `scene-14.png` |
| 15 | 后续使用新模型的确认 | `scene-15.png` |
| 16 | 对话模型菜单“跟随设置”；专用功能显示实际模型 | `scene-16.png` |
| 17 | 快速任务开始时拦截 | `scene-17.png` |

## 12. 实现落点与需协调的接口

| 位置 | 内容 |
| --- | --- |
| `apps/marginmind/lib/settings/settings_window.dart` | `SettingsTab.aiTasks`、导航、`showSettings` 的 `focus` 参数 |
| `apps/marginmind/lib/features/assistant/settings/ai_task_settings.dart`（新增） | 页面、草稿、底部条、定位高亮 |
| `apps/marginmind/lib/features/assistant/settings/model_route_picker.dart`（新增） | `ModelRoutePicker`、`routeModelLabel()`（同名区分规则的唯一实现） |
| `.../settings/model_settings.dart` | 移除默认模型组和“设为默认”；“分配…”；删除前检查引用；添加后的 HUD |
| `.../widgets/assistant_model_menu.dart`、`assistant_messages.dart` | “跟随设置”；“AI 功能设置…”；专用功能回答的模型元信息 |
| 各功能设置面板、错误卡、任务面板 | §6、§7 |
| `apps/marginmind/lib/l10n/app_{zh,en}.arb` | §10 文案 |

需要 S1/S2 的接口提供以下信息（本任务不实现，交父负责人协调，不另造兼容协议）：

1. **失效引用的显示名快照。** 父负责人决定：路由默认/显式绑定保存服务名与模型显示名快照，只用于显示，仍以 `(serviceId, modelId)` 解析，不另建完整服务删除墓碑。旧记录无快照时保留 ID 作为显示回退，不猜测同名模型。Run 的配置阶段也保存显示快照。
2. **按引用列出使用方。** `RoutingUsage.of(ModelReference | serviceId)` 返回默认、功能、会话覆盖、可恢复 run 的列表，供 §4.4 与 §4.3 使用。
3. **按行解析状态。** Resolver 对每个 taskType 返回 `{effective: ModelReference?, source: explicit|inherit, issue: none|unset|deleted|modelOff|serviceOff|serviceRemoved|secretUnavailable|thinkingAlwaysOn|capabilityMissing(kind)|unknown}`。界面只按此枚举渲染，不自行判断能力或匹配名字。
4. **重型思考可选值。** 能力档案给出该模型支持的 `ReasoningPolicy` 值集合，用于 §2.2 和 §2.4。
5. **能力测试入口。** `capability_probe` 需可取消，并返回能映射到上述 issue 的结果。
6. **保存。** `save(draft, expectedRevision)` 区分 `conflict` 与其他失败。
7. **run 的模型阶段。** `RunManifest` 提供 `[(model, range)]`，并提供“后续使用”所需的新配置阶段接口。

## 13. 验收对照

| 上位文档要求 | 本文位置 |
| --- | --- |
| 快速/重型默认、按功能继承与覆盖 | §2 |
| 模型保存后的分配入口 | §4.1–4.3 |
| heavy 可选思考策略，quick 固定 off | §2.2、§2.4 |
| 实际生效模型 | §2.3、§5、§6、§7.2 |
| 失效引用、能力未知、不能关闭思考、密钥不可用、保存失败、删除影响 | §3、§2.5、§4.4 |
| 不暗中 fallback、保存只影响新任务 | §3、§6.3、§2.5、§7.2 |
| 对话模型不覆盖专用功能 | §5 |
| 窄屏、键盘与无障碍 | §8、§9 |
| 长任务 partial / paused / interrupted 与本次模型 | §7 |
| 不暴露内部 prompt、taskType、协议参数 | 原则、§10 |
