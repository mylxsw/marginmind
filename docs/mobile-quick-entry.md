# 手机与 iPad 快速录入（GUL-659）

系统分享的网页链接、PDF、EPUB、MOBI/AZW/AZW3、Markdown，统一进入“导入到 Foliarc”面板。用户选择已有学习集或新建学习集；已有列表按最近打开排序，当前/最近使用的学习集置顶，并支持搜索。新建名称默认取文件名、分享标题或域名。

面板复用 mm_design 的 Sheet、分段控件、搜索框、按钮和设计令牌。手机按内容高度展示，保证目标列表首次打开即可见；iPad 使用居中面板。文件复用 DocumentImporter，保留已有的解析、部分成功提示和全失败回滚。网页进入目标学习集的内置浏览器，再沿用现有“转换”流程保存为阅读文档、PDF 或 Markdown；本次没有加入后台自动抓取。

应用内网页表单提供“粘贴链接”。只在用户点击后读取剪贴板；iPhone 的 UIKit URL 表单使用系统 UIPasteControl。带标题的分享文本可提取首个有效 HTTP(S) 链接，不主动读取应用启动/恢复时的剪贴板。

## 各平台入口

- Android：ACTION_SEND、ACTION_SEND_MULTIPLE、ACTION_VIEW；同时支持 EXTRA_STREAM 与仅提供 ClipData 的文件管理器。singleTask 将连续分享交给现有 Flutter 实例，避免启动多个资料库写入者。VIEW 文档接收 content://，不把外部 file:// 输入当作应用私有文件读取入口。无需新增存储权限。
- iOS/iPadOS：独立 ShareExtension 接收 Safari 等应用的链接和文档；文档类型关联支持“用 Foliarc 打开”。SceneDelegate 同时处理冷启动和运行中的文件打开。
- iPad：Flutter 根视图上的 UIDropInteraction 接收其他应用拖入的网址、PDF/EPUB 和文件 URL，仍由用户选择导入目标。应用内拖动和普通文本编辑不被这个入口接管。

### iOS 扩展的交接方式

Share Extension 保存成功后显示“已保存，请打开 Foliarc，选择加入已有学习集或创建新学习集”。用户返回主应用后继续选择目标。iPad 上主应用已在前台时，通过 Darwin 通知提醒它重新读取收件箱。

先前分析中“扩展可通过 custom scheme 立即拉起主应用”的假设已修正。Apple 的公开扩展接口不保证 Share Extension 可以启动宿主应用；本实现不使用 responder-chain、私有 API 或强制跳转技巧。[Apple 扩展生命周期说明](https://developer-mdn.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html)

Runner 与 ShareExtension 均需启用 App Group：`group.io.github.mylxsw.marginmind`。设备签名时，两者使用相同开发团队，并为两个 App ID 配置该能力和匹配的 provisioning profile。扩展不包含 Flutter 引擎，也不直接写资料库。

## 队列与安全边界

原生层先流式复制，再原子发布 manifest。每个批次独立目录，保存原始显示名称与应用生成的内部文件名；Dart 只接收已经落盘的路径，不接收临时 URI 授权。iOS 的 provider 临时 URL 在其回调返回前复制完成，并正确释放 security scope；直接文件打开使用 NSFileCoordinator。

`marginmind/incoming_share` 契约：

| 方法/通知 | 行为 |
| --- | --- |
| pending | 返回所有已发布、未确认的批次；读取不删除 |
| changed | 提醒 Dart 重新读取，不作为唯一事件副本 |
| failed | Android 无法落盘时报告错误，不悄悄丢弃输入 |
| complete(id) | 导入结束或用户取消后确认；先落确认标记，再清理文件 |

主应用在首帧和恢复前台时读取队列，逐个展示目标面板。相同批次的重复通知不会重复弹窗。解析完成前保留输入；用户取消、解析失败或部分成功后才清理。清理失败的已确认目录不会在重启后再次提示导入；超过 24 小时的残留在启动/分享时清理。损坏的单个 manifest 不阻塞其余批次。

- 只接受 HTTP(S)，拒绝带账户密码或其他协议的链接。
- 文件扩展名与现有 DocumentFormat 保持一致；显示名与内部路径分离，不允许路径穿越。
- 单批最多 20 个文件，总大小 512 MiB；PDF 256 MiB、MOBI/AZW/AZW3 500 MiB、EPUB/Markdown 64 MiB。
- 原生复制与读取在后台执行；导入事务仍由现有工作区写队列处理。
- iOS 共享目录排除备份并使用文件保护；Android 使用应用私有目录且沿用禁用备份的配置。错误提示不包含外部 URL、文件路径或异常详情。

## 验证

本次实际运行结果、覆盖率、原生截图和既有失败见 [GUL-659 验证记录](evidence/gul-659/validation.md)。

新增 Dart 测试覆盖：冷启动收件箱、重复通知、顺序消费、前后台恢复、搜索目标、新建/已有学习集的网页与文件路径、解析期间保留文件、部分成功、全失败回滚、取消、清理/通知失败、剪贴板显式读取，以及手机/iPad 的浅色和深色布局。

原生测试包括 Foundation 收件箱的真实文件复制、原子发布、重放和清理；iOS NSItemProvider 的 URL/文件回调；Android 的文本分享、ClipData、content URI 复制、文件名与协议校验和超量输入。CI 会运行 Dart/Python 测试、Android 单测及 iOS RunnerTests。

```sh
flutter analyze
(cd packages/mm_platform && flutter test --coverage)
(cd apps/marginmind && flutter test test/share_import_test.dart test/library_test.dart test/browser_test.dart --coverage)
python3 -m unittest tool.tests.test_incoming_share_store
(cd apps/marginmind && flutter build apk --debug)
(cd apps/marginmind/android && ./gradlew :app:testDebugUnitTest --no-daemon)
(cd apps/marginmind && flutter build ios --simulator)
# 使用当前可用的 iPhone 或 iPad simulator ID
(cd apps/marginmind && xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,id=<ID>' -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-)
```

手动验收还应覆盖 Safari/Chrome/文件 App 的真实分享、单文件与多文件、系统“用其他应用打开”、iPad 分屏拖放，以及目标学习集中的网页转换与重启恢复。设备签名与 App Group 授权需要在真机发布配置上核对，不能由 Widget 测试替代。
