import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../workspace/workspace_controller.dart';

class ResearchPanelState {
  const ResearchPanelState({this.noteId});
  final String? noteId;
}

class ResearchPanelController extends Notifier<ResearchPanelState> {
  ResearchPanelController(this.studySetId);
  final String studySetId;
  @override
  ResearchPanelState build() => const ResearchPanelState();
  void showNote(String noteId, {PanelOrigin origin = PanelOrigin.toolbar}) {
    state = ResearchPanelState(noteId: noteId);
    ref.read(workspaceProvider(studySetId).notifier).openPanel(RightPanel.assistant, origin: origin);
  }

  void closeNote() => state = const ResearchPanelState();
}

final researchPanelProvider = NotifierProvider.family<ResearchPanelController, ResearchPanelState, String>(
  ResearchPanelController.new,
);
