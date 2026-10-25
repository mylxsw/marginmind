<p align="center">
  <img src="apps/marginmind/assets/icon/app_icon_macos.png" width="128" alt="MarginMind icon">
</p>

<h1 align="center">MarginMind</h1>

<p align="center">读 → 摘 → 图：在原文、卡片和脑图之间来回穿梭的学习工具。<br>
<em>Read, excerpt and map what you learn — an open-source study tool for macOS, built with Flutter.</em></p>

---

MarginMind 把 PDF 阅读、标注摘录和思维导图放进同一个工作区：在原文里划线，摘录就变成脑图上的卡片；点卡片，一步回到原文的出处。一个“学习集”可以包含多份文档，共同构建一张（或多张）脑图。

> **状态：v0.3 MVP。** 读 → 摘 → 图 → 复习的完整闭环已经可用：导入 PDF、划线摘录、在脑图里整理、从卡片回到原文、间隔重复复习、导出脑图，数据保存在本机。仍处于早期阶段，欢迎试用和反馈。

## 安装

1. 在 [Releases](https://github.com/mylxsw/marginmind/releases) 下载最新的 `MarginMind-x.y.z.dmg`，把 MarginMind 拖进“应用程序”。
2. 目前还没有 Apple 开发者签名，第一次打开时 macOS 会拦截：在 Finder 里**右键 MarginMind → 打开**；如果仍被拦截，到“系统设置 › 隐私与安全性”里点“仍要打开”。也可以在终端执行 `xattr -dr com.apple.quarantine /Applications/MarginMind.app`。

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

## 可以做什么（v0.3）

1. **资料库**：新建学习集、一键打开示例学习集；把 PDF 从 Finder 拖进窗口直接新建学习集；右键可打开、复习、重命名、收藏、删除（⌘⌫）。
2. **导入 PDF**（⌘O、侧栏 +，或直接拖进学习集窗口）：文件被复制进学习集包，原文件移动或删除都不受影响。侧栏里右键文档可以重命名或移除。
3. **划线即摘录**：高亮工具下拖选文字，松开鼠标就生成高亮，同时在脑图上生成卡片（挂在当前选中的主题下）。关闭“摘录同步到脑图”则只高亮；选择工具下选中文字会弹出操作条（摘录 / 高亮 / 拷贝 / 换色）。
4. **原文 ↔ 卡片**：点原文中的高亮，脑图里对应卡片闪烁；点卡片右上角箭头（或 ⌘L），切到对应文档、跳页并闪烁原句。
5. **整理脑图**：拖动节点改变层级和顺序（拖到节点中部成为子节点，拖到上下边缘插在前后）；折叠/展开分支；右键菜单；方向键在节点间移动，Tab 添加子主题，双击 / 回车 / F2 / 空格或直接打字原地编辑主题、摘录标题和笔记（笔记用 ⇧Enter 换行），⌘↑/⌘↓ 调整顺序，Delete 移除；大纲视图支持同样的原地编辑和快捷键。
6. **撤销 / 重做**（⌘Z / ⇧⌘Z）：脑图、摘录、高亮、文档的每一步编辑都能撤销。
7. **复习**（⌘R 或侧栏“复习”）：脑图里的摘录和笔记自动成为复习卡片，按简化 SM-2 间隔重复排期。先回想、再翻面（空格），用 1–4 评分（重来 / 困难 / 良好 / 简单）；把摘录重命名成一个问题，它就成为题面。资料库显示每个学习集待复习的数量。
8. **搜索**（⌘F）：侧栏搜索同时匹配文档和卡片内容，点结果直接定位。
9. **导出**：文件 › 将脑图导出为 Markdown / OPML（可导入 MarginNote、XMind、幕布等）。
10. **一切自动保存**：退出再打开，学习集、高亮、脑图、复习进度、每份文档读到的页码都在。

### 快捷键

| 操作 | 快捷键 | 操作 | 快捷键 |
| --- | --- | --- | --- |
| 新建学习集 | ⌘N | 导入 PDF | ⌘O |
| 撤销 / 重做 | ⌘Z / ⇧⌘Z | 搜索 | ⌘F |
| 添加主题 / 子主题 | ⇧⌘N / Tab | 添加笔记 | ⌥⌘N |
| 定位原文 | ⌘L | 开始复习 | ⌘R |
| 原文 / 分栏 / 脑图 | ⌘1 / ⌘2 / ⌘3 | 显示资料库 | ⇧⌘L |

## 已完成（v0.1 基础设施）

- **设计系统 `mm_design`**：语义色（浅色/深色，含对比度测试）、6 色标注色板、macOS 文本样式、同心圆角、动效时长，以及窗口骨架、悬浮侧栏、工具栏与玻璃胶囊、分段控件、搜索框、表单、可拖动分栏、表单面板（sheet）、HUD 提示、空状态等组件。应用内“帮助 › 组件库（⌥⌘G）”可实时查看。
- **基础能力**：中文/英文多语言（ARB + gen-l10n），外观（跟随系统/浅色/深色）与语言设置并持久化，读取 macOS 强调色、“降低透明度”和“减少动态效果”。
- **应用图标**：脚本生成的图标母版和 macOS / Windows 全套尺寸。
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

发布：推送形如 `v0.3.0` 的标签后，`Release` 工作流会构建 DMG 并创建草稿 Release（版本号取自 `apps/marginmind/pubspec.yaml`）。

更多见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 路线图

完整的项目背景、已完成工作和后续计划见 [docs/project-plan.md](docs/project-plan.md)。

- [x] 设计稿与 UI 规范（`design/`）
- [x] 设计系统、应用框架、多语言、外观设置、应用图标
- [x] 学习集文件包（`.mmset`，JSON + PDF 副本）
- [x] PDF 渲染与文本层、划线 → 摘录 → 卡片、原文 ↔ 卡片双向定位
- [x] 脑图布局与画布、大纲视图
- [x] 撤销/重做、拖拽调整脑图结构、折叠
- [x] 间隔重复复习、导出（Markdown / OPML）、集合内搜索
- [x] 拖入 PDF 导入、学习集与文档管理、DMG 发布流程
- [ ] 跨页选择、框选（图片/公式）摘录、手写批注
- [ ] 卡片间关联、多张脑图、标签
- [ ] FSRS 排期、复习统计
- [ ] 数据量变大后迁移到 SQLite（drift），同一套端口
- [ ] 多窗口、iCloud 同步、Developer ID 签名与公证

## 许可证

[MIT](LICENSE)
