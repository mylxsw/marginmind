<p align="center">
  <img src="apps/marginmind/assets/icon/app_icon_macos.png" width="128" alt="MarginMind icon">
</p>

<h1 align="center">MarginMind</h1>

<p align="center">读 → 摘 → 图：在原文、卡片和脑图之间来回穿梭的学习工具。<br>
<em>Read, excerpt and map what you learn — an open-source study tool for macOS, built with Flutter.</em></p>

---

MarginMind 把 PDF 阅读、标注摘录和思维导图放进同一个工作区：在原文里划线，摘录就变成脑图上的卡片；点卡片，一步回到原文的出处。一个“学习集”可以包含多份文档，共同构建一张（或多张）脑图。

> **状态：早期开发（v0.2，可用 Demo）。** 已经可以导入 PDF、划线摘录、在脑图里整理、从卡片回到原文，数据保存在本机。撤销、复习、导出等还在路上，见下方路线图。

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

## 可以做什么（v0.2）

1. **资料库**：新建学习集（可在创建时直接选择 PDF），或一键打开示例学习集。
2. **导入 PDF**（⌘O 或侧栏 +）：文件被复制进学习集包，原文件移动或删除都不受影响。
3. **划线即摘录**：高亮工具下拖选文字，松开鼠标就生成高亮，同时在脑图上生成卡片（挂在当前选中的主题下）。关闭“摘录同步到脑图”则只高亮；选择工具下选中文字会弹出操作条（摘录 / 高亮 / 拷贝 / 换色）。
4. **原文 ↔ 卡片**：点原文中的高亮，脑图里对应卡片闪烁；点卡片右上角箭头（或 ⌘L），切到对应文档、跳页并闪烁原句。
5. **整理脑图**：添加主题（⇧⌘N）、添加笔记（⌥⌘N）、双击或回车重命名、Delete 移除（原文高亮保留）；平移缩放；大纲视图。
6. **一切自动保存**：退出再打开，学习集、高亮、脑图、每份文档读到的页码都在；资料库的“继续学习”显示真实进度。

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
(cd packages/mm_design && flutter test)
(cd packages/mm_platform && flutter test)
(cd apps/marginmind && flutter test)
(cd apps/marginmind && flutter gen-l10n)  # 修改 lib/l10n/*.arb 之后
./tool/icons.sh                          # 重新生成应用图标（需要 Python + Pillow）
```

更多见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 路线图

- [x] 设计稿与 UI 规范（`design/`）
- [x] 设计系统、应用框架、多语言、外观设置、应用图标
- [x] 学习集文件包（`.mmset`，JSON + PDF 副本）
- [x] PDF 渲染与文本层、划线 → 摘录 → 卡片、原文 ↔ 卡片双向定位
- [x] 脑图布局与画布、大纲视图
- [ ] 撤销/重做（编辑操作已是纯函数，接入命令历史即可）
- [ ] 拖拽调整脑图结构、折叠、卡片间关联
- [ ] 复习（FSRS）、导出（Markdown / OPML）
- [ ] 数据量变大后迁移到 SQLite（drift），同一套端口
- [ ] 拖入 PDF 导入、多窗口

## 许可证

[MIT](LICENSE)
