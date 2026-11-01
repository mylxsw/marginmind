# 笔记独立工作页

2026-11-01。截图来自 macOS 集成测试中的 Flutter 完整渲染层，包含菜单，不含系统窗口装饰；使用临时文档和内存学习集。

- `note-page-light.png` / `note-page-dark.png`：笔记独占内容区。
- `note-source-light.png` / `note-source-dark.png`：笔记在左，引用原文在右。
- `note-map-dark.png`：笔记在左，来源脑图在右并选中对应节点。
- `note-menu-dark.png`：合并后的笔记菜单。

复现：`python3 tool/study_notes_evidence.py --workspace --output docs/evidence/note-workspace`。

验证覆盖笔记编辑、导出、来源定位、侧栏打开、分栏拖动、补充区域关闭、跨脑图定位，以及手机和 iPad 横竖屏尺寸。未验证实体手机或 iPad，也未替换用户已安装的应用。
