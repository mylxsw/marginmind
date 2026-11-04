import 'package:mm_core/mm_core.dart';
import 'package:mm_sync/mm_sync.dart';
import 'package:test/test.dart';

void main() {
  test('folder schema round trips unicode and rejects malformed identities and fields', () {
    const folder = Folder(id: 'f-1', name: '语言 📚');
    expect(folderFromSync(folder.id, sharedFolder(folder)), folder);
    for (final value in [
      {'id': 'other', 'name': 'valid'},
      {'id': 'f-1', 'name': ''},
      {'id': 'f-1', 'name': ' space '},
      {'id': 'f-1', 'name': 'x' * 257},
      {'id': 'f-1', 'name': 1},
      {'id': 'f-1', 'name': 'name', 'extra': true},
    ]) {
      expect(() => folderFromSync(folder.id, value), throwsFormatException);
    }
    for (final id in ['', '../outside', 'x' * 129]) {
      expect(() => folderFromSync(id, {'id': id, 'name': 'Name'}), throwsFormatException);
    }
  });
}
