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
  String get firstRunTitle => '开始你的第一个学习集';

  @override
  String get firstRunMessage => '把一本或几本 PDF 拖到这里，MarginMind 会为它们建一个学习集。之后的划线、卡片和脑图都放在里面。';

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
  String get sheetLocation => '位置';

  @override
  String get sheetColor => '颜色';

  @override
  String get sheetImportAfterCreate => '创建后立即导入 PDF…';

  @override
  String get cancel => '取消';

  @override
  String get create => '创建';

  @override
  String get done => '完成';

  @override
  String createdHud(String name) {
    return '已创建「$name」';
  }

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
  String get toolSelect => '选择';

  @override
  String get toolHighlight => '高亮';

  @override
  String get toolArea => '框选';

  @override
  String get toolPen => '手写';

  @override
  String get toolText => '文本';

  @override
  String get syncToMapOn => '摘录同步到脑图：开';

  @override
  String get syncToMapOff => '摘录同步到脑图：关';

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
  String get mapEmptyMessage => '在原文里划线，摘录就会变成卡片，挂在当前选中的主题下。';

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
}
