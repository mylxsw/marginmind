# 手机导航令牌 · GUL-632

依据：`foliarc-mobile-redesign.html` 场景 1、8、10；实现令牌位于 mm_design 的 `tokens/phone_navigation.dart`，组件位于 `widgets/phone_navigation.dart` 与 `widgets/tab_bar.dart`。

| 元素 | 规格 |
| --- | --- |
| 标签栏 | regular Liquid Glass；64 高、左右 22、底部 max(26, safe bottom)、圆角 32 |
| 透镜 | 内缩 4；420ms cubic(.3, 1.35, .45, 1)；局部不透明底，保持强调色文本对比度 ≥4.5:1 |
| 抽屉 | 左侧全高；宽 min(328, 可用宽度−32)；380ms cubic(.25, 1, .35, 1) |
| 抽屉背景 | 浅 #F2F2F7 / 深 #0E0E10 |
| 分组与行 | 圆角 14；行高至少 46；15.5 字号；学习数量 caution；不加副标题 |
| 复习 | 4 高的分段进度；评分按钮高 58 |

透镜浅色底 #F8FAFF / 深色底 #343438，选中强调色保持色相并按实际背景调节亮度。其余区域继续透出封面。所有变化仅在 phone + compact 生效。
