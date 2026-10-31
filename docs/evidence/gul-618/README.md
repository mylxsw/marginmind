# 全文翻译任务界面与生命周期（GUL-618）

实现依据：`docs/full-translation.md` 与 `design/prototype/full-translation.html`。复用现有 PR #147；合并最新 main，保留原分支，不自行合并 PR。

## Review 修复

1. 格式化并修复分析告警。
2. 侧栏和菜单只订阅轻量任务摘要，不创建完整控制器、不提取 PDF 段落；持久化加载与删除并发时不会恢复旧任务。
3. 入口统一按内容语言选择初始目标语言，已有任务沿用持久化语言；标题与内容语言不同时也能找到同一个任务。
4. 从侧栏启动非当前文档时，明确传递文档 ID。
5. 设置面板等待启动就绪后再关闭，提前取得控制器；等待期间固定任务参数，避免路由销毁或语言切换打断启动。
6. 用加载 Future 代替 5ms 轮询；加载失败显示不可用状态并拒绝启动。
7. 完成、有失败的完成、停止和“翻译剩余全部”都有工作区级 HUD。
8. 应用命令使用中英文本地化字符串，不绑定默认快捷键。
9. 设置面板、任务面板、检查点各有浅色/深色 `matchesGoldenFile` 比对；Linux 和 macOS 各保留精确基线。普通测试不写入 `docs/`。
10. 覆盖系统网络事件、云端离线/恢复、手动暂停保留、Ollama 离线运行。
11. 全部改动文件的完整及新增可执行行覆盖率见 [coverage.md](coverage.md) 与 [changed-coverage.json](changed-coverage.json)。

三条建议也已处理：恢复 HUD 使用范围内首个未完成页；段落状态直接读取调度器、按页聚合统计；单页翻译同时检查 fingerprint 和 textKey 缓存。

自审还补齐了自适应阅读工具栏入口和 AI 标题条的空闲胶囊，并修复空白/非数字页码、多行输入 Enter 误触启动、移除译文期间关闭学习集的异步生命周期问题，以及页网格遗漏 PDF 末尾空白页的问题。

## 验证

Flutter 3.47.2 / Dart 3.13.2，Linux。

- `dart format --output=none --set-exit-if-changed apps packages`：818 个文件，0 个改动。
- `flutter analyze --no-pub`：No issues found。
- `python3 -m unittest discover -s tool/tests`：26 个测试通过。
- `flutter test --no-pub --concurrency=2 --coverage test/full_translation_test.dart test/translation_controls_test.dart test/translation_lifecycle_test.dart test/translation_entry_points_test.dart test/translation_page_grid_test.dart`（`apps/marginmind`）：45 个测试通过，包含六张 Linux golden 的正常比对。
- 新增/变更执行行覆盖率 **87.11%**；全仓合并覆盖率 **85.54%**。完整文件表与方法见 [coverage.md](coverage.md)。
- 合并最新 main 前的全量应用：1,246 通过、36 跳过、10 个 main 基线失败；另有设计包 golden 79px 基线差异，均已独立复现。详细结果和复现命令见覆盖率报告。
- 同步 main（95c79cee）后：全文翻译及脑图生成/更新相关应用测试共 67 项通过，模型生成器 13 项通过。
- 最后同步 main（93f78c04）后：应用集成回归 192 项通过、4 项已复现的手机 dock 基线失败，45 项翻译测试全部通过；设计组件 71 项、PDF 全量 127 项通过，分析无问题。覆盖率移除合并前所有变化文件的旧记录，使用最新源码的实测记录重新汇总。

## 截图

截图由 widget 测试的显式证据模式生成，使用虚构段落和模型数据，不访问模型服务。

| 场景 | 浅色 | 深色 |
| --- | --- | --- |
| 设置面板 | [sheet-light.png](sheet-light.png) | [sheet-dark.png](sheet-dark.png) |
| 翻译中与任务面板 | [running-reader-light.png](running-reader-light.png) | [running-reader-dark.png](running-reader-dark.png) |
| 检查点 | [checkpoint-expanded-light.png](checkpoint-expanded-light.png) | [checkpoint-expanded-dark.png](checkpoint-expanded-dark.png) |

另有胶囊状态、离线设置、检查点收起、页占位和单独任务面板截图。

在 `apps/marginmind` 下生成截图：

```sh
TRANSLATION_EVIDENCE_DIR=../../docs/evidence/gul-618 \
TRANSLATION_EVIDENCE_FONT=/path/to/a/CJK/font.otf \
flutter test --no-pub test/full_translation_test.dart --name 'FullTranslation Widgets'
```

不设置这些环境变量时运行 golden 比对，不改动截图。证据模式只用于截图，不能替代 golden 的正常验证。

## 自审

核查了入口到任务启动、暂停/恢复/检查点/停止/移除及重开恢复的完整链路，语言与文档作用域，空值和非法页码，慢加载/失败分支，订阅释放、窗口销毁与在途请求落盘，文案/设计令牌，以及凭证和错误信息的暴露边界。修复项均有回归验证；不新增范围外重构或真实模型请求。
