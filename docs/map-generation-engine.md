# 文档生成引擎接入（GUL-624）

`ModelMapGenerator(connection, model)` 实现核心 `MapGenerator`；每章默认 90 秒、2048 输出 tokens，合成/差异默认 120 秒、4096 tokens，每次响应最多 2 MiB。构造参数可覆盖预算。请求不提供工具，错误复用 `ResearchFailure`，全部无效报 `protocol/noValidMapContent`。三章并发、失败章节重试、模型连接创建与 `mapGeneratorProvider` 由 GUL-625 控制器负责。

`DocumentDigestBuilder(reader, repository: ..., loadOutline: ...)` 的 `build(snapshot, studySetId:, documentId:, mapId:, draftPrefix:, documentAlias:, chapters:, includeAnnotations:, organization:, instructions:, inputCharacters:, cancellation:)` 返回 `DocumentDigest(source, chapters)`。每个 `MapDigestChapter` 有 `input` 和独立 `fingerprint`。每次请求/重试都重新 build，使用唯一 draftPrefix；不要复用被解析器消耗过的 context。PDF 的原始目录通过 loadOutline 接入（用户保存的 DocumentOutline 优先），文字由 WorkspaceReader 读取，复用现有 OCR；无文字抛 `MapDigestNeedsText`，宿主可展示“需要识别文字”。

EPUB/MOBI/Markdown/网页沿用 DocumentRepository 和 ReflowDocument 的 canonical Book IR。契约目前只有页码出处，没有 TextAnchor 出处：textByPage 的键在这些格式下是 1 起始的 spine 段序号，context.pages 刻意留空，避免伪造物理页码；文字和标注照常参与生成。精确文本出处跳转需以后扩展核心契约。

缓存通过 `ref.read(mapDigestCacheProvider(studySetId))` 获取。为每段调用核心 `mapDigestCacheKey`，model 包含服务配置 ID、模型名及可用版本，不含密钥。章节流成功结束后，用 `mapPointCacheLines(points, input.context)` 转回规范 point NDJSON，再 `cache.write(key, lines, context: input.context)`。读时 `cache.read(key, context: newInput.context)` 将本地来源 ID 重映射到当前别名；随后逐行 `parseMapLine`。省略 context 的 read/write 保留基本三方法接口，但有来源/标注时应始终传 context。不要缓存失败流的片段。

“只处理新内容”仍构造完整计划，通过每章实际文字、标注/批注和局部阅读进度的 fingerprint 查缓存，仅 miss 的章节调用模型；合成/更新合并缓存与新读的全部要点。全量重新梳理也可复用未变的章节要点。clear 使用队列与 epoch，清空 map-digests 全部版本，不改图、依据指纹或其他 AI 缓存。非文件仓库使用进程内缓存。
