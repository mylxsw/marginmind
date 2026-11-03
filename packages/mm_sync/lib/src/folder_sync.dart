import 'package:mm_core/mm_core.dart';

Map<String, Object?> sharedFolder(Folder folder) => {'id': folder.id, 'name': folder.name};

Folder folderFromSync(String id, Map<String, Object?> value) {
  if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id) ||
      id.length > 128 ||
      value.length != 2 ||
      value['id'] != id ||
      value['name'] is! String) {
    throw const FormatException('Invalid folder identity');
  }
  final name = value['name'] as String;
  if (name.isEmpty || name.length > 256 || name != name.trim()) throw const FormatException('Invalid folder name');
  return Folder(id: id, name: name);
}
