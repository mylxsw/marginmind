// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => 'MarginMind';

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
  String get readerEmptyMessage => '在侧栏选择一份文档，或者向这个学习集导入 PDF。';

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
  String get readerStyleDark => '黑暗';

  @override
  String get readerStylePaper => '纸质';

  @override
  String get readerStyleGreen => '浅绿';

  @override
  String get readerZoom => '页面适配';

  @override
  String get readerAppearance => '阅读外观';

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
  String get ocrStart => '开始识别';

  @override
  String get ocrNoText => '本页文字尚不能选择';

  @override
  String get ocrReady => '已识别 · 可选字和搜索';

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
}
