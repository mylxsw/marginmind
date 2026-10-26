# GUL-517：外部图片卡片

本机 macOS Debug 构建，中文浅色界面，1280 × 820 窗口。macrun 未连接，改用本机运行和窗口截图。

截图使用独立测试学习集，通过 `FileLibraryStore.importImage` 导入 PNG，再用格式 7 的 `createImage` 保存题面、图片引用和主题归属。删除源 PNG 后重新启动应用，截图仍能显示包内图片。测试入口只替换仓库和初始路由，工作区、详情、预览和复习均使用正式组件；临时入口未纳入产品代码。

- `image-details.png`：题面可编辑，无原文跳转。
- `image-preview.png`：详情中的图片打开可缩放大图。
- `review-front.png`：分支路径和题面，未显示图片。
- `review-back.png`：显示图片，不提供原文跳转。

自动化覆盖粘贴截图 / Finder 路径、选择 / 拖入的入口、格式拒绝、批量导入的一步撤销 / 重做、失败不新增卡片、导入忙碌时防重复、无题面时使用父节点、删除源文件后重新加载。原生 XCTest 使用独立剪贴板测试 PNG、JPEG、Finder URL 和截图 TIFF 转 PNG。
