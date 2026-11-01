# 笔记章节目录

这组图片由真实 Flutter 页面使用内存中的 17 节中文笔记渲染，加载系统字体；不读取或修改用户笔记。

- `desktop-dark.png`、`desktop-light.png`：1600 × 1000，目录与正文分开布局，序号独立成列，长标题最多两行。
- `chapter-selected.png`：1400 × 650，点击第 11 节后的正文位置与目录高亮。
- `short-window.png`：1280 × 520，目录独立滚动，正文停留在第一节。

复现截图（在 `apps/marginmind` 运行）：

```sh
MM_NOTE_CONTENTS_SCREENSHOTS="$PWD/../../docs/evidence/note-contents" \
  flutter test test/note_contents_test.dart --no-pub
```

验证：目录测试 6 项，连同笔记编辑、更新和工作区回归共 37 项通过。覆盖深浅色、长目录、章节跳转、正文滚动同步、返回顶部、目录独立滚动、窄窗口菜单、两倍字号及键盘回车操作。

截图属于测试页面渲染，不代表已安装应用已更新。
