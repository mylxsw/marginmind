import '../study_set/folder.dart';
import '../study_set/study_set.dart';

/// Sample content matching the design canvas (artboard 00), used until
/// real study sets can be imported.
abstract final class DemoLibrary {
  static const folders = [
    Folder(id: 'cognition', name: '认知科学'),
    Folder(id: 'design', name: '产品与设计'),
    Folder(id: 'investing', name: '投资理财'),
  ];

  static List<StudySet> studySets(DateTime now) {
    StudySet make(
      String id,
      String title, {
      required int color,
      String? folder,
      required int docs,
      required int cards,
      int due = 0,
      required int read,
      required int total,
      required Duration openedAgo,
      bool starred = false,
      required ReadingPosition position,
    }) {
      return StudySet(
        id: id,
        title: title,
        colorIndex: color,
        folderId: folder,
        starred: starred,
        documentCount: docs,
        cardCount: cards,
        dueCount: due,
        readPages: read,
        totalPages: total,
        lastPosition: position,
        createdAt: now.subtract(const Duration(days: 90)),
        lastOpenedAt: now.subtract(openedAgo),
      );
    }

    return [
      make(
        'demo-1',
        '认知科学入门',
        color: 2,
        folder: 'cognition',
        docs: 2,
        cards: 6,
        due: 5,
        read: 26,
        total: 176,
        openedAgo: const Duration(minutes: 2),
        starred: true,
        position: const ReadingPosition(documentTitle: '学习的底层逻辑', page: 24),
      ),
      make(
        'demo-2',
        '注意力与专注',
        color: 5,
        folder: 'cognition',
        docs: 3,
        cards: 42,
        due: 8,
        read: 310,
        total: 500,
        openedAgo: const Duration(days: 1),
        position: const ReadingPosition(documentTitle: '深度工作的条件', page: 88),
      ),
      make(
        'demo-3',
        '产品设计方法论',
        color: 4,
        folder: 'design',
        docs: 4,
        cards: 128,
        read: 640,
        total: 800,
        openedAgo: const Duration(days: 3),
        starred: true,
        position: const ReadingPosition(documentTitle: '用户访谈指南', page: 12),
      ),
      make(
        'demo-4',
        '交互设计原则笔记',
        color: 3,
        folder: 'design',
        docs: 1,
        cards: 57,
        due: 10,
        read: 140,
        total: 310,
        openedAgo: const Duration(days: 7),
        position: const ReadingPosition(documentTitle: '交互设计原则', page: 140),
      ),
      make(
        'demo-5',
        '指数基金投资课',
        color: 1,
        folder: 'investing',
        docs: 2,
        cards: 33,
        read: 90,
        total: 300,
        openedAgo: const Duration(days: 14),
        position: const ReadingPosition(documentTitle: '资产配置基础', page: 51),
      ),
      make(
        'demo-6',
        '论文文献综述',
        color: 0,
        docs: 12,
        cards: 214,
        read: 400,
        total: 2000,
        openedAgo: const Duration(days: 32),
        position: const ReadingPosition(documentTitle: '综述草稿', page: 3),
      ),
    ];
  }
}
