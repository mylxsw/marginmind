import '../ids.dart';
import 'editor.dart';
import 'reading.dart';
import 'reading_editor.dart';
import 'study_set_content.dart';
import 'study_set_content_repository.dart';

/// Works for native, browser and in-memory stores. Each operation sees the
/// latest content inside update, including concurrently completed translations.
extension ReadingRepository on StudySetContentRepository {
  StudySetEditor get _readingEditor => StudySetEditor(newId: newId, now: DateTime.now);
  Future<StudySetContent> setDocumentCrop(String setId, String documentId, DocumentCrop? crop) =>
      update(setId, (c) => _readingEditor.setDocumentCrop(c, documentId, crop));
  Future<StudySetContent> upsertMarginNote(String setId, MarginNote note) =>
      update(setId, (c) => _readingEditor.upsertMarginNote(c, note));
  Future<StudySetContent> removeMarginNote(String setId, String id) =>
      update(setId, (c) => _readingEditor.removeMarginNote(c, id));
  Future<StudySetContent> upsertComparePair(String setId, ComparePair pair) =>
      update(setId, (c) => _readingEditor.upsertComparePair(c, pair));
  Future<StudySetContent> removeComparePair(String setId, String id) =>
      update(setId, (c) => _readingEditor.removeComparePair(c, id));
  Future<StudySetContent> mergeTranslationParagraphs(String setId, TranslationCache cache) =>
      update(setId, (c) => _readingEditor.mergeTranslationParagraphs(c, cache));
  Future<StudySetContent> removeTranslationCache(String setId, String documentId, String targetLang) =>
      update(setId, (c) => _readingEditor.removeTranslationCache(c, documentId, targetLang));
}
