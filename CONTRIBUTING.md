# 参与开发

## 环境

- Flutter 3.47.2（见 `.fvmrc`），Dart 3.13
- macOS 构建：Xcode（macOS 部署目标 12.0）
- 图标脚本：Python 3 + Pillow

仓库是 [Dart pub workspace](https://dart.dev/tools/pub/workspaces)：在根目录执行一次 `flutter pub get` 即可解析所有包。

项目背景、当前进度和开发计划：[docs/project-plan.md](docs/project-plan.md)。

## 约定

- **分层与依赖**：见 [docs/architecture.md](docs/architecture.md)。`mm_core` 不能引入 Flutter；功能代码不能直接使用第三方 UI 或平台插件，只能通过 `mm_design` / `mm_platform`。
- **样式只来自令牌**：颜色、字号、圆角、间距、动效一律使用 `mm_design` 的令牌（`context.mmColors`、`context.mmText`、`MMSpacing`、`MMRadii`、`MMMotion`），不要在功能代码里写死数值。新增令牌时同步更新 `design/` 的规范稿和 [docs/design-system.md](docs/design-system.md)。
- **文案只来自 ARB**：界面文字放进 `apps/marginmind/lib/l10n/app_en.arb` 和 `app_zh.arb`，然后运行 `flutter gen-l10n`。
- **命令先进菜单**：新的用户命令先在 `lib/app/app_commands.dart` 里定义（菜单栏 + 快捷键），工具栏按钮只是快捷入口。快捷键用 `primaryShortcut()` 定义，自动在 Windows/Linux 上换成 Ctrl。
- **格式**：`dart format`，行宽 120（已写在各包 `analysis_options.yaml`）。

## 提交前

```bash
flutter analyze
dart format --set-exit-if-changed apps packages
(cd packages/mm_core && dart test)
(cd packages/mm_data && dart test)
(cd packages/mm_layout && dart test)
(cd packages/mm_design && flutter test)
(cd packages/mm_platform && flutter test)
(cd packages/mm_pdf && flutter test)
(cd apps/marginmind && flutter test)
# macOS：原生窗口命中、工具栏和全屏切换
(cd apps/marginmind && xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=macOS' -enableCodeCoverage YES)
```

CI（`.github/workflows/ci.yml`）会在 Linux 上执行同样的检查，并在 macOS 上构建应用、运行原生窗口测试。

## 覆盖率

在仓库根目录运行：

```bash
python3 -m unittest discover -s tool/tests
python3 tool/coverage.py
# 已有各包报告时，只重新汇总：
python3 tool/coverage.py --report-only
```

脚本对七个测试套件逐包启用 `--coverage`；纯 Dart 包再用
`coverage:format_coverage` 转为 LCOV。报告按仓库相对路径与行号合并，
同一源码被多个套件执行时只计一次。包含报告中的项目 `lib/` 源码（含生成代码），
不计 SDK、第三方依赖或测试代码。`mm_pdf` 使用可控的测试后端验证真实 PDF 视图与选区回调，
无需原生 PDFium。报告未包含的文件不在该行覆盖率口径内。

输出为 `coverage/lcov.info` 和 `coverage/summary.md`，CI 同时上传附件并写入
Job Summary。汇总行覆盖率低于 **80%**、缺少报告、空报告或测试失败都会失败。
