# GUL-659 验证记录

2026-11-03，基线 `cac2ef0d`，Flutter 3.47.2。Dart/Python 在 Linux 开发主机运行；iOS、Android 构建与原生验证通过 macrun 在已连接的 Mac mini 运行。下列成功命令均返回 0。

## 本次功能

| 检查 | 结果 |
| --- | --- |
| `flutter analyze --no-pub` | 通过 |
| 对本次 13 个 Dart 文件运行 `dart format --output=none --set-exit-if-changed` | 无改动 |
| `flutter test test/share_import_test.dart test/library_test.dart test/browser_test.dart --coverage` | 40 项通过，其中新增分享测试 13 项 |
| `packages/mm_platform` 的 `flutter test --coverage` | 73 项通过，其中新增分享契约测试 5 项 |
| `python3 -m unittest discover -s tool/tests` | 27 项通过，包含编译实际 Swift 收件箱并执行文件复制/发布/清理验证 |
| `flutter build ios --simulator --no-codesign` | 通过，扩展正确嵌入 Runner |
| iOS `xcodebuild test`，Runner scheme，`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-` | 5 项通过，含原有 Keychain 测试及 4 项分享提供器测试 |
| iPhone 17 / iOS 26.5，XCTest Safari 分享流程 | 通过：系统菜单 → 扩展保存 → 冷启动选择新建 → 浏览器；再次分享 → 恢复已有进程 → 最近学习集 |
| iPad Air 11-inch M4 / iOS 26.5，深色模式，同一 XCTest | 通过，新建和已有学习集均可导入 |
| `flutter build apk --debug` | 通过 |
| Android `./gradlew testDebugUnitTest --no-daemon` | 通过，包含本次接收器的 3 项 Robolectric 测试；CI 仅运行 `:app:testDebugUnitTest` |
| Android API 36 / ARM64 模拟器实际运行 | 通过：冷启动 URL 新建、热启动 URL 加入已有集、真实 content URI 的 PDF 与 EPUB 解析入库；保持同一进程和一个学习集，确认后收件箱为空 |
| `git diff --check` | 通过 |

新增 Dart 源文件行覆盖率：`incoming_share.dart` 56/57（98.2%），`share_import_sheet.dart` 166/171（97.1%），`paste_web_url.dart` 11/12（91.7%）；合计 233/240（97.1%）。这是本次三个文件的覆盖率，不代表全仓库覆盖率。

`phone-*.png` / `tablet-*.png` 是带真实字体的 Widget 渲染证据；`native-iphone-existing.png` / `native-ipad-existing.png` 是真实 Simulator 上 XCTest 捕获的目标选择面板，`native-android-epub.png` 是 Android 模拟器接收实际 EPUB 文件时的面板。两类证据分别验证布局和系统交接。测试创建的 iOS 模拟器已关闭并删除；Android 模拟器由测试的 finally 分支停止。

## 全仓库既有失败

未声称全量检查通过。`python3 tool/coverage.py` 在未改动的 mm_assistant 测试失败，未完成全仓库覆盖率汇总。在干净的 `cac2ef0d` worktree 上复现了以下失败：

- mm_assistant：`every skill carries the style contract`、`native search rejects unknown tools and Quick without provider dispatch`、`unknown multimodal rejected even if spec omits capability`。
- app：`document_formats_test.dart` 中 Kindle 大文件及 reflow/crop 用例，`ink_test.dart` 的快捷键用例，`multiple_maps_test.dart` 的侧栏用例。

另有 mm_design 的图标/安全区用例失败；仓库格式检查报告两个未改动文件：`assistant_model_menu.dart`、`capability_review_regression_test.dart`。本次没有修改这些既有问题。额外运行的 mm_layout 44 项、mm_data 52 项、mm_pdf 6 项测试通过。

## 自审与验收边界

已检查入口到工作区的完整路径、错误与空值、重复事件和异步生命周期、临时文件权限、流与 security scope 释放、路径穿越、大小上限、凭据 URL 拒绝、错误信息脱敏、中文/英文及文档一致性。修复了手机面板过矮、空搜索仍保留隐藏目标、Android 多实例写资料库、确认清理失败可能重放，以及 iOS `loadItem` 返回不透明数据导致网址/文本读取失败的问题；最终相关测试全部通过。

iOS 扩展保存后需由用户打开 Foliarc；网页进入内置浏览器后沿用现有转换流程。本次未实现强制拉起或后台自动抓取。真机 App Group/provisioning、文件 App 的“用 Foliarc 打开”、多文件系统 UI 及 iPad 分屏拖放仍需发布前人工验收；模拟器测试不能证明这些设备与提供器组合全部可用。
