import 'package:flutter/widgets.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Shared Lucide icon vocabulary for controls and menu commands.
abstract final class MMIcons {
  static const moveUp = LucideIcons.arrowUp;
  static const moveDown = LucideIcons.arrowDown;
  static const sortAscending = LucideIcons.arrowDown01;
  static const sortDescending = LucideIcons.arrowDown10;
  static const sortTitle = LucideIcons.arrowDownAZ;
  static const model = LucideIcons.cpu;
  static const section = LucideIcons.heading;
  static const template = LucideIcons.panelsTopLeft;
  static const palette = LucideIcons.palette;
  static const expand = LucideIcons.unfoldVertical;
  static const collapse = LucideIcons.foldVertical;
  static const split = LucideIcons.split;
  static const relation = LucideIcons.moveUpRight;
  static const summary = LucideIcons.braces;
  static const ocr = LucideIcons.scanText;

  static const context = LucideIcons.textQuote;
  static const regenerate = LucideIcons.refreshCw;
  static const grip = LucideIcons.gripVertical;
  static const studyNote = LucideIcons.notebookText;
  static const share = LucideIcons.share;
  static const export = LucideIcons.download;
  static const IconData speaker = LucideIcons.volume2;
  static const compare = LucideIcons.columns2;
  static const swapSides = LucideIcons.arrowLeftRight;
  static const alignHere = LucideIcons.equal;
  static const marginNote = LucideIcons.messageSquareText;
  static const IconData quoteBubble = LucideIcons.messageSquareQuote;
  static const IconData captionsBubble = LucideIcons.captions;
  static const IconData readerNavigation = LucideIcons.layers2;
  static const IconData actualSize = LucideIcons.square;
  static const IconData fitMap = LucideIcons.minimize2;
  static const IconData fitWidth = LucideIcons.moveHorizontal;
  static const IconData fitPage = LucideIcons.maximize;
  static const IconData pageZoom = LucideIcons.scaling;
  static const IconData zoomControl = LucideIcons.zoomIn;
  static const IconData crop = LucideIcons.crop;
  static const IconData locate = LucideIcons.locateFixed;
  static const IconData home = LucideIcons.house;
  static const IconData sidebar = LucideIcons.panelLeft;
  static const IconData sidebarClose = LucideIcons.panelLeftClose;
  static const IconData sidebarRight = LucideIcons.panelRight;
  static const IconData search = LucideIcons.search;
  static const IconData add = LucideIcons.plus;
  static const IconData grid = LucideIcons.layoutGrid;
  static const IconData list = LucideIcons.list;
  static const IconData sort = LucideIcons.arrowDownUp;
  static const IconData star = LucideIcons.star;
  // Filled saved-state glyph used outside menus.
  static const IconData starFill = CupertinoIcons.star_fill;
  static const IconData recent = LucideIcons.clock;
  static const IconData folder = LucideIcons.folder;
  static const IconData newFolder = LucideIcons.folderPlus;
  static const IconData trash = LucideIcons.trash;
  static const IconData editNote = LucideIcons.squarePen;
  static const IconData vocabulary = LucideIcons.bookA;
  static const IconData ebook = LucideIcons.book;
  static const IconData mobi = LucideIcons.bookOpenText;
  static const IconData markdown = LucideIcons.fileCode;
  static const IconData readingSettings = LucideIcons.aLargeSmall;
  static const IconData document = LucideIcons.fileText;
  static const IconData collections = LucideIcons.libraryBig;
  static const IconData studySet = LucideIcons.libraryBig;
  static const organizeNote = LucideIcons.notebookPen;
  static const IconData ai = LucideIcons.sparkles;
  /// Settings › AI Features: which model each feature routes to.
  static const IconData aiTasks = LucideIcons.split;
  static const IconData research = LucideIcons.fileSearch;
  static const IconData info = LucideIcons.info;
  // Preserve the reader's established selection cursor when updating menu icons.
  static const IconData select = CupertinoIcons.cursor_rays;
  static const IconData underline = LucideIcons.pencilLine;
  static const IconData highlight = LucideIcons.highlighter;
  static const IconData mapStyle = LucideIcons.paintbrush;
  static const IconData image = LucideIcons.image;
  static const IconData areaSelect = LucideIcons.scan;
  static const IconData pen = LucideIcons.pencil;
  static const IconData inkFreehand = LucideIcons.pencilLine;
  static const IconData inkAnnotations = LucideIcons.lineSquiggle;
  static const IconData inkEllipse = LucideIcons.circle;
  static const IconData inkArrow = LucideIcons.arrowUpRight;
  static const IconData inkEraser = LucideIcons.eraser;
  static const IconData undo = LucideIcons.undo2;
  static const IconData redo = LucideIcons.redo2;
  static const IconData text = LucideIcons.type;
  static const IconData syncToMap = LucideIcons.gitBranch;
  static const IconData layoutReader = LucideIcons.fileText;
  static const IconData layoutSplit = LucideIcons.columns2;
  static const IconData mindMap = LucideIcons.graphStar;
  static const IconData layoutMap = mindMap;
  static const IconData revealSource = LucideIcons.arrowUpRight;
  static const IconData popUp = LucideIcons.chevronsUpDown;
  static const IconData thumbnails = LucideIcons.panelsTopLeft;
  static const IconData outline = LucideIcons.listTree;
  static const IconData bookmark = LucideIcons.bookmark;
  static const IconData bookmarkFill = LucideIcons.bookmarkCheck;
  static const IconData annotations = LucideIcons.textQuote;
  static const IconData more = LucideIcons.ellipsis;
  static const IconData chevronUp = LucideIcons.chevronUp;
  static const IconData chevronDown = LucideIcons.chevronDown;
  static const IconData chevronLeft = LucideIcons.chevronLeft;
  static const IconData chevronRight = LucideIcons.chevronRight;
  static const IconData close = LucideIcons.x;
  static const IconData clear = LucideIcons.circleX;
  static const IconData success = LucideIcons.circleCheck;
  static const IconData appearance = LucideIcons.contrast;
  static const IconData settings = LucideIcons.settings;
  static const IconData review = LucideIcons.brain;
  static const IconData statistics = LucideIcons.chartNoAxesColumn;
  static const IconData tag = LucideIcons.tag;
  static const IconData addTopic = LucideIcons.squarePlus;
  static const IconData copy = LucideIcons.copy;
  static const IconData addNote = LucideIcons.squarePen;
  static const IconData bold = LucideIcons.bold;
  static const IconData italic = LucideIcons.italic;
  static const IconData bulletList = LucideIcons.list;
  static const IconData numberList = LucideIcons.listOrdered;
  static const IconData zoomIn = LucideIcons.plus;
  static const IconData zoomOut = LucideIcons.minus;
  static const IconData addDocument = LucideIcons.filePlusCorner;
  static const IconData import = LucideIcons.import;
  static const IconData library = LucideIcons.libraryBig;

  // Research: intents, modes, sources and their states.
  static const IconData explain = LucideIcons.lightbulb;
  static const IconData interpret = LucideIcons.bookOpen;
  static const IconData verify = LucideIcons.badgeCheck;
  static const IconData video = LucideIcons.squarePlay;
  static const IconData paper = LucideIcons.fileText;
  static const IconData translate = LucideIcons.languages;
  static const IconData web = LucideIcons.globe;
  static const IconData offline = LucideIcons.wifiOff;
  static const IconData later = LucideIcons.clock;
  static const IconData history = LucideIcons.history;
  static const IconData lock = LucideIcons.lock;
  static const IconData link = LucideIcons.link;
  static const IconData openExternal = LucideIcons.externalLink;
  static const IconData warning = LucideIcons.triangleAlert;
  static const IconData shield = LucideIcons.shield;
  static const IconData check = LucideIcons.check;
  static const IconData stop = LucideIcons.square;
  static const IconData microphone = LucideIcons.mic;
  static const IconData returnKey = LucideIcons.cornerDownLeft;
  static const IconData send = LucideIcons.arrowUp;
  static const IconData evidence = LucideIcons.messageSquareQuote;
  static const IconData summarize = LucideIcons.alignLeft;
  static const IconData organize = LucideIcons.wandSparkles;
  static const IconData eye = LucideIcons.eye;
  static const IconData eyeSlash = LucideIcons.eyeOff;
  static const IconData remove = LucideIcons.circleMinus;
  static const IconData chevronUpDown = LucideIcons.chevronsUpDown;
  static const IconData reading = LucideIcons.bookOpen;
  static const IconData mention = LucideIcons.atSign;
  static const IconData command = LucideIcons.slash;
  static const IconData newConversation = LucideIcons.messageCirclePlus;
  static const IconData conversationHistory = LucideIcons.listMinus;
  static const IconData conversation = LucideIcons.messageCircle;

  // AI idea expansion: expand a topic, group topics under a new parent,
  // fill in missing siblings, adjust the settings while reviewing.
  static const IconData expandIdeas = LucideIcons.listTree;
  static const IconData groupParent = LucideIcons.group;
  static const IconData fillSiblings = LucideIcons.listPlus;
  static const IconData adjust = LucideIcons.slidersHorizontal;

  // Mind map from a document: generate / update the map (distinct from the
  // assistant's sparkles and organize notes' notebook-pen), merge another
  // document into the current map.
  static const IconData generateMap = LucideIcons.wandSparkles;
  static const IconData mergeIntoMap = LucideIcons.merge;

  // Full-document translation (GUL-599).
  static const IconData layers = LucideIcons.layers;
  static const IconData pause = LucideIcons.pause;
  static const IconData play = LucideIcons.play;
  static const IconData retry = LucideIcons.rotateCcw;
  static const IconData wifiOff = LucideIcons.wifiOff;
  static const IconData key = LucideIcons.key;
  static const IconData recycle = LucideIcons.recycle;
  static const IconData skip = LucideIcons.stepForward;
}

/// Shared vocabulary for reader commands, including toolbar overflow entries.
abstract final class MMReaderIcons {
  static const select = MMIcons.select;
  static const underline = LucideIcons.underline;
  static const pen = LucideIcons.pencil;
  static const area = LucideIcons.scan;
  static const syncToMap = LucideIcons.gitBranch;
  static const marginNote = LucideIcons.messageSquareText;
  static const actualSize = LucideIcons.square;
  static const fitWidth = LucideIcons.moveHorizontal;
  static const fitPage = LucideIcons.maximize;
  static const crop = LucideIcons.crop;
  static const white = LucideIcons.sun;
  static const dark = LucideIcons.moon;
  static const paper = LucideIcons.scrollText;
  static const green = LucideIcons.leaf;
  static const zoomIn = LucideIcons.plus;
  static const zoomOut = LucideIcons.minus;
  static const layoutReader = LucideIcons.fileText;
  static const assistant = LucideIcons.sparkles;
}
