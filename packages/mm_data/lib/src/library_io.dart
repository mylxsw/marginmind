import 'dart:io' show Directory;
export 'dart:io';

String resourcePath(String path) => path;

Directory browserRoot() => throw UnsupportedError('Browser storage requires the browser');
