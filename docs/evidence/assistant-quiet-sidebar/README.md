> 此整体侧栏改版已因超出用户要求而撤回。这里保留的是历史方案，不代表当前实现。解释、引用和输入框等已恢复原来的布局。

# 助手轻量侧栏

第 1 版设计方向的实际 Flutter 实现与对照。完整记录见仓库根目录 `design-qa.md`。

- `selected-design.png`：用户选择的原设计图。
- `comparison-normal-v1.png`：第一轮侧栏对照。
- `comparison-normal-final.png`：修改后的完整侧栏对照。
- `comparison-states-final.png`：未配置、正常、凭据不可用的局部对照。
- `comparison-workspace-final.png`：整体布局对照；测试环境的 PDF 不加载真实文档，只能用于布局检查。
- `implementation-states.png`：三个实际状态的并排预览。
- `quiet-answer-dark-panel.png`、`quiet-answer-narrow-panel.png`：深色和窄窗口检查。

重新生成 Flutter 截图：

```sh
cd apps/marginmind
MM_SCREENSHOTS=/absolute/output/path MM_FONT='/System/Library/Fonts/Hiragino Sans GB.ttc' flutter test test/assistant_screenshots_test.dart --plain-name quiet
```

界面调整已完成，原生验收仍有一次未定位的崩溃；不要把测试通过描述为所有验收均已通过。
