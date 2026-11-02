# iPhone 系统呈现改造验收

这是正式应用的证据，区别于上一阶段的独立 UIKit 参考样板。

## 页面与操作

- [iPhone 页面截图](iphone/)：54 张，覆盖资料库、全宽导航、设置全部分类、阅读与选区工具、文档目录管理、助手及草稿、脑图样式/详情/导出、笔记、生词本、复习、统计、网页转换、重排文档、深色与横屏。
- [页面联系表](contact-sheets/)：页面及系统组件概览。
- [完整流程运行记录](iphone-tail/run.log)：通过。因截图分批补充，末批仅输出 `06da` 起的截图，但从入口完整执行全部操作。
- [首批来源](iphone/build-source.json)、[中段来源](iphone-continued/build-source.json)、[完整流程来源](iphone-tail/build-source.json)：Dart 与 Swift 正式代码哈希完全一致；`iphone/` 汇总同名截图时使用后批覆盖前批，原始分批日志保留。
- [原生操作结果](iphone-tail/)：7 项 XCTest 通过。包含目录实际拖动到展开高度、类别切换定位、管理入口、书签表单保存、系统颜色选择、网址校验与保留输入、设置退出确认、重排文档目录定位。颜色与书签结果另由 Dart 断言核对已进入业务状态。
- [PDF 与横屏键盘](iphone-gestures-final/run.log)：通过。拖动 80pt 对应页面 80pt；触摸中断惯性、双指缩放稳定；XCTest 系统触摸滚动实际改变 PDF 位置；原生表单键盘不改变底下阅读位置。

助手、设置正文、阅读器及脑图画布仍使用 Flutter；复杂内容面板使用 Cupertino Sheet 或应用内底部面板。UIKit 的系统表单、目录列表、确认与颜色选择单独有 XCTest 证据，不把这些实现混称为全部原生。

- [iPad 正式应用页面](ipad-final/run.log)：竖屏和横屏通过。XCTest 旋转模拟器后另外检查宽高，避免 iPad 多任务模式忽略应用方向请求而产生误判；保留分栏与居中设置窗口。

- [普通应用启动及新建](normal-app/summary.json)：iOS 27 正式入口运行，UIKit medium/large 实际拖动、草稿保留与保存通过；关闭后 Flutter 可访问性与操作恢复。另保留 iPhone/iPad 正式入口启动截图。
- [iOS 模拟器构建](validation/ios-simulator-build.log)、[macOS 构建](validation/macos-build.log)均通过。

## 回归与已知基线

[静态分析](validation/analyze.log)无问题；[设计组件测试](validation/design-tests.log)58 项通过；[应用与平台测试](validation/platform-tests.log)93 项通过、3 项旧断言失败。

已在改造前 `da46fedb` 的独立工作区运行相同 iPad/PC 测试，结果为21项通过、相同3项失败，见[基线记录](validation/baseline-da46-tests.log)。两项 iPad 工具栏间距断言预期21、实际13；一项 PC 测试仍要求“Fit Width”直接出现在更多菜单，而现有产品放在子菜单。本轮没有修改这些既有行为或放宽断言。

原始 `.xcresult` 已导出 PNG、JSON 结果与日志；不把大体积测试包及失败诊断视频提交到仓库。测试使用模拟器自有示例及本地网页，无生产文档。

首批与中段运行分别因测试工具无法操作 Flutter 可访问性节点、系统关闭按钮大小写匹配而中断；最终流程修正操作分工与选择器后完整通过，未把先前中断的日志标记为通过。

## 真机安装

最终从已提交的 `88b7d4eb` 独立工作区构建签名 Release，版本 **0.8.0（13）**。该工作区在构建后无源码变更，Dart/Swift 哈希与最终安卓回归源码一致；[制品记录](release-artifact.json)记录可执行文件哈希。iPhone主流程和原生操作在安卓补丁前完成，补丁后另做iPhone实际键盘专项，UIKit Swift未改变。

用户自己的 iPhone 14 Pro（iOS 27.2）已完成安装、启动、安装后版本查询及新进程核对。另外已检查启动后的前台资料库画面；真机图片含私人文档信息，未提交仓库。页面与触摸交互的公开证据来自上述正式应用模拟器运行。签名包保存在本机 `/tmp/foliarc-native-device-final-0.8.0-13.app`，不提交签名制品。

## 安卓横屏复查补丁

逐图复查发现高键盘下发送按钮被遮挡；等待真实键盘完全展开后仍能复现，详见[修复前记录](diagnostics/android-keyboard-before.log)。安卓手机横屏且可用高度不足180时，输入区压成单行，保留发送/停止和关闭；收起键盘恢复完整助手。输入组件跨布局移动时保留同一编辑状态，避免键盘被意外关闭。iPhone/iPad/PC 不进入这个分支。

[安卓键盘专项](android-keyboard/run.log)已通过：实际键盘高度261.3，发送按钮底部146.1，小于可用区域150.1；44点点击区域、关闭入口、可点击性与旋转后的草稿均检查。[iPhone键盘专项](iphone-keyboard/run.log)也通过；[助手补充回归](validation/assistant-final-tests.log)43项通过，覆盖手机草稿、面板布局、桌面历史和只读会话。

此补丁是上述iPhone主流程之后追加的安卓分支修复。因此各批次来源哈希分开记录，不能把所有截图声称为同一份Dart源码；UIKit Swift与设计组件未改变。最终签名制品另按最终提交记录。

最终[安卓完整流程](android/run.log)已通过，53张截图全部复核；横屏等待系统键盘展开后同时检查发送与关闭按钮位于键盘之上且可点击，结束时核对草稿恢复。修复后的最终截图见 [android/14aa-assistant-landscape-keyboard.png](android/14aa-assistant-landscape-keyboard.png)。

[安卓 PDF 与横屏输入专项](android-gestures/run.log)最终源码重跑通过：80pt拖动对应80pt页面位移，触摸中断惯性、双指缩放保持稳定，横屏网址表单在高键盘下可滚动到操作按钮，真实软键盘已检查。[覆盖索引与图片校验值](coverage.json)记录各批来源和完整截图清单。

安卓普通APK另已构建、安装和冷启动；设备查询确认0.8.0（13）及运行进程，[普通入口截图](normal-app/android-launched.png)与[制品记录](normal-app/android-runtime.json)一并保留。
