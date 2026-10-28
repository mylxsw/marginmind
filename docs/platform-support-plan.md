# 跨平台支持评估与开发方案

> 更新：2026-10-28。代码评估基线：[`7839b170735e92ca57ce50d28ae67592c6d9b3de`](https://github.com/mylxsw/marginmind/commit/7839b170735e92ca57ce50d28ae67592c6d9b3de)，已先同步 `origin/main`。应用版本字段为 `0.8.0+8`，包含 v0.8 后的助手改版，不能只按版本号判断实现。
>
> 本文是交给后续 Agent 的实施任务书；文中“目标”“验收”都是待完成工作，不代表当前已支持。任务 ID 为本文内部编号，不是已经创建的 GitHub Issue 或 Linear 事项。本次只交付方案，不修改运行代码、不发布安装包。

## 1. 结论与范围

MarginMind 当前仍以 macOS 为主要交付平台。Windows/Linux 已有原生工程和部分桌面适配，但存在确定的功能缺口，也缺少完整构建、运行和发布证据。iOS/iPadOS、Android、Web 均没有平台工程。

优先把 Windows/Linux 做成可以验证、可安装、功能边界明确的桌面版本。保留当前 macOS 体验与文件格式；不要为移植重写领域层或另起助手实现。移动端和 Web 单列后续阶段，不与桌面任务捆绑交付。

### 1.1 当前支持矩阵

“有实现”不等于本次已实机验证；Windows/Linux 的通用功能仍需 CP-01、CP-10、CP-12 验收。

| 能力 | macOS | Windows / Linux | 移动端 / Web |
| --- | --- | --- | --- |
| 原生应用工程 | 有，部署目标 12.0 | 有 Runner、CMake 配置 | 无 `ios/`、`android/`、`web/` |
| 窗口、主要快捷键 | 原生标题栏与菜单；Command | 原生标题栏；主要命令转 Ctrl，无应用菜单栏 | 未形成产品适配 |
| PDF、脑图、复习、本地保存 | 已有完整实现及历史验收记录 | 主要 Dart/Flutter 逻辑可复用；未完成原生闭环验收 | 需要文件交互、布局与平台接入 |
| Markdown / OPML 导出 | 有 | 节点右键可进入导出面板；保存待实测 | 当前保存流程需替换 |
| PNG / 矢量 PDF 导出 | 有原生编码器 | 没有对应原生通道，选择后会失败 | 未实现 |
| 脑图结构化剪贴板 | 文本 + 内部结构 | 只传纯文本；卡片类型、原文关联等不能完整往返 | 未适配 |
| 剪贴板图片 | 有 | `readImage()` 返回 null | 未适配 |
| 扫描 PDF OCR | Vision 本机实现 | 明确标记不支持 | 未接入 |
| 助手模型/搜索凭据 | Keychain | 没有 SecretStore 后端，影响设置与调用 | 未适配 |
| 助手网页正文提取 | WebKit + Readability | 没有解析通道，抓取后的正文解析失败 | 未适配 |
| 在系统浏览器打开来源 | NSWorkspace | 没有通道，返回 false | 未适配 |
| 系统强调色与辅助功能读取 | 有原生实现 | 使用默认值；普通浅/深色主题仍有通用实现 | 未适配 |
| 自动化与发布 | CI 构建、原生测试；DMG 工作流 | 无应用构建任务、无安装包发布 | 无 |

### 1.2 必须更新的旧结论

1. **助手已经不是占位界面。** 当前有 `mm_assistant`、真实设置界面、模型服务、独立搜索后端、会话与提议执行链路。旧 `mm_research/session_engine.dart` 已移除；不要按早期研究面板方案重新开发或恢复旧引擎。
2. **非 macOS 已有导出入口。** 节点右键“导出分支”打开统一面板，面板可切换整图/分支；仍缺少无需选中节点的通用全局入口。PNG/PDF 的原生实现缺失与入口问题是两件事。
3. **PNG 也依赖 macOS。** Flutter 只完成离屏分块绘制，最终调用 `NativeMapExport.png` 合成，不能因为使用 Flutter 绘图就认定跨平台。
4. **密钥问题已影响实际助手流程。** `AssistantServicesStore._load()` 在首次/旧配置迁移时读取 SecretStore；运行工厂也读取凭据，不能假设“本机 Ollama 不需要 Key，所以其他系统直接能用”。
5. 历史测试数、旧 macOS 截图不作为当前 Windows/Linux 支持证据。

## 2. 接手前阅读与代码入口

先读 [开发约定](../CONTRIBUTING.md)、[架构](architecture.md)、[助手契约](assistant-architecture.md)、[ADR 0002](decisions/0002-assistant-agent.md) 及其后续补充。助手交互遵循 [三期方案](phase-3-assistant.md) 和 [三期 UI](phase-3-assistant-ui.md)。与旧二期文本冲突时，以当前实现和较新的助手契约为准。

| 问题/职责 | 当前入口 |
| --- | --- |
| 平台窗口、快捷键、外观 | [`mm_platform/lib/src`](../packages/mm_platform/lib/src/)、[`app_commands.dart`](../apps/marginmind/lib/app/app_commands.dart) |
| 硬编码 Command 的资料库命令 | [`library_screen.dart`](../apps/marginmind/lib/features/library/library_screen.dart) 中 `meta: true` |
| 导出入口、选项与分块绘制 | [`map_pane.dart`](../apps/marginmind/lib/features/workspace/widgets/map_pane.dart)、[`map_export_sheet.dart`](../apps/marginmind/lib/features/workspace/widgets/map_export_sheet.dart)、[`map_export_scene.dart`](../apps/marginmind/lib/features/workspace/widgets/map_export_scene.dart) |
| 原生 PNG/PDF 编码 | [`map_export.dart`](../packages/mm_platform/lib/src/map_export.dart)、[`MapExportChannel.swift`](../apps/marginmind/macos/Runner/MapExportChannel.swift) |
| 剪贴板格式、复制剪切事务 | [`map_clipboard.dart`](../packages/mm_platform/lib/src/map_clipboard.dart)、[`mm_core` 剪贴板模型](../packages/mm_core/lib/src/content/map_clipboard.dart)、[`workspace_controller.dart`](../apps/marginmind/lib/features/workspace/workspace_controller.dart) |
| OCR 与能力判断 | [`pdf_ocr.dart`](../packages/mm_platform/lib/src/pdf_ocr.dart)、[`reader_ocr.dart`](../apps/marginmind/lib/features/workspace/reader_ocr.dart)、[`PdfOcr.swift`](../apps/marginmind/macos/Runner/PdfOcr.swift) |
| 凭据及服务配置 | [`secret_store.dart`](../packages/mm_platform/lib/src/secret_store.dart)、[`assistant_settings.dart`](../apps/marginmind/lib/features/assistant/assistant_settings.dart)、[`assistant_services.dart`](../apps/marginmind/lib/features/assistant/assistant_services.dart) |
| 网页提取、浏览器跳转 | [`article_parser.dart`](../packages/mm_platform/lib/src/article_parser.dart)、[`external_link.dart`](../packages/mm_platform/lib/src/external_link.dart)、[`assistant_network.dart`](../apps/marginmind/lib/features/assistant/assistant_network.dart)、[`assistant_overlays.dart`](../apps/marginmind/lib/features/assistant/widgets/assistant_overlays.dart) |
| 文件包、对话、快照 | [`mm_data/lib/src`](../packages/mm_data/lib/src/)、[`main.dart`](../apps/marginmind/lib/main.dart) |
| 助手网络与现有边界 | [`mm_assistant/lib/src`](../packages/mm_assistant/lib/src/)、[`mm_research/lib/src`](../packages/mm_research/lib/src/) |
| CI / 发布 | [`ci.yml`](../.github/workflows/ci.yml)、[`release.yml`](../.github/workflows/release.yml)、[`coverage.py`](../tool/coverage.py) |

基线中的 `marginmind/map_export`、`map_clipboard`、`pdf_ocr`、`secret_store`、`article_parser`、`external_link` 原生处理器都在 macOS Runner；Windows/Linux Runner 没有相应实现。`external_link` 缺失返回 false，但部分调用方未展示失败，需连同 UI 修复。

## 3. 交付目标与约束

### 3.1 分阶段目标

| 阶段 | 交付内容 | 完成门槛 |
| --- | --- | --- |
| D0：可验证构建 | Windows/Linux 原生构建、启动和问题基线；能力统一声明 | CP-01、CP-02；只能称开发验证版 |
| D1：桌面预览版 | 阅读→摘录→脑图→复习→重启恢复；命令、结构剪贴板、四种导出；助手设置、离线提问、联网正文与来源跳转 | CP-01～CP-08、CP-10～CP-12 全部完成；未支持 OCR 时明确披露，不称功能完全一致 |
| D2：桌面 OCR 补齐 | Windows/Linux 本机识别扫描 PDF | CP-09 与对应验收通过后再更新支持矩阵 |
| M：移动端 | 先做工程与交互验证，再做可用闭环 | MOB-01～MOB-03；不由桌面通过自动推导 |
| W：Web | 先验证存储与网络边界，再决定正式实现 | WEB-01～WEB-03；不把浏览器演示当正式支持 |

首轮建议测试目标为 **Windows 11 x64、Ubuntu 24.04 x64**，macOS 保持现有部署目标和发布方式。这是本方案的首轮验收范围，不是已验证的最低系统版本。CP-01 必须记录实际 OS/架构、插件和系统库约束。Linux 首轮记录 X11 会话；Wayland 必须单独实测并标记结果，不能用 X11 通过代替。Windows/Linux ARM64、其他发行版、Windows 10 另列扩展矩阵，未验收不承诺支持。

### 3.2 实现约束

- 领域编辑、FSRS、文件格式、助手会话契约继续共用；平台插件留在 `mm_platform`，组合根选择后端，功能界面不直接导入新的平台插件。
- 新 UI 使用 `mm_design` 令牌和中英文 ARB；保留 macOS 菜单、键盘、窗口与辅助功能回归。
- 能力必须区分“平台未实现”“运行环境暂不可用”“服务尚未配置”和“操作失败”。不把所有异常都当平台不支持，也不靠点击后捕获 MissingPluginException 作为正常产品流程。
- `SecretStore` 缺失时不能改存 SharedPreferences、`.mmset`、日志或明文文件；不引入静默明文回退。
- 平台迁移不改变助手的授权范围、提议确认、事务/撤销、引用快照、联网开关和恢复语义。关闭联网不注册联网工具；恢复中断会话不自动重发或执行工具。
- 新网页解析后端仍只处理已经安全抓取的 HTML，不能让 WebView 自行联网加载原网页或资源而绕过现有 UrlPolicy。模型/搜索地址的显式例外不能传给正文抓取。
- 新依赖先提交最小验证和选型记录：固定版本、许可证、支持的 OS/架构、原生库大小、离线可用性与维护成本。不能只凭插件首页的平台图标声明完成。
- 本计划不安排收费服务订阅、商店发布、自动更新、同步功能或 Developer ID 签名/公证；保持已有发布策略。

## 4. 桌面开发任务

优先级：P0 为阻断使用或可能造成内容降级的问题；P1 为 D1 功能完整性/交付保障；P2 为后续功能补齐。全部任务初始为“未开始”。每项都需按第 7 节交付证据。

### CP-01（P0）建立 Windows/Linux 构建与启动基线

**依赖：** 无。**入口：** 两个平台 Runner、pubspec/lock、`.fvmrc`。

**工作：** 在目标系统安装并记录匹配的 Flutter 3.47.2 工具链；Windows 使用 Visual Studio C++ 桌面工具链，Linux 配齐 CMake/Ninja/GTK 等依赖。先原样构建，再按最小范围修复平台注册、PDFium/FFI 打包与启动错误；不要批量重新生成并覆盖已有 Runner。确认不安装 Flutter 的机器也能启动构建产物。记录调试版与发布版、启动日志和系统库需求。

**验收：** 两个平台 `flutter build <platform> --debug/--release` 成功；打开示例 PDF，至少完成一次选字摘录、编辑和重启恢复。工具链缺失、编译错误、运行错误分开登记；不能把 `flutter test` 通过当作此项通过。

**交付：** `docs/platform-acceptance.md` 的环境/基线章节、`docs/evidence/platform/CP-01/` 的脱敏日志与截图，以及必要的构建修复。

### CP-02（P0）统一平台能力与不可用状态

**依赖：** 可先定义接口；环境探测以 CP-01 为依据。**入口：** `mm_platform`、应用 Provider、导出/OCR/助手设置。

**工作：** 增加可注入的能力接口，至少覆盖结构化剪贴板、图片粘贴、PNG、PDF、OCR、凭据存储、正文解析、外部浏览器、系统外观；用 typed status + reason 表达实现与运行时可用性。实现选择和 UI 使用同一来源。未实现的格式不作为默认导出选项；调用前检查并提供明确说明。暂不支持结构剪切的平台先禁用该操作或提供明确的仅文本复制，不能先删原节点再静默降级。密钥/解析失败不得阻断普通阅读与编辑。

**验收：** 注入完整、部分、全部不可用能力分别测试；无有效导出格式时说明原因；OCR 不可用时无误导入口；Linux 无凭据服务时设置仍可打开并说明状态。macOS 原有可用功能不被误关。

### CP-03（P1）补齐命令菜单与快捷键

**依赖：** CP-02。**入口：** `app_commands.dart`、`library_screen.dart`、设计系统菜单。

**工作：** 从同一命令定义生成 macOS 系统菜单和 Windows/Linux 应用内菜单；无快捷键命令也要可发现、可用键盘访问。提供无需选中节点的整图导出入口。替换资料库硬编码 `meta: true`，检查助手、查找、缩放、视图、删除/剪切等焦点路由。当前非 Mac 注册列表漏了 `fullScreen`，且它的 Ctrl 映射会与查找 Ctrl+F 冲突；需选用平台合适的独立键位并同步提示文案。

**验收：** 三个平台的命令启用状态一致；编辑文本时 Ctrl/Cmd+C/X/V/Z 不被画布劫持；查找与全屏不冲突；中文输入法确认文字不触发提交命令；仅键盘可打开导出、设置及助手。增加按平台和焦点范围检查重复快捷键的测试。

### CP-04（P0）无损结构剪贴板与图片粘贴

**依赖：** CP-02；原生验证依赖 CP-01。**入口：** 两层 `map_clipboard.dart`、`WorkspaceController.copySelection/pasteSelection`。

**工作：** Windows/Linux 写入纯文本和有版本的内部结构格式，优先读取内部格式；沿用现有序列化和资源导入契约，保留卡片类型、层级、原文锚点、标签、宽度/格式、图片与研究/AI 笔记引用。支持外部文本大纲降级，但不能把应用内结构当文本处理。实现截图字节/图片文件粘贴，资源复制进 `.mmset`。剪切必须在所需数据写入成功后才能删节点；失败不修改文档。

**验收：** 同图、同学习集跨图往返保留摘录类型与原文定位；跨学习集遵守现有 `StudySetEditor.paste` 契约：目标没有原 PDF 时摘录转成保留引文的笔记，不伪造可定位锚点。图片复制入目标包、研究快照与已有跨集引用处理不退化，不能承诺剪贴板自动搬运整本 PDF。外部文本往返层级正确；损坏格式有明确结果；复制源应用关闭后的行为被验证并说明。剪切失败内容不变，粘贴/批量移动各一步撤销。分别实测 Windows、Linux X11/Wayland 的剪贴板所有权与图片 MIME 行为，不用进程内缓存冒充系统剪贴板。

### CP-05（P1）PNG 与矢量 PDF 跨平台编码

**依赖：** CP-02；入口联调 CP-03。**入口：** `NativeMapExport`、`MapExportScene`、`MapExportSheet`。

**工作：** 保留现有场景、分块与尺寸预算，新增 Windows/Linux 编码后端或经过验证的共用实现。PNG 合并分块并保留透明通道；PDF 保留可搜索文字、连线/概要和图片，不用整页截图替代矢量导出。处理中文字体映射/嵌入及许可证、保存取消、权限错误、磁盘失败；同一快照不受导出时继续编辑影响。导出格式能力单独声明。

**验收：** 整图/分支、浅色/深色/透明 PNG、多张脑图、中文/英文、500 节点大图、外部图片和 AI 笔记均有样本；无裁边、缺字、错行、丢图片。PDF 可选字搜索，PNG 尺寸与预览一致；32M 像素等现有预算不被取消。原生编码和真实保存必须实测，mock channel 测试只验证桥接契约。

### CP-06（P0）跨平台凭据存储与助手初始化

**依赖：** CP-02；CP-01 提供系统环境。**入口：** `SecretStore`、`assistantSecretsProvider`、`AssistantServicesStore`、运行工厂与搜索配置。

**工作：** 为 Windows/Linux 接入系统保护的凭据后端；保留 `assistant.service.<id>`、`assistant.search.<backend>`、Cloudflare accountId 等命名与迁移规则。首次启动无旧配置时可正常打开设置；旧服务迁移只有凭据复制成功才提交完成标记。区分“没有 Key”和“凭据服务不可用/锁定”。本机无 Key 模型的配置/运行不能无条件依赖远端 Key 读取；若其配置确有凭据仍须正确处理，不能吞掉所有读取错误。模型/搜索的保存、删除和重启读取统一走端口。

**验收：** 全新用户、旧配置迁移、多服务同协议不同 Key、删除服务、切换模型、进程重启；Linux 凭据服务缺失/锁定时无明文落盘且阅读正常。显式启用的无 Key 本机模型可保存、测试连接并发送；远端服务缺 Key 有明确提示；对话、`.mmset`、preferences 和日志不包含秘密。沿用取消、恢复不自动重发和提议事务测试。

### CP-07（P1）外部链接在默认浏览器打开

**依赖：** CP-02。**入口：** `ExternalLinks`、助手来源抽屉与 Markdown 链接回调。

**工作：** Windows/Linux 实现默认浏览器启动；保留绝对 http(s) 校验。所有调用方处理 false/异常并展示失败或复制链接入口；不要通过 shell 拼接 URL。继续使用当前引用的真实 URL，不从模型文本推导可信来源。

**验收：** 中文、查询参数、锚点 URL 可打开；无浏览器/桌面会话、无效 URL 失败可理解；拒绝 file/javascript/自定义协议；来源抽屉与正文链接都实测。

### CP-08（P1）跨平台正文解析与助手联网闭环

**依赖：** CP-02、CP-06；完整来源操作依赖 CP-07。**入口：** `HtmlArticleParser`、`WebKitArticleParser`、`assistantArticleParserProvider`、助手网络与快照实现。

**工作：** 比较“隔离的本地 JS 运行环境 + 已打包 Readability”与目标平台 WebView 方案，以仓库正文 fixtures 做一致性试验后选定后端并写 ADR。输入仍是安全传输已抓取的 HTML；禁用页面脚本/子资源主动联网，不复用有用户登录态的浏览器。实现取消、超时、清理和正文/标题/canonical 输出；不能用搜索摘要或模型回答补成抓取正文。保留快照先落盘、段落编号与引用登记的既有顺序。

**验收：** 中文/英文样本、空页面/登录页、损坏 HTML、超时/取消；结果至少满足现有 extractor fixtures 的断言。模型服务与独立搜索后端分开测试，联网关闭无网络工具；实际来源可抓取、保存、重启查看并回到被引段落；解析失败不登记伪造证据。真实模型未接入时只记录“假服务/回放通过”，不可标为真实供应商验收通过。

### CP-09（P2）Windows/Linux 本机 OCR

**依赖：** CP-01、CP-02、CP-10。**入口：** `PdfOcrService`、阅读器 OCR 控制器和 PDF 文件副本处理。

**工作：** 保留 macOS Vision；为两个平台分别验证系统能力或可分发的本机 OCR 引擎，明确中文/英文字库来源、许可证、下载体积及离线行为。输出和当前契约一致的可搜索 PDF 副本，原 PDF 保留；实现页范围、进度、取消及失败恢复，不改成默认上传云端识别。

**验收：** 扫描中文/英文、混合文字层 PDF、旋转页、多页范围；识别后可搜索/选字/摘录，矩形定位正确；取消保留已完成结果，重启可恢复使用；缺字库/损坏文件/磁盘不足有明确退路。D1 若未完成此项，支持矩阵必须继续标注不支持 OCR。

### CP-10（P1）文件兼容、输入、字体与辅助功能验收

**依赖：** CP-01；对新增功能的检查在 CP-03～CP-08 合入后补齐。**入口：** `mm_data`、文件选择/拖入、窗口布局、字体令牌、系统外观。

**工作：** 验证不同系统 Application Support 路径与 `.mmset` 迁移；覆盖图片、OCR 副本、研究快照、`conversations/` 和助手执行凭据。保留已有 schema/原子迁移，不为平台名称分叉格式。检查路径分隔符、中文/空格、大小写、Windows 保留文件名、文件占用下 rename、权限错误及损坏包处理。验证高 DPI、多显示器、中文输入法、鼠标/触控板、屏幕阅读器；补充平台字体回退和必要的系统外观能力，保持统一设计令牌。

**验收：** 使用测试副本，Mac→Windows→Linux→Mac 往返后 PDF/图片/引用可读，脑图/复习记录/会话不丢，running 会话恢复为 interrupted 不自动请求；跨机 Key 不随文件包迁移。拖入 PDF/图片、取消选择、保存失败均不产生半成品。125%/150%/200% DPI 和 960×600 窗口无关键入口遮挡；记录 Linux 字体和显示会话，未支持的辅助功能明确列出。

### CP-11（P1）三桌面 CI 与分层测试

**依赖：** CP-01 后先接构建，随 CP-02～CP-10 增量接入回归。

**工作：** 保留现有 macOS 构建/原生测试与覆盖率门禁；新增 Windows/Linux 原生 debug/release 构建任务，固定可复现 runner 和系统依赖，缓存按 OS/架构/lock/Flutter 版本隔离。上传可运行的完整 bundle 和失败日志。将能力/命令/剪贴板契约参数化到三个桌面目标；真实原生集成另跑，不把 TargetPlatform override 当系统实现。已有 `coverage.py` 已包含 `mm_assistant`，不得漏掉新包或降低 80% 门禁。

**验收：** 干净 runner 无本机缓存也能构建；引入原生注册错误时目标构建失败；平台后端行为错误由真实集成测试或明确的人工门禁阻断。CI 不依赖个人 API Key，使用确定性 fixtures/假服务；公网和真实凭据联调单独登记。

### CP-12（P1）桌面预览包与发布前验收

**依赖：** CP-01～CP-08、CP-10、CP-11；CP-09 非 D1 必选，但必须标注状态。

**工作：** 首批提供 Windows 完整便携 ZIP、Linux 完整 bundle 压缩包；不要只发 exe/可执行文件，必须携带 Flutter/PDFium/插件依赖。记录外部系统运行库、启动方式、数据目录、升级与卸载行为、SHA-256 校验值。将产物接到现有手动/标签发布流程，沿用草稿 Release，不擅自公开或新增签名账号。README 和支持矩阵写清 OS/架构、已验收功能及 OCR 等限制。

**验收：** 无开发工具的目标系统安装/解压即运行；升级旧数据成功，取消/失败可恢复，卸载不误删用户学习集。完成第 6 节全部 D1 场景，测试的是待发布产物及其确切 commit。文档、安装包名称、版本号和发布说明一致；不能拿 debug 运行通过替代 release 包验收。

## 5. 移动端与 Web 后续任务

这些任务进入独立里程碑。桌面 CP-02 的能力接口和 CP-10 的文件契约应复用；不得因 Flutter 支持某平台就直接把该平台标成可用。

| ID / 依赖 | 具体工作 | 验收与交付 |
| --- | --- | --- |
| MOB-01 / CP-02 | 在独立分支补 iOS/Android 工程，锁定 SDK/最低系统/设备矩阵，逐项盘点 pdfrx、拖入、选文件、分享、凭据和助手依赖；只为缺失平台生成工程，保留现有桌面 Runner | iOS 模拟器及真机、Android 模拟器及真机各完成启动与应用沙盒内 PDF 打开；提供构建命令、插件缺口和签名配置说明；未接入功能显示正确能力状态 |
| MOB-02 / MOB-01 | 手机采用单主面板导航；平板评估横向分栏；提供长按菜单、触摸选字、拖拽、双指缩放、屏幕键盘、SafeArea 和系统返回；消除“必须右键/Command”的唯一入口 | 手机竖屏与平板横/竖屏完整执行阅读→摘录→脑图→复习；软键盘不遮住确认/发送；触控不能误触桌面拖拽；更新设计稿与截图 |
| MOB-03 / MOB-01、MOB-02 | 文件选择结果按可读字节/授权资源复制入沙盒；导出使用系统保存/分享而非桌面 getSaveLocation；验证平台凭据、应用切后台/杀进程恢复、网络取消与 OCR/剪贴板能力 | Android 内容 URI 与 iOS 文件提供者均测试；外部授权失效后已导入文档仍可读；导出文件可由外部应用打开；重启保留学习/会话状态且无自动工具执行。记录发行构建，之后才能形成移动端发布任务 |
| WEB-01 / CP-02、CP-10 | 做架构可行性验证：列出启动链及 mm_data/mm_assistant/mm_research 的 dart:io、Socket、文件路径依赖；设计浏览器持久化端口、PDF 字节/URL 读取、导入导出与离线缓存；评估同源/CORS、凭据与代理 | 提交单独 ADR，明确浏览器版本、配额/清理/备份边界。服务端代理意味着新增服务与部署，需另立工作范围，不能默认已有。浏览器无法照搬当前 DNS/IP 固定与 TLS 传输策略，必须明确替代架构 |
| WEB-02 / WEB-01 方案确定 | 实现浏览器存储、文件导入/下载、PDF 打开与重启恢复；使用条件导入/平台后端隔离，核心领域模型继续复用 | web release 构建成功；浏览器创建→导入→编辑→刷新→导出闭环；大文件、空间不足、取消、存储被清理有可理解结果，提供用户备份出口 |
| WEB-03 / WEB-02 | 按已确定的网络架构接助手，验证 CORS、流式取消、凭据使用范围、外部链接和来源快照；移动浏览器另做触控验证 | 真实支持的浏览器逐项验收；不把长期 API Key 默默保存在不受保护的持久化存储；不能通过禁用现有来源/网络约束换取演示可用。发布前完成独立部署、隐私与运维说明 |

移动端文件接口需逐项核实：当前固定的 [file_selector 1.1.0 平台表](https://pub.dev/packages/file_selector/versions/1.1.0#features-supported-by-platform) 中，选择保存位置不支持 Android/iOS/Web；不能仅添加 Runner 后沿用桌面导出。

## 6. 验收场景与验证命令

### 6.1 D1 必测场景

同一组测试资料包括：中英文文字 PDF、扫描 PDF、多页摘录、图片卡、带关联线/概要的多张脑图、旧格式包、含 AI 引用和中断会话的文件包。只能使用测试副本。

| 场景 | 必须观察的结果 |
| --- | --- |
| 新用户首次启动 | 资料库与设置可用；没有 Key、凭据服务缺失、未配置模型的状态分别可理解；普通阅读不受助手初始化失败影响 |
| 核心学习闭环 | PDF 导入→跨页摘录→脑图编辑→原文定位→复习→退出重开，内容和进度正确 |
| 文件与包迁移 | 跨系统复制整个包后资源及引用可用；旧格式迁移、失败备份和会话恢复正确 |
| 结构编辑 | 类型/资源完整复制与剪切粘贴；失败不删原内容；撤销/重做事务正确 |
| 导出 | 四格式、整图/分支、大图与中英混排，真实文件在外部应用可打开；取消不报成功 |
| 助手 | 配置/保存/重启读取、离线问答、来源抓取/浏览器跳转、停止/重试、提议确认与撤销、关闭面板继续生成、重启不重发 |
| 系统交互 | 默认浏览器、文件选择器、拖入、字体、高 DPI、键盘/IME、窗口缩放与辅助功能 |
| Release 包 | 在无开发工具的目标机运行，确认运行库/原生依赖、数据路径和升级；OCR 未完成则入口与说明一致 |

新增 OCR、移动端、Web 用各自任务的验收补充，不能以桌面场景替代。

### 6.2 命令与证据口径

从仓库根目录运行；先确认 `flutter --version` 为仓库固定版本。Windows 使用 PowerShell 等价的进入目录命令；各平台原生构建在各自宿主上执行。

```bash
flutter pub get --enforce-lockfile
flutter analyze
dart format --set-exit-if-changed apps packages
python3 -m unittest discover -s tool/tests
python3 tool/coverage.py
```

定向回归（目录和测试文件以合入时仓库为准）：

```bash
cd apps/marginmind
flutter test --no-pub ../../packages/mm_platform/test \
  test/map_export_test.dart test/reader_ocr_test.dart \
  test/map_selection_clipboard_test.dart test/assistant_services_test.dart \
  test/assistant_settings_test.dart test/assistant_network_test.dart
```

```bash
# 在对应目标宿主，apps/marginmind 目录执行
flutter doctor -v
flutter build windows --debug
flutter build windows --release
# 或在 Linux 宿主
flutter build linux --debug
flutter build linux --release
# macOS 回归
flutter build macos --debug
xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Debug -destination 'platform=macOS' -enableCodeCoverage YES
```

Windows 工具链参见 [Flutter Windows setup](https://docs.flutter.dev/platform-integration/windows/setup)；Linux 参见 [Flutter Linux setup](https://docs.flutter.dev/platform-integration/linux/setup)。这些是上游环境说明，不代表项目已支持其中所有系统；仍需与固定 Flutter、插件版本和 CP-01 实测对齐。

证据分四层记录：①纯 Dart/Widget 与模拟通道测试；②原生构建；③真实系统/插件交互；④待发布安装包验收。每层分别写通过、失败、未运行及原因。模拟 `TargetPlatform.windows`、注入假 OCR/LLM、替身文件选择器或关闭 PDF 渲染都不能当作系统集成通过。

### 6.3 本次方案基线验证

本轮在 Ubuntu ARM64 服务器复核 `7839b17`，不是首轮目标矩阵的 Ubuntu x64 验收。未接真实模型账号；没有 Windows/macOS 真机重新验收。结果仅代表上述基线：

| 检查 | 结果与边界 |
| --- | --- |
| `flutter pub get --enforce-lockfile` | 通过；使用锁定依赖，没有升级包 |
| 第 6.2 节定向 Flutter 测试 | 55 项通过；含平台模拟、假通道和假服务，不代表原生能力通过 |
| `packages/mm_data` 下 `dart test --reporter expanded` | 39 项通过；覆盖本地文件、迁移、对话存储等测试，不是跨系统互通实测 |
| `apps/marginmind` 下 `flutter build linux --debug --no-pub` | 失败于环境前置检查：`CMake is required for Linux development.`，尚未进入应用编译，不能归因为产品编译错误 |
| 本次未运行 | 全仓静态分析/覆盖率、原生 Windows/macOS 构建、Linux release 与真实 UI 闭环、真实模型联调 |

本次只修改文档，另检查 Markdown 本地链接与 `git diff --check`。后续实现仍必须完成第 6.2 节对应的完整检查，不以本次定向测试替代。命令与结果摘录见 [基线记录](evidence/platform/2026-10-28-baseline.txt)。

## 7. 任务顺序与 Agent 交接规则

建议顺序：CP-01 与 CP-02 先完成；CP-11 随 CP-01 立即接入构建。优先关闭 CP-04 的剪切降级和 CP-06 的助手初始化问题，再推进 CP-03、CP-05、CP-07、CP-08、CP-10，最后 CP-12。CP-09 单独补齐；移动端/Web 按第 5 节进入后续里程碑。

可拆分的工作是编码器、凭据、剪贴板、正文解析的独立后端；**接口和能力枚举先统一**。多个任务会修改 `mm_platform.dart`、应用 Provider、ARB 和命令列表，接手者须先检查最新主干与已有 PR，避免重复接口或覆盖别人的工作。

每个任务的交付必须包含：

1. PR 标题标明本文 ID；描述触发条件、修改后的行为、未支持范围与依赖。
2. 更新本文任务状态和支持矩阵；未经过真实平台验证时只能写“实现完成、待原生验收”，不能直接写完成。
3. 在 `docs/platform-acceptance.md` 登记 commit、OS/架构/显示会话、Flutter/编译器版本、命令、结果、产物位置；首次接手 CP-01 创建该文件。
4. 截图/脱敏日志放 `docs/evidence/platform/<任务ID>/`，大安装包通过 CI artifact/Release 保存，不提交进仓库。失败附最小复现，注明环境问题还是代码问题；跨平台测试跳过必须有理由。
5. 更新中英文文案、设计令牌/稿（如涉及）及必要测试；说明 macOS 回归范围。新增接口必须在不可用平台有明确结果，不能默默吞错。
6. 合入前重新同步主干并复核能力矩阵；不把本文基线或某次测试数当成永久事实。

| ID | 状态 | 依赖 | 完成记录（PR / 验收证据） |
| --- | --- | --- | --- |
| CP-01 | 未开始 | 无 | — |
| CP-02 | 未开始 | 接口可先做，实测 CP-01 | — |
| CP-03 | 未开始 | CP-02 | — |
| CP-04 | 未开始 | CP-02，原生验证 CP-01 | — |
| CP-05 | 未开始 | CP-02，入口 CP-03 | — |
| CP-06 | 未开始 | CP-02、CP-01 | — |
| CP-07 | 未开始 | CP-02 | — |
| CP-08 | 未开始 | CP-02、CP-06、CP-07 | — |
| CP-09 | 未开始 | CP-01、CP-02、CP-10 | — |
| CP-10 | 未开始 | CP-01，功能合入后补验 | — |
| CP-11 | 未开始 | CP-01，随功能增量接入 | — |
| CP-12 | 未开始 | CP-01～CP-08、CP-10、CP-11 | — |
| MOB-01～03 | 后续阶段 | 见第 5 节 | — |
| WEB-01～03 | 后续阶段 | 见第 5 节 | — |
