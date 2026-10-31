import 'package:flutter_test/flutter_test.dart';
import 'package:marginmind/features/workspace/workspace_pane_chrome_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('adapters dispatch current commands and ignore stale unbinds', () {
    final chrome = WorkspacePaneChromeController();
    final oldOwner = Object(), newOwner = Object();
    var value = 0, notifications = 0;
    chrome.addListener(() => notifications++);
    WorkspacePaneCommands commands(String doc, int n, {bool selected = false}) => WorkspacePaneCommands(doc, {
      'fit': WorkspacePaneCommand(() => value = n, selected: selected),
      'disabled': const WorkspacePaneCommand(null),
    });
    chrome.bindReader(oldOwner, commands('first', 1));
    chrome.reader!.execute('fit');
    expect(value, 1);
    chrome.reader!.execute('disabled');
    chrome.reader!.execute('missing');
    expect(value, 1);
    chrome.bindReader(newOwner, commands('second', 2));
    chrome.unbindReader(oldOwner);
    expect(chrome.reader!.documentKey, 'second');
    chrome.reader!.execute('fit');
    expect(value, 2);
    chrome.bindMap(oldOwner, commands('main', 3));
    chrome.map!.execute('fit');
    expect(value, 3);
    chrome.bindMap(newOwner, commands('other', 4, selected: true));
    chrome.unbindMap(oldOwner);
    expect(chrome.map!.commands['fit']!.selected, isTrue);
    chrome.unbindReader(newOwner);
    expect(chrome.reader, isNull);
    chrome.unbindMap(newOwner);
    expect(chrome.map, isNull);
    expect(notifications, 6);
    chrome.dispose();
  });
  test('same presentation updates callback without redundant notification', () {
    final chrome = WorkspacePaneChromeController(), owner = Object();
    var calls = 0, notifications = 0;
    chrome.addListener(() => notifications++);
    chrome.bindReader(owner, WorkspacePaneCommands('doc', {'fit': WorkspacePaneCommand(() => calls = 1)}));
    chrome.bindReader(owner, WorkspacePaneCommands('doc', {'fit': WorkspacePaneCommand(() => calls = 2)}));
    expect(notifications, 1);
    chrome.reader!.execute('fit');
    expect(calls, 2);
    chrome.dispose();
  });
}
