import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Markdown can read resources beneath its own directory, including symlink
/// resolution. It cannot turn a document into an arbitrary local file reader.
Future<Uint8List?> readRelativeResource(String source, String path) async {
  final uri = Uri.tryParse(path);
  if (uri == null || uri.hasScheme || p.isAbsolute(path)) return null;
  final directory = await File(source).parent.resolveSymbolicLinks();
  final candidate = File(p.normalize(p.join(directory, Uri.decodeComponent(path))));
  if (!p.isWithin(directory, candidate.path) || !await candidate.exists()) return null;
  final resolved = await candidate.resolveSymbolicLinks();
  if (!p.isWithin(directory, resolved) || await File(resolved).length() > 32 * 1024 * 1024) return null;
  return File(resolved).readAsBytes();
}
