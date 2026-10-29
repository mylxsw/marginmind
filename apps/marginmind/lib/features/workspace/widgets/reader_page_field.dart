import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

import '../../../shared/l10n.dart';

/// Page number badge shared by PDF and fixed EPUB viewports.
class ReaderPageField extends StatefulWidget {
  const ReaderPageField({
    super.key,
    required this.page,
    required this.pageCount,
    required this.onJump,
    required this.editRequests,
  });

  final int page;

  /// Changes when the field should open, without a click.
  final int editRequests;
  final int pageCount;
  final ValueChanged<int> onJump;

  @override
  State<ReaderPageField> createState() => _ReaderPageFieldState();
}

class _ReaderPageFieldState extends State<ReaderPageField> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _editing = false;

  @override
  void didUpdateWidget(ReaderPageField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.editRequests != oldWidget.editRequests) _start();
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _start() {
    _text.text = '${widget.page}';
    _text.selection = TextSelection(baseOffset: 0, extentOffset: _text.text.length);
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _finish({required bool jump}) {
    if (!_editing) return;
    final page = int.tryParse(_text.text.trim());
    setState(() => _editing = false);
    if (jump && page != null) widget.onJump(page);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = context.mmText;
    final style = t.callout.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    if (!_editing) {
      return MMInteractive(
        onTap: _start,
        semanticLabel: l.pageNumberField,
        builder: (context, _) => Text(l.pageOf(widget.page, widget.pageCount), style: style),
      );
    }
    final digits = '${widget.pageCount}'.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 10.0 * digits + 6,
          child: MMInlineTextField(
            controller: _text,
            focusNode: _focus,
            style: style,
            semanticLabel: l.pageNumberField,
            maxLines: 1,
            onSubmitted: () => _finish(jump: true),
            onCancel: () => _finish(jump: false),
            onTapOutside: () => _finish(jump: true),
          ),
        ),
        Text(' / ${widget.pageCount}', style: style),
      ],
    );
  }
}
