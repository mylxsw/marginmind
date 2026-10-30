/// Keep user titles out of path separators and platform-reserved characters.
String noteFileName(String title, String extension) {
  final sanitized = title.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]'), '').trim();
  return '${sanitized.isEmpty ? 'note' : sanitized}.$extension';
}
