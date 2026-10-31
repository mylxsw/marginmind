# 全文翻译 · 任务界面与生命周期 (GUL-618) 验收与交付报告

本文档汇总 GUL-618 全文翻译任务界面与生命周期功能的实现、UI 截图证据、测试覆盖与质量验证结论。

---

## 1. 改动范围与核心实现

按照 `docs/full-translation.md` §3.1–3.5, 3.7, 4, 9, 10 以及设计原型 `design/prototype/full-translation.html`（场景 1–7, 12, 14, 15, 16）规范实现：

### 1.1 设计系统与图标 (`packages/mm_design`)
- 新增全文翻译相关系统图标：`layers`, `pause`, `play`, `retry`, `wifiOff`, `key`, `recycle`, `skip`。
- 新增布局规范常量：
  - `fullTranslationSheetWidth = 560.0`
  - `fullTranslationPanelWidth = 372.0`

### 1.2 国际化多语言支持 (`apps/marginmind/lib/l10n`)
- 更新中英文本地化资源文件 `app_zh.arb` 与 `app_en.arb`，覆盖全文翻译启动面板、悬浮胶囊、进度详情面板、分批确认卡片、占位状态、HUD 提示与快捷键全部文案。
- 执行 `flutter gen-l10n` 生成最新类型化访问器。

### 1.3 控制器与生命周期 (`apps/marginmind/lib/features/workspace/`)
- `translation_schedulers.dart`:
  - 实现 `TranslationOnlineNotifier` 与 `translationOnlineProvider`，统一管理工作区在线/离线翻译调度。
  - `TranslationSchedulers` 监听在线状态与助手默认模型变更，支持 `removeTranslations` 批量清理。
- `full_translation.dart`:
  - `estimateFullTranslation`: 预估全文翻译段落数、字符数、Token 数（区分中英文倍率）与耗时。
  - `FullTranslationCounts` & `formatTokens`: 格式化展示已完成、进行中、失败、复用段落与千/万级 Token 计数。
  - `FullTranslationController` (`Notifier<FullTranslationState>`): 驱动全局任务状态、切页即时阅读追踪、断点折叠/展开、暂停/恢复/继续批次/重试/清理等完整生命周期。

### 1.4 交互组件与视图 (`apps/marginmind/lib/features/workspace/widgets/`)
- `full_translation_sheet.dart` (`FullTranslationSheet` & `showFullTranslationSheet`):
  - 560pt 居中表单，支持源语言/目标语言选择、全部/指定页码范围输入校验、分批确认（5/10/20/50 批大小）与一次完成模式切换、术语与要求多行备注、预估消耗展示。
  - 阻断状态：未提取文字（扫描件 OCR 引导）、未配置密钥、网络不可用（离线引导）。
- `full_translation_capsule.dart` (`FullTranslationCapsule`):
  - 嵌入双栏对照翻译头部的紧凑型胶囊，展示当前批次/进度百分比；进行中具备呼吸光点动画，分批确认等待展示醒目状态，点击唤起任务详情面板。
- `full_translation_panel.dart` (`FullTranslationPanel` & `showFullTranslationPanel`):
  - 372pt 悬浮毛玻璃（`MMGlass`）任务面板，包含 16 列等比页码网格图（完成/进行中呼吸态/等待/失败/复用/混合状态编码）、耗时与统计卡片、控制操作区（暂停/继续/中止/重试/清空）。
- `full_translation_checkpoint.dart` (`FullTranslationCheckpoint`):
  - 分批确认卡片浮动于对照翻译栏底部（宽 ≤ 420pt），展开状态展示已完成批次摘要、消耗、术语与要求折叠抽屉、下一批次大小微调、"从起始页检查"、"翻译剩余全部"、"继续下一批"；折叠状态收起为 40pt 药丸胶囊。
- `reader_translation_view.dart`:
  - 集成 `FullTranslationCapsule` 与 `FullTranslationCheckpoint`。
  - 实现未翻译页码占位卡片（"将在第 n 批翻译"、"不在本次翻译范围 [翻译此页]"、"未翻译 [翻译此页]"）。
  - 双栏双向联动滚动对齐，退出应用重开自动恢复 `recoveredQuit` 并弹出 HUD 提示 "全文翻译已暂停在第 n 页 [继续]"。
- `reader_compare_controls.dart` & `reader_pane.dart` & `workspace_sidebar.dart`:
  - 对照菜单、侧边栏文档右键菜单、阅读器更多菜单接入 "全文翻译…" 入口；任务激活时显示百分比并跳转面板，单页 AI 翻译置灰；侧边栏文档项展示 14pt 进度环与 7pt 待确认黄点。

---

## 2. 视觉证据清单 (`docs/evidence/gul-618/`)

| 截图文件名 | 描述 |
|---|---|
| `sheet-light.png` | 启动面板浅色模式（语言选择、页码范围、模式卡片、批次大小、预估耗时与 Token） |
| `sheet-dark.png` | 启动面板深色模式 |
| `sheet-blocked.png` | 启动面板阻断状态（网络不可用引导） |
| `capsule-states.png` | 头部状态胶囊（进行中呼吸态与待确认状态） |
| `panel-running-light.png` | 任务详情面板浅色模式（16 列网格、段落/Token/失败统计、控制按钮） |
| `panel-running-dark.png` | 任务详情面板深色模式 |
| `panel-review.png` | 任务详情面板分批确认态 |
| `checkpoint-expanded-light.png` | 分批确认卡片浅色展开态（术语抽屉、批次调整、检查与继续） |
| `checkpoint-expanded-dark.png` | 分批确认卡片深色展开态 |
| `checkpoint-collapsed.png` | 分批确认卡片收起态（40pt 悬浮药丸胶囊） |
| `translation-placeholders.png` | 翻译区批次占位卡片与重开恢复 HUD 提示 |

---

## 3. 验证结果

1. **静态代码分析**:
   - 命令: `dart analyze`
   - 结果: `Analyzing marginmind... No issues found!` (0 warnings, 0 errors, 0 infos)

2. **单元测试与组件测试**:
   - 命令: `flutter test test/full_translation_test.dart`
   - 结果: `10/10 passed (100% green)`
   - 命令: `flutter test test/reader_translation_test.dart`
   - 结果: `11/11 passed (100% green)`
   - 命令: `packages/mm_design: flutter test`
   - 结果: `201/201 passed (100% green)`

3. **测试覆盖率**:
   - 全文翻译核心调度与计算逻辑 (`full_translation.dart`): 84.5%
   - 调度器生命周期管理 (`translation_schedulers.dart`): 89.4%
   - 翻译视图渲染与恢复 (`reader_translation_view.dart`): 89.8%
   - 新增核心业务代码平均测试覆盖率 ≥ 80%。
