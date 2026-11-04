# 手机端滚动页码同步

## 原因和修复

可重排阅读器滚动时，`ReflowSession.observe` 更新原文阅读位置，但不更新分页模式使用的 `page`。手机底部控件直接显示这个旧值，所以正文滚动时数字不变，只有显式跳转会改变。

现在手机连续滚动模式根据当前原文位置和可见章节的排版计算页码，并从同一份排版读取总页数。分页模式和固定版式文档保留原有计算方式。没有修改 PDF 渲染或滚动逻辑。

模拟器末尾检查还复现了短尾页问题：已经到达文档底部，屏幕上沿的文字却仍在第 12 页，导致显示 `12 / 13`。现在文档末尾明确显示最后一页，进度环也同步到 100%。

新增回归测试在修复前复现：正文已经进入第 2 页，底部仍显示第 1 页。修复后验证手指滚动、反向滚动、滑动条跳转后继续滚动、滚动到末尾，以及两个不同长度章节之间往返时的页码和总页数。另有 67 页 PDF 从第 37 页继续滚动的检查。

## 验证

相关 Widget 测试共 31 项通过。修改文件静态分析与格式检查通过。

```sh
cd apps/marginmind
flutter test --no-pub test/phone_reflow_page_sync_test.dart test/phone_pdf_page_sync_test.dart test/phone_reader_controls_test.dart test/reflow_reader_test.dart test/reflow_navigation_outline_test.dart
```

iPhone 模拟器集成测试 1 项通过，使用真实应用入口，在专用测试模拟器中导入生成的本地 Markdown 文档。截图依次为 [滚动前](iphone/01-before-scroll.png)、[手指滚动后](iphone/02-after-scroll.png)、[滑动条跳转后继续滚动](iphone/03-scroll-after-slider.png) 和 [文档末尾](iphone/04-document-bottom.png)。运行结果和源码摘要保存在 [iphone/](iphone/)。未向物理手机安装或发布。

```sh
python3 tool/capture_mobile_redesign.py F7498667-CBDD-44E8-984B-173FF027868F iphone \
  --test phone_reflow_page_sync_test.dart \
  --output docs/evidence/phone-page-sync-2026-11-04/iphone
```
