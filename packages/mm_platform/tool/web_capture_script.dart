import 'dart:io';
import 'dart:convert';

import 'package:mm_platform/src/browser_image_loader_io.dart';

import 'package:mm_platform/src/browser_scripts.dart';

Future<void> main(List<String> args) async {
  if (args.length == 2 && args.first == '--image-url') {
    final bytes = await loadPublicBrowserImage(Uri.parse(args.last), timeout: const Duration(seconds: 8));
    stdout.write(bytes == null ? '' : base64Encode(bytes));
    return;
  }
  stdout.write(
    browserDocumentScript(
      File('packages/mm_platform/assets/readability/Readability.js').readAsStringSync(),
      'testCapture',
      original: args.contains('--original'),
    ),
  );
}
