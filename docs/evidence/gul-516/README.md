# GUL-516 右侧面板与 C01 真机验证（2026-10-27）

Mac mini（macOS 26.6.2），分支 `gul-516-right-panel-c01` 的非沙盒 Release 包，示例学习集；通过 macrun + Cua Driver 操作。

| 截图 | 内容 |
| --- | --- |
| `cut-card.jpg` | 长摘录被截断，底部显示“展开全文” |
| `expanded-card.jpg` | ⌥空格 展开：原地变长，显示“收起”，相邻节点让位 |
| `details-wide-light.jpg` / `details-wide-dark.jpg` | 宽窗口（1280）：“显示详情”打开 400 宽面板，完整原文、回到原文、拷贝、标签、复习状态 |
| `details-narrow-dark.jpg` | 窄窗口（1000）：资料库侧栏自动收起，面板 360 |
| `details-closed-dark.jpg` | 关闭面板：脑图位置与缩放不变，节点仍选中 |

记录：

- 自动化注入的组合键不带修饰键状态（与 GUL-510 相同）：⌘I 会被当作输入字符。⌘I 改用菜单“脑图 › 显示详情”验证；⌥空格 在 macOS 上以“不换行空格”字符到达，已修复为展开而不是进入编辑，并补了测试。
- 一次切换外观后移动指针时，Flutter 引擎无障碍代码崩溃（`FlutterTextPlatformNode::GetFrame`，`EXC_BAD_ACCESS`）。按相同步骤（展开、详情开关、窗口缩放、外观切换、原地编辑后 Esc）复现三次未再出现，暂记为待观察。
- 验证时在示例学习集里新增的摘录卡片已移除；对应的原文高亮仍在第 2 页（自动化点击打不开高亮工具条）。
