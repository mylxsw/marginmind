# GUL-596 生词本验收记录

实现桌面 340pt 列表与详情、compact 推入式详情、工作区/资料库入口及按 entryId 打开的路由；包含筛选搜索分组、真实本文命中次数、详情持久化编辑、系统朗读、释义重新生成、HUD 撤销及 PDF/流式来源定位和临时闪烁。

## 截图

`vocabulary-light.png` / `vocabulary-dark.png` 为桌面；`vocabulary-list-compact-*.png` 与 `vocabulary-detail-compact-*.png` 为 compact 列表与详情。截图使用测试夹具和本机中文字体；另有固定字体 golden 测试覆盖浅深主题。

## 验证

- `python3 tool/coverage.py`：全部 12 个包测试通过，超过 80% 门槛。
- 同步 main `a9f47f9` 后，再运行应用全量 `flutter test --coverage --no-pub --reporter expanded`：916 个通过、24 个按既有条件跳过。
- `packages/mm_design`: `flutter test --coverage --no-pub --reporter expanded`：171 个通过。
- `apps/marginmind`: `flutter test test/vocabulary_screen_test.dart test/vocabulary_source_test.dart --coverage --coverage-path=coverage/vocabulary.info --no-pub --reporter expanded`：16 个通过，涵盖筛选、搜索、分组、持久化、撤销、错误、再生成、跨集/失效来源、PDF/流式闪烁、长字段布局和浅深主题。
- `flutter analyze --no-pub`：无问题。
- `dart format --set-exit-if-changed apps packages`：622 文件，无变更。
- `python3 -m unittest discover -s tool/tests`：26 个通过。
- `apps/marginmind`: `flutter build macos --debug --no-pub`：成功。
- `apps/marginmind`: `xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=macOS' -enableCodeCoverage YES`：成功，23 个原生测试通过。
- `git diff HEAD --check`：通过。

## 自审与取舍

检查了完整导航与持久化链路、空值/已删除来源/写入失败/过期撤销/长字段边界、异步取消及控制器和计时器释放、转义匹配与数据最小化、中英文和文档一致性。已修复首次打开 PDF 丢失定位、重挂载重复定位及旧回调切错文档的问题；撤销和失败 HUD 在详情卸载后仍可显示；窄屏长音标和词形不会溢出。来源闪烁不写入批注。

筛选分两行以容纳英文；不足 600pt 的桌面窗口使用 compact 导航。按数据契约保留规范词形，重新生成只替换释义，不覆盖用户行间释义、笔记和词形。朗读使用系统语音，新增 flutter_tts 及其 iOS/macOS CocoaPods 集成；本次本机验证覆盖 macOS，其他原生平台未构建。

最终合并覆盖率：35568 / 38773 = **91.73%**；新增可执行 Dart 行（包括生成的本地化代码）覆盖率：464 / 479 = **96.87%**。新增行按 `git diff HEAD --unified=0` 与各包 LCOV 行记录求交集计算。
