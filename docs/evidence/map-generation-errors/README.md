# 导图失败提示展示优化

原始问题来自用户提供的截图 `01-before.png`：原因、章节位置和技术参数使用同一段文本，缺少层次；弹窗留白较大，复制后没有明确反馈。

本次调整沿用应用的颜色、字体、按钮及弹窗/底部面板组件。下面的更新后截图来自实际 Flutter 组件的测试渲染，使用模拟错误和系统字体，没有调用模型或操作真实文档。

| 步骤 | 检查结果 | 截图 |
| --- | --- | --- |
| 1. 查看失败原因 | 通过：原因优先，章节位置、阶段和模型分层展示；诊断默认收起。 | `02-dark-summary.png`、`02-light-summary.png` |
| 2. 展开诊断 | 通过：参数按名称和值排列，中文原因可读；长内容可滚动。 | `03-dark-diagnostics.png`、`03-light-diagnostics.png` |
| 3. 复制完整报告 | 通过：无需展开即可复制完整诊断，按钮显示“已拷贝”；报告不包含原始模型响应。 | `05-phone-copied.png` |
| 4. 窄屏与大字体 | 通过：手机使用底部面板，窄窗口与多处失败可滚动，操作区固定；大字体按钮纵向排列。 | `04-phone-summary.png`、`04-phone.png`、`04-narrow-window.png`、`04-large-text.png`、`04-short-window.png` |

交互验证覆盖诊断折叠/展开、复制内容及反馈、关闭、Esc、返回后重试、多处失败滚动，以及中英文布局。颜色使用现有语义色，错误同时通过文字和图标表达；折叠按钮带展开状态，复制反馈带辅助阅读通知。未通过截图推断完整无障碍合规，也未把测试渲染当作真机或安装版验收。

复现截图：在 `apps/marginmind` 下运行：

```sh
MM_FAILURE_SCREENSHOTS="$PWD/../../docs/evidence/map-generation-errors" flutter test --no-pub test/map_generation_failure_layout_test.dart
```

截图模式需要本机 macOS 系统字体；不设置该环境变量时，测试不依赖这些字体路径。
