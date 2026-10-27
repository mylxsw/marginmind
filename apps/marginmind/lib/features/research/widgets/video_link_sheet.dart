import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_research/mm_research.dart';

import '../../../shared/l10n.dart';
import '../research_controller.dart';

Future<void> showVideoLinkSheet(BuildContext context, String studySetId, String sessionId) =>
    showMMSheet<void>(context: context, builder: (_) => _VideoLinkSheet(studySetId, sessionId));

class _VideoLinkSheet extends ConsumerStatefulWidget {
  const _VideoLinkSheet(this.studySetId, this.sessionId);
  final String studySetId;
  final String sessionId;
  @override
  ConsumerState<_VideoLinkSheet> createState() => _VideoLinkSheetState();
}

class _VideoLinkSheetState extends ConsumerState<_VideoLinkSheet> {
  final _text = TextEditingController();
  bool _busy = false;
  bool _invalid = false;
  bool _failed = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final url = Uri.tryParse(_text.text.trim());
    try {
      if (url == null) throw const FormatException();
      videoSource(url, DateTime.now());
    } catch (_) {
      setState(() => _invalid = true);
      return;
    }
    setState(() {
      _busy = true;
      _invalid = false;
      _failed = false;
    });
    try {
      await ref.read(researchPanelProvider(widget.studySetId).notifier).saveVideoLink(widget.sessionId, url);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return MMSheet(
      title: l.researchSaveVideo,
      actions: [
        MMButton(label: l.cancel, onPressed: _busy ? null : () => Navigator.of(context).pop()),
        MMButton(
          key: const ValueKey('video-save'),
          label: l.save,
          variant: MMButtonVariant.primary,
          onPressed: _busy ? null : _save,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MMTextField(
            key: const ValueKey('video-url'),
            controller: _text,
            autofocus: true,
            semanticLabel: l.researchVideoUrl,
          ),
          if (_invalid || _failed) ...[
            const SizedBox(height: MMSpacing.s),
            Text(
              _invalid ? l.researchInvalidVideo : l.somethingWentWrong,
              style: context.mmText.footnote.copyWith(color: context.mmColors.critical),
            ),
          ],
        ],
      ),
    );
  }
}
