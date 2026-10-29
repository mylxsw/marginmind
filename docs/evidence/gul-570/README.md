# GUL-570 验证报告

日志入库仅清理行尾空白，测量数值未改写。

2026-10-29。结论：**No-Go（当前原型尚不能作为完整 EPUB 引擎交付）；Flutter 原生文本排版的性能和原文锚点路线已得到正向验证。**

阻止 Go 的实际内容问题：技术书使用大量 SVG 公式，当前仅使用 Flutter raster codec，不能渲染 SVG；每次失败都记录 `unsupported_image`，没有伪装为图片成功。表格里的图片降级为表后块，diagnostics 明确记录。三书总计 2,927 次不支持图片的解码尝试（包括重载，不是唯一资源数）。因此“各类内容不丢失”门槛未通过，即使纯布局和帧耗时通过，也不能给完整 Go。

工程检查曾被基线问题阻塞：初始完整应用测试 737 pass / 21 skip / 22 fail；干净 main ce6fed2 上 right_panel_test 复现两项。工作区随后 rebase 到已合入 GUL-579 修复的 main 6a1ac58。最终全部 package/app suites 通过（应用 770 pass / 21 skip），总覆盖率 91.24%，见 tests-final.log 和 coverage-summary.md。早期失败记录只作基线诊断。

## 实际环境与参数

- 宿主：Apple M4、Darwin arm64/macOS 26.6.2；Flutter 3.47.2 / Dart 3.13.2 / engine a804b26164。
- 本地 AVD `mm_phone`，Android 16/API 36 Google APIs ARM64，1080×2400、420 dpi、60Hz；AVD 配置 4 vCPU，模拟器启动将 RAM 提至 2560MB。
- Emulator 37.1.11，Hypervisor.Framework。此机器不是 x86_64 Linux，不能使用 KVM。
- 首次启动因缺少系统镜像失败，安装 `system-images;android-36;google_apis;arm64-v8a` 后成功；JDK 26 构建在 androidJdkImage/jlink 失败，使用 JDK 21.0.13 后成功。
- 正式 `android.jsonl` 使用 `-gpu host`（日志确认 Apple M4）；`android-swiftshader.jsonl` 为此前软件 GPU 对照。profile=true 记录在 JSONL 首行。软件 GPU 运行与其他检查有并发，不能据此否定硬件性能。正式运行时本任务完整 Flutter 测试与 Web 编译已结束，原生构建仍卡在不消耗 CPU 的 lsregister；共享宿主没有排他占用保证。
- 全部 55 个 spine 项均计入，包括封面和 Gutenberg 许可页，不做挑选。每章两次热身后 30 次 × 三种宽度（320/768/1200）× 两种字号（16/22），共 9,900 个记录。字号 22 在同一迭代字号 16 后执行，为无缓存重排；含图片尺寸的布局不包含图片解码时间，不能称为端到端首次打开耗时。
- 每书选 canonicalText 最长的 spine 项连续翻页 200 次，含许可页可能成为最长项；测量是预排布局后的硬切页，不是手势翻页动画。每帧等待 endOfFrame 后另等 20ms。FrameTiming 记录 build/raster；超预算定义任一超过 16.67ms，不能等同用户交互端到端延迟。

## 正式测量结果（宿主 GPU）

| 书籍 | 章节数 | 布局样本 | 最慢章/参数 p95 | build p95 | raster p95 | 超预算帧 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 道德經（7337） | 3 | 540 | 16.672ms | 2.075ms | 2.844ms | 0/200 |
| Calculus Made Easy（33283） | 37 | 6660 | 20.868ms | 2.292ms | 2.825ms | 0/200 |
| Alice（28885，Rackham 插图） | 15 | 2700 | 16.452ms | 2.314ms | 3.391ms | 0/200 |

以上为所有字号/宽度组合中的最坏章 p95；逐章首布局、字号重排的 p50/p95/max 见 `chapters.csv`，未删慢样本。图片解码失败会用占位矩形，尤其技术书数据**不包含 SVG 渲染成本**，不能外推为公式支持后的性能。

9,900 次原文范围与高亮矩形校验全部通过。单元/Widget 测试覆盖中文、emoji 字素、跨页几何、表格单元格命中、拖选后改字号锚点保持不变，以及真实 EPUB 章节切换。`selection-16.png` 与 `selection-22.png` 是同次拖选/改字号的 AVD 截图（视口会按选区起点恢复，截图不是像素级 golden）。跨章节拖选、移动端选择柄、自动跨页选择和屏幕阅读器语义未实现。

Android dumpsys 5 秒间隔采样：首次 PSS 147,177 KiB，采样峰值 194,616 KiB，末次 171,913 KiB（11 次）。这不是全时刻峰值或纯 Dart heap；未单独做空壳启动基线，也未完成多轮 GC/内存泄漏证明，所以内存稳定性门槛仍待补。软件 GPU 对照 raster p95 67–88ms，正式宿主 GPU 2.8–3.4ms，说明必须区分模拟器渲染模式。

## 样本与许可

`books.json` 保存 URL、SHA-256、大小及作者。原始 EPUB 在 `packages/mm_reflow/example/assets`，未更改书籍内容，包含完整 Gutenberg 使用条款。`fetch_books.py` 只在哈希匹配时接受重下载，若上游重新生成 EPUB 则报错，不能悄悄替换基准。

- [道德經](https://www.gutenberg.org/ebooks/7337)：老子，中文原文。
- [Calculus Made Easy](https://www.gutenberg.org/ebooks/33283)：Silvanus P. Thompson（1916 年去世）；15 个 table 元素，68 个 raster 图片文件，另有 2,273 个 SVG 文件。
- [Alice's Adventures in Wonderland](https://www.gutenberg.org/ebooks/28885)：Lewis Carroll（1898）、Arthur Rackham（1939）、Austin Dobson（1921）；38 个 raster 图片文件，17 个 table 元素。

三个 EPUB 的 OPF rights 均为 Public domain in the USA；本次保留原版而不使用现代译本/改编插图。其他司法辖区应按项目发行地核对，不能将 Gutenberg 的美国公版声明等同全球授权。依赖许可证原文见 `licenses/`：archive/xml/html 为 MIT，markdown 为 BSD-3-Clause（后续 Markdown 解析才直接使用）。

## 实际命令与结果

从仓库根目录执行；SDK 路径按环境调整。

```bash
python3 docs/evidence/gul-570/fetch_books.py
# 三份 EPUB 校验通过；附带样本可直接使用，不必重新下载。
flutter pub get
flutter analyze
# 通过，analyze.log。
dart format --set-exit-if-changed apps packages
# 初始基线三个文件格式不符；GUL-579 已修复。最终 501 files / 0 changed，format-final.log。
python3 -m unittest discover -s tool/tests
# 17 tests 通过，tool-tests.log。
python3 tool/coverage.py
# 最终全部通过，应用 suite 770 pass / 21 skip，仓库总覆盖率 91.24%，tests-final.log。
(cd packages/mm_book && dart test --coverage=coverage && dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib)
(cd packages/mm_reflow && flutter test --coverage)
(cd packages/mm_reflow/example && flutter test --no-pub)
# 新包测试和 example 回归通过；新包 lib 行覆盖率 mm_book 99.31%、mm_reflow 100%。
# example lib 单独 54.95%；三个新增范围合计 425/526 = 80.80%，含 example，new-coverage.txt。
(cd packages/mm_reflow/example && flutter build web --release --no-pub)
# 通过，web-build.log。无 dart:io 解析入口，Web 编译成功；未做浏览器交互验收。
```

```bash
/opt/homebrew/share/android-commandlinetools/emulator/emulator -list-avds
/opt/homebrew/share/android-commandlinetools/emulator/emulator -accel-check
JAVA_HOME=/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home \
  sdkmanager --sdk_root=/opt/homebrew/share/android-commandlinetools 'system-images;android-36;google_apis;arm64-v8a'
/opt/homebrew/share/android-commandlinetools/emulator/emulator -avd mm_phone -no-window -no-audio -no-snapshot -gpu host
# 上一条需在另一个终端保持运行。
(cd packages/mm_reflow/example && \
  JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
  PATH=/opt/homebrew/opt/openjdk@21/bin:$PATH \
  flutter build apk --profile --no-pub --dart-define=BENCHMARK=true)
adb -s emulator-5554 install -r packages/mm_reflow/example/build/app/outputs/flutter-apk/app-profile.apk
python3 docs/evidence/gul-570/run_android.py
python3 docs/evidence/gul-570/summarize.py
# 正式运行退出 0，55 章全量采样，summary.json/chapters.csv。
```

native 检查：先执行任务要求的 xcodebuild test，因缺少 FlutterInputs/Outputs.xcfilelist 失败。随后 flutter build macos --debug 完成。系统 lsregister 两次长时间阻塞，分别终止对应注册子进程后 Xcode 继续执行；最终 xcodebuild test 退出 0，**TEST SUCCEEDED**，native-tests.log 保存最终输出。native-timeout.txt 为中途诊断，不是最终测试失败。基线复核在独立 clean worktree ce6fed2 执行 flutter pub get 与 `flutter test --no-pub test/right_panel_test.dart`：21 pass / 2 fail，见 baseline-tests.log；随后已清理该 worktree。本任务启动的 AVD 已正常关闭。

## 原型限制与下一步

本次原型没有接入产品阅读器、MOBI、浏览器、格式迁移、翻译、固定版式；这些按批准范围留给后续任务。最小 IR 的 HTML 解析器不实现完整 CSS、nav/NCX、复杂嵌套列表/表格及内联图片；脚注和 ruby 也未作为 Go 证明。解析虽有 ZIP 大小/条目/路径限制，尚未进行恶意 EPUB fuzz。

**推荐保留 Flutter 路线，修复内容与门槛再测：**

1. 在 mm_design 包装 SVG→Picture 渲染适配器，mm_book 保留内联/单元格资源位置；不能把公式/图片移到段尾或表后。补图文混排、跨行表格的真实样本黄金测试。
2. 缓存与调度由 GUL-572 完成：当前仅持有当前章，不是完整的 generation/LRU/分块后台排版实现。增加多轮进出章的 PSS/heap 和资源释放验证；测量包含 SVG 解码/绘制的真实成本。
3. 补跨页手势、选择柄、无障碍与普通手机上的 profile 运行；本次 AVD 数据只能说明此环境可行。
4. 基线窄屏与格式问题已由 GUL-579 修复，本任务提供完整检查与独立技术验证 PR；解决内容/内存门槛后再评审 Go。

如果补齐上述内容后仍不能达标，备选是基于 DOM 的 WebView 阅读器（CSS/SVG 交给浏览器，原文锚点保留），代价是全平台嵌入、Flutter 覆盖层选区和 Linux/Web 适配重做；另一个备选是固定 PDF 降级，但会失去即时重排。这两条都改变已定产品方案，应再评审，不能擅自切换。固定版式仍按已确认纯 Flutter 固定视口，且不进入本任务 Go 门槛。
