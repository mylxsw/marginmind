# 文档生成引擎接入（GUL-624）

`ModelMapGenerator(connection, model)` 实现核心 `MapGenerator`；每章默认 90 秒、2048 输出 tokens，合成/差异默认 120 秒、4096 tokens，每次响应最多 2 MiB。构造参数可覆盖预算。请求不提供工具，错误复用 `ResearchFailure`，全部无效报 `protocol/noValidMapContent`。三章并发、失败章节重试、模型连接创建与 `mapGeneratorProvider` 由 GUL-625 控制器负责。

`DocumentDigestBuilder(reader, repository: ..., loadOutline: ...)` 的 `build(snapshot, studySetId:, documentId:, mapId:, draftPrefix:, documentAlias:, chapters:, includeAnnotations:, organization:, instructions:, inputCharacters:, cancellation:)` 返回 `DocumentDigest(source, chapters)`。每个 `MapDigestChapter` 有 `input` 和独立 `fingerprint`。每次请求/重试都重新 build，使用唯一 draftPrefix；不要复用被解析器消耗过的 context。PDF 的原始目录通过 loadOutline 接入（用户保存的 DocumentOutline 优先），文字由 WorkspaceReader 读取，复用现有 OCR；无文字抛 `MapDigestNeedsText`，宿主可展示“需要识别文字”。

EPUB/MOBI/Markdown/网页沿用 DocumentRepository 和 ReflowDocument 的 canonical Book IR。契约目前只有页码出处，没有 TextAnchor 出处：textByPage 的键在这些格式下是 1 起始的 spine 段序号，context.pages 刻意留空，避免伪造物理页码；文字和标注照常参与生成。精确文本出处跳转需以后扩展核心契约。

缓存通过 `ref.read(mapDigestCacheProvider(studySetId))` 获取。为每段调用核心 `mapDigestCacheKey`，model 包含服务配置 ID、模型名及可用版本，不含密钥。章节流成功结束后，用 `mapPointCacheLines(points, input.context)` 转回规范 point NDJSON，再 `cache.write(key, lines, context: input.context)`。读时 `cache.read(key, context: newInput.context)` 将本地来源 ID 重映射到当前别名；随后逐行 `parseMapLine`。省略 context 的 read/write 保留基本三方法接口，但有来源/标注时应始终传 context。不要缓存失败流的片段。

“只处理新内容”仍构造完整计划，通过每章实际文字、标注/批注和局部阅读进度的 fingerprint 查缓存，仅 miss 的章节调用模型；合成/更新合并缓存与新读的全部要点。全量重新梳理也可复用未变的章节要点。clear 使用队列与 epoch，清空 map-digests 全部版本，不改图、依据指纹或其他 AI 缓存。非文件仓库使用进程内缓存。

章节输入按 JSON 编码后的实际长度分配：正文约 50%，标注与批注合计约 20%，其余留给提示、组织方式、要求及 JSON 外壳。中文不额外倍乘；控制字符、引号、反斜线按实际转义长度计费，切分不会拆开 emoji 的代理对。发送前核对共享的 `mapChapterPayload` 加系统提示总长。宿主可把当前模型的 `chapterBudget.inputCharacters` 传给 builder；默认 24000。48 页、每页约 1500 个中文字的单章会切成 7 段，测试同时校验各段完整请求不超过预算。

`generate` 和 `update` 自动在内部调用确定性 `fitPointsToBudget`：先丢最深层的要点，同层按原出现顺序从后往前丢；始终保留剩余要点的父要点和原顺序。预算计入对应系统提示、重新分配的别名、页码、标注及现有脑图结构的完整 JSON 长度；二分查找最少需要移除的要点数。原始要点、章节缓存和上下文不变，GUL-625 控制器无需另做裁剪。若仅现有结构/设置已超预算，或预算连一个要点也容不下，发送前返回明确的 `budget` 错误，不调用模型生成无依据内容。
