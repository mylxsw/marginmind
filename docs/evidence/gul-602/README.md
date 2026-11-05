# 导出副本的三端走查

截图来自 `integration_test/document_export_screens_test.dart`，在真实应用里走完每个状态（`tool/capture_document_export.py` 截取真实窗口）。写出的文件也一起检查：PDF 注释由设备上的 PDFium 读回。

| 总览图 | 设备 | 外观 |
| --- | --- | --- |
| [mac-light](mac-light.jpg)、[mac-dark](mac-dark.jpg) | macOS 窗口 | 浅色、深色 |
| [ipad-dark](ipad-dark.jpg) | iPad Air 11 英寸模拟器 | 深色 |
| [iphone-light](iphone-light.jpg)、[iphone-dark](iphone-dark.jpg) | iPhone 17 模拟器 | 浅色、深色 |
| [android-light](android-light.jpg) | Android 模拟器（mm_phone） | 浅色 |

状态依次是：入口菜单、三个选项、更多选项、页码出错、页码正确、导出成功提示、没有标注的文档、EPUB 的选项和更多选项、Markdown 的选项、系统存储或分享面板（只在带 `--real-save` 的那次运行里有）。

iPhone 的「⋯」在正式应用里是原生面板，这个测试默认看到的是共用的 Flutter 面板。原生面板由 `--native-menu` 模式验证：XCTest 点击 `native-actions-export-copy`，导出面板随后打开。

[exported-pdf-in-pdfkit](exported-pdf-in-pdfkit.jpg) 是导出的 PDF 用 PDFKit（macOS“预览”的引擎）渲染的结果，高亮、下划线、批注图标和画笔都与阅读器位置一致。

导出的 EPUB 用 EPUBCheck 5.2.1 校验：0 错误，0 警告。

没有运行：Windows、Linux 桌面应用（PDF 写入代码在 Linux 上用真实 PDFium 跑过单元测试）。Web 版只验证了构建通过和面板逻辑（只提供原文件）。
