# 扩展想法：界面与层级修复验证

2026-10-30。截图由 Flutter widget 测试生成，使用内存演示数据，不能代表已安装应用或真实服务验收。

- `options-dark.png` / `options-light.png`：macOS 平台测试中的中性扩展区、并排层级和数量、独立补充要求，以及设置下方的主按钮。
- `two-level-preview.png`：经过实际 `ModelIdeaExpander` 解析与控制器处理的模拟流，首次只返回“主动回忆”，补生成“闭卷自测”，画布显示两层父子关系。保留后核对实际节点父子关系，一次撤销移除整批新增。

验证：

- `packages/mm_assistant` 全套原有及新增测试通过（完整运行后又对最终扩展实现运行 17 项专项测试）。
- 应用扩展、快捷操作和中英文文案共 51 项通过；最终 macOS 深浅色与英文布局另行复核 3 项通过。
- `flutter analyze --no-pub`、变更 Dart 文件格式检查及 `git diff --check` 通过。
- macOS release 构建通过。未替换当前安装应用，未进行真实模型服务调用。

层级回归覆盖：两层自动补全、三层一次完成及逐层补全、只补缺层分支、补生成取消、响应大小共享预算、层级不足保留草稿、全图去重后复核层级、预览保留和一次撤销。界面与行为规格见 `docs/mindmap-ai-expand-ui.md` 和 `docs/mindmap-ai-expand-arch.md`。
