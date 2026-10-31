# GUL-629 手机端重设计 · iOS 模拟器最终验收证据

本目录包含 **GUL-629 手机端样式优化**（Stage 4 最终验收证据）在 iOS 模拟器上实际运行生成的真机级全场景验收截图。

## 运行环境

- **基线 Commit**: `84157be6800bca94381cb9bb2635d9e4efc862fc`（`origin/main`，GUL-633 合并后）
- **设备类型**: iPhone 16（6.1″ 视网膜屏）
- **逻辑尺寸**: 393 × 852 pt（物理分辨率 1179 × 2556 px，3× Retina）
- **系统版本**: iOS 26.5（`com.apple.CoreSimulator.SimRuntime.iOS-26-5`）
- **开发工具**: Xcode 27.2（Build 27B52），Flutter 3.47.2 / Dart 3.13.2
- **系统字体**: 原生 Apple SF Pro 与 PingFang SC（中文显示完整清晰，无缺失或方框）

## 原型 10 个场景验收截图列表

全部 10 个场景均在原生 iOS 模拟器中实际渲染截取，分别覆盖浅色（Light）与深色（Dark）模式：

| 场景编号与名称 | 浅色（Light） | 深色（Dark） | 场景特性说明 |
| :--- | :---: | :---: | :--- |
| **01 资料库** | [01-library-light.png](01-library-light.png) | [01-library-dark.png](01-library-dark.png) | 悬浮 Liquid Glass 标签栏（资料库选中）、左侧玻璃抽屉按钮、右侧玻璃“+”新建按钮、大标题“资料库”、搜索栏、学习集卡片与继续学习卡片 |
| **02 阅读默认态** | [02-reading-light.png](02-reading-light.png) | [02-reading-dark.png](02-reading-dark.png) | 顶部三组悬浮玻璃控件（学习集/阅读脑图切换/助手更多）、渐隐 scroll edge、底部居中页码胶囊（带环形进度）与右下角工具球 |
| **03 工具栏展开态** | [03-tools-light.png](03-tools-light.png) | [03-tools-dark.png](03-tools-dark.png) | 工具栏沿底部展开、页码让位；选中高亮工具，上方弹出颜色条（黄/绿/蓝/红/橙/紫）及当前色指示点 |
| **04 跳页滑块** | [04-scrub-light.png](04-scrub-light.png) | [04-scrub-dark.png](04-scrub-dark.png) | 点击页码胶囊展开快速跳页滑块，显示当前章节名称、页码进度与拖动条 |
| **05 沉浸态** | [05-immersive-light.png](05-immersive-light.png) | [05-immersive-dark.png](05-immersive-dark.png) | 向下滚动正文时顶部浮动控件自动滑走隐藏，保留页码与工具球，正文延伸至顶部状态栏渐隐下方 |
| **06 “更多”底部面板** | [06-more-light.png](06-more-light.png) | [06-more-dark.png](06-more-dark.png) | 浮动 Liquid Glass 底部面板；第一层 3 个开关磁贴（阅读外观带实时 Aa 色块、页边批注、生词提示仅以底色表达开启），第二层文档操作组，第三层学习操作组 |
| **07 阅读外观二级面板** | [07-appearance-light.png](07-appearance-light.png) | [07-appearance-dark.png](07-appearance-dark.png) | 点击“阅读外观”横向推入二级面板，4 张真实纸样卡片（白底/羊皮纸/护眼绿/深色），背后正文透过极淡半透明遮罩实时可见 |
| **08 学习集抽屉** | [08-drawer-light.png](08-drawer-light.png) | [08-drawer-dark.png](08-drawer-dark.png) | 全高侧边抽屉（宽 328pt），上下无缝；包含返回资料库、学习集标题、文档列表（当前激活高亮）、脑图、学习（卡片与待复习高亮数）、标签，底部固定设置与完成 |
| **09 脑图页** | [09-map-light.png](09-map-light.png) | [09-map-dark.png](09-map-dark.png) | 沿用同一套顶部控件，“阅读 \| 脑图”透镜切换至右侧；底部为脑图玻璃胶囊工具栏，画布节点清晰呈现 |
| **10 复习页** | [10-review-light.png](10-review-light.png) | [10-review-dark.png](10-review-dark.png) | 复习会话页面，顶部返回与分段进度条；卡片翻面展示问题与摘录答案；底部 58pt 高单手评分按钮（重来/困难/良好/简单）及 Liquid Glass 标签栏 |

## 走查与修复记录

1. **资料库大标题规范修复**：
   - 原 `library_screen.dart` 在手机紧凑屏（`isPhoneCompact`）下，顶部大标题读取 `_filterTitle(AllFilter)` 输出了“全部学习集”；与设计原型场景 1 及 GUL-633 设计说明“大标题‘资料库’（`l.librarySection`）”不一致。
   - 本次在 `library_screen.dart` 中进行了轻量修复：当处于手机紧凑屏且查看全部时，大标题使用 `l.librarySection`（“资料库”）；非紧凑屏及桌面端保持 `l.libraryTitleAll` 不受影响。
2. **过期截图替换**：
   - 之前 `docs/evidence/gul-633/` 下的截图因缺乏真实系统字体环境，中文渲染为方框字符，且资料库大标题未采用最终修复。已用本次 iOS 模拟器真机级截图进行全量覆盖替换。
3. **可复现自动化工具交付**：
   - 提供 `marginmind/tool/capture_phone_acceptance.py` 自动化截屏控制脚本。
   - 提供 `marginmind/apps/marginmind/integration_test/phone_gul629_acceptance_test.dart` 端到端全场景驱动测试。
