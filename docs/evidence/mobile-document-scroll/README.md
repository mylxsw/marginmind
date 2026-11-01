# 移动端 PDF 滑动优化

## 原因与改动

原先仅 `phone && compact` 使用自定义惯性；手机横屏、iPad 横竖屏及分屏都回到 pdfrx 默认路径，相同手势松手后很快停止。现在所有移动平台均启用自定义惯性，不再由窗口宽度决定是否启用；窄屏手机保留原有双击缩放，其他布局只调整滑动。

原手机释放速度倍率从 1.6 调整为 2.0，保留每毫秒 0.998 的衰减，远离边界时理论惯性行程增加 25%。手指拖动仍为 1:1；缩放和滚轮独立处理。首尾回弹继续限制传入速度，避免高速滑动把页面弹得过远。

## 测量

使用真实 MMPdfView / pdfrx 手势路径，PDF 解码与绘制使用确定性测试后端：60 页，每页 600×800，从第 30 页开始。上下各拖动 180 逻辑像素，释放速度分别为 300、1500、5000 px/s，采样松手后的 8 秒。手机横竖屏、iPad 横竖屏和窄分屏均覆盖；iPad 横屏另以 8,333µs 虚拟帧间隔验证，其他场景为 16,667µs。

以下均为松手后的屏幕逻辑像素行程，取向上阅读的一组；双向原始测量摘要见 [measurements.json](measurements.json)。

| 释放速度 px/s | 原默认路径（横屏手机 / iPad） | 原竖屏手机 | 优化后所有移动布局 |
| --- | ---: | ---: | ---: |
| 300 | 26.75 | 229.68 | 289.39 |
| 1500 | 133.76 | 1188.64 | 1488.45 |
| 5000 | 445.61 | 3985.81 | 4984.92 |

测试还验证了拖动跟手、再次触摸中断惯性、捏合缩放稳定、放大后的横向边界、页面首尾归位，以及滚轮距离不被放大。应用层测试覆盖手机、平板、桌面在横竖屏和窄窗口下的配置，桌面仍使用原默认路径。

复现（仓库根目录）：

```sh
MM_SCROLL_EVIDENCE=/tmp/mobile-scroll.json flutter test --no-pub packages/mm_pdf/test/phone_pdf_scroll_test.dart
flutter test --no-pub packages/mm_pdf/test
cd apps/marginmind
flutter test --no-pub test/phone_navigation_redesign_test.dart --plain-name 'PDF inertia'
```

这些测量验证滑行距离和手势行为，不是渲染帧率基准；尚未用物理手机或 iPad 验收手感。本次没有调整 EPUB / Markdown 等重排阅读器的系统滚动配置。

## 验证结果

- `packages/mm_pdf/test`：135 项通过。
- 手机导航、阅读位置保留、触摸工作区、手写标注及文档对照：30 项通过。
- 修改涉及的 PDF 包、阅读器文件及应用配置测试静态检查通过。
- `flutter build ios --simulator --debug --no-pub` 构建通过；未向物理设备安装。
