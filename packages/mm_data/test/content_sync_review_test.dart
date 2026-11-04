import 'package:mm_core/mm_core.dart';
import 'package:mm_data/src/content_sync_review.dart';
import 'package:test/test.dart';

void main() {
  Map<String, Object?> payload(Map<String, Object?> content) => {'title': 'Set', 'content': content};
  test('entire atomic transaction includes companion edits and current values, omitting bookkeeping dates', () {
    final before = payload({
      'cards': {
        'c': {'title': 'Old', 'body': 'Body', 'updatedAt': 'old-date'},
      },
    });
    final candidate = payload({
      'cards': {
        'c': {'title': 'Proposed', 'body': 'Companion edit', 'updatedAt': 'new-date'},
      },
    });
    final current = payload({
      'cards': {
        'c': {'title': 'Current', 'body': 'Independent body'},
      },
    });
    final changes = contentSyncReview(before, candidate, current);
    expect(changes.map((c) => (c.current, c.candidate)), [
      ('Current', 'Proposed'),
      ('Independent body', 'Companion edit'),
    ]);
    expect(changes.every((c) => c.title == 'Current'), isTrue);
    expect(contentSyncReview(before, before, current), isEmpty);
  });

  test('structure and nested order use referenced names and full note additions expose authored text', () {
    final common = <String, Object?>{
      'cards': {
        'card-id': {'title': 'Named card'},
      },
      'nodes': {
        'node-id': {'cardId': 'card-id'},
      },
      'studyNotes': {
        'note-id': {
          'title': 'Notes',
          'sections': {
            'items': {
              'section-id': {
                'title': 'Chapter',
                'blocks': {
                  'items': {
                    'block-id': {'text': 'Nested text'},
                  },
                },
              },
            },
          },
        },
      },
    };
    final before = payload({
      ...common,
      'relations': {
        'edge': {'fromId': null, 'toId': null},
      },
    });
    final candidate = payload({
      ...common,
      'relations': {
        'edge': {'fromId': 'node-id', 'toId': 'block-id'},
      },
    });
    final refs = contentSyncReview(before, candidate, before);
    expect(refs.map((c) => c.candidate), ['Named card', 'Nested text']);
    final added = contentSyncReview(payload({}), payload({'studyNotes': common['studyNotes']}), payload({}));
    expect(added.single.candidate, contains('Chapter'));
    expect(added.single.candidate, contains('Nested text'));
    expect(added.single.current, isNull);
    expect(added.single.candidate, isNot(contains('block-id')));
    final order = contentSyncReview(
      payload({
        ...common,
        'order': ['section-id', 'block-id'],
      }),
      payload({
        ...common,
        'order': ['block-id', 'section-id'],
      }),
      payload(common),
    );
    expect(order.single.candidate, 'Nested text\nChapter');
  });

  test('deletion preserves current excerpt and source storage identifiers never become review text', () {
    final before = payload({
      'documents': {
        'd': {'title': 'Source', 'revision': 'hash-a', 'fileName': 'private/a.pdf'},
      },
    });
    final candidate = payload({
      'documents': {
        'd': {'title': 'Source', 'revision': 'hash-b', 'fileName': 'private/b.pdf'},
      },
    });
    expect(contentSyncReview(before, candidate, before).map((c) => c.candidate), ['', '']);
    final deleted = contentSyncReview(before, payload({'documents': {}}), before);
    expect(deleted.single.current, 'Source');
    expect(deleted.single.candidate, isNull);
    expect(deleted.single.entity, ContentSyncEntity.document);
  });

  test('tags, booleans, layout values and collection baseline stay meaningful', () {
    final before = {
      'title': 'Set',
      'starred': false,
      'colorIndex': 1,
      'tags': ['before'],
    };
    final candidate = {
      'title': 'Set',
      'starred': true,
      'colorIndex': 2,
      'tags': ['after', 'other'],
    };
    expect(contentSyncReview(before, candidate, before).map((c) => c.candidate), ['✓', '2', 'after\nother']);
    final baseline = contentSyncReview(
      payload({
        'studyNotes': {
          'n': {'organizedAt': '2026-01-01'},
        },
      }),
      payload({
        'studyNotes': {
          'n': {'organizedAt': '2026-02-01'},
        },
      }),
      payload({}),
    );
    expect(baseline.single.field, ContentSyncField.collectionBaseline);
    expect(baseline.single.current, isNull);
  });
}
