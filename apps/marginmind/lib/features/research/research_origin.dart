import 'package:mm_core/mm_core.dart';

/// What a card is called where it is listed by name: its title, the note
/// title for a research card, or the excerpt it was made from.
String researchCardTitle(StudySetContent content, String cardId) {
  final card = content.card(cardId);
  if (card == null) return '';
  if (card.kind == CardKind.research) return content.researchNote(card.researchNoteId ?? '')?.title ?? '';
  if (card.title.isEmpty) return content.annotation(card.annotationId ?? '')?.quote ?? '';
  return card.title;
}
