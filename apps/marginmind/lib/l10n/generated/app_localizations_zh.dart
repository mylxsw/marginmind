// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => 'Foliarc';

  @override
  String get libraryTitleAll => '全部学习集';

  @override
  String get libraryRecent => '最近打开';

  @override
  String get libraryStarred => '已收藏';

  @override
  String get libraryDue => '待复习';

  @override
  String get librarySection => '资料库';

  @override
  String get libraryFolders => '文件夹';

  @override
  String get libraryUnfiled => '未分类';

  @override
  String get libraryRecentlyDeleted => '最近删除';

  @override
  String librarySetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count 个学习集', zero: '还没有学习集');
    return '$_temp0';
  }

  @override
  String libraryDueCount(int count) {
    return '$count 张卡片待复习';
  }

  @override
  String get libraryContinue => '继续学习';

  @override
  String get libraryAllHeading => '全部';

  @override
  String libraryLastPosition(String document, int page) {
    return '上次读到：$document · 第 $page 页';
  }

  @override
  String get libraryNoDocumentsYet => '尚未导入文档';

  @override
  String libraryCardMeta(int documents, int cards) {
    return '$documents 份文档 · $cards 张卡片';
  }

  @override
  String dueBadge(int count) {
    return '$count 张待复习';
  }

  @override
  String get relativeJustNow => '刚刚';

  @override
  String relativeMinutes(int count) {
    return '$count 分钟前';
  }

  @override
  String relativeHours(int count) {
    return '$count 小时前';
  }

  @override
  String get relativeYesterday => '昨天';

  @override
  String relativeDays(int count) {
    return '$count 天前';
  }

  @override
  String relativeWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count 周前', one: '上周');
    return '$_temp0';
  }

  @override
  String relativeMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '$count 个月前', one: '上个月');
    return '$_temp0';
  }

  @override
  String get viewAsIcons => '图标';

  @override
  String get viewAsList => '列表';

  @override
  String get sortRecent => '最近打开';

  @override
  String get sortTitle => '名称';

  @override
  String get sortCards => '卡片数量';

  @override
  String sortBy(String field) {
    return '按$field';
  }

  @override
  String get sortTooltip => '排序方式';

  @override
  String get search => '搜索';

  @override
  String get searchLibrary => '搜索学习集';

  @override
  String get newStudySet => '新建学习集';

  @override
  String get newFolder => '新建文件夹';

  @override
  String get openSample => '打开示例学习集';

  @override
  String get noResultTitle => '没有符合条件的学习集';

  @override
  String noResultSearch(String query) {
    return '没有名称包含“$query”的学习集。';
  }

  @override
  String get noResultFilter => '这个分类下还没有学习集，可以把学习集拖进侧栏的文件夹里。';

  @override
  String get columnName => '名称';

  @override
  String get columnFolder => '文件夹';

  @override
  String get columnDocuments => '文档';

  @override
  String get columnCards => '卡片';

  @override
  String get columnDue => '待复习';

  @override
  String get columnLastOpened => '最近打开';

  @override
  String get star => '收藏';

  @override
  String get unstar => '取消收藏';

  @override
  String get open => '打开';

  @override
  String get sheetName => '名称';

  @override
  String get sheetNamePlaceholder => '例如：认知心理学';

  @override
  String get cancel => '取消';

  @override
  String get create => '创建';

  @override
  String get done => '完成';

  @override
  String get colorYellow => '黄色';

  @override
  String get colorGreen => '绿色';

  @override
  String get colorBlue => '蓝色';

  @override
  String get colorPink => '粉色';

  @override
  String get colorOrange => '橙色';

  @override
  String get colorPurple => '紫色';

  @override
  String get colorRed => '红色';

  @override
  String get colorBlack => '黑色';

  @override
  String get showLibrary => '显示资料库';

  @override
  String get hideSidebar => '隐藏侧栏';

  @override
  String get showSidebar => '显示侧栏';

  @override
  String get searchInSet => '搜索';

  @override
  String get sectionMaps => '脑图';

  @override
  String get sectionDocuments => '文档';

  @override
  String get sectionLearn => '学习';

  @override
  String get mainMap => '主脑图';

  @override
  String get review => '复习';

  @override
  String get tags => '标签';

  @override
  String get importDocument => '导入文档…';

  @override
  String get noSidebarMatches => '没有匹配的条目';

  @override
  String get toggleAnnotationTool => '切换高亮笔';

  @override
  String get toggleAreaTool => '切换框选';

  @override
  String get toggleInkTool => '切换画笔';

  @override
  String get toolSelect => '选择';

  @override
  String get toolHighlight => '高亮';

  @override
  String get toolArea => '框选';

  @override
  String get toolPen => '画笔';

  @override
  String get toolText => '文本';

  @override
  String get inkFreehand => '自由线';

  @override
  String get inkEllipse => '圈画';

  @override
  String get inkArrow => '箭头';

  @override
  String get inkEraser => '橡皮擦';

  @override
  String get inkThin => '细';

  @override
  String get inkMedium => '中';

  @override
  String get inkBold => '粗';

  @override
  String get syncToMapOn => '摘录同步到脑图：开';

  @override
  String get syncToMapOff => '摘录同步到脑图：关';

  @override
  String get annotationColor => '标注颜色';

  @override
  String get layoutReader => '只看原文';

  @override
  String get layoutSplit => '分栏';

  @override
  String get layoutMap => '只看脑图';

  @override
  String get paneSource => '阅读';

  @override
  String get paneMap => '脑图';

  @override
  String get moreTools => '更多';

  @override
  String get aiAssistant => 'AI 助手';

  @override
  String pageNumber(int page) {
    return '第 $page 页';
  }

  @override
  String pageOf(int page, int total) {
    return '$page / $total';
  }

  @override
  String get readerEmptyTitle => '打开一份文档开始阅读';

  @override
  String get readerEmptyMessage => '在侧栏选择文档，或导入文档。';

  @override
  String get readerPlaceholder => 'PDF 渲染会在 mm_pdf 包接入后出现在这里，这一页只是占位。';

  @override
  String get mapEmptyTitle => '摘录会出现在这里';

  @override
  String get mapView => '脑图';

  @override
  String get outlineView => '大纲';

  @override
  String newExcerptTarget(String topic) {
    return '新摘录 → $topic';
  }

  @override
  String get addTopic => '添加主题';

  @override
  String get addNote => '添加笔记';

  @override
  String get removeFromMap => '从脑图移除';

  @override
  String get zoomIn => '放大';

  @override
  String get zoomOut => '缩小';

  @override
  String get previousPage => '上一页';

  @override
  String get nextPage => '下一页';

  @override
  String get switchDocument => '切换文档';

  @override
  String get closeCurrentDocument => '关闭当前文档';

  @override
  String get closeTab => '关闭标签页';

  @override
  String get comingSoon => '即将推出';

  @override
  String get settings => '设置…';

  @override
  String get settingsTitle => '设置';

  @override
  String get appearance => '外观';

  @override
  String get appearanceSystem => '跟随系统';

  @override
  String get appearanceLight => '浅色';

  @override
  String get appearanceDark => '深色';

  @override
  String get language => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get menuFile => '文件';

  @override
  String get menuView => '显示';

  @override
  String get menuWindow => '窗口';

  @override
  String get menuHelp => '帮助';

  @override
  String get componentGallery => '组件库';

  @override
  String get galleryTitle => '组件库';

  @override
  String get gallerySubtitle => 'mm_design · 设计令牌与组件';

  @override
  String get galleryColors => '颜色';

  @override
  String get galleryTypography => '字体';

  @override
  String get galleryControls => '控件';

  @override
  String get galleryFeedback => '反馈';

  @override
  String get galleryShowHud => '显示提示';

  @override
  String get galleryShowSheet => '显示表单';

  @override
  String get galleryHudMessage => '已摘录到「遗忘的规律」';

  @override
  String get back => '返回';

  @override
  String get importPdf => '导入 PDF…';

  @override
  String importedHud(int count) {
    return '已导入 $count 份文档';
  }

  @override
  String importFailed(String name) {
    return '无法以 PDF 打开「$name」';
  }

  @override
  String get pdfFiles => 'PDF 文档';

  @override
  String get excerptAction => '摘录到脑图';

  @override
  String get highlightAction => '高亮';

  @override
  String get copyAction => '拷贝';

  @override
  String get addToMapAction => '加入脑图';

  @override
  String get deleteHighlight => '删除高亮';

  @override
  String excerptedHud(String target) {
    return '已摘录到「$target」';
  }

  @override
  String get excerptView => '查看';

  @override
  String get highlightedHud => '已高亮';

  @override
  String get copiedHud => '已拷贝';

  @override
  String get removedHud => '已从脑图移除，原文高亮保留';

  @override
  String get highlightDeletedHud => '已删除高亮';

  @override
  String get rename => '重命名…';

  @override
  String get renameTitle => '重命名';

  @override
  String mapNodeNoteCount(int count) {
    return '笔记 · $count';
  }

  @override
  String get deleteMapNote => '删除笔记';

  @override
  String get editNote => '编辑笔记';

  @override
  String get save => '保存';

  @override
  String get newTopicName => '新主题';

  @override
  String get newNoteText => '新笔记';

  @override
  String get untitledExcerpt => '未命名摘录';

  @override
  String get imageExcerpt => '图片摘录';

  @override
  String get revealSource => '定位原文';

  @override
  String get menuMap => '脑图';

  @override
  String documentPages(int count) {
    return '$count 页';
  }

  @override
  String get sampleSetTitle => '示例：遗忘曲线与间隔重复';

  @override
  String get sampleTopic1 => '遗忘的规律';

  @override
  String get sampleTopic2 => '对策一：间隔重复';

  @override
  String get sampleTopic3 => '对策二：主动提取';

  @override
  String get readerHintHighlight => '拖选文字即可摘录';

  @override
  String get readerHintSelect => '选中文字后选择操作';

  @override
  String get outlineEmpty => '大纲里还没有内容';

  @override
  String get sampleDocTitle => '示例章节：遗忘曲线与间隔重复';

  @override
  String get somethingWentWrong => '出了点问题，请重试';

  @override
  String get addChildTopic => '添加子主题';

  @override
  String get backToStudySet => '返回学习集';

  @override
  String get collapseNode => '折叠';

  @override
  String get expandNode => '展开';

  @override
  String get delete => '删除';

  @override
  String get deleteEllipsis => '删除…';

  @override
  String deleteStudySetTitle(String title) {
    return '删除“$title”？';
  }

  @override
  String get deleteStudySetMessage => '其中的文档、高亮、卡片和复习记录都会被删除，且无法撤销。';

  @override
  String deletedHud(String title) {
    return '已删除“$title”';
  }

  @override
  String get documentRemovedHud => '已移除文档';

  @override
  String get dropToCreateSet => '松开即可新建学习集';

  @override
  String get dropToImport => '松开即可导入到当前学习集';

  @override
  String get dropOnlyPdf => '目前只能导入 PDF 文件';

  @override
  String get exportMarkdown => '将脑图导出为 Markdown…';

  @override
  String get exportOpml => '将脑图导出为 OPML…';

  @override
  String get exportedHud => '已导出';

  @override
  String get menuEdit => '编辑';

  @override
  String get moveUp => '上移';

  @override
  String get moveDown => '下移';

  @override
  String get rateAgain => '重来';

  @override
  String get rateHard => '困难';

  @override
  String get rateGood => '良好';

  @override
  String get rateEasy => '简单';

  @override
  String get undo => '撤销';

  @override
  String get redo => '重做';

  @override
  String get undoneHud => '已撤销';

  @override
  String get redoneHud => '已重做';

  @override
  String get remove => '移除';

  @override
  String get removeDocumentEllipsis => '从学习集中移除…';

  @override
  String removeDocumentTitle(String title) {
    return '移除“$title”？';
  }

  @override
  String removeDocumentMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '它的 $count 处高亮及对应摘录卡片也会一并移除，可用 ⌘Z 撤销。',
      zero: '该文档将从学习集中移除。',
    );
    return '$_temp0';
  }

  @override
  String get renameEllipsis => '重命名…';

  @override
  String get renameDocument => '重命名文档';

  @override
  String get renameStudySet => '重命名学习集';

  @override
  String reviewCount(int count) {
    return '复习 $count 张卡片';
  }

  @override
  String get reviewTitle => '复习';

  @override
  String reviewRemaining(int count) {
    return '剩余 $count 张';
  }

  @override
  String get reviewProgress => '复习进度';

  @override
  String get reviewDoneTitle => '本轮复习完成';

  @override
  String reviewDoneMessage(int count) {
    return '已复习 $count 张卡片';
  }

  @override
  String get reviewNothingDueTitle => '暂无需要复习的卡片';

  @override
  String get showAnswer => '显示答案';

  @override
  String get startReview => '开始复习';

  @override
  String get reviewBranch => '复习此分支';

  @override
  String get reviewTag => '复习此标签';

  @override
  String get suspendCard => '暂停复习';

  @override
  String get resumeCard => '恢复复习';

  @override
  String get cardSuspended => '已暂停';

  @override
  String get sectionCards => '卡片';

  @override
  String intervalMinutes(int count) {
    return '$count 分钟';
  }

  @override
  String intervalHours(int count) {
    return '$count 小时';
  }

  @override
  String intervalDays(int count) {
    return '$count 天';
  }

  @override
  String intervalMonths(int count) {
    return '$count 个月';
  }

  @override
  String excerptInColor(String color) {
    return '用$color摘录';
  }

  @override
  String get locateCard => '定位卡片';

  @override
  String get excerptWithNote => '摘录并添加笔记';

  @override
  String get addSiblingAfter => '在后面添加同级节点';

  @override
  String get addSiblingBefore => '在前面添加同级节点';

  @override
  String get promoteNode => '提升一级';

  @override
  String get insertParentNode => '插入父节点';

  @override
  String get toggleNodeFold => '折叠或展开';

  @override
  String get fitMap => '查看全图';

  @override
  String get centerCurrentNode => '定位选中节点';

  @override
  String get cutNodes => '剪切';

  @override
  String get pasteNodes => '粘贴';

  @override
  String get newMap => '新建脑图…';

  @override
  String get newMapName => '未命名脑图';

  @override
  String get renameMap => '重命名脑图…';

  @override
  String get deleteMap => '删除脑图';

  @override
  String addToNamedMap(String title) {
    return '加入“$title”';
  }

  @override
  String get cardTags => '标签…';

  @override
  String get sectionTags => '标签';

  @override
  String get addTag => '添加标签';

  @override
  String get removeTag => '删除标签';

  @override
  String get allTags => '全部标签';

  @override
  String get backToMap => '返回脑图';

  @override
  String get viewInMap => '在脑图中查看';

  @override
  String tagNodesInMap(int count) {
    return '$count 个相关节点 · 当前脑图';
  }

  @override
  String get tagNoNodes => '没有带此标签的节点';

  @override
  String get addRelation => '添加关联线';

  @override
  String get addSummary => '添加概要';

  @override
  String get newSummaryLabel => '概要';

  @override
  String get editMarkLabel => '编辑标签';

  @override
  String get deleteRelation => '删除关联线';

  @override
  String get deleteSummary => '删除概要';

  @override
  String exportSummary(String label) {
    return '概要：$label';
  }

  @override
  String get exportRelations => '关联';

  @override
  String get readerThumbnails => '缩略图';

  @override
  String get readerOutline => '目录';

  @override
  String get readerBookmarks => '书签';

  @override
  String get readerAnnotations => '标注';

  @override
  String get inkAnnotations => '手绘标注';

  @override
  String inkStrokeCount(int count) {
    return '$count 处笔迹';
  }

  @override
  String get showReaderSidebar => '显示页面侧栏';

  @override
  String get hideReaderSidebar => '隐藏页面侧栏';

  @override
  String get addBookmark => '添加书签';

  @override
  String get removeBookmark => '取消书签';

  @override
  String get renameBookmark => '重命名书签…';

  @override
  String get deleteBookmark => '删除书签';

  @override
  String get findInDocument => '在文档中查找';

  @override
  String get findNext => '查找下一个';

  @override
  String get findPrevious => '查找上一个';

  @override
  String get noResults => '无结果';

  @override
  String matchOf(int current, int total) {
    return '$current / $total';
  }

  @override
  String get pageNumberField => '页码';

  @override
  String get goBack => '返回上一个位置';

  @override
  String get firstPage => '首页';

  @override
  String get lastPage => '末页';

  @override
  String get goToPage => '前往页面…';

  @override
  String get menuGo => '前往';

  @override
  String get enterFullScreen => '进入全屏';

  @override
  String get exitFullScreen => '退出全屏';

  @override
  String get noBookmarks => '没有书签';

  @override
  String get noAnnotations => '没有标注';

  @override
  String get expandSection => '展开';

  @override
  String get collapseSection => '折叠';

  @override
  String get pdfActualSize => '实际大小';

  @override
  String get pdfFitWidth => '适合宽度';

  @override
  String get pdfFitPage => '适合页面';

  @override
  String get statistics => '统计';

  @override
  String get statsReviewed => '复习量';

  @override
  String get statsRetention => '记住率';

  @override
  String get statsUpcoming => '未来 30 天';

  @override
  String get pdfOptions => 'PDF 操作';

  @override
  String get readerStyleWhite => '白色';

  @override
  String get readerStyleDark => '深色';

  @override
  String get readerStylePaper => '纸质';

  @override
  String get readerStyleGreen => '浅绿';

  @override
  String get readerZoom => '页面';

  @override
  String get readerAppearance => '阅读外观';

  @override
  String get readerMenuReading => '阅读辅助';

  @override
  String get readerMenuPage => '页面显示';

  @override
  String get readerMenuTools => '工具与工作区';

  @override
  String get research => '研究';

  @override
  String get showResearchPanel => '显示研究面板';

  @override
  String get hideResearchPanel => '隐藏研究面板';

  @override
  String get researchEmptyTitle => '选中原文或脑图节点，开始研究';

  @override
  String get showCardDetails => '显示详情';

  @override
  String get hideCardDetails => '隐藏详情';

  @override
  String get closePanel => '关闭';

  @override
  String get expandCardText => '展开全文';

  @override
  String get collapseCardText => '收起';

  @override
  String get toggleCardText => '展开或收起全文';

  @override
  String get detailsExcerpt => '摘录卡片';

  @override
  String get detailsImage => '图片卡片';

  @override
  String get detailsNote => '笔记';

  @override
  String get detailsTopic => '主题';

  @override
  String get addTitle => '添加标题';

  @override
  String revealSourcePage(int page) {
    return '回到原文 · 第 $page 页';
  }

  @override
  String get reviewStatusNew => '尚未复习';

  @override
  String reviewStatusScheduled(DateTime date, int count) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.MMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return '下次 $dateString · 已复习 $count 次';
  }

  @override
  String get insertImage => '插入图片…';

  @override
  String get imageFiles => 'PNG / JPEG 图片';

  @override
  String get imageQuestion => '题面';

  @override
  String get imageImportFailed => '图片导入失败，请选择 PNG 或 JPEG 文件。';

  @override
  String get imageInserted => '已插入图片';

  @override
  String get dropImage => '松开以插入图片';

  @override
  String get previewImage => '预览图片';

  @override
  String get ocrRecognize => '识别文字…';

  @override
  String get ocrTitle => '识别文字';

  @override
  String get ocrStart => '开始识别';

  @override
  String get ocrNoText => '本页文字尚不能选择';

  @override
  String get ocrRecognized => '已识别';

  @override
  String get ocrCancelled => '已取消 · 已识别页面已保留';

  @override
  String get ocrFailed => '识别失败 · 请重试';

  @override
  String ocrProgress(int done, int total) {
    return '识别文字 $done/$total';
  }

  @override
  String get ocrScope => '范围';

  @override
  String get ocrAllPages => '全部';

  @override
  String get ocrCurrentPage => '当前页';

  @override
  String get ocrPageRange => '页码范围';

  @override
  String get ocrLanguage => '语言';

  @override
  String get ocrChineseEnglish => '中文 + 英文';

  @override
  String get ocrChinese => '仅中文';

  @override
  String get ocrEnglish => '仅英文';

  @override
  String get ocrFirstPage => '起始页';

  @override
  String get ocrLastPage => '结束页';

  @override
  String ocrInvalidRange(int count) {
    return '请输入 1 至 $count 内的页码范围';
  }

  @override
  String get ocrThisPage => '识别本页';

  @override
  String get ocrCancel => '取消文字识别';

  @override
  String get exportTitle => '导出脑图';

  @override
  String get exportMap => '导出脑图…';

  @override
  String get exportBranch => '导出此分支…';

  @override
  String get exportAction => '导出…';

  @override
  String get exportFormat => '格式';

  @override
  String get exportRange => '范围';

  @override
  String get exportWholeMap => '整张脑图';

  @override
  String get exportCurrentBranch => '当前分支';

  @override
  String get exportAppearance => '外观';

  @override
  String get exportLight => '浅色';

  @override
  String get exportDark => '深色';

  @override
  String get exportTransparent => '透明背景';

  @override
  String get exportScale => '清晰度';

  @override
  String get exportLarge => '图片超过 8000 像素，部分应用可能打不开。请降低倍率或改用 PDF。';

  @override
  String get exportReduced => '已自动降低倍率，以满足图片尺寸和内存限制。';

  @override
  String get exportLoading => '正在准备导出…';

  @override
  String get exportFailed => '导出失败，请重试。';

  @override
  String get exportRetry => '重试';

  @override
  String exportPixels(String width, String height) {
    return '$width × $height 像素';
  }

  @override
  String exportCentimeters(String width, String height) {
    return '$width × $height 厘米';
  }

  @override
  String get exportResearchNote => '研究笔记';

  @override
  String get exportSource => '出处';

  @override
  String get formatBold => '加粗';

  @override
  String get formatItalic => '斜体';

  @override
  String get formatBulletList => '无序列表';

  @override
  String get formatNumberList => '有序列表';

  @override
  String get densityCompact => '紧凑';

  @override
  String get densityFull => '完整';

  @override
  String get mapStyle => '样式';

  @override
  String get mapStructureMind => '思维导图';

  @override
  String get mapStructureLogic => '逻辑图';

  @override
  String get mapStructureBrace => '括号图';

  @override
  String get mapStructureTree => '树形图';

  @override
  String get mapPaletteSystem => '系统';

  @override
  String get mapPaletteRainbow => '多彩';

  @override
  String get mapPaletteFresh => '清新';

  @override
  String get mapPaletteWarm => '暖阳';

  @override
  String get mapPaletteMorandi => '莫兰迪';

  @override
  String get mapPaletteInk => '墨水';

  @override
  String get cardWidthHandle => '卡片宽度';

  @override
  String get resetCardWidth => '恢复默认宽度';

  @override
  String get detailsResearchNote => '研究笔记';

  @override
  String get researchSelection => '研究所选内容';

  @override
  String get researchSelectionEllipsis => '研究所选内容…';

  @override
  String get researchNode => '研究节点';

  @override
  String researchNodeMenu(String title) {
    return '研究「$title」';
  }

  @override
  String get researchIntentExplain => '解释概念';

  @override
  String get researchIntentInterpret => '解读这段';

  @override
  String get researchIntentVerify => '查证观点';

  @override
  String get researchIntentVideo => '找视频 / 图解';

  @override
  String get researchIntentPaper => '找论文';

  @override
  String get researchIntentDeep => '深入研究';

  @override
  String get researchIntentTranslate => '翻译并解释';

  @override
  String get researchRecommended => '推荐';

  @override
  String get researchQuestion => '问题';

  @override
  String get researchQuestionPlaceholder => '写下你想弄清的问题';

  @override
  String researchQuestionExplain(String term) {
    return '「$term」是什么意思？请结合上下文举一个例子。';
  }

  @override
  String get researchQuestionInterpret => '这段话的论点、推理过程和隐含前提分别是什么？';

  @override
  String get researchQuestionVerify => '这段话中的结论有依据吗？有没有反例或适用条件？';

  @override
  String researchQuestionVerifyQuote(String quote) {
    return '“$quote”——这个说法可靠吗？有没有反例或适用条件？';
  }

  @override
  String researchQuestionVideo(String term) {
    return '找一个直观讲解「$term」的视频或图解';
  }

  @override
  String researchQuestionPaper(String term) {
    return '关于「$term」有哪些代表性研究？结论和局限是什么？';
  }

  @override
  String get researchQuestionTranslate => '翻译这段话，并解释其中的术语。';

  @override
  String get researchKeywords => '搜索关键词';

  @override
  String get researchAddKeyword => '添加关键词';

  @override
  String get researchSourcesLabel => '来源';

  @override
  String get researchKindWeb => '网页';

  @override
  String get researchKindPaper => '论文';

  @override
  String get researchKindVideo => '视频';

  @override
  String get researchKindImage => '图片';

  @override
  String get researchMethod => '方式';

  @override
  String get researchMethodSearch => '只搜索';

  @override
  String get researchMethodOffline => '问 AI（不联网）';

  @override
  String get researchMethodWeb => '联网研究';

  @override
  String get researchMethodSearchNote => '不调用 AI，不产生 AI 费用';

  @override
  String get researchMethodOfflineNote => '只发送所选内容和上下文，不联网';

  @override
  String researchMethodWebNote(int searches, int pages) {
    return '最多 $searches 次搜索、读取 $pages 个页面';
  }

  @override
  String get researchSetUpAi => '设置 AI 服务…';

  @override
  String get researchNoAi => '未设置 AI 服务';

  @override
  String get researchNoAiTitle => '还没有设置 AI 服务';

  @override
  String get researchNoWeb => '当前服务不支持联网';

  @override
  String researchContextSummary(String parts, int count) {
    return '将发送给 AI：$parts（约 $count 字）';
  }

  @override
  String get researchContextSelection => '所选内容';

  @override
  String get researchContextBefore => '前一段';

  @override
  String get researchContextAfter => '后一段';

  @override
  String get researchContextChapter => '章节标题';

  @override
  String get researchContextNode => '节点';

  @override
  String get researchContextPath => '上级路径';

  @override
  String get researchContextChildren => '子节点内容';

  @override
  String get researchRunningChoice => '有一项研究正在进行';

  @override
  String get researchAsNew => '作为新研究';

  @override
  String get researchJoin => '加入当前问题';

  @override
  String get researchLater => '稍后研究';

  @override
  String get researchStart => '开始研究';

  @override
  String get researchNeedQuestion => '先写下要研究的问题';

  @override
  String get researchSavedForLater => '已加入稍后研究';

  @override
  String get researchJoined => '已加入当前研究';

  @override
  String get researchSettings => '研究设置';

  @override
  String get researchBackToOrigin => '回到起点';

  @override
  String get researchOriginGone => '原位置已删除';

  @override
  String get researchStageSearch => '检索资料';

  @override
  String get researchStageAnswer => '生成解答';

  @override
  String get researchStageWebAnswer => '检索并生成解答';

  @override
  String researchStageRead(int done, int total) {
    return '读取资料 $done/$total';
  }

  @override
  String get researchRetry => '重试';

  @override
  String get researchRestart => '重新开始';

  @override
  String get researchCancelled => '已取消';

  @override
  String get researchInterrupted => '上次退出时中断';

  @override
  String get researchFailed => '失败';

  @override
  String get researchRunning => '进行中';

  @override
  String researchDoneAt(String time) {
    return '$time 完成';
  }

  @override
  String researchUsedSources(int count) {
    return '使用 $count 个来源';
  }

  @override
  String get researchErrorTimeout => '超时';

  @override
  String get researchErrorUnavailable => '无法连接服务';

  @override
  String get researchErrorAuthentication => 'API Key 无效';

  @override
  String get researchErrorBudget => '已达到上限';

  @override
  String get researchErrorRefusal => 'AI 拒绝回答';

  @override
  String get researchErrorUnsupported => '当前服务不支持';

  @override
  String get researchErrorInvalid => '请求无效';

  @override
  String get researchErrorProtocol => '回答不完整';

  @override
  String get researchTabAnswer => '解答';

  @override
  String get researchTabSources => '资料';

  @override
  String get researchTabSaved => '已摘取';

  @override
  String researchBadgeWeb(int count) {
    return '联网研究 · 实际使用了 $count 个来源';
  }

  @override
  String get researchBadgeOffline => '未联网 · 没有外部来源，因此不附引用';

  @override
  String researchBadgeSources(int count) {
    return '只基于你选的 $count 份资料，没有联网搜索';
  }

  @override
  String get researchViewSources => '查看资料';

  @override
  String get researchNoSourceBasis => '无来源依据';

  @override
  String get researchEdited => '你修改过';

  @override
  String researchQuoteFrom(int number) {
    return '来源 [$number] · 原文摘录，未改写';
  }

  @override
  String get researchEditPoint => '编辑';

  @override
  String get researchAskPoint => '追问';

  @override
  String get researchSavePoint => '保存';

  @override
  String researchAskAbout(String point) {
    return '关于「$point」：';
  }

  @override
  String researchFailedSources(int count) {
    return '$count 个来源读取失败';
  }

  @override
  String researchChecked(int count) {
    return '已选 $count 条要点';
  }

  @override
  String get researchClearChecked => '取消选择';

  @override
  String get researchSaveNote => '保存为研究笔记…';

  @override
  String get researchNoAnswerSearch => '“只搜索”不生成解答';

  @override
  String get researchNoAnswer => '还没有解答';

  @override
  String researchAnswerFromChosen(int count) {
    return '基于所选 $count 份资料回答';
  }

  @override
  String get researchAnswering => '正在生成解答…';

  @override
  String get researchFollowUpPlaceholder => '追问，或补充你的想法…';

  @override
  String get researchCanUseWeb => '可联网';

  @override
  String get researchOffline => '不联网';

  @override
  String get researchSend => '发送';

  @override
  String get researchFilterAll => '全部';

  @override
  String get researchReadUnread => '未读取';

  @override
  String get researchReadSnippet => '仅搜索简介';

  @override
  String get researchReadAbstract => '仅摘要';

  @override
  String get researchReadFullText => '已提取正文';

  @override
  String get researchReadTranscript => '已取得字幕';

  @override
  String get researchReadFailed => '读取失败';

  @override
  String get researchReadNoTranscript => '无字幕';

  @override
  String get researchOpenAccess => '开放获取';

  @override
  String get researchSubscription => '需订阅';

  @override
  String get researchUsedInAnswer => '用于解答';

  @override
  String researchMerged(int count) {
    return '另有 $count 处转载已合并，不计为独立证据';
  }

  @override
  String get researchRead => '阅读';

  @override
  String get researchWhyFailed => '查看原因';

  @override
  String get researchChoose => '加入资料';

  @override
  String get researchChosen => '已加入资料';

  @override
  String get researchPasted => '用户粘贴';

  @override
  String researchExternalSearch(String site, String query) {
    return '在 $site 中搜索「$query」';
  }

  @override
  String get researchExternal => '外部搜索';

  @override
  String researchSearching(String keywords) {
    return '正在检索：$keywords';
  }

  @override
  String get researchNoSources => '暂无资料';

  @override
  String get researchOfflineNoSources => '这项研究没有联网';

  @override
  String get researchOpenPage => '打开原网页';

  @override
  String researchFetchedAt(String date) {
    return '抓取于 $date';
  }

  @override
  String get researchAiSummary => 'AI 摘要 · 不是原文';

  @override
  String get researchSummarize => 'AI 摘要';

  @override
  String get researchClipEvidence => '摘取为证据';

  @override
  String get researchWriteNote => '直接写成笔记…';

  @override
  String researchClipped(int count) {
    return '已摘取（$count）';
  }

  @override
  String get researchCantRead => '无法提取正文';

  @override
  String get researchReadLogin => '页面需要登录';

  @override
  String get researchReadTimeout => '页面加载超时。';

  @override
  String get researchReadUnparseable => '没有找到正文。';

  @override
  String get researchReadUnsafe => '不允许访问这个地址。';

  @override
  String get researchReadUnsupported => '不是网页。';

  @override
  String get researchReadEncoding => '不支持这个网页的文字编码。';

  @override
  String get researchReadUnavailable => '无法访问该网页。';

  @override
  String get researchPasteText => '粘贴正文…';

  @override
  String get researchSaveLinkOnly => '只保存链接';

  @override
  String get researchReadAgain => '重新读取';

  @override
  String get researchAbstractOnly => '只读到摘要';

  @override
  String get researchOpenPublisher => '出版商页面';

  @override
  String get researchPasteTitle => '粘贴正文';

  @override
  String get researchClipsTitle => '摘取的证据（草稿）';

  @override
  String get researchSavedNotes => '已保存的研究笔记';

  @override
  String get researchNoteFromClips => '用这些证据写研究笔记…';

  @override
  String get researchNothingSaved => '还没有摘取内容';

  @override
  String researchInSource(int page) {
    return '原文 · 第 $page 页';
  }

  @override
  String researchInMap(String title) {
    return '脑图 · $title';
  }

  @override
  String researchCitations(int count) {
    return '$count 个引用';
  }

  @override
  String get researchContinue => '继续研究';

  @override
  String get researchSaveTitle => '保存研究笔记';

  @override
  String get researchNoteTitle => '标题';

  @override
  String get researchNoteBody => '内容';

  @override
  String get researchNoteDefaultTitle => '研究笔记';

  @override
  String researchCitationsLabel(int count) {
    return '引用（$count）';
  }

  @override
  String get researchNoExternalBasis => '无外部依据';

  @override
  String get researchSaveTo => '保存到';

  @override
  String get researchDestBoth => '原文和脑图';

  @override
  String get researchDestSource => '只附到原文';

  @override
  String get researchDestMap => '只加入脑图';

  @override
  String get researchDestNoSource => '从节点发起，没有原文位置';

  @override
  String get researchAttachUnder => '挂在脑图的';

  @override
  String researchSplitPoints(int count) {
    return '把 $count 条要点拆成子节点';
  }

  @override
  String get researchSaving => '保存中';

  @override
  String get researchSavedBoth => '已保存到原文和脑图';

  @override
  String get researchSavedSource => '已保存到原文';

  @override
  String get researchSavedMap => '已保存到脑图';

  @override
  String get researchShowInMap => '在脑图中查看';

  @override
  String researchCardKind(int count) {
    String _temp0 = intl.Intl.pluralLogic(count, locale: localeName, other: '研究笔记 · $count 个来源', zero: '研究笔记');
    return '$_temp0';
  }

  @override
  String get researchCardOpen => '查看全文与引用';

  @override
  String researchNoteLabel(String title) {
    return '研究笔记：$title';
  }

  @override
  String get researchLocateInMap => '在脑图中定位';

  @override
  String get researchOpenResearch => '打开研究';

  @override
  String get researchPlaces => '关联位置';

  @override
  String researchPlaceSource(String document, int page) {
    return '$document 第 $page 页';
  }

  @override
  String get researchLocate => '定位';

  @override
  String get researchDetach => '解除';

  @override
  String get researchNotInSource => '未附到原文';

  @override
  String get researchNoteGone => '这条研究笔记已删除';

  @override
  String get researchDeleteNote => '删除研究笔记…';

  @override
  String get researchDeleteTitle => '删除这条研究笔记？';

  @override
  String researchDeleteMessage(int marks, int cards) {
    String _temp0 = intl.Intl.pluralLogic(marks, locale: localeName, other: '原文上的 $marks 处标记会一并移除。', zero: '');
    String _temp1 = intl.Intl.pluralLogic(cards, locale: localeName, other: '脑图上的 $cards 张卡片会一并删除。', zero: '');
    return '$_temp0$_temp1';
  }

  @override
  String get researchService => 'AI 服务';

  @override
  String get researchServiceNone => '未设置';

  @override
  String get researchServiceCompatible => '兼容接口';

  @override
  String get researchServiceIncomplete => '填写模型后才能使用这个服务';

  @override
  String get researchApiKey => 'API Key';

  @override
  String get researchKeySaved => '已保存在钥匙串';

  @override
  String get researchKeyFailed => '无法保存到钥匙串';

  @override
  String get researchModel => '模型';

  @override
  String get researchEndpoint => '接口地址';

  @override
  String get researchPaperSearch => '论文检索';

  @override
  String get researchLimits => '联网研究上限';

  @override
  String researchLimitSearches(int count) {
    return '搜索 $count 次';
  }

  @override
  String researchLimitPages(int count) {
    return '读取 $count 个页面';
  }

  @override
  String researchLimitMinutes(int count) {
    return '最长 $count 分钟';
  }

  @override
  String get researchPrivacy => '隐私';

  @override
  String get researchShowContext => '开始研究前显示将要发送的上下文';

  @override
  String get researchBlockPrivate => '阻止访问本机和内网地址';

  @override
  String get researchCache => '网页缓存';

  @override
  String get researchClearCache => '清理缓存';

  @override
  String get researchCacheCleared => '已清理网页缓存';

  @override
  String get researchInterruptedShort => '已中断';

  @override
  String get researchAddReview => '加入复习';

  @override
  String get researchSaveVideo => '保存视频链接…';

  @override
  String get researchVideoUrl => '视频链接';

  @override
  String get researchInvalidVideo => '请输入 YouTube 或 B 站视频链接。';

  @override
  String get researchViewMore => '查看更多';

  @override
  String get researchHistory => '历史研究';

  @override
  String get researchDelete => '删除研究';

  @override
  String get researchErrorUnsafeUrl => '接口地址被网络检查拦截';

  @override
  String get researchErrorTls => '无法建立安全连接';

  @override
  String get researchFixAuthentication => '请检查 API Key 是否有效、是否有此模型的使用权限，以及账户额度。修改后再重试。';

  @override
  String get researchFixRequest =>
      '请检查接口地址、模型名称，以及服务商是否支持当前请求方式。兼容接口可填写基础地址（如 https://example.com/v1）或完整的 chat/completions 地址。';

  @override
  String get researchFixUnsafeUrl => '请检查接口地址和代理的 DNS 设置。网页抓取不允许访问私有地址；只有明确配置的 HTTPS AI 接口支持代理虚拟地址。';

  @override
  String get researchFixTls => '请检查系统时间、服务端证书和代理设置。证书验证失败不会自动重试。';

  @override
  String get researchFixRateLimit => '服务商限制了请求频率或账户额度。已有限重试；请稍后再试，或检查账户余额和配额。';

  @override
  String get researchFixConnection => '请检查网络、代理和服务商状态，必要时增加研究时长。临时连接故障会有限重试；总时长用尽或回答已开始输出后，需要手动重试。';

  @override
  String get researchFixProtocol => '服务商返回的内容不完整或与所选接口格式不符。请确认接口支持流式回答；已有内容会保留，可手动重试。';

  @override
  String get researchFixBudget => '已达到研究的内容或输出上限。请缩小问题范围、减少所选资料，或调整研究设置。';

  @override
  String researchDiagnosticCode(String code) {
    return '错误代码：$code';
  }

  @override
  String get assistant => '助手';

  @override
  String get askAssistant => '问助手';

  @override
  String get askAssistantEllipsis => '问助手…';

  @override
  String get showAssistant => '显示助手';

  @override
  String get hideAssistant => '隐藏助手';

  @override
  String get assistantNewConversation => '新对话';

  @override
  String get assistantHistory => '对话记录';

  @override
  String get assistantConversations => '对话';

  @override
  String get assistantNoConversations => '还没有对话';

  @override
  String get assistantPlaceholder => '提问…';

  @override
  String get assistantConnectFirst => '先配置模型';

  @override
  String get assistantMention => '引用';

  @override
  String get assistantCommands => '快捷指令';

  @override
  String get assistantOnline => '联网';

  @override
  String get assistantOffline => '不联网';

  @override
  String get assistantSend => '发送';

  @override
  String get assistantStop => '停止';

  @override
  String get assistantPermissionTitle => '需要你的授权';

  @override
  String get assistantPermissionWaiting => '等待授权';

  @override
  String get assistantPermissionExplain => '助手想读取以下内容，以补充回答所需的上下文。';

  @override
  String get assistantPermissionScope => '仅本轮生效，允许后才会读取。';

  @override
  String get assistantPermissionAllow => '本轮允许';

  @override
  String get assistantPermissionDeny => '拒绝';

  @override
  String get assistantPermissionAllowed => '本轮已允许';

  @override
  String get assistantPermissionDenied => '已拒绝';

  @override
  String get assistantPermissionCancelled => '请求已取消';

  @override
  String assistantPermissionPages(String document, int from, int to) {
    return '$document · 第 $from–$to 页';
  }

  @override
  String assistantPermissionSelection(String title) {
    return '所选文字 · $title';
  }

  @override
  String assistantPermissionBranch(String title) {
    return '脑图分支 · $title';
  }

  @override
  String get assistantToolReadSelection => '读取所选内容';

  @override
  String get assistantToolReadPages => '读取原文';

  @override
  String get assistantToolSearch => '检索学习集';

  @override
  String get assistantToolReadBranch => '读取脑图分支';

  @override
  String get assistantToolWebSearch => '联网搜索';

  @override
  String get assistantToolPapers => '查找论文';

  @override
  String get assistantToolFetch => '读取网页';

  @override
  String get assistantToolPropose => '整理修改';

  @override
  String get assistantToolSkills => '选择方式';

  @override
  String get assistantToolOther => '处理中';

  @override
  String get assistantNotOnline => '未联网';

  @override
  String get assistantInsertChild => '插入为子节点';

  @override
  String get assistantSaveNote => '记笔记';

  @override
  String get assistantAnswerToMap => '整理成导图';

  @override
  String assistantAnswerToMapPrompt(String answer) {
    return '把下面这条回答整理成思维导图，保留主要观点和层级，并给出可预览的导图修改建议：\n\n$answer';
  }

  @override
  String get assistantSavedNote => '已存为笔记';

  @override
  String get assistantLocate => '定位';

  @override
  String get assistantRegenerate => '重新生成';

  @override
  String get assistantErrorNetwork => '网络不可用';

  @override
  String get assistantErrorKey => 'API Key 无效';

  @override
  String get assistantErrorService => '服务暂时不可用';

  @override
  String get assistantErrorBudget => '超出本次上限';

  @override
  String get assistantErrorRefused => '模型拒绝回答';

  @override
  String get assistantErrorToolProtocol => '模型没能正确调用工具';

  @override
  String get assistantErrorFailed => '请求失败';

  @override
  String get assistantStopped => '已停止';

  @override
  String get assistantInterrupted => '上次退出时没有完成';

  @override
  String get assistantRetry => '重试';

  @override
  String get assistantUseLocal => '改用本机模型';

  @override
  String get assistantOpenSettings => '打开设置';

  @override
  String get assistantContinue => '继续';

  @override
  String get assistantProposalTitle => '修改脑图';

  @override
  String get assistantProposalApplied => '已应用';

  @override
  String get assistantProposalDismissed => '已忽略';

  @override
  String get assistantDismiss => '不用了';

  @override
  String assistantApply(int count) {
    return '应用 $count 处';
  }

  @override
  String get assistantShowInMap => '在脑图中查看';

  @override
  String get assistantReopen => '重新查看';

  @override
  String get assistantTargetDeleted => '目标已删除';

  @override
  String assistantAppliedHud(int count) {
    return '已应用 $count 处修改';
  }

  @override
  String assistantPutInMap(String title) {
    return '放进脑图「$title」';
  }

  @override
  String assistantAttachToSource(int page) {
    return '附到原文第 $page 页的这句话旁';
  }

  @override
  String get assistantNoteDefault => '笔记';

  @override
  String get assistantNoteTitle => '笔记标题';

  @override
  String get assistantBack => '返回';

  @override
  String get assistantKindWeb => '网页';

  @override
  String get assistantKindPaper => '论文';

  @override
  String get assistantKindVideo => '视频';

  @override
  String get assistantOpenInBrowser => '在浏览器打开';

  @override
  String assistantMapContext(String title) {
    return '脑图 · $title';
  }

  @override
  String assistantBranchContext(String title) {
    return '分支 · $title';
  }

  @override
  String assistantPageContext(String document, int page) {
    return '第 $page 页 · $document';
  }

  @override
  String assistantDocumentContext(String document) {
    return '整本 · $document';
  }

  @override
  String get assistantWholeMap => '整张脑图';

  @override
  String get assistantAutoContext => '自动附带';

  @override
  String get assistantRemoveContext => '移除';

  @override
  String assistantContextCount(int count) {
    return '引用 $count 项';
  }

  @override
  String get assistantManageContexts => '管理引用';

  @override
  String get assistantSelectionContext => '所选文字';

  @override
  String get assistantMoreActions => '更多';

  @override
  String assistantCurrentPage(int page) {
    return '第 $page 页';
  }

  @override
  String get assistantSkillExplain => '解释';

  @override
  String get assistantSkillTranslate => '翻译';

  @override
  String get assistantSkillVerify => '查证';

  @override
  String get assistantSkillSummarize => '总结';

  @override
  String get assistantSkillQuiz => '出复习题';

  @override
  String get assistantSkillQuizShort => '出题';

  @override
  String get assistantSkillOrganize => '整理进脑图';

  @override
  String get assistantSkillOrganizeShort => '整理';

  @override
  String get assistantSkillPapers => '找论文';

  @override
  String get assistantSkillVideos => '找视频';

  @override
  String get assistantPromptExplain => '解释一下这段话';

  @override
  String get assistantPromptTranslate => '翻译这段话';

  @override
  String get assistantPromptVerify => '查证这个说法';

  @override
  String get assistantPromptSummarize => '总结这部分的要点';

  @override
  String get assistantPromptQuiz => '为这部分出几道复习题';

  @override
  String get assistantPromptOrganize => '把这部分整理进脑图';

  @override
  String get assistantPromptPapers => '找相关的论文';

  @override
  String get assistantPromptVideos => '找相关的视频';

  @override
  String assistantSuggestSummarize(int page) {
    return '总结第 $page 页';
  }

  @override
  String assistantSuggestExplain(String title) {
    return '解释「$title」';
  }

  @override
  String assistantSuggestVerify(int page) {
    return '查证第 $page 页的一个说法';
  }

  @override
  String get assistantSuggestTranslate => '翻译所选内容';

  @override
  String assistantSuggestQuiz(String title) {
    return '为「$title」出复习题';
  }

  @override
  String get assistantSuggestOrganize => '把当前一节整理进脑图';

  @override
  String get assistantSavedKeyUnavailable => '无法读取 API Key，请重新填写并保存。';

  @override
  String get assistantKeySaveUnavailable => '暂时无法保存 API Key。输入内容仍保留在此处，可稍后重试；这不代表 Key 无效。';

  @override
  String get assistantPasteKey => '粘贴 API Key';

  @override
  String get assistantCannotConnect => '连不上服务';

  @override
  String assistantQuestions(int count) {
    return '$count 个问题';
  }

  @override
  String get assistantHasNote => '有笔记';

  @override
  String get assistantRunning => '生成中';

  @override
  String get assistantUnfinished => '未完成';

  @override
  String get assistantFailed => '失败';

  @override
  String get assistantDeleteEllipsis => '删除…';

  @override
  String get assistantDeleteTitle => '删除这个对话？';

  @override
  String get assistantDeleteMessage => '已存的笔记会保留。';

  @override
  String get assistantRenameConversation => '重命名对话';

  @override
  String get assistantExplainTopic => '解释这个主题';

  @override
  String get assistantExplainCard => '解释这张卡片';

  @override
  String get assistantOrganizeBranch => '整理这个分支…';

  @override
  String get assistantQuizBranch => '为这个分支出复习题…';

  @override
  String get assistantVerifyCard => '查证这张卡片';

  @override
  String get assistantAskWith => '带上它自由提问…';

  @override
  String get assistantAnchorGone => '原位置已删除';

  @override
  String get assistantOpenConversation => '打开原对话';

  @override
  String get assistantAskMore => '继续问';

  @override
  String get settingsGeneral => '通用';

  @override
  String get settingsReading => '阅读';

  @override
  String get settingsModels => '模型';

  @override
  String get settingsWebSearch => '网页搜索';

  @override
  String get settingsDefaultModel => '默认模型';

  @override
  String get settingsServices => '服务';

  @override
  String settingsServiceModels(int count) {
    return '已启用 $count 个模型';
  }

  @override
  String get settingsServiceNoModels => '还没有模型';

  @override
  String get settingsServiceOff => '已停用';

  @override
  String get settingsName => '名称';

  @override
  String get settingsAddress => '地址';

  @override
  String get settingsShowKey => '显示';

  @override
  String get settingsHideKey => '隐藏';

  @override
  String get settingsSetDefault => '设为默认';

  @override
  String get settingsIsDefault => '默认';

  @override
  String get settingsRemoveModel => '移除';

  @override
  String get settingsAddModel => '添加模型…';

  @override
  String get settingsCustomAddress => '使用自定义地址';

  @override
  String get settingsRemoveService => '移除服务';

  @override
  String settingsRemoveServiceTitle(String name) {
    return '移除“$name”？';
  }

  @override
  String get settingsRemoveServiceMessage => '它的 API Key 会一并删除，对话会保留。';

  @override
  String get settingsAddService => '添加服务';

  @override
  String get settingsAddModelTitle => '添加模型';

  @override
  String get settingsSearchModels => '搜索，或输入模型 ID';

  @override
  String get settingsAdded => '已添加';

  @override
  String settingsAddManual(String id) {
    return '添加“$id”';
  }

  @override
  String get settingsAdd => '添加';

  @override
  String settingsAddCount(int count) {
    return '添加 $count 个';
  }

  @override
  String get settingsOpenAiCompatible => 'OpenAI 兼容';

  @override
  String get settingsOllamaLocal => 'Ollama（本机）';

  @override
  String get settingsSearchService => '搜索服务';

  @override
  String get settingsSearchUnconfigured => '未配置';

  @override
  String get settingsAccountId => '账户 ID';

  @override
  String get settingsTokenInvalid => 'API Token 无效';

  @override
  String get settingsSearchUnreachable => '连不上搜索服务';

  @override
  String get assistantManageModels => '管理模型…';

  @override
  String get assistantModel => '模型';

  @override
  String get assistantThinking => '思考中…';

  @override
  String assistantWorkedFor(int seconds) {
    return '处理了 $seconds 秒';
  }

  @override
  String assistantToolFailures(int count) {
    return '工具调用失败 $count 次';
  }

  @override
  String get assistantAnswerWithoutTools => '不用工具重答';

  @override
  String get assistantSwitchModel => '换模型重试';

  @override
  String get assistantCopyDiagnostics => '复制诊断信息';

  @override
  String get assistantDetails => '详情';

  @override
  String get assistantDiagnosticModel => '模型';

  @override
  String get assistantDiagnosticHost => '地址';

  @override
  String get assistantDiagnosticStatus => 'HTTP 状态码';

  @override
  String get assistantDiagnosticTools => '失败的工具';

  @override
  String get assistantDiagnosticReason => '停止原因';

  @override
  String get assistantDiagnosticRequest => '请求 ID';

  @override
  String get settingsVoice => '语音输入';

  @override
  String get voiceService => '语音服务商';

  @override
  String get voiceDisabled => '未启用';

  @override
  String get voiceDoubao => '豆包实时语音识别 2.0';

  @override
  String get voiceAliyun => '阿里云实时语音识别';

  @override
  String get voiceAuthentication => '鉴权方式';

  @override
  String get voiceResource => '资源类型';

  @override
  String get voiceDuration => '2.0 小时版';

  @override
  String get voiceConcurrent => '2.0 并发版';

  @override
  String get voicePrivacy => '录音会发送给所选服务商进行识别，密钥保存在本机钥匙串。';

  @override
  String get voiceTest => '测试连接';

  @override
  String get voiceSave => '保存';

  @override
  String get voiceTestPassed => '连接正常';

  @override
  String get voiceSaved => '已保存';

  @override
  String get voiceSaveError => '保存失败，请检查钥匙串访问权限。';

  @override
  String get voiceKeyError => '无法读取密钥，请检查钥匙串访问权限。';

  @override
  String get voiceConfigurationError => '请在语音设置中补全服务配置和密钥。';

  @override
  String get voiceConnectionError => '语音服务连接失败，请检查网络、密钥及服务是否已开通。';

  @override
  String get voicePermissionError => '未获得麦克风权限，请在系统设置中允许访问。';

  @override
  String get voiceRecordingError => '麦克风录音中断，请检查设备后重试。';

  @override
  String get voiceTimeoutError => '语音服务响应超时，请重试。';

  @override
  String get voiceEmptyError => '没有识别到语音，请再试一次。';

  @override
  String get voiceConnecting => '正在连接语音服务…';

  @override
  String get voiceListening => '正在聆听，点击结束';

  @override
  String get voiceFinishing => '正在确认识别结果…';

  @override
  String get voiceCancel => '取消语音输入';

  @override
  String get voiceFinish => '结束录音';

  @override
  String get voiceKeyPlaceholder => '粘贴密钥';

  @override
  String get mapMultiSelect => '多选';

  @override
  String get voiceAppIdPlaceholder => '填写 App ID';

  @override
  String get settingsNamePlaceholder => '填写服务名称';

  @override
  String get settingsAccountIdPlaceholder => '填写账户 ID';

  @override
  String get settingsApiTokenPlaceholder => '粘贴 API Token';

  @override
  String get settingsSaveFailed => '保存失败，请重试';

  @override
  String get settingsSaving => '正在保存…';

  @override
  String get settingsUnsaved => '未保存';

  @override
  String get settingsSaveBeforeModels => '请先保存服务配置，再获取模型';

  @override
  String get settingsRequiredFields => '请填写必填项后保存';

  @override
  String get assistantModelSetupTitle => '配置 AI 助手';

  @override
  String get assistantModelUnavailableTitle => '模型暂不可用';

  @override
  String get assistantConfigureModels => '配置模型';

  @override
  String get microphonePermission => '录制音频以转写文字。';

  @override
  String get localNetworkPermission => '连接你的本地模型服务。';

  @override
  String get assistantOpenModelSettings => '打开模型设置 →';

  @override
  String get assistantSetupHint => '添加模型后即可使用';

  @override
  String get assistantKeyNeedsAttention => '请重新填写 API Key';

  @override
  String get assistantQuickTitle => 'AI 助手';

  @override
  String get assistantQuickExplain => '解释这段';

  @override
  String get assistantQuickSummarize => '总结要点';

  @override
  String get assistantQuickOutline => '整理大纲';

  @override
  String get assistantQuickOutlinePrompt => '请将所选文字整理为清晰的文字大纲，梳理主要观点及其层次。直接在回答中展示大纲，不要修改脑图。';

  @override
  String get assistantQuickAsk => '或直接问一个问题…';

  @override
  String get assistantQuickFollowUp => '继续问这段内容…';

  @override
  String get assistantQuickSidebar => '在侧边栏继续对话';

  @override
  String get assistantQuickBusy => '另一个对话正在回答，完成后即可提问。';

  @override
  String get assistantQuickChanged => '此对话已切换，可在侧边栏继续查看。';

  @override
  String get assistantQuickGenerated => 'AI 生成内容';

  @override
  String get assistantQuickSelection => '已选文字';

  @override
  String get cropMargins => '裁掉白边';

  @override
  String get uncropMargins => '取消裁边';

  @override
  String get cropAdjust => '调整裁边';

  @override
  String get cropScopeAll => '所有页';

  @override
  String get cropScopeOddEven => '奇偶页分开';

  @override
  String get cropScopePage => '仅本页';

  @override
  String get cropAuto => '自动';

  @override
  String get cropNone => '不裁';

  @override
  String get cropOddPages => '奇数页';

  @override
  String get cropEvenPages => '偶数页';

  @override
  String get cropCustomPage => '单独设置';

  @override
  String cropHiddenAnnotations(int count) {
    return '$count 处标注将被隐藏';
  }

  @override
  String get croppedHud => '已裁边';

  @override
  String get uncroppedHud => '已取消裁边';

  @override
  String get marginNotes => '页边批注';

  @override
  String get marginNoteAction => '批注';

  @override
  String get writeMarginNote => '+ 写批注';

  @override
  String get showMarginNotes => '显示页边批注';

  @override
  String get hideMarginNotes => '隐藏页边批注';

  @override
  String get expandMargin => '显示页边';

  @override
  String get cropExpandMargin => '裁掉白边，展开页边';

  @override
  String get marginNoteDeleted => '已删除批注';

  @override
  String get marginNoteAddedToMap => '已加入脑图';

  @override
  String get compareReading => '对照阅读';

  @override
  String get compareRecommended => '推荐';

  @override
  String compareAiTranslate(String language) {
    return 'AI 逐段翻译成$language';
  }

  @override
  String get languageChinese => '中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageCodeZh => '中';

  @override
  String get languageCodeEn => 'EN';

  @override
  String get compareAiOffline => '断网';

  @override
  String get compareAiNeedsOcr => '先识别文字';

  @override
  String get compareAiPending => '暂未提供';

  @override
  String get compareTooNarrow => '窗口太窄';

  @override
  String get compareExit => '退出对照阅读';

  @override
  String get compareSync => '同步滚动';

  @override
  String get compareAlign => '对齐此处';

  @override
  String get compareAlignedHud => '已对齐';

  @override
  String get compareSwap => '左右互换';

  @override
  String compareMapHiddenHud(String shortcut) {
    return '已收起脑图 · $shortcut';
  }

  @override
  String compareTranslationProgress(int done, int total) {
    return '翻译中 $done/$total';
  }

  @override
  String get compareTranslationSaved => '已保存';

  @override
  String get compareTranslationFailed => '翻译失败';

  @override
  String get compareTranslationPageEmpty => '此页没有可翻译文字';

  @override
  String compareTranslationPageSaved(int page) {
    return '第 $page 页已保存';
  }

  @override
  String compareTranslationPageProgress(int page, int done, int total) {
    return '第 $page 页翻译中 $done/$total';
  }

  @override
  String get chooseHighlightColor => '选择高亮颜色';

  @override
  String get moreHighlightColors => '更多颜色';

  @override
  String get selectionTranslate => '翻译';

  @override
  String get selectionTranslationDirection => '划词翻译方向';

  @override
  String get selectionTranslationAutomatic => '自动（中英互译）';

  @override
  String get selectionTranslationEnglishToChinese => '英文 → 中文';

  @override
  String get selectionTranslationChineseToEnglish => '中文 → 英文';

  @override
  String get selectionTranslationLoading => '正在翻译…';

  @override
  String get selectionTranslationFailed => '翻译失败，请检查模型配置或网络后重试。';

  @override
  String get selectionTranslationOffline => '当前处于离线模式。请启用联网或选择本地模型后重试。';

  @override
  String get selectionTranslationTooLong => '所选内容过长，请缩小选区后再翻译。';

  @override
  String get selectionTranslationCopy => '复制译文';

  @override
  String get highlightCustomColor => '自定义颜色';

  @override
  String get highlightColorHue => '色相';

  @override
  String get highlightColorSaturationValue => '饱和度和明暗';

  @override
  String get highlightColorHex => '颜色代码';

  @override
  String get highlightColorHexInvalid => '请输入六位十六进制颜色，例如 #12A4B8';

  @override
  String get translationSourceLanguage => '原文语言';

  @override
  String get translationTargetLanguage => '译文语言';

  @override
  String get translationDetectLanguage => '自动检测';

  @override
  String get translationSwapLanguages => '互换原文与译文';

  @override
  String get translationSameLanguage => '请选择不同的原文和译文语言。';

  @override
  String get translationTraditionalChinese => '繁体中文';

  @override
  String get translationJapanese => '日语';

  @override
  String get translationKorean => '韩语';

  @override
  String get translationFrench => '法语';

  @override
  String get translationGerman => '德语';

  @override
  String get translationSpanish => '西班牙语';

  @override
  String get translationPortuguese => '葡萄牙语';

  @override
  String get translationItalian => '意大利语';

  @override
  String get translationRussian => '俄语';

  @override
  String get translationArabic => '阿拉伯语';

  @override
  String get translationChooseSourceToSwap => '先选择原文语言，再互换方向';

  @override
  String get translationChinese => '中文';

  @override
  String get translationEnglish => '英文';

  @override
  String get editBookmark => '编辑书签…';

  @override
  String get addOutlineEntry => '新增目录条目…';

  @override
  String get addOutlineChild => '新增子目录…';

  @override
  String get editOutlineEntry => '编辑目录条目…';

  @override
  String get deleteOutlineEntry => '删除目录条目';

  @override
  String get deleteOutlineBranch => '删除条目及其子目录';

  @override
  String get noOutlineEntries => '没有目录，点击 + 新增条目';

  @override
  String get outlineNoDestination => '页码填 0 表示不跳转的分组标题';

  @override
  String get readerEntryActions => '条目操作';

  @override
  String get readerDragToMove => '拖动调整顺序';

  @override
  String get readerSortPageAscending => '按页码升序';

  @override
  String get readerSortPageDescending => '按页码降序';

  @override
  String get readerSortTitle => '按名称排序';

  @override
  String get bookmarkPageOccupied => '这一页已有书签，请编辑已有书签';

  @override
  String readerInvalidPage(int count) {
    return '请输入有效页码，最大为 $count';
  }

  @override
  String get outlineDragHint => '拖到条目上方或下方调整顺序，拖到中间成为子目录';

  @override
  String get toolUnderline => '下划线';

  @override
  String get lineSolid => '实线';

  @override
  String get lineDashed => '虚线';

  @override
  String get lineDotted => '点线';

  @override
  String get lineWavy => '波浪线';

  @override
  String get underlinedHud => '已添加下划线';

  @override
  String get deleteUnderline => '删除下划线';

  @override
  String get underlineDeletedHud => '已删除下划线';

  @override
  String mergeNodes(int count) {
    return '合并 $count 个节点';
  }

  @override
  String splitNodes(int count) {
    return '拆分为 $count 个节点';
  }

  @override
  String selectedNodes(int count) {
    return '已选 $count 个';
  }

  @override
  String get mergedNodes => '已合并节点';

  @override
  String mergeCleanup(int relations, int summaries) {
    return '已移除 $relations 条关联线和 $summaries 个概要';
  }

  @override
  String mergedSources(int count) {
    return '$count 处原文 · 已合并';
  }

  @override
  String get relationNeedsTwo => '请选择两个节点';

  @override
  String get mapEditTooFewCards => '请至少选择两个节点';

  @override
  String get mapEditMissingCard => '选中的节点已不可用';

  @override
  String get mapEditCenterTopic => '不能操作中心主题';

  @override
  String get mapEditImageCard => '图片卡片不能合并';

  @override
  String get mapEditSummaryTopic => '不能操作概要主题';

  @override
  String get mapEditUnsupportedCard => '此类卡片不能合并';

  @override
  String get mapEditNotMerged => '此卡片没有可拆分的段落';

  @override
  String get mapEditDifferentParents => '请选择同一父主题下的节点';

  @override
  String get mapEditOverlappingSummary => '范围与现有概要重叠';

  @override
  String get mapEditMissingSummary => '概要已不可用';

  @override
  String get nodeBarChild => '子主题';

  @override
  String get nodeBarSibling => '同级';

  @override
  String get nodeBarNote => '记笔记';

  @override
  String get nodeBarImage => '图片';

  @override
  String get nodeBarAssistant => 'AI';

  @override
  String get selectionMerge => '合并';

  @override
  String get selectionSummary => '概要';

  @override
  String get selectionRelation => '关联';

  @override
  String get selectionDelete => '删除';

  @override
  String get relationArrowEnd => '单向箭头';

  @override
  String get relationArrowBoth => '双向箭头';

  @override
  String get relationArrowNone => '无箭头';

  @override
  String get relationReverse => '交换方向';

  @override
  String get relationLineStyle => '实线 / 虚线';

  @override
  String summaryIncludedNodes(int count) {
    return '包含了中间未选中的 $count 个节点';
  }

  @override
  String get addWebPage => '添加网页…';

  @override
  String get webUrlPlaceholder => '网址';

  @override
  String get webUrlEmpty => '请输入网址';

  @override
  String get webUrlInvalid => '网址无效';

  @override
  String get webUrlScheme => '只支持 http 和 https';

  @override
  String get browserBack => '后退';

  @override
  String get browserForward => '前进';

  @override
  String get browserReload => '重新载入';

  @override
  String get browserStop => '停止';

  @override
  String get browserClose => '关闭网页';

  @override
  String get browserConvert => '转换为文档…';

  @override
  String get browserConvertShort => '转换';

  @override
  String get webReadyPrompt => '转换为文档？';

  @override
  String get webStillLoading => '部分内容仍在加载';

  @override
  String get webLater => '稍后';

  @override
  String get webErrorTitle => '无法打开页面';

  @override
  String get webRetry => '重试';

  @override
  String get settingsClearWebsiteData => '清除…';

  @override
  String get clearWebsiteDataConfirm => '清除所有网站数据？';

  @override
  String get websiteDataCleared => '已清除网站数据';

  @override
  String get addWebTitle => '添加网页';

  @override
  String get webKeepWaiting => '继续等待';

  @override
  String get webConvertAction => '转换';

  @override
  String get webErrorTimeout => '连接超时';

  @override
  String get webErrorHost => '找不到服务器';

  @override
  String get webErrorCertificate => '证书无效';

  @override
  String get webErrorOffline => '未连接网络';

  @override
  String get settingsBrowserGroup => '内置浏览器';

  @override
  String get settingsWebsiteData => '网站数据';

  @override
  String get clearAction => '清除';

  @override
  String get browserUnsaved => '未保存';

  @override
  String get addDocumentMenu => '添加';

  @override
  String get documentFiles => '文档';

  @override
  String unsupportedFile(String name) {
    return '不支持「$name」';
  }

  @override
  String get readingSettings => '阅读设置';

  @override
  String get cancelImport => '取消导入';

  @override
  String get okAction => '好';

  @override
  String importFailedTitle(String name) {
    return '无法导入「$name」';
  }

  @override
  String importFailedMany(int count) {
    return '$count 份文档无法导入';
  }

  @override
  String get importErrorDrm => '受 DRM 保护';

  @override
  String get importErrorDamaged => '文件已损坏';

  @override
  String get importErrorKfx => '不支持 KFX 格式';

  @override
  String get importErrorEmpty => '没有可读内容';

  @override
  String get importErrorUnsupported => '不支持此格式';

  @override
  String get readerFontSmaller => '缩小字号';

  @override
  String get readerFontLarger => '增大字号';

  @override
  String get readerLineTight => '紧凑';

  @override
  String get readerLineNormal => '适中';

  @override
  String get readerLineLoose => '宽松';

  @override
  String get readerFontOriginal => '原书';

  @override
  String get readerFontSerif => '宋体';

  @override
  String get readerFontSans => '黑体';

  @override
  String get readerModePaged => '翻页';

  @override
  String get readerModeScroll => '滚动';

  @override
  String get readerPositionMissing => '找不到原文位置';

  @override
  String get readerLoadFailed => '无法打开文档';

  @override
  String get readerNeedsReview => '需要确认';

  @override
  String get readerRetry => '重试';

  @override
  String get readerNoOutline => '没有目录';

  @override
  String get readerSelectionStart => '选区起点';

  @override
  String get readerSelectionEnd => '选区终点';

  @override
  String get convertTitle => '转换为文档';

  @override
  String get convertTitlePlaceholder => '标题';

  @override
  String get convertReadable => '阅读模式';

  @override
  String get convertPdf => 'PDF';

  @override
  String get convertMarkdown => 'Markdown';

  @override
  String get docSaving => '正在保存';

  @override
  String docSaved(String title) {
    return '已保存「$title」';
  }

  @override
  String get docSaveFailed => '保存失败';

  @override
  String get docUpdated => '已更新';

  @override
  String annotationsNeedReview(int count) {
    return '需要确认 $count';
  }

  @override
  String annotationsNeedReviewHud(int count) {
    return '$count 处标注需要确认';
  }

  @override
  String get viewAction => '查看';

  @override
  String get openOriginalPage => '打开原网页';

  @override
  String get refetchPage => '重新抓取';

  @override
  String get browserUpdate => '更新文档';

  @override
  String get webUpdatePrompt => '更新文档？';

  @override
  String get webUpdateAction => '更新';

  @override
  String webSource(String domain, DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return '$domain · $dateString';
  }

  @override
  String get annotationNotFound => '找不到原文位置';

  @override
  String get vocabularyTitle => '生词本';

  @override
  String get vocabularyLookup => '查词（T）';

  @override
  String get vocabularyTranslate => '翻译（T）';

  @override
  String get vocabularyAdd => '加入生词本';

  @override
  String get vocabularyAdded => '已加入生词本';

  @override
  String get vocabularyLearning => '学习中';

  @override
  String get vocabularyKnown => '已掌握';

  @override
  String get vocabularyView => '在生词本中查看';

  @override
  String get vocabularyMarkKnown => '标为已掌握';

  @override
  String get vocabularyRemove => '移出生词本';

  @override
  String get vocabularyExample => '收录为例句';

  @override
  String get vocabularySentence => '翻译整句';

  @override
  String get vocabularyDetails => '详情 ›';

  @override
  String get vocabularyLongSelection => '生词本收录单词和 8 个词以内的短语';

  @override
  String get vocabularySettings => '打开设置';

  @override
  String get vocabularySpeak => '朗读';

  @override
  String get vocabularySetup => '未设置模型';

  @override
  String get vocabularyOffline => '联网已关闭';

  @override
  String get vocabularyUK => '英';

  @override
  String get vocabularyUS => '美';

  @override
  String get vocabularySearch => '搜索单词、释义';

  @override
  String get vocabularyThisSet => '本学习集';

  @override
  String get vocabularyAll => '全部';

  @override
  String get vocabularyToday => '今天';

  @override
  String get vocabularyEarlier => '更早';

  @override
  String get vocabularyNoMatch => '没有匹配的词';

  @override
  String get vocabularyEmpty => '这里还没有词';

  @override
  String get vocabularyOccurrences => '本文出现次数';

  @override
  String get vocabularySenses => '释义';

  @override
  String get vocabularyRegenerate => '重新生成';

  @override
  String get vocabularyModelRequired => '未设置模型';

  @override
  String get vocabularyGloss => '行间释义';

  @override
  String get vocabularyNote => '笔记';

  @override
  String get vocabularyForms => '词形';

  @override
  String get vocabularyForgetForm => '不再识别';

  @override
  String get vocabularyExamples => '例句';

  @override
  String get vocabularyNoExamples => '没有例句。';

  @override
  String get vocabularyReturn => '回到原文';

  @override
  String get vocabularyOpenSet => '打开学习集 ›';

  @override
  String get vocabularyDeleteExample => '删除这条例句';

  @override
  String get vocabularyLearnAgain => '重新学习';

  @override
  String get vocabularyDelete => '从生词本删除';

  @override
  String get vocabularyRemoved => '已移除';

  @override
  String get vocabularyExampleDeleted => '已删除例句';

  @override
  String get vocabularyRead => '朗读';

  @override
  String get vocabularyUk => '英';

  @override
  String get vocabularyUs => '美';

  @override
  String get vocabularyAddForm => '添加';

  @override
  String get vocabularyHints => '生词提示';

  @override
  String get vocabularyHintsOff => '关闭';

  @override
  String get vocabularyHintsUnderline => '仅下划线';

  @override
  String get vocabularyHintsGloss => '显示释义';

  @override
  String get vocabularyHintsHidden => '本文档隐藏';

  @override
  String get vocabularyHintsKnown => '标出已掌握';

  @override
  String get mapIdeaMenu => 'AI 扩展想法';

  @override
  String get mapIdeaExpand => '扩展想法';

  @override
  String mapIdeaExpandEach(int count) {
    return '分别扩展 $count 个主题';
  }

  @override
  String get mapIdeaExpandMap => '扩展整张脑图…';

  @override
  String get mapIdeaWholeMap => '扩展整张脑图';

  @override
  String get mapIdeaBranchesOnly => '只加新分支';

  @override
  String get mapIdeaGroup => '归纳上级主题';

  @override
  String get mapIdeaFillSiblings => '补全同级';

  @override
  String get mapIdeaDirection => '方向';

  @override
  String get mapIdeaDirectionAuto => '自动';

  @override
  String get mapIdeaDirectionWhy => '原因';

  @override
  String get mapIdeaDirectionExample => '例子';

  @override
  String get mapIdeaDirectionCounter => '反方';

  @override
  String get mapIdeaDirectionQuestion => '问题';

  @override
  String get mapIdeaDirectionAction => '行动';

  @override
  String get mapIdeaDepth => '层级';

  @override
  String mapIdeaDepthLevels(int count) {
    return '$count 层';
  }

  @override
  String get mapIdeaAmount => '数量';

  @override
  String get mapIdeaAmountFew => '少';

  @override
  String get mapIdeaAmountSome => '适中';

  @override
  String get mapIdeaAmountMany => '多';

  @override
  String get mapIdeaHint => '补充要求';

  @override
  String get mapIdeaGrounded => '参考原文';

  @override
  String mapIdeaExpanding(String title) {
    return '扩展「$title」';
  }

  @override
  String mapIdeaExpandingCount(int count) {
    return '扩展 $count 个主题';
  }

  @override
  String get mapIdeaIncompleteDepth => '部分分支未达到所选层级，可换一批重试';

  @override
  String get mapIdeaStopped => '已停止';

  @override
  String mapIdeaDraftCount(int count) {
    return '$count 条';
  }

  @override
  String mapIdeaKeptCount(int kept, int total) {
    return '保留 $kept / $total';
  }

  @override
  String get mapIdeaRegenerate => '换一批';

  @override
  String get mapIdeaAdjust => '调整';

  @override
  String get mapIdeaRegenerateAdjusted => '重新生成';

  @override
  String get mapIdeaDiscard => '放弃';

  @override
  String mapIdeaKeep(int count) {
    return '保留 $count 条';
  }

  @override
  String get mapIdeaDraftKeep => '保留';

  @override
  String get mapIdeaDraftSkip => '不要';

  @override
  String get mapIdeaDraftEdit => '修改';

  @override
  String get mapIdeaDraftMore => '继续扩展';

  @override
  String mapIdeaDraftSemantics(String title, String state) {
    return 'AI 草稿，$title，$state';
  }

  @override
  String get mapIdeaDraftKept => '已保留';

  @override
  String get mapIdeaDraftSkipped => '未保留';

  @override
  String get mapIdeaNewBranches => '新分支';

  @override
  String mapIdeaAddCount(int count) {
    return '+$count';
  }

  @override
  String get mapIdeaFewer => '减少';

  @override
  String get mapIdeaMore => '增加';

  @override
  String get mapIdeaGenerate => '扩展';

  @override
  String get mapIdeaStart => '开始扩展';

  @override
  String mapIdeaAdded(int count) {
    return '已添加 $count 个主题';
  }

  @override
  String get mapIdeaBlocked => '请先保留或放弃扩展内容，再继续操作';

  @override
  String get mapIdeaNothing => '这里暂时没有值得补充的方向，换个方向试试';

  @override
  String get mapIdeaStoppedEmpty => '已停止，没有生成内容';

  @override
  String get mapIdeaBusy => '模型正忙，请稍后再试';

  @override
  String get mapGenerate => '生成脑图';

  @override
  String get mapGenerateMenu => '从文档生成…';

  @override
  String get mapGenerateDocumentMenu => '生成脑图…';

  @override
  String get mapGenerateUpdate => '更新脑图';

  @override
  String get mapGenerateRunning => '生成中';

  @override
  String get mapGenerateReviewing => '审阅中';

  @override
  String get mapHasUpdates => '有新内容';

  @override
  String get mapHasMap => '已有脑图';

  @override
  String get mapEmptyGenerateTitle => '从资料生成脑图';

  @override
  String get mapEmptyGenerateSubtitle => '提炼重点，梳理结构，保留原文脉络';

  @override
  String get mapEmptySourceStart => '从这份资料开始';

  @override
  String get mapEmptyInstructionsPlaceholder => '例如：按事件经过、影响和应对措施整理';

  @override
  String mapGenerateFrom(String document) {
    return '从「$document」生成脑图';
  }

  @override
  String get mapGenerateSettings => '设置';

  @override
  String get mapGenerateStart => '生成';

  @override
  String get mapGenerateBlank => '新建空白主题';

  @override
  String get mapGenerateSuggestExam => '侧重考试要点';

  @override
  String get mapGenerateSuggestExplain => '每个主题附一句解释';

  @override
  String get mapGenerateSuggestQuotes => '保留原文关键句';

  @override
  String get mapGenerateSuggestExamples => '举例说明';

  @override
  String get mapGenerateDocuments => '文档';

  @override
  String mapGeneratePages(int count) {
    return '$count 页';
  }

  @override
  String mapGenerateSegments(int count) {
    return '分 $count 段阅读';
  }

  @override
  String get mapGenerateNeedsOcr => '需先识别文字';

  @override
  String get mapGenerateWholeDocument => '全文';

  @override
  String mapGenerateChapterCount(int selected, int total) {
    return '$selected / $total 章';
  }

  @override
  String get mapGenerateOrganization => '组织方式';

  @override
  String get mapGenerateByChapter => '按原文章节';

  @override
  String get mapGenerateByTopic => '按主题重组';

  @override
  String get mapGenerateMergeByTopic => '按主题合并';

  @override
  String get mapGenerateByQuestion => '按问题组织';

  @override
  String get mapGenerateDetail => '详细程度';

  @override
  String get mapGenerateDetailBrief => '概要';

  @override
  String get mapGenerateDetailMedium => '适中';

  @override
  String get mapGenerateDetailFull => '详细';

  @override
  String mapGenerateEstimate(int levels, int count) {
    return '$levels 层 · 约 $count 个主题';
  }

  @override
  String get mapGenerateContent => '内容';

  @override
  String get mapGenerateMyMarks => '放入我的高亮和批注';

  @override
  String mapGenerateMarkCount(int count) {
    return '$count 条';
  }

  @override
  String get mapGenerateQuotes => '摘录原文关键句';

  @override
  String get mapGenerateTarget => '生成到';

  @override
  String get mapGenerateTargetNew => '新脑图';

  @override
  String get mapGenerateTargetBranch => '当前脑图的新分支';

  @override
  String mapGenerateTargetReplace(String title) {
    return '替换「$title」';
  }

  @override
  String get mapGenerateInstructions => '要求';

  @override
  String mapGenerateReading(String document) {
    return '阅读「$document」';
  }

  @override
  String get mapGenerateBuilding => '生成脑图';

  @override
  String mapGenerateTopicCount(int count) {
    return '$count 个主题';
  }

  @override
  String get mapGenerateQueued => '等待中';

  @override
  String mapGenerateChapterFailed(String chapter) {
    return '「$chapter」未生成';
  }

  @override
  String get mapGenerateBlocked => '请先保留或放弃生成的脑图，再继续操作';

  @override
  String get mapGenerateBlockedRunning => '正在生成内容，请等待完成，或点击“停止”';

  @override
  String mapGenerateCreated(String title, int count) {
    return '已生成脑图「$title」 · $count 个主题';
  }

  @override
  String get mapGenerateNothing => '没有得到可用的结构，换个组织方式试试';

  @override
  String get mapGenerateStoppedEmpty => '已停止，没有生成内容';

  @override
  String mapGenerateDraftSemantics(String title, int page, String state) {
    return 'AI 草稿，$title，第 $page 页，$state';
  }

  @override
  String mapGenerateReadProgress(int done, int total) {
    return '已读 $done / $total 章';
  }

  @override
  String mapGenerateReady(int count) {
    return '可以审阅，$count 个主题';
  }

  @override
  String mapSourceSemantics(String document, int page) {
    return '$document，第 $page 页';
  }

  @override
  String mapBannerNoMap(String document) {
    return '「$document」还没有脑图';
  }

  @override
  String get mapBannerGenerate => '生成新脑图';

  @override
  String get mapBannerMerge => '并入当前脑图';

  @override
  String get mapBannerNeedsOcr => '先识别文字才能生成';

  @override
  String mapFollowSwitched(String title) {
    return '已切换到「$title」';
  }

  @override
  String get mapUpdateDescription => '选择更新依据，预览并确认改动后再应用到脑图。';

  @override
  String mapUpdateReadBaseline(int page) {
    return '上次更新至第 $page 页';
  }

  @override
  String get mapUpdateTitle => '更新脑图';

  @override
  String get mapUpdateSources => '更新依据';

  @override
  String get mapUpdateAddDocument => '添加文档';

  @override
  String get mapUpdateSince => '上次生成之后';

  @override
  String get mapUpdateNewHighlights => '新增高亮';

  @override
  String get mapUpdateNewNotes => '新增批注';

  @override
  String get mapUpdateReadTo => '读到';

  @override
  String mapUpdateReadRange(int from, int to) {
    return 'p.$from → p.$to';
  }

  @override
  String get mapUpdateScope => '更新范围';

  @override
  String get mapUpdateScopeNew => '只处理新内容';

  @override
  String get mapUpdateScopeAll => '全文重新梳理';

  @override
  String mapUpdateProtected(int count) {
    return '你改过、添加的 $count 个节点保持不变';
  }

  @override
  String get mapUpdatePreview => '预览更改';

  @override
  String get mapUpdateNothing => '没有需要更新的内容';

  @override
  String get mapDiffAdded => '新增';

  @override
  String get mapDiffRenamed => '改名';

  @override
  String get mapDiffMoved => '移动';

  @override
  String get mapDiffRemoved => '建议删除';

  @override
  String get mapDiffTagNew => '新';

  @override
  String mapDiffTagMovedFrom(String from) {
    return '移自 $from';
  }

  @override
  String get mapDiffTagRemove => '建议删除';

  @override
  String mapDiffMoveRoute(String from, String to) {
    return '从「$from」移到「$to」';
  }

  @override
  String mapDiffExcerpt(String text) {
    return '摘录：$text';
  }

  @override
  String get mapDiffProtected => '受保护';

  @override
  String mapUpdateApply(int count) {
    return '应用 $count 项';
  }

  @override
  String mapUpdateApplied(int count) {
    return '已更新 $count 处';
  }

  @override
  String get mapUpdateBlocked => '请先应用或放弃脑图更新，再继续操作';

  @override
  String mapDiffAddSemantics(String title) {
    return '建议新增，$title';
  }

  @override
  String mapDiffRenameSemantics(String old, String title) {
    return '建议改名，$old 改为 $title';
  }

  @override
  String mapDiffMoveSemantics(String title, String from, String to) {
    return '建议移动，$title，从$from移到$to';
  }

  @override
  String mapDiffRemoveSemantics(String title, String reason) {
    return '建议删除，$title，$reason';
  }

  @override
  String get settingsMapFollowDocument => '随文档切换脑图';

  @override
  String get settingsMapClearCache => '清除生成缓存';

  @override
  String get notesTitle => '笔记';

  @override
  String get organizeStudyNote => '整理学习笔记…';

  @override
  String get organizeNotes => '整理笔记';

  @override
  String get organizeSelection => '整理成笔记';

  @override
  String get exportStudyNote => '导出笔记…';

  @override
  String get noteMoreOptions => '更多选项';

  @override
  String get noteSetupTitle => '整理学习笔记';

  @override
  String get noteScope => '范围';

  @override
  String get noteMaterials => '素材';

  @override
  String get noteOrganization => '组织方式';

  @override
  String get noteDepth => 'AI 参与';

  @override
  String get noteContext => '上下文';

  @override
  String get noteTemplate => '版式';

  @override
  String get noteSelected => '选中的划线';

  @override
  String get noteWhole => '整个学习集';

  @override
  String get noteRecent => '最近 7 天';

  @override
  String get noteHighlights => '划线';

  @override
  String get noteOwn => '我的批注';

  @override
  String get noteMapNotes => '脑图笔记';

  @override
  String get noteSavedAi => '已存的 AI 笔记';

  @override
  String get noteImages => '图片卡片';

  @override
  String get noteTheme => '按主题归纳';

  @override
  String get noteSourceOrder => '按原文顺序';

  @override
  String get noteMapOrder => '按脑图结构';

  @override
  String get noteLocal => '只排版';

  @override
  String get noteAiContext => '补全与小结';

  @override
  String get noteAiDeep => '深度整理';

  @override
  String get noteNextPhase => '下一期开放';

  @override
  String get noteComplete => '补全指代';

  @override
  String get noteReading => '读书笔记';

  @override
  String get noteCornell => '康奈尔笔记';

  @override
  String get noteReview => '复习提纲';

  @override
  String get noteGenerate => '生成笔记';

  @override
  String get noteEmptyScope => '这个范围还没有划线';

  @override
  String get noteGenerated => '已生成';

  @override
  String get noteFailureAuthentication => '模型服务验证未通过。请检查模型设置中的密钥，或改为只排版。';

  @override
  String get noteFailureTimeout => '模型响应超时。可继续整理，保留已完成的内容，也可改为只排版。';

  @override
  String get noteFailureBudget => '模型单次输出未完成。可继续整理重试，或改为只排版。';

  @override
  String get noteFailureNetwork => '无法连接模型服务。请检查网络后继续整理，或改为只排版。';

  @override
  String get noteFailureService => '模型服务繁忙或暂时不可用。可稍后继续整理，或改为只排版。';

  @override
  String get noteFailureProtocol => '模型返回的内容不完整或不受支持。可继续整理重试，或改为只排版。';

  @override
  String get noteFailed => '整理失败';

  @override
  String get noteUnused => '未用上';

  @override
  String get notePutBack => '放回笔记';

  @override
  String get noteRestored => '已放入笔记';

  @override
  String get noteRemoved => '已从笔记中移除';

  @override
  String get noteExpandContext => '展开上下文';

  @override
  String get noteCollapseContext => '收起上下文';

  @override
  String get noteNoText => '无原文文本';

  @override
  String get noteMissingHighlight => '划线已删除';

  @override
  String get noteMissingDocument => '原文已移除';

  @override
  String get noteNotIncluded => '这条划线不在笔记里';

  @override
  String get noteRemoveBlock => '从笔记中移除';

  @override
  String get noteSources => '出处';

  @override
  String get noteInclude => '包含';

  @override
  String get noteCitationPage => '页码';

  @override
  String get noteCitationFootnote => '脚注';

  @override
  String get noteCitationNone => '不标';

  @override
  String get noteAiContent => 'AI 内容';

  @override
  String get noteQuestions => '复习题';

  @override
  String get noteSourceList => '出处列表';

  @override
  String get noteAiMarks => 'AI 标记';

  @override
  String get noteMark => '标出';

  @override
  String get noteUnmark => '不标';

  @override
  String get noteCornellSummary => '总结';

  @override
  String noteContextSentences(int count) {
    return '前后 $count 句';
  }

  @override
  String noteCoverage(int count) {
    return '$count 条划线全部引用 · 原文未改写';
  }

  @override
  String noteUnusedCount(int count) {
    return '$count 条划线未用上';
  }

  @override
  String noteSelectedCount(int count) {
    return '已选 $count 条';
  }

  @override
  String noteRecallQuestion(String title, String location) {
    return '《$title》$location 说了什么？';
  }

  @override
  String get noteSelectAll => '全选';

  @override
  String get noteDeselectAll => '取消全选';

  @override
  String get noteReviewAdded => '已生成 1 张复习卡';

  @override
  String get noteExplain => '解释这句话';

  @override
  String get noteCreateReview => '生成复习卡';

  @override
  String get noteAddedToMap => '已加入脑图';

  @override
  String get noteExport => '导出';

  @override
  String get noteMarginSource => '页边批注';

  @override
  String notePage(int page) {
    return 'p.$page';
  }

  @override
  String noteSourceTitle(String title) {
    return '《$title》';
  }

  @override
  String get notePageSeparator => '、';

  @override
  String noteSourcePage(String title, int page) {
    return '《$title》p.$page';
  }

  @override
  String get noteOutlineTitle => '确认提纲';

  @override
  String get noteGenerating => '整理笔记';

  @override
  String get noteStop => '停止';

  @override
  String get noteContinue => '继续整理';

  @override
  String get noteLayoutOnly => '改为只排版';

  @override
  String get noteStepOutline => '归纳主题';

  @override
  String get noteAddSection => '添加节';

  @override
  String get noteNewSection => '新节';

  @override
  String get noteUnassigned => '未归入';

  @override
  String get noteAiUnavailable => '未配置 AI';

  @override
  String get notePreviewOutline => '先看提纲';

  @override
  String get noteAiFallback => 'AI 整理失败，已按原文排版';

  @override
  String get noteShowAi => '显示 AI 标记';

  @override
  String get noteAiEdited => 'AI · 已改';

  @override
  String get noteRephrase => '换一种说法';

  @override
  String get noteConcise => '更简洁';

  @override
  String get noteExpand => '展开说明';

  @override
  String get noteMakeMine => '改为我的话';

  @override
  String get noteRegenerate => '重新整理';

  @override
  String get noteAddAllReview => '全部加入复习';

  @override
  String noteStepWrite(int done, int total) {
    return '撰写 $done / $total · 核对引用';
  }

  @override
  String noteSending(int highlights, int notes, int characters, String model) {
    String _temp0 = intl.Intl.pluralLogic(
      notes,
      locale: localeName,
      other: '将发送 $highlights 条划线、$notes 条批注（约 $characters 字）给 $model',
      zero: '将发送 $highlights 条划线（约 $characters 字）给 $model',
    );
    return '$_temp0';
  }

  @override
  String get noteStepCollect => '收集素材';

  @override
  String get noteStepContext => '补全上下文';

  @override
  String get noteStepCompose => '撰写';

  @override
  String get noteStepVerify => '核对引用';

  @override
  String get noteStopped => '已停止';

  @override
  String get noteLocked => '更新时保留';

  @override
  String get resizeCompanionPanel => '调整面板大小';

  @override
  String noteNewMaterials(int highlights, int notes) {
    String _temp0 = intl.Intl.pluralLogic(notes, locale: localeName, other: '、写了 $notes 条批注', zero: '');
    String _temp1 = intl.Intl.pluralLogic(
      highlights,
      locale: localeName,
      other: '又划了 $highlights 条$_temp0',
      zero: '又写了 $notes 条批注',
    );
    return '$_temp1';
  }

  @override
  String get notePreviewUpdate => '预览更新';

  @override
  String get noteApplyUpdate => '应用更新';

  @override
  String get noteIgnoreUpdate => '忽略';

  @override
  String noteUpdateReady(int count) {
    return '新增 $count 处';
  }

  @override
  String get noteUpdateStale => '笔记或原文已更改，请重新预览';

  @override
  String noteUpdateApplied(int count) {
    return '已更新 · 新增 $count 条';
  }

  @override
  String get noteLocalPlacement => '按原文顺序';

  @override
  String get noteAddToReview => '加入复习';

  @override
  String noteUpdateChanges(int count) {
    return '$count 处更新';
  }

  @override
  String get noteShareTitle => '分享长图';

  @override
  String get noteShareQuote => '一句金句';

  @override
  String get noteShareSection => '一节';

  @override
  String get noteShareSummary => '整篇摘要';

  @override
  String get noteSharePaper => '纸张';

  @override
  String get noteSharePlain => '简洁';

  @override
  String get noteShareNight => '夜读';

  @override
  String get noteShareAi => 'AI 小结';

  @override
  String get noteShareFooter => '摘自我的 Foliarc 笔记';

  @override
  String noteSharedCount(int count) {
    return '$count 条划线';
  }

  @override
  String get noteNoQuotes => '没有摘录';

  @override
  String get noteCopyImage => '拷贝图片';

  @override
  String get noteSaveImage => '存储图片…';

  @override
  String get noteShareAction => '分享…';

  @override
  String get noteCopyRich => '复制为富文本';

  @override
  String get noteCopyMarkdown => '拷贝为 Markdown';

  @override
  String get noteRichText => '富文本';

  @override
  String get studyNoteSavedImage => '已存储';

  @override
  String get vocabularyHintsPreview => '效果预览';

  @override
  String get vocabularyHintsPreviewMeaning => '好奇的';

  @override
  String get settingsReadingPreferences => '阅读偏好';

  @override
  String get appIconTitle => '应用图标';

  @override
  String get appIconPaperArc => '翻页（默认）';

  @override
  String get appIconLeafFolio => '书叶';

  @override
  String get appIconFoldedF => '折纸 F';

  @override
  String get appIconDockHint => '更换 Dock 图标，访达中保留默认图标。';

  @override
  String get appIconHomeHint => '更换主屏幕图标，系统可能显示确认提示。';

  @override
  String get appIconChanging => '正在更换图标…';

  @override
  String get appIconChangeFailed => '图标更换失败，请重试。';

  @override
  String get fullTranslationMenu => '全文翻译…';

  @override
  String get fullTranslationTokensUsed => '已用 ';

  @override
  String get fullTranslationTask => '全文翻译任务…';

  @override
  String fullTranslationTaskMenu(int percent) {
    return '全文翻译任务… $percent%';
  }

  @override
  String get fullTranslationCapsule => '全文翻译';

  @override
  String fullTranslationCapsuleRunning(int percent, int batch, int done, int total) {
    return '$percent% 第 $batch 批 · $done/$total 页';
  }

  @override
  String fullTranslationCapsuleRunningAll(int percent, int done, int total) {
    return '$percent% $done/$total 页';
  }

  @override
  String fullTranslationCapsuleReview(int batch) {
    return '第 $batch 批待确认';
  }

  @override
  String fullTranslationCapsulePaused(int done, int total) {
    return '已暂停 $done/$total 页';
  }

  @override
  String get fullTranslationCapsuleOffline => '等待网络';

  @override
  String get fullTranslationCapsuleBudget => '已暂停 · 超出预估';

  @override
  String get fullTranslationCapsuleError => '已暂停';

  @override
  String get fullTranslationCapsuleDone => '全文已译';

  @override
  String fullTranslationCapsuleDoneFailed(int count) {
    return '已完成 · $count 段未译';
  }

  @override
  String fullTranslationCapsuleStopped(int done, int total) {
    return '已停止 $done/$total 页';
  }

  @override
  String fullTranslationPlaceholderBatch(int batch) {
    return '将在第 $batch 批翻译';
  }

  @override
  String fullTranslationPlaceholderPageSub(int page) {
    return '第 $page 页';
  }

  @override
  String get fullTranslationPlaceholderOutOfRange => '不在本次翻译范围';

  @override
  String get fullTranslationPlaceholderUntranslated => '未翻译';

  @override
  String get fullTranslationTranslatePage => '翻译此页';

  @override
  String get fullTranslationViewSaved => '查看译文';

  @override
  String get fullTranslationConfirmIntro =>
      '将按原文顺序逐段翻译整份文档，译文与原文对照显示。请先确认原文语言和目标语言。点击“开始翻译”后，原文将发送给你配置的 AI 模型，可能产生费用；可随时暂停，已译内容会保留。';

  @override
  String get fullTranslationSameLanguage => '原文语言和目标语言相同，请选择另一种目标语言。';

  @override
  String get fullTranslationStartFailed => '未能开始翻译，请检查模型连接后重试。已有译文会保留。';

  @override
  String fullTranslationTextProgress(int percent, int done, int total) {
    return '$percent% · $done/$total 段';
  }

  @override
  String get fullTranslationTitle => '全文翻译';

  @override
  String fullTranslationDocSubtitle(String doc, int pages) {
    return '$doc · $pages 页';
  }

  @override
  String get fullTranslationSourceLangDetect => '检测';

  @override
  String fullTranslationSourceDetected(String language) {
    return '$language（检测）';
  }

  @override
  String get fullTranslationRange => '范围';

  @override
  String get fullTranslationRangeAll => '全部';

  @override
  String get fullTranslationRangePages => '页码';

  @override
  String get fullTranslationMode => '方式';

  @override
  String get fullTranslationModeBatch => '分批确认';

  @override
  String get fullTranslationModeBatchDesc => '每批完成后停下，检查后再继续';

  @override
  String get fullTranslationModeAll => '一次完成';

  @override
  String get fullTranslationModeAllDesc => '连续翻译到最后，可随时暂停';

  @override
  String get fullTranslationBatchSize => '每批';

  @override
  String fullTranslationBatchPages(int count) {
    return '$count 页';
  }

  @override
  String fullTranslationBatchCount(int count) {
    return '共 $count 批';
  }

  @override
  String get fullTranslationNote => '术语与要求';

  @override
  String get fullTranslationNotePlaceholder => '可选。例如：attention 统一译为“注意”；人名保留原文';

  @override
  String fullTranslationCkptFailed(int count) {
    return '$count 段未译';
  }

  @override
  String get fullTranslationNoteHint => '只用于之后的批次；已译段落不会自动重译。';

  @override
  String get fullTranslationNoteConfigured => ' · 已设置';

  @override
  String get fullTranslationFooterNote => '译文保存在学习集内，不修改原文';

  @override
  String fullTranslationStartBatch(int from, int to) {
    return '开始 · 第 $from–$to 页';
  }

  @override
  String get fullTranslationStartAll => '开始翻译';

  @override
  String get fullTranslationNothingToTranslate => '没有需要翻译的段落';

  @override
  String get fullTranslationBlockedScannedTitle => '这份文档没有可选文字';

  @override
  String get fullTranslationBlockedScannedDesc => '先在本机识别文字，再翻译全文。';

  @override
  String get fullTranslationActionOcr => '识别文字';

  @override
  String get fullTranslationBlockedNoModelTitle => '还没有可用的模型';

  @override
  String get fullTranslationBlockedBadKeyTitle => 'API Key 无效';

  @override
  String get fullTranslationBlockedModelDesc => '全文翻译使用助手的默认模型。';

  @override
  String get fullTranslationActionSettings => '打开助手设置';

  @override
  String get fullTranslationBlockedOfflineTitle => '网络不可用';

  @override
  String get fullTranslationBlockedOfflineDesc => '可以先开始，联网后自动翻译。';

  @override
  String fullTranslationEstChanged(int reused, int total) {
    return '原文已重新识别 · 已有译文 $reused / $total 段仍可复用';
  }

  @override
  String fullTranslationEstNeeds(String paras, String chars) {
    return '需翻译 $paras 段 · 约 $chars 字符';
  }

  @override
  String fullTranslationEstMinutes(int minutes) {
    return '约 $minutes 分钟';
  }

  @override
  String fullTranslationEstReused(int paras, int pages) {
    return '已有 $paras 段译文（$pages 页），直接复用';
  }

  @override
  String fullTranslationEstReusedNoPages(int paras) {
    return '已有 $paras 段译文，直接复用';
  }

  @override
  String fullTranslationEstSkip(String details) {
    return '不发送：$details';
  }

  @override
  String fullTranslationEstSkipMargin(int count) {
    return '页眉页码 $count 处';
  }

  @override
  String fullTranslationEstSkipSame(String language, int count) {
    return '已是$language $count 段';
  }

  @override
  String fullTranslationEstSkipDupe(int count) {
    return '重复段落 $count 段';
  }

  @override
  String fullTranslationEstModel(String model, String tokens) {
    return '$model · 预计 $tokens token';
  }

  @override
  String get fullTranslationEstBudgetWarning => '；超出 50% 时暂停询问';

  @override
  String get fullTranslationPanelTitle => '全文翻译';

  @override
  String fullTranslationStateRunningBatch(int batch, int from, int to) {
    return '翻译中 · 第 $batch 批（$from–$to 页）';
  }

  @override
  String get fullTranslationStateRunningAll => '翻译中 · 一次完成';

  @override
  String fullTranslationStateReview(int batch) {
    return '第 $batch 批待确认';
  }

  @override
  String get fullTranslationStatePaused => '已暂停';

  @override
  String get fullTranslationStateOffline => '等待网络';

  @override
  String get fullTranslationStateBudget => '已暂停 · 超出预估';

  @override
  String get fullTranslationStateError => '已暂停 · 需要处理';

  @override
  String get fullTranslationStateDone => '已完成';

  @override
  String get fullTranslationStateStopped => '已停止';

  @override
  String get fullTranslationLegendDone => '已译';

  @override
  String get fullTranslationLegendReused => '复用';

  @override
  String get fullTranslationLegendRunning => '翻译中';

  @override
  String get fullTranslationLegendQueued => '本批排队';

  @override
  String get fullTranslationLegendFailed => '有未译段落';

  @override
  String get fullTranslationLegendSkipped => '无需翻译';

  @override
  String get fullTranslationStatParas => '段落';

  @override
  String fullTranslationStatEstToken(String tokens) {
    return '预估 $tokens';
  }

  @override
  String get fullTranslationStatFailed => '未译';

  @override
  String get fullTranslationDetailReused => '复用已有译文';

  @override
  String fullTranslationDetailParas(int count) {
    return '$count 段';
  }

  @override
  String get fullTranslationDetailDedup => '重复段落只译一次';

  @override
  String fullTranslationDetailSkipped(String language) {
    return '不发送（页眉、页码、已是$language）';
  }

  @override
  String fullTranslationDetailItems(int count) {
    return '$count 处';
  }

  @override
  String get fullTranslationDetailModelCalls => '模型 · 请求';

  @override
  String fullTranslationDetailCalls(String model, int calls) {
    return '$model · $calls 次';
  }

  @override
  String get fullTranslationDetailElapsed => '用时';

  @override
  String fullTranslationDetailTime(int minutes, int seconds) {
    return '$minutes 分 $seconds 秒';
  }

  @override
  String get fullTranslationActionStop => '停止';

  @override
  String get fullTranslationActionEnd => '结束';

  @override
  String get fullTranslationActionPause => '暂停';

  @override
  String get fullTranslationActionResume => '继续';

  @override
  String get fullTranslationActionNextBatch => '继续下一批';

  @override
  String fullTranslationActionRetryFailed(int count) {
    return '重试 $count 段';
  }

  @override
  String get fullTranslationActionContinueTranslation => '继续翻译…';

  @override
  String get fullTranslationActionClear => '移除译文…';

  @override
  String get fullTranslationClearTitle => '移除这份文档的全部 AI 译文？';

  @override
  String get fullTranslationClearMessage => '手动修改过的译文也会被移除。';

  @override
  String fullTranslationCkptBatchDone(int batch) {
    return '第 $batch 批已完成';
  }

  @override
  String fullTranslationCkptPages(int from, int to) {
    return '第 $from–$to 页';
  }

  @override
  String get fullTranslationCkptCollapseTip => '收起，先读一读';

  @override
  String get fullTranslationCkptExpandTip => '展开';

  @override
  String fullTranslationCkptMin(int batch) {
    return '第 $batch 批待确认';
  }

  @override
  String fullTranslationCkptNextBatch(int from, int to) {
    return '继续第 $from–$to 页';
  }

  @override
  String fullTranslationCkptFromPage(int page) {
    return '从第 $page 页开始检查';
  }

  @override
  String fullTranslationCkptRemain(int pages, String tokens) {
    return '剩余 $pages 页 · 约 $tokens token';
  }

  @override
  String get fullTranslationCkptTranslateRest => '翻译剩余全部';

  @override
  String fullTranslationHudStartBatch(int from, int to) {
    return '开始翻译第 $from–$to 页';
  }

  @override
  String get fullTranslationHudStartAll => '开始翻译全文';

  @override
  String get fullTranslationHudDone => '全文翻译完成';

  @override
  String fullTranslationHudDoneFailed(int count) {
    return '全文翻译完成 · $count 段未译';
  }

  @override
  String get fullTranslationHudView => '查看';

  @override
  String get fullTranslationHudStopped => '已停止 · 已译内容已保存';

  @override
  String fullTranslationHudPausedAt(int page) {
    return '全文翻译已暂停在第 $page 页';
  }

  @override
  String get fullTranslationHudContinue => '继续';

  @override
  String get fullTranslationHudRestAll => '剩余页面将一次翻译完成';

  @override
  String fullTranslationGridCell(int page, String state) {
    return '第 $page 页 · $state';
  }

  @override
  String fullTranslationCapsuleA11y(int percent, int batch, int done, int total) {
    return '全文翻译，$percent%，第 $batch 批，$done / $total 页';
  }

  @override
  String get fullTranslationStripBadKey => 'API Key 无效，已暂停';

  @override
  String get fullTranslationStripSavedNote => '已译内容已保存';

  @override
  String get fullTranslationStripNoModel => '没有可用的模型，已暂停';

  @override
  String get fullTranslationStripStorage => '无法保存译文，已暂停';

  @override
  String get fullTranslationStripOffline => '网络不可用，联网后自动继续';

  @override
  String fullTranslationStripBudget(String tokens) {
    return '已用 $tokens token，超出预估 50%';
  }

  @override
  String get fullTranslationStripOpenSettings => '打开设置';

  @override
  String get fullTranslationStripRetry => '重试';

  @override
  String get fullTranslationHudNetworkRestored => '网络已恢复，继续翻译';

  @override
  String fullTranslationNotificationBodyFailed(String doc, int count) {
    return '$doc · $count 段未译';
  }

  @override
  String get phoneGlassTitle => '手机 Liquid Glass';

  @override
  String get phoneGlassRegular => '标准';

  @override
  String get phoneGlassThick => '厚材质';

  @override
  String get phoneGlassOpaque => '不透明';

  @override
  String get phoneNavigationCloseDrawer => '关闭学习集抽屉';

  @override
  String get phoneNavigationNotes => '学习笔记';

  @override
  String get phoneReaderReading => '阅读';

  @override
  String get phoneReaderTools => '标注工具';

  @override
  String get phoneReaderCollapse => '收起';

  @override
  String get phoneReaderExitTools => '结束标注';

  @override
  String phoneReaderPercent(int percent) {
    return '$percent%';
  }

  @override
  String get mapCacheClearFailed => '清除缓存失败';

  @override
  String get translationRetranslate => '重新翻译';

  @override
  String get translationEdit => '修改译文';

  @override
  String get translationRetranslated => '已重新翻译';

  @override
  String get translationEdited => '已手动修改';

  @override
  String translationParagraphFailed(String reason) {
    return '未译 · $reason';
  }

  @override
  String get translationEditSaved => '已保存修改';

  @override
  String get translationCopied => '已拷贝译文';

  @override
  String get translationRemoved => '已移除译文';

  @override
  String get phoneMoreOutlineAndBookmarks => '目录与书签';

  @override
  String get phoneMoreClose => '关闭';

  @override
  String get phoneMoreBack => '返回';

  @override
  String get mapFailureDetails => '失败详情';

  @override
  String get mapFailureDialogTitle => '生成未完成';

  @override
  String get mapFailureDiagnostics => '诊断信息';

  @override
  String get mapFailureCopy => '复制详情';

  @override
  String get mapFailureTruncated => '模型输出被截断，请重试';

  @override
  String get mapFailureInvalid => '模型返回内容未通过脑图格式校验';

  @override
  String get mapFailureEmpty => '模型没有返回脑图内容';

  @override
  String get mapFailureTimeout => '模型请求超时，请重试';

  @override
  String get mapFailureLimit => '内容超出单次处理上限';

  @override
  String get mapFailureRate => '模型服务请求过于频繁，请稍后重试';

  @override
  String get mapFailureRequest => '模型服务不接受此请求，请检查模型配置';

  @override
  String get mapFailureDocumentText => '文档中没有可读取的文字';

  @override
  String get mapFailureStage => '失败阶段';

  @override
  String get mapFailurePrepare => '准备文档';

  @override
  String get mapFailureChapter => '读取章节要点';

  @override
  String get mapFailureBuild => '组织脑图';

  @override
  String get mapFailureUpdate => '更新脑图';

  @override
  String get mapFailureModel => '使用模型';

  @override
  String get mapFailureCode => '错误码';

  @override
  String get mapFailureLines => '返回行数 / 通过校验行数';

  @override
  String get mapFailureStop => '模型结束原因';

  @override
  String get mapFailureOutputLimit => '输出额度（含模型思考，tokens）';

  @override
  String get mapFailureReasoning => '模型思考字符数';

  @override
  String get mapFailureRejected => '未通过校验';

  @override
  String get mapFailureInvalidJson => '不是完整的 JSON 对象';

  @override
  String get mapFailureFields => '字段或操作不符合要求';

  @override
  String get mapFailureReference => '节点编号无效或重复';

  @override
  String get mapFailureTitle => '标题为空或重复';

  @override
  String get mapFailureParent => '父节点不存在或无效';

  @override
  String get mapFailureDepth => '节点层级超过要求';

  @override
  String get mapFailureAnnotation => '引用的批注无效';

  @override
  String get mapFailureSource => '来源字段格式错误';

  @override
  String get mapFailureProtected => '尝试修改受保护的内容';

  @override
  String get mapFailureLineSize => '单行内容过长';

  @override
  String get mapGenerateSource => '来源';

  @override
  String get mapGenerateChangeSources => '更换 / 添加';

  @override
  String get mapGenerateMoreSettings => '更多设置';

  @override
  String get mapGenerateSelectSources => '选择文档';

  @override
  String mapGenerateSourceCount(int count) {
    return '共 $count 份文档';
  }

  @override
  String get mapGenerateStructurePreview => '结构示意';

  @override
  String get mapGeneratePreviewDisclaimer => '仅示意组织方式，具体内容以生成结果为准';

  @override
  String get mapGeneratePreviewRoot => '文档主题';

  @override
  String mapGeneratePreviewChapter(int count) {
    return '第 $count 章';
  }

  @override
  String get mapGeneratePreviewConcepts => '核心概念';

  @override
  String get mapGeneratePreviewLinks => '关联关系';

  @override
  String get mapGeneratePreviewMethods => '应用方法';

  @override
  String get mapGeneratePreviewWhat => '是什么';

  @override
  String get mapGeneratePreviewWhy => '为什么';

  @override
  String get mapGeneratePreviewHow => '怎么做';

  @override
  String mapGeneratePreviewPoint(int count) {
    return '要点 $count';
  }

  @override
  String get mapGenerateInstructionsHint => '补充要求（选填）';

  @override
  String get mapGenerateDestinationNew => '将创建新脑图';

  @override
  String get mapGenerateDestinationBranch => '将添加到当前脑图';

  @override
  String get mapGenerateMapTitle => '脑图名称';

  @override
  String get mapGenerateNoSources => '暂无可用文档';

  @override
  String get mapGenerateSourceRange => '文档范围';

  @override
  String get mapGenerateResetRange => '恢复全文';

  @override
  String mapGenerateMarksSummary(int count) {
    return '含 $count 条批注';
  }

  @override
  String mapGenerateStructureDepth(int count) {
    return '$count 层结构';
  }
}
