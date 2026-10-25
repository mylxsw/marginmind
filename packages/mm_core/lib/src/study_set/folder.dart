import 'package:meta/meta.dart';

/// A user folder in the library sidebar. Study sets without a folder are
/// shown under "Unfiled".
@immutable
class Folder {
  const Folder({required this.id, required this.name});

  final String id;
  final String name;

  @override
  bool operator ==(Object other) => other is Folder && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}
