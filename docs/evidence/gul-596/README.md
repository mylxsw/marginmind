# GUL-596 生词本验收记录

实现桌面 340pt 列表与详情、compact 推入式详情、工作区/资料库入口及按 entryId 打开的路由；包含筛选搜索分组、真实本文命中次数、详情持久化编辑、系统朗读、释义重新生成、HUD 撤销及 PDF/流式来源定位和临时闪烁。

## 截图

`vocabulary-light.png` / `vocabulary-dark.png` 为桌面；`vocabulary-list-compact-*.png` 与 `vocabulary-detail-compact-*.png` 为 compact 列表与详情。截图使用测试夹具和本机中文字体；另有固定字体 golden 测试覆盖浅深主题。

## Review 修订

统一使用 main 的 `MMSpeech` 原生通道；`supported` 仅在 macOS 返回 true，其他平台隐藏查词卡片和生词详情的朗读按钮。移除了 flutter_tts 和所有 CocoaPods/插件注册/锁文件改动，构建体系与 main 一致。

查词卡片的“详情 ›”现在进入真实生词本详情，并保留返回来源。样式按原型修订：例句 0.5pt 细边和 10pt 圆角卡片；译文 12pt 常规次级文字；来源图标、标题与操作同一行；区块标题为 11pt semibold 次级文字；词形和添加输入均为 20pt，删除按钮在 chip 内；笔记不再重复占位文字。

## 自审与取舍

检查完整导航与持久化链路、来源失效/写入失败/过期撤销/长字段边界、异步取消及控制器/计时器释放、转义匹配及文档一致性。保留首次 PDF 定位、重挂载不重复定位及旧回调校验；闪烁不写入批注。

不足 600pt 的桌面窗口使用 compact，保留规范词形；重新生成只替换释义，不覆盖用户行间释义、笔记和词形。以上取舍已获 Review 同意。iOS 暂不新增原生语音通道，隐藏按钮。

## 验证

- `flutter analyze --no-pub`：无问题。
- `dart format --set-exit-if-changed apps packages`：631 个文件，无格式变更。
- `python3 -m unittest discover -s tool/tests`：26 个通过。
- `apps/marginmind`: `flutter test test/vocabulary_screen_test.dart test/vocabulary_source_test.dart test/selection_lookup_test.dart --update-goldens --no-pub --reporter expanded`：34 个通过；浅深 golden 已更新。
- `packages/mm_platform`: `flutter test --no-pub --coverage --reporter expanded`：55 个通过，包含 macOS 支持判断及语音通道测试。
- `apps/marginmind`: `flutter build macos --debug --no-pub`：成功。
- `apps/marginmind`: `xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=macOS' -enableCodeCoverage YES`：成功，24 个原生测试通过，包含 SpeechChannel 验证。
- `MM_SCREENSHOTS=... flutter test test/vocabulary_screen_test.dart --plain-name screenshot --no-pub --reporter expanded`：2 个通过，六张截图已重新生成并目视检查；原句使用实际 Songti 字体，固定字体 golden 不依赖本机字体。

`python3 tool/coverage.py` 首轮的其他 11 个包均通过，应用发现 5 项与 main 工具栏改版相关的测试失败。修正全局图标查找范围、与当前同排多选/浮动玻璃一致的断言，以及 hover 测试的单一鼠标设备输入；4 文件专项复跑 36 项通过，未更改导图功能代码。应用全量复跑与最终覆盖率见下。

最终应用全量 `flutter test --coverage --no-pub --reporter expanded`：**946 通过、26 跳过**。`python3 tool/coverage.py --report-only`：通过 80% 门槛。

整体覆盖率：**36191 / 39406 = 91.84%**。

整个 PR 的新增可执行 Dart 行覆盖率（对比 main `c0d43d0`，包括本地化生成代码）：**472/484 = 97.52%**。通过 `git diff origin/main --unified=0` 新增行与各包 LCOV 行记录求交集计算。
