# GUL-632 验证证据

环境：Flutter 3.47.2 / Dart 3.13.2，Linux arm64。macrun 返回 `connected: false`，本机无 iOS 模拟器，因此截图采用任务允许的 393×852 Flutter golden，字体为 Noto Sans SC。未进行真机系统阅读器手感对比，也不提供设备 FPS 或 GPU 帧耗时结论。

## 阅读滑动

使用真实 MMPdfView / pdfrx 视图，PDF 解码替换为仓库已有的可控测试后端：60 页、每页 600×800，起点第 30 页，适合宽度缩放 0.655。相同 180px 拖动轨迹、双向低/中/高速释放，以 16,667µs 虚拟帧间隔采样 480 帧。释放速度由原始指针事件的 VelocityTracker 记录。以下行程均为屏幕逻辑像素，惯性行程从抬手开始计算。

| 释放速度 px/s | 旧惯性行程 px | 新惯性行程 px | 旧总行程 px | 新总行程 px |
| ---: | ---: | ---: | ---: | ---: |
| 300 | 26.75 | 229.68 | 185.15 | 388.08 |
| 1500 | 133.76 | 1188.64 | 292.16 | 1347.04 |
| 5000 | 445.61 | 3985.81 | 604.01 | 4144.21 |

两方向数据对称。对远离边界的 0.1–1.0s 位移差分拟合，新曲线的对数速度斜率约 −1.997/s，目标为 `1000 × ln(0.998) ≈ −2.002/s`；偏差来自毫秒取整与差分采样。原始轨迹见 `scroll-frames.json`。这些是虚拟时钟下的视图集成测量，不是真机帧性能数据。

参数单测验证释放速度 ×1.6、逐毫秒指数衰减、低速停止、不可滚动轴、已越界恢复，以及双向高速撞边后的回弹幅度小于 30px。视图集成测试验证首尾最终位置距边界小于 1px、捏合后缩放稳定、放大后的横向边界、再次触摸中断惯性和鼠标滚轮行程不变。

自审修复了 pdfrx 对回弹帧重复施加拖动阻力而留下约 23px 空隙的问题：仅直接手势使用阻力，模拟帧不重复过滤；同时收紧边缘停止容差，避免依赖库跳过最后一帧造成可见残差。未 fork 第三方依赖。

## 视觉与行为

浅深色截图各包含资料库、全高抽屉和复习页。标签栏 64pt / 左右 22pt / 底部 max(26pt, safe area)，选中透镜局部不透明并调节强调色亮度以满足 4.5:1；这是为解决彩色封面透出时对比度不足而与原型透明透镜保留的差异。动态字号时标签栏、抽屉操作区与复习评分按钮可增长，抽屉顶部随列表滚动，底部操作固定。

保留已有统计入口；生词本从既有“更多”菜单访问，抽屉保持原型的学习三行。学习笔记数量行可展开已有笔记，避免丢失多笔记导航。标签分组的 + 复用已有“编辑选中卡片标签”命令，没有选中卡片时禁用。手机抽屉左边缘手势仅接收触摸，不抢占笔输入。

`reader_pane.dart` 仅增加三行 scrollProfile 调用方配置；工作区文件仅改抽屉与 sidebar scaffold 接入，阅读控件保持 GUL-631 的归属。资料库卡片和复习文案按本任务范围修改。

已自审完整导航/搜索/新增/设置/关闭路径、空列表与大复习队列、动态字号与安全区、触摸和笔竞争、模态焦点/语义、动画释放、本地化、默认平台路径和敏感信息；修复了空搜索导致卡片计数为 0、当前文档再次点击无法关闭抽屉、导入/生成进度丢失及大字号底部按钮被挤压，以及手机连接鼠标后评分行可能溢出、长“定位原文”按钮未约束宽度的问题。

## 检查记录

最终检查结果与变更覆盖率在 PR 描述和 `changed-coverage.json` 中记录。基线对照使用独立的 main 检出 `62c179ec`。

基线已复现：mm_design 的 `phone_glass_test` 浅色 golden；app 的 liquid_glass 两项、workspace_chrome 四项、study_notes_ai_ui 一项、note_rich_export 三项。本任务修正了标签栏材质与尺寸对应的 liquid_glass 断言。

全仓格式检查在 main 上提示 8 个文件，本分支剩余 7 个，均位于未修改的地图生成/脑图区域；本任务的 workspace_sidebar 已按项目格式整理。未提交这些无关格式变更。

最终本地检查：

| 命令（在对应包目录运行） | 结果 |
| --- | --- |
| `flutter analyze --no-pub`（根目录） | 通过；最后修改的 review/sidebar 文件另用 `dart analyze` 复查通过 |
| `dart format --set-exit-if-changed apps packages`（根目录） | 发现 7 个未修改的基线文件；本次 26 个 Dart 文件格式检查通过 |
| `flutter gen-l10n`（app） | 通过，中英文同步 |
| `flutter test --no-pub --coverage`（mm_pdf） | 127 项通过 |
| `flutter test --coverage`（mm_design，由 coverage.py 调用） | 216 项通过，1 项已复现的基线浅色 golden 失败 |
| `flutter test --no-pub --coverage --coverage-path=coverage/navigation.info test/phone_workspace_sidebar_test.dart test/phone_layout_test.dart test/workspace_sidebar_test.dart test/liquid_glass_test.dart test/review_card_view_test.dart test/library_test.dart test/touch_library_test.dart`（app） | 63 项通过 |
| `flutter test --no-pub --coverage --coverage-path=coverage/evidence.info test/phone_navigation_redesign_test.dart test/review_card_view_test.dart`（app） | 15 项通过，包含大字号/鼠标、旋转、浅深色、平板与桌面对照 |
| `flutter test --no-pub --coverage`（mm_platform） | 61 项通过 |
| `python3 tool/coverage.py`（根目录） | 在上述 mm_design 基线失败处退出；未声称完整工作区通过 |

应用全量扩大运行也命中了已复现的基线失败，随后停止；没有声称完成全部 app 测试。上表为最终完成的受影响回归。CI 由推送触发，不等待 CI。

变更可执行行覆盖率：**90.61%（415/458）**。以最终 app 场景/复习报告及 mm_design/mm_pdf 包报告与 `git diff` 新增可执行行求交，覆盖生成本地化中的实际执行行。运行 `python3 docs/evidence/gul-632/changed_coverage.py` 可重算，明细见 `changed-coverage.json`。
