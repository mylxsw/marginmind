# GUL-502 双向定位验证

2026-10-26，Mac mini、macOS 26.6.2、Flutter 3.47.2，Release 构建。

## 真机结果

使用 `benchmark/reveal.dart` 启动完整工作区、真实 PDFium 和 Metal 渲染。
数据由入口创建于临时目录，未读取或修改用户学习集。命令由脚本调用工作区控制器；
这是实际桌面渲染验证，不是物理点击、快捷键或触控板验收。
独立 bundle ID 在系统沙盒初始化阶段停住，最终使用构建原有应用标识运行；
重签保留 Release.entitlements。

[录屏](reveal.mp4)：先将 PDF 设为 100%，回原文到第 2 页；
随后将脑图缩至 10%，执行定位卡片，恢复到 100% 并居中、闪烁。

控制器实测输出：

```text
REVEAL zoom=1.0
LOCATE scale=1.0
```

- U-B1 修改前：[原审查截图](../../ux-audit/09-reveal-zoomed.jpg)。
- U-B1 修改后：[回原文](reveal.png)，PDF 页面两侧仍可见。居中请求受 PDF 页边界约束，保持缩放优先。
- U-B2 修改前：[原审查截图](../../ux-audit/10-locate-card.jpg)。
- U-B2 修改后：[定位卡片](locate.png)，卡片在脑图视口中心，缩放为 100%。

复现构建：在应用目录执行 `flutter build macos --release -t benchmark/reveal.dart`。
入口约 30 秒自动退出，使用生成的测试摘录；卡片引文是测试占位文字。
正常产品构建使用默认 `lib/main.dart`。

## 自动化结果

- format、analyze：通过。
- 七套 Dart / Flutter 测试：全部通过；汇总行覆盖率 91.88%。
- 新增 PDF 测试：100% / 200% 缩放不变，多个矩形的联合区域居中且完整可见，非法页码安全忽略。
- 脑图测试：10% → 100%，150% 保持；连续定位同一卡片仍居中且完整可见。
- 控制器测试：展开折叠祖先；连续定位递增请求编号。
- Python 工具测试：3 个通过。
- macOS 原生窗口测试：通过。
- 默认产品入口及验证入口的 macOS Release 构建：通过。

物理输入验收项列于 `docs/macos-acceptance.md`，未将自动化结果记作人工通过。
