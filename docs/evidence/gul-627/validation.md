# GUL-627：更新与差异审阅验证

基线：`62c179e`（开始实现后同步到的 main）。

更新检测由共享异步 provider 缓存文档指纹，订阅原始阅读进度和 OCR revision；脑图改名等无关修改不重新读取文档。更新范围与改字约束通过 `MapBuildInput.onlyNewContent/titleConstraints` 传给生成器，真实文档和节点 ID 仍不发送给模型。提交沿用 `diffToProposal` 和既有单次撤销事务。

## 验证命令

在 `apps/marginmind`：

```sh
flutter analyze --no-pub
flutter test --no-pub --concurrency=4 --reporter expanded
flutter test --no-pub --coverage --coverage-package='^(marginmind|mm_core|mm_assistant)$' test/map_update_test.dart test/map_generation_ui_test.dart test/map_generation_flow_test.dart --reporter expanded
MM_SCREENSHOTS=/path/to/output MM_FONT='/Library/Fonts/Arial Unicode.ttf' flutter test --no-pub test/map_update_screenshots_test.dart --reporter expanded
```

在 `packages/mm_core`：`dart test`。在 `packages/mm_assistant`：`dart test test/map_generation_test.dart`。

相关测试验证真实指纹及缓存失效、更新表单和凭据惰性检查、模型更新流、删除默认不选、级联取舍、列表与画布互相定位且保持缩放、键盘编辑/选择、普通编辑锁、应用后 ⌘Z 恢复 generation、放弃无写入、受保护摘录不变，以及手机底部审阅布局。

截图测试仅在设置 `MM_SCREENSHOTS` 与 `MM_FONT` 时运行；场景 11、12 的浅/深色截图作为任务评论附件交付，不提交生成的 PNG。

## 基线完整测试

main：1202 通过，36 跳过，10 失败。失败为 `workspace_chrome_test` 4 项、`study_notes_ai_ui_test` 1 项、`note_rich_export_test` 3 项、`liquid_glass_test` 2 项；均为任务列明的既有失败。

## 相关测试

- `mm_core`：319 项通过。
- `mm_assistant` 生成器：13 项通过，包含更新范围和编辑标题约束的模型请求验证。
- 应用生成与更新流程：22 项通过。
- `flutter analyze --no-pub`：无问题。
- 可选截图：2 项通过，生成场景 11/12 的浅色、深色共 4 张截图。

覆盖率按 `git diff --unified=0` 的新增行与 LCOV 可执行行交集计算，包含应用、`mm_core`、`mm_assistant` 的改动；应用测试未覆盖的模型实现行保守计为未覆盖，不将独立的 Dart 测试覆盖合入。

变更可执行行覆盖率为 **448 / 488 = 91.80%**，高于 80% 门槛。
