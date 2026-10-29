import 'dart:io';

import 'package:mm_platform/src/browser_scripts.dart';

void main(List<String> args) {
  stdout.write(
    browserDocumentScript(
      File('packages/mm_platform/assets/readability/Readability.js').readAsStringSync(),
      'testCapture',
      original: args.contains('--original'),
    ),
  );
}
