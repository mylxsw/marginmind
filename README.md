<p align="center">
  <img src="apps/marginmind/assets/icon/app_icon_macos.png" width="128" alt="Foliarc icon">
</p>

<h1 align="center">Foliarc</h1>

<p align="center">读 → 摘 → 图：在原文、卡片和脑图之间来回穿梭的学习工具。<br>
<em>Read, excerpt and map what you learn — an open-source study tool for macOS, built with Flutter.</em></p>

---

Foliarc 把 PDF 阅读、标注摘录和思维导图放进同一个工作区：在原文里划线，摘录就变成脑图上的卡片；点卡片，一步回到原文的出处。一个“学习集”可以包含多份文档，共同构建一张（或多张）脑图。

> **状态：v0.7。** 读 → 摘 → 图 → 复习的完整闭环已经可用：导入 PDF、选中文字后摘录、像 XMind 一样用键盘整理脑图、从卡片回到原文、FSRS 间隔重复复习与统计、导出脑图，数据保存在本机。仍处于早期阶段，欢迎试用和反馈。

## 安装

1. 在 [Releases](https://github.com/mylxsw/marginmind/releases) 下载最新的 `Foliarc-x.y.z.dmg`，把 Foliarc 拖进“应用程序”。
2. 目前还没有 Apple 开发者签名，第一次打开时 macOS 会拦截：在 Finder 里**右键 Foliarc → 打开**；如果仍被拦截，到“系统设置 › 隐私与安全性”里点“仍要打开”。也可以在终端执行 `xattr -dr com.apple.quarantine /Applications/Foliarc.app`。

需要 macOS 12 或更高版本（Apple 芯片和 Intel 均可）。数据存放在 `~/Library/Containers/io.github.mylxsw.marginmind/Data/Library/Application Support/Library/`，每个学习集是一个独立的 `.mmset` 文件夹。

## 设计原则

1. **它首先是一个 Mac 应用。** 遵循 Apple Human Interface Guidelines（macOS 26）：浮动玻璃侧栏、统一工具栏、系统字体与语义色、跟随系统强调色和辅助功能设置、完整的菜单栏。
2. **原文是锚点。** 每张摘录卡片都能一步回到出处，每处高亮都能一步找到卡片。
3. **书里的话用宋体，自己的话用系统字体。** 不看颜色也能分清“作者说的”和“我想的”。
4. **本地优先。** 单机运行、数据留在本机；数据结构为将来的同步预留了空间，但现在不依赖任何服务端。

## 仓库结构

```
marginmind/
├─ apps/marginmind/        Flutter 应用：窗口、菜单、路由、功能界面（组合根）
├─ packages/
│  ├─ mm_design/           设计令牌、主题（浅色/深色）与 macOS 风格组件库
│  ├─ mm_core/             领域层：实体、编辑操作、仓库端口、查询（纯 Dart，无 Flutter）
│  ├─ mm_data/             持久化：学习集文件包（JSON + PDF 副本）
│  ├─ mm_pdf/              PDF：渲染、选字、高亮叠加、定位（pdfrx / PDFium）
│  ├─ mm_layout/           脑图树布局算法（纯 Dart）
│  └─ mm_platform/         平台适配：原生窗口、拖动、快捷键、系统外观
├─ design/                 UI 设计稿源文件（资料库、工作区、规范、架构）
├─ docs/                   架构、设计系统、应用框架说明
└─ tool/                   图标生成等脚本
```

依赖方向只允许向内：`apps → mm_design / mm_platform / mm_pdf / mm_data / mm_layout → mm_core`，`mm_core` 不依赖任何包。详见 [docs/architecture.md](docs/architecture.md)。

## 可以做什么（v0.8）

1. **资料库**：新建学习集（先选 PDF，以文档名命名，之后可改）、一键打开示例学习集；把 PDF 从 Finder 拖进窗口直接新建学习集；右键可打开、复习、重命名、收藏、删除（⌘⌫）。
2. **导入 PDF**（⌘O、侧栏 +，或直接拖进学习集窗口）：文件被复制进学习集包，原文件移动或删除都不受影响。侧栏里右键文档可以重命名或移除。
3. **先选中，再摘录**：选中文字后，选区上方弹出浮动工具条：点颜色点（或按 E）高亮并在脑图上生成卡片（挂在当前选中的主题下），也可以仅高亮（H）或复制（⌘C）。点已有高亮可以换色、加入脑图或定位卡片、复制、删除。切到高亮笔（⇧⌘H）后，拖选即高亮并生成卡片；应用会记住上次使用的工具。
4. **原文 ↔ 卡片**：点原文中的高亮，脑图里对应卡片闪烁；点卡片右上角箭头（或 ⌘L），切到对应文档、跳页并闪烁原句。
5. **整理脑图**：快捷键与 XMind 一致（见下表），新建的节点直接进入编辑；双击 / F2 / 空格或直接打字原地编辑主题、摘录标题和笔记（笔记用 ⇧Enter 换行），支持中文输入法；⇧ / ⌘ 点击或拖出选框多选，批量删除、移动、改色；⌘C / ⌘X / ⌘V 复制剪切粘贴节点和子树，可与备忘录、XMind 以缩进文本互贴；拖动节点改变层级和顺序（预览线或高亮框标出落点，拖到边缘时画布自动滚动）；大纲视图支持同样的原地编辑和快捷键。
6. **撤销 / 重做**（⌘Z / ⇧⌘Z）：脑图、摘录、高亮、文档的每一步编辑都能撤销。
7. **复习**（⌘R 或侧栏“复习”）：脑图里的摘录和笔记自动成为复习卡片，按 FSRS 间隔重复排期。先回想、再翻面（空格），用 1–4 评分（重来 / 困难 / 良好 / 简单）；把摘录重命名成一个问题，它就成为题面。资料库显示每个学习集待复习的数量。可以按标签或脑图分支复习，也可以暂停某张卡片；复习过后，侧栏“学习”分组里的“统计”显示每天的复习量、记住率和未来 30 天的到期数。
8. **搜索**（⌘F）：侧栏搜索同时匹配文档和卡片内容，点结果直接定位。
9. **导出**：文件 › 导出脑图…，整图或某个分支导出为 PNG、矢量 PDF、Markdown 或 OPML（后两种可导入 MarginNote、XMind、幕布等）。
10. **卡片与内容**：长卡片可展开全文，⌘I 打开详情；调整卡片宽度、紧凑 / 完整显示；笔记支持加粗、斜体和列表；粘贴、拖入或选择图片生成图片卡，也能复习；扫描版 PDF 可以在本机识别文字后选字、搜索、摘录；画笔（⇧⌘M）在原文上圈画、画箭头。
11. **助手**：选中原文或脑图节点，按 ⇧⌘E 提问，⌃⌘R 打开助手。支持解释、翻译、查证、总结、出题、整理、找论文和视频；改图先提议再确认，回答可以保存为关联原文与脑图的 AI 笔记。联网搜索只发现链接，引用来自实际抓取并保存的网页快照或 OpenAlex 元数据，可查看被引段落与快照时间。Claude / OpenAI 使用内置搜索，兼容接口和 Ollama 使用设置中的 SearXNG；关闭联网不注册联网工具。Ollama 支持显式启用的本机地址，远端连接失败可改用已配置的本机模型。Key 存在钥匙串。输入框支持内置语音输入，可在设置中配置豆包实时识别 2.0 或阿里云百炼服务，详见 [语音输入](docs/voice-input.md)。
12. **全文翻译**：对照阅读菜单或侧栏文档右键「翻译全文…」，把整份 PDF 或一段页码分批或一次译完，译文逐段对应原文，可随时暂停、断网或退出后从断点继续，已译段落不会重复请求。
13. **PDF 目录和书签管理**：页面侧栏的目录、书签页都可通过 + 新增，用条目右侧 ⋯ 或右键修改标题和跳转页码、删除、上移或下移。目录可整段拖动，放在条目中间成为子目录，放在上方或下方调整顺序；个人书签拖动左侧手柄排序。两者都支持按页码升序、降序或名称排序，以及撤销 / 重做。没有自带目录的 PDF 也能新增目录。修改保存在学习集内，不写回 PDF 文件。
14. **一切自动保存**：退出再打开，学习集、高亮、脑图、复习进度、每份文档读到的页码都在。

### 快捷键

| 操作 | 快捷键 | 操作 | 快捷键 |
| --- | --- | --- | --- |
| 新建学习集 | ⌘N | 导入 PDF | ⌘O |
| 撤销 / 重做 | ⌘Z / ⇧⌘Z | 搜索 | ⌘F |
| 添加主题 / 添加笔记 | ⇧⌘N / ⌥⌘N | 切换高亮笔 | ⇧⌘H |
| 定位原文 | ⌘L | 开始复习 | ⌘R |
| 原文 / 分栏 / 脑图 | ⌘1 / ⌘2 / ⌘3 | 显示资料库 | ⇧⌘L |
| 摘录 / 仅高亮（工具条打开时） | E / H | 适应窗口 | ⌘0 |
| 后 / 前加兄弟节点 | Enter / ⇧Enter | 加子节点 / 提升一级 | Tab / ⇧Tab |
| 插入父节点 | ⌘Enter | 编辑 | 空格 / F2 |
| 删除节点 | ⌫ | 折叠 / 展开 | ⌘/ |
| 调整顺序 | ⌘↑ / ⌘↓ | 复制 / 剪切 / 粘贴节点 | ⌘C / ⌘X / ⌘V |
| 向助手提问 | ⇧⌘E | 助手面板 | ⌃⌘R |
| 卡片详情 | ⌘I | 展开 / 收起卡片 | ⌥空格 |
| 画笔 | ⇧⌘M | 发送追问 | ⌘↩ |

## 已完成（v0.1 基础设施）

- **设计系统 `mm_design`**：语义色（浅色/深色，含对比度测试）、6 色标注色板、macOS 文本样式、同心圆角、动效时长，以及窗口骨架、悬浮侧栏、工具栏与玻璃胶囊、分段控件、搜索框、表单、可拖动分栏、表单面板（sheet）、HUD 提示、空状态等组件。应用内“帮助 › 组件库（⌥⌘G）”可实时查看。
- **基础能力**：中文/英文多语言（ARB + gen-l10n），外观（跟随系统/浅色/深色）与语言设置并持久化，读取 macOS 强调色、“降低透明度”和“减少动态效果”。
- **应用图标**：默认使用 Foliarc「翻页」图标；macOS / iOS / iPadOS 可在设置 → 通用 → 应用图标中切换「书叶」和「折纸 F」，选择会保留。
- **应用框架**：资料库（筛选、搜索、排序、图标/列表视图、新建学习集、继续学习、首次启动）；学习集工作区（可收起侧栏、侧栏搜索、文档标签页、原文/分栏/脑图三种布局、可拖动分隔线、标注工具栏与浮动控件）；菜单栏与快捷键。

## 开发

需要 Flutter **3.47.2**（仓库根目录的 `.fvmrc` 已固定版本，可以用 [fvm](https://fvm.app)）。macOS 构建需要 Xcode。

```bash
flutter pub get                          # 在仓库根目录执行，解析整个 workspace
cd apps/marginmind && flutter run -d macos
```

常用命令：

```bash
flutter analyze                          # 静态检查（根目录）
dart format --set-exit-if-changed apps packages
(cd packages/mm_core && dart test)
(cd packages/mm_data && dart test)
(cd packages/mm_layout && dart test)
(cd packages/mm_design && flutter test)
(cd packages/mm_platform && flutter test)
(cd apps/marginmind && flutter test)
(cd apps/marginmind && flutter gen-l10n)  # 修改 lib/l10n/*.arb 之后
./tool/icons.sh                          # 重新生成应用图标（需要 Python + Pillow）
```

发布：按 [docs/macos-acceptance.md](docs/macos-acceptance.md) 完成真机验收，然后推送形如 `v0.4.0` 的标签，`Release` 工作流会构建 DMG 并创建草稿 Release（版本号取自 `apps/marginmind/pubspec.yaml`）。

更多见 [CONTRIBUTING.md](CONTRIBUTING.md)。

Windows/Linux、移动端和 Web 的当前支持边界与开发任务见 [跨平台支持评估与开发方案](docs/platform-support-plan.md)。除 macOS 外的平台尚未完成完整应用验收。

## 路线图

完整的项目背景、已完成工作和后续计划见 [docs/project-plan.md](docs/project-plan.md)。

二期需求与 agent 接手说明见 [内容增强与阅读研究](docs/phase-2-requirements.md)，涵盖卡片全文、外部图片、OCR、批注、导出和 Research 工作台。

- [x] 设计稿与 UI 规范（`design/`）
- [x] 设计系统、应用框架、多语言、外观设置、应用图标
- [x] 学习集文件包（`.mmset`，JSON + PDF 副本）
- [x] PDF 渲染与文本层、划线 → 摘录 → 卡片、原文 ↔ 卡片双向定位
- [x] 脑图布局与画布、大纲视图
- [x] 撤销/重做、拖拽调整脑图结构、折叠
- [x] 间隔重复复习、导出（Markdown / OPML）、集合内搜索
- [x] 拖入 PDF 导入、学习集与文档管理、DMG 发布流程
- [x] 跨页选择、框选（图片/公式）摘录
- [x] 卡片间关联、多张脑图、标签
- [x] FSRS 排期、复习统计、按标签 / 分支复习、暂停卡片
- [x] 二期首批：卡片全文、外部图片、扫描 PDF 识别、圈画、导出 PNG / PDF、卡片宽度与笔记格式、阅读研究
- [ ] 页面文字批注、笔迹套索、自由白板
- [ ] 数据量变大后迁移到 SQLite（drift），同一套端口
- [ ] 多窗口、iCloud 同步、Developer ID 签名与公证

## 许可证

[MIT](LICENSE)
