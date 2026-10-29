# GUL-570 验证报告

原始 Android 测量以 gzip 压缩保留，数值未改写；完整构建/测试日志不入库，结果与退出码见下文。

## 2026-10-29 补测结论：Go（负责人限定的原型门槛）

保留 Flutter 路线；本次补齐 SVG → Picture、段落/表格图片原位、Android profile 重测及 50 次切章检查。PR #100 的 Go 不等于完整 EPUB 产品验收。跨页/跨章选区、移动选择柄、无障碍归 GUL-576；LRU/generation/分块调度、长期内存及真机归 GUL-572；恶意 EPUB fuzz、nav/NCX、完整 CSS、脚注/ruby 归 GUL-574。接口和依赖见架构第 12 节。

| 补测项目 | 结果 |
| --- | --- |
| Calculus 全部 37 个 spine，30 次 × 3 宽度 × 2 字号 | 6,660 个布局样本，最慢章/参数 p95 **30.889ms**，低于 100ms |
| SVG 解码/缺图 | **0 unsupported_image，0 missing_image**；2,273 个 SVG 资源所在真实 EPUB 未替换；正文使用到的资源均由 mm_design 解码 |
| 冷帧（200） | build p95 1.795ms，raster p95 4.354ms，**0/200 超预算** |
| 热帧（200） | build p95 1.880ms，raster p95 4.585ms，**0/200 超预算** |
| 冷加载：资源解码 + 章节首次布局 | 37 章 p95 **260.830ms**，max 269.803ms |
| 热加载：资源解码 + 章节首次布局 | 37 章 p95 **247.865ms**，max 256.685ms |
| 原文锚点 | 6,660/6,660 校验通过；真实段落/表格几何断言、widget 命中及 16→22 字号保持锚点测试通过 |

冷加载清除 SVG 编译字节缓存后执行；热加载紧接着重开同章，保留默认最多 100 项编译缓存，仍重新创建 Picture。较大章节可能超过缓存上限，所以热加载不保证全命中，不能把这两行当作纯布局或首次可交互耗时。原样本宽度 320/768/1200、字号 16/22、每参数两次热身 + 30 次、profile、宿主 GPU 均保持不变。FrameTiming 本次明确覆盖前十个含内联图片的真实章节（每章 20 次页面切换），冷轮切章清编译缓存，热轮保留缓存；每轮 200 帧，包括实际 SVG Picture 绘制。新测量原始记录为 `svg-android.jsonl.gz`，逐章统计 `svg-chapters.csv`，汇总 `svg-summary.json`；旧记录不覆盖。

简单稳定性检查：两秒静置后取相同终点章节的 PSS，不强制 GC。0/10/20/30/40/50 次切换分别为 **179041 / 178448 / 177795 / 178395 / 179019 / 178375 KiB**。五轮无持续增长，末次比基线低 666 KiB，轮间范围 1,246 KiB；此结果只覆盖短程稳定性，不证明长期无泄漏。原始 `dumpsys meminfo` 及轮次标记在 `svg-android-memory.txt`。

真实测试素材是原 EPUB 的 CHAPTER I 行内 d 公式和导数表格，源路径登记在 `packages/mm_reflow/test/fixtures/calculus/README.md`。测试保留原 HTML/SVG 字节；使用平台无关的几何断言验证行内公式夹在源文字之间且在文字行盒内，表格图片位于对应单元格矩形内。16/22 字号均验证源顺序、资源对应关系、包含关系和锚点不变；不使用像素 golden。

明确剩余排版精度限制：ex 按 0.5em、公式垂直对齐用 middle，未实现字体实际 x-height/CSS vertical-align；表格仍为等宽列、不支持 rowspan/colspan；这些均保留图片内容和源位置，由 GUL-572/574 后续验收。当前冷加载约 0.27 秒，不满足单帧交互预算，分块调度由 GUL-572 完成，不能用 <100ms 重排数据掩盖。

复现（从仓库根目录执行；仅 7337.epub 随仓库提供，另外两本必须先下载）：

```bash
python3 docs/evidence/gul-570/fetch_books.py
flutter pub get
(cd packages/mm_reflow/example && JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home PATH=/opt/homebrew/opt/openjdk@21/bin:$PATH flutter build apk --profile --no-pub --dart-define=BENCHMARK=true --dart-define=BOOK=33283)
adb -s emulator-5554 install -r packages/mm_reflow/example/build/app/outputs/flutter-apk/app-profile.apk
EVIDENCE_PREFIX=svg- python3 docs/evidence/gul-570/run_android.py
python3 docs/evidence/gul-570/summarize_svg.py
```

同一 AVD/Flutter/宿主，启动参数 `-avd mm_phone -no-window -no-audio -no-snapshot -gpu host`；当时启动日志确认 Apple M4。正式基准期间未并行启动本任务测试/编译，结果收集完成后才运行全套检查。

本轮工程检查：`flutter analyze --no-pub` 无问题；`dart format --set-exit-if-changed apps packages` 504 文件、0 改动；完整 Dart/Flutter suites 通过（应用 770 pass / 21 skip），Python 工具测试 17/17，Web release 构建通过。补充 probe 基准流程测试 2/2 通过，默认 Android 参数不变，测试用显式短参数覆盖两种帧状态及内存轮次。总覆盖率 **91.47%**；新增 mm_book/mm_reflow/example 与图片适配器合计 **593/631 = 93.98%**（包含测试覆盖到的生成本地化源码），分项见 `svg-new-coverage.txt`。

macOS 原生首次 21/22 通过，既有 `testArticleChannelContract` 在 `XCTAssertNotNil` 失败（`svg-native-first-result.json`）；未改该原生代码，完整重跑 **22/22 通过**。保留首次失败的精简 JSON 摘要，不将重试描述为首次全绿。


## 环境、样本与复现

Apple M4，macOS 26.6.2，Flutter 3.47.2 / Dart 3.13.2 / engine a804b26164；Emulator 37.1.11，AVD mm_phone，Android 16/API 36 Google APIs ARM64，4 vCPU / 2560MB，1080×2400、420dpi、60Hz，Hypervisor.Framework，JDK 21.0.13。此环境不代表真机。共享宿主没有排他占用保证。

`books.json` 登记原 EPUB 的 URL、SHA-256、许可和作者。`fetch_books.py` 下载并严格验证哈希；上游重新生成书籍时会报错，须恢复匹配样本或明确重审基准版本，不能静默换书。仅小型道德經 7337.epub（79KB）作为 example 离线测试素材跟踪；Calculus 33283.epub 和 Alice 28885.epub 为被 gitignore 的本地下载。未下载时 example 的这两本不可打开，三书基准运行前须先下载。Calculus 单元测试只使用独立 HTML/SVG fixture，无网络和整书依赖。

- 道德經：老子，中文原文，https://www.gutenberg.org/ebooks/7337。
- Calculus Made Easy：Silvanus P. Thompson（1916 年去世），15 个 table、68 个 raster、2,273 个 SVG，https://www.gutenberg.org/ebooks/33283。
- Alice：Lewis Carroll（1898）、Arthur Rackham（1939）、Austin Dobson（1921），17 个 table、38 个 raster，https://www.gutenberg.org/ebooks/28885。

原 EPUB 均包含 Gutenberg 使用条款，OPF rights 为 Public domain in the USA；不等同全球授权。fixture 摘自同一哈希锁定书籍，来源在 fixture README。依赖许可证原文在 `licenses/`，xml 仅保留当前 7.0.1；新增 SVG 依赖见架构第 12 节。

采集程序直接输出 `android.jsonl.gz` 或 `svg-android.jsonl.gz`；汇总脚本读取 gzip，无需解压。已有压缩证据可离线重新汇总：

```bash
python3 docs/evidence/gul-570/summarize.py
python3 docs/evidence/gul-570/summarize_svg.py
```

## 检查摘要与退出码（原型交付时）

| 命令 | 退出码 | 结果 |
| --- | ---: | --- |
| flutter analyze --no-pub | 0 | 无问题 |
| dart format --set-exit-if-changed apps packages | 0 | 504 文件，0 改动 |
| python3 -m unittest discover -s tool/tests | 0 | 17/17 |
| python3 tool/coverage.py | 0 | 所有包通过；应用 770 pass / 21 skip；91.47% |
| flutter test --coverage（example） | 0 | 2/2；基准流程与章节切换 |
| flutter build web --release --no-pub（example） | 0 | 构建成功 |
| flutter build apk --profile --no-pub（example，参数见上） | 0 | profile APK 构建成功 |
| xcodebuild test（app macOS，首次） | 65 | 21/22；ArticleChannel 断言失败 |
| xcodebuild test（app macOS，完整重试） | 0 | 22/22 |
| run_android.py / summarize_svg.py | 0 | 37 章补测完成；数据见上 |

完整日志已按 Review 要求移出 Git；覆盖率摘要和原生失败摘要保留。CI 是当前修订版跨平台检查的权威记录，链接见 PR #100。

## 历史无 SVG 基线（已被补测 Go 取代）

`android.jsonl.gz`、`chapters.csv`、`summary.json` 保存 55 章 / 9,900 次布局的原始基线。三书最慢章 p95 分别为 16.672 / 20.868 / 16.452ms，每书 200 帧均无超预算；但有 2,927 次 SVG 解码失败，因此当时 No-Go。旧结果不含 SVG 绘制成本，不可作为当前支持能力证明。早期 SwiftShader 对照数据已删除。

最初全套应用测试 737 pass / 21 skip / 22 fail；main ce6fed2 复现两项，随后 rebase 到 GUL-579 的 6a1ac58 后通过。此处只留历史摘要。旧 PSS 首次 147,177、峰值 194,616、末次 171,913 KiB（11 次采样），不构成多轮稳定性证明；新补测已有 50 次切章。

`selection-16.png` / `selection-22.png` 是原 AVD 同次拖选/改字号截图，不作为像素 golden。跨页/跨章选择、移动选择柄、无障碍和长期内存仍按上述后续任务验收。
