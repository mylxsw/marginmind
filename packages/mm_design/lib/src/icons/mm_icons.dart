import 'package:flutter/cupertino.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Shared icon vocabulary. Primarily uses Cupertino icons, supplemented by
/// Lucide icons. Feature code refers to these names so icon
/// sources can change without altering controls or their behavior.
abstract final class MMIcons {
  static const context = LucideIcons.textQuote;
  static const regenerate = LucideIcons.refreshCw;
  static const grip = LucideIcons.gripVertical;
  static const studyNote = LucideIcons.notebookText;
  static const share = LucideIcons.share;
  static const export = LucideIcons.download;
  static const IconData speaker = CupertinoIcons.speaker_2;
  static const compare = LucideIcons.columns2;
  static const swapSides = CupertinoIcons.arrow_right_arrow_left;
  static const alignHere = CupertinoIcons.equal;
  static const marginNote = CupertinoIcons.text_bubble;
  static const IconData quoteBubble = CupertinoIcons.quote_bubble;
  static const IconData captionsBubble = CupertinoIcons.captions_bubble;
  static const IconData readerNavigation = LucideIcons.layers2;
  static const IconData actualSize = CupertinoIcons.square;
  static const IconData fitMap = CupertinoIcons.arrow_up_left_arrow_down_right;
  static const IconData fitWidth = CupertinoIcons.arrow_left_right;
  static const IconData fitPage = CupertinoIcons.rectangle;
  static const IconData pageZoom = CupertinoIcons.resize;
  static const IconData zoomControl = CupertinoIcons.plus_slash_minus;
  static const IconData crop = CupertinoIcons.crop;
  static const IconData locate = CupertinoIcons.location_circle;
  static const IconData home = LucideIcons.house;
  static const IconData sidebar = CupertinoIcons.sidebar_left; // sidebar.left
  static const IconData sidebarRight = CupertinoIcons.sidebar_right; // sidebar.right
  static const IconData search = CupertinoIcons.search; // magnifyingglass
  static const IconData add = CupertinoIcons.add; // plus
  static const IconData grid = CupertinoIcons.square_grid_2x2; // square.grid.2x2
  static const IconData list = CupertinoIcons.list_bullet; // list.bullet
  static const IconData sort = CupertinoIcons.arrow_up_arrow_down; // arrow.up.arrow.down
  static const IconData star = CupertinoIcons.star; // star
  static const IconData starFill = CupertinoIcons.star_fill; // star.fill
  static const IconData recent = CupertinoIcons.clock; // clock
  static const IconData folder = CupertinoIcons.folder; // folder
  static const IconData newFolder = CupertinoIcons.folder_badge_plus; // folder.badge.plus
  static const IconData trash = LucideIcons.trash;
  static const IconData editNote = LucideIcons.squarePen;
  static const IconData vocabulary = LucideIcons.bookA;
  static const IconData ebook = CupertinoIcons.book;
  static const IconData markdown = LucideIcons.hash;
  static const IconData readingSettings = LucideIcons.aLargeSmall;
  static const IconData document = CupertinoIcons.doc_text; // doc.text
  static const IconData collections = LucideIcons.libraryBig;
  static const IconData studySet = CupertinoIcons.book_fill; // books.vertical.fill
  static const organizeNote = LucideIcons.notebookPen;
  static const IconData ai = CupertinoIcons.sparkles; // sparkles
  static const IconData research = CupertinoIcons.doc_text_search; // text.magnifyingglass
  static const IconData info = CupertinoIcons.info_circle; // info.circle
  static const IconData select = CupertinoIcons.cursor_rays; // cursorarrow
  static const IconData underline = LucideIcons.pencilLine;
  static const IconData highlight = LucideIcons.highlighter;
  static const IconData mapStyle = CupertinoIcons.paintbrush; // structure and palette
  static const IconData image = CupertinoIcons.photo; // photo
  static const IconData areaSelect = CupertinoIcons.viewfinder; // rectangle.dashed
  static const IconData pen = CupertinoIcons.pencil; // pencil.tip
  static const IconData inkFreehand = CupertinoIcons.scribble; // scribble
  static const IconData inkAnnotations = LucideIcons.lineSquiggle;
  static const IconData inkEllipse = CupertinoIcons.circle; // circle
  static const IconData inkArrow = CupertinoIcons.arrow_up_right; // arrow.up.right
  static const IconData inkEraser = CupertinoIcons.delete_left; // delete.left (no Cupertino eraser)
  static const IconData undo = CupertinoIcons.arrow_uturn_left; // arrow.uturn.backward
  static const IconData text = CupertinoIcons.textformat; // character.textbox
  static const IconData syncToMap = CupertinoIcons.arrow_branch; // arrow.triangle.branch
  static const IconData layoutReader = CupertinoIcons.doc_plaintext; // doc.text
  static const IconData layoutSplit = CupertinoIcons.square_split_2x1; // rectangle.split.2x1
  static const IconData network = LucideIcons.network;
  static const IconData layoutMap = network;
  static const IconData mindMap = CupertinoIcons.arrow_branch;
  static const IconData revealSource = CupertinoIcons.arrow_up_right; // arrow.up.right
  static const IconData popUp = CupertinoIcons.chevron_up_chevron_down; // chevron.up.chevron.down
  static const IconData thumbnails = CupertinoIcons.rectangle_grid_1x2; // rectangle.grid.1x2
  static const IconData outline = CupertinoIcons.list_bullet_indent; // list.bullet.indent
  static const IconData bookmark = CupertinoIcons.bookmark; // bookmark
  static const IconData bookmarkFill = CupertinoIcons.bookmark_fill; // bookmark.fill
  static const IconData annotations = CupertinoIcons.text_quote; // text.quote
  static const IconData more = CupertinoIcons.ellipsis; // ellipsis
  static const IconData chevronUp = CupertinoIcons.chevron_up;
  static const IconData chevronDown = CupertinoIcons.chevron_down;
  static const IconData chevronLeft = CupertinoIcons.chevron_left;
  static const IconData chevronRight = CupertinoIcons.chevron_right;
  static const IconData close = CupertinoIcons.xmark;
  static const IconData clear = CupertinoIcons.xmark_circle_fill;
  static const IconData success = CupertinoIcons.checkmark_circle;
  static const IconData appearance = CupertinoIcons.circle_lefthalf_fill; // circle.lefthalf.filled
  static const IconData settings = CupertinoIcons.gear;
  static const IconData review = CupertinoIcons.square_stack; // rectangle.on.rectangle
  static const IconData statistics = CupertinoIcons.chart_bar; // chart.bar
  static const IconData tag = CupertinoIcons.tag;
  static const IconData addTopic = CupertinoIcons.plus_rectangle; // plus.rectangle
  static const IconData copy = LucideIcons.copy;
  static const IconData addNote = CupertinoIcons.square_pencil; // square.and.pencil
  static const IconData bold = CupertinoIcons.bold; // bold
  static const IconData italic = CupertinoIcons.italic; // italic
  static const IconData bulletList = CupertinoIcons.list_bullet; // list.bullet
  static const IconData numberList = CupertinoIcons.list_number; // list.number
  static const IconData zoomIn = CupertinoIcons.plus;
  static const IconData zoomOut = CupertinoIcons.minus;
  static const IconData import = CupertinoIcons.tray_arrow_down; // square.and.arrow.down
  static const IconData library = CupertinoIcons.square_grid_2x2;

  // Research: intents, modes, sources and their states.
  static const IconData explain = CupertinoIcons.lightbulb; // lightbulb
  static const IconData interpret = CupertinoIcons.book; // book
  static const IconData verify = CupertinoIcons.checkmark_seal; // checkmark.seal
  static const IconData video = CupertinoIcons.play_rectangle; // play.rectangle
  static const IconData paper = CupertinoIcons.doc_richtext; // doc.richtext
  static const IconData translate = LucideIcons.languages;
  static const IconData web = CupertinoIcons.globe; // globe
  static const IconData offline = CupertinoIcons.wifi_slash; // wifi.slash
  static const IconData later = CupertinoIcons.clock; // clock
  static const IconData history = CupertinoIcons.arrow_counterclockwise; // clock.arrow.circlepath
  static const IconData lock = CupertinoIcons.lock; // lock
  static const IconData link = CupertinoIcons.link; // link
  static const IconData openExternal = CupertinoIcons.arrow_up_right_square; // arrow.up.right.square
  static const IconData warning = CupertinoIcons.exclamationmark_triangle; // exclamationmark.triangle
  static const IconData shield = CupertinoIcons.shield; // shield
  static const IconData check = CupertinoIcons.checkmark; // checkmark
  static const IconData stop = CupertinoIcons.stop_fill; // stop.fill
  static const IconData microphone = CupertinoIcons.mic; // mic
  static const IconData returnKey = LucideIcons.cornerDownLeft;
  static const IconData send = CupertinoIcons.arrow_up; // arrow.up
  static const IconData evidence = CupertinoIcons.quote_bubble; // quote.bubble
  static const IconData summarize = CupertinoIcons.text_alignleft; // text.alignleft
  static const IconData organize = CupertinoIcons.wand_stars; // wand.and.stars
  static const IconData eye = CupertinoIcons.eye; // eye
  static const IconData eyeSlash = CupertinoIcons.eye_slash; // eye.slash
  static const IconData remove = CupertinoIcons.minus_circle; // minus.circle
  static const IconData chevronUpDown = CupertinoIcons.chevron_up_chevron_down; // chevron.up.chevron.down
  static const IconData reading = CupertinoIcons.book; // book
  static const IconData mention = CupertinoIcons.at; // at
  static const IconData command = CupertinoIcons.slash_circle; // slash.circle
  static const IconData conversation = CupertinoIcons.chat_bubble; // bubble.left

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

/// Lucide vocabulary for reader commands, including toolbar overflow entries.
abstract final class MMReaderIcons {
  static const select = LucideIcons.mousePointer2;
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
