import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'capabilities.dart';
import 'file_share.dart';

import 'note_files_native.dart' if (dart.library.js_interop) 'note_files_web.dart' as files;

/// The system save panel and relative image assets of a portable study note.
abstract final class MMNoteFiles {
  static Future<bool> save(String name, Uint8List bytes, {Map<String, Uint8List> attachments = const {}}) async {
    if (MMPlatformCapabilities.current.shareFile) return const MobileFileShare().share(name, bytes);
    final extension = p.extension(name).replaceFirst('.', '');
    final mime = switch (extension) {
      'pdf' => 'application/pdf',
      'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'png' => 'image/png',
      'html' => 'text/html',
      _ => 'text/markdown',
    };
    if (kIsWeb) {
      if (attachments.isNotEmpty) throw UnsupportedError('Image assets require a desktop export');
      await XFile.fromData(bytes, name: name, mimeType: mime).saveTo('');
      return true;
    }
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: [
        XTypeGroup(label: extension.toUpperCase(), extensions: [extension]),
      ],
    );
    if (location == null) return false;
    for (final entry in attachments.entries) {
      if (!entry.key.startsWith('attachments/') ||
          p.split(entry.key).length != 2 ||
          entry.key.contains('\\') ||
          p.split(entry.key).any((s) => s == '..' || s == '.')) {
        throw ArgumentError('Unsafe attachment path');
      }
      await files.write(p.dirname(location.path), entry.key, entry.value);
    }
    await XFile.fromData(bytes, name: name, mimeType: mime).saveTo(location.path);
    return true;
  }

  static Future<bool> exists(String path) async {
    try {
      return await XFile(path).length() > 0;
    } catch (_) {
      return false;
    }
  }

  static Future<Uint8List> read(String path) => XFile(path).readAsBytes();
}
