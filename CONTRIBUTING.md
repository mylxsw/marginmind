# 参与开发

## 环境

- Flutter 3.47.2（见 `.fvmrc`），Dart 3.13
- macOS 构建：Xcode（macOS 部署目标 12.0）
- 图标脚本：Python 3 + Pillow

仓库是 [Dart pub workspace](https://dart.dev/tools/pub/workspaces)：在根目录执行一次 `flutter pub get` 即可解析所有包。

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
(cd packages/mm_design && flutter test)
(cd packages/mm_platform && flutter test)
(cd apps/marginmind && flutter test)
```

CI（`.github/workflows/ci.yml`）会在 Linux 上执行同样的检查，并在 macOS 上构建应用。
