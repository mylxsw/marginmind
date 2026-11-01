import 'package:flutter/material.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

/// A quiet reading rail. It scrolls independently from the note and keeps the
/// current chapter visible without rebuilding the editable document on scroll.
class NoteContents extends StatefulWidget {
  const NoteContents({
    super.key,
    required this.title,
    required this.sections,
    required this.activeId,
    required this.onSelected,
  });

  final String title;
  final List<NoteSection> sections;
  final String activeId;
  final ValueChanged<String> onSelected;

  @override
  State<NoteContents> createState() => _NoteContentsState();
}

class _NoteContentsState extends State<NoteContents> {
  final _scroll = ScrollController();
  final _keys = <String, GlobalKey>{};

  @override
  void didUpdateWidget(NoteContents oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = widget.sections.map((s) => s.id).toSet();
    _keys.removeWhere((id, _) => !ids.contains(id));
    if (oldWidget.activeId != widget.activeId) {
      final movingBack =
          widget.sections.indexWhere((s) => s.id == widget.activeId) <
          widget.sections.indexWhere((s) => s.id == oldWidget.activeId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final target = _keys[widget.activeId]?.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : MMMotion.quick,
            alignmentPolicy: movingBack
                ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
                : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    final numberWidth =
        (MediaQuery.textScalerOf(context).scale(context.mmText.callout.fontSize!) *
                    widget.sections.length.toString().length *
                    .65 +
                8)
            .clamp(26.0, double.infinity);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        key: const ValueKey('note-contents'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 14, bottom: 12),
            child: Text(widget.title, style: context.mmText.subheadline.copyWith(color: c.secondaryLabel)),
          ),
          Flexible(
            child: Scrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                key: const ValueKey('note-contents-scroll'),
                controller: _scroll,
                primary: false,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: c.separator)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (index, section) in widget.sections.indexed)
                        KeyedSubtree(
                          key: _keys.putIfAbsent(section.id, GlobalKey.new),
                          child: MMInteractive(
                            key: ValueKey('note-contents-${section.id}'),
                            selected: section.id == widget.activeId,
                            semanticLabel: '${index + 1}. ${section.title}',
                            tooltip: section.title,
                            onTap: () => widget.onSelected(section.id),
                            builder: (context, state) {
                              final selected = section.id == widget.activeId;
                              return Container(
                                constraints: BoxConstraints(minHeight: context.mmTouchPlatform ? 44 : 36),
                                padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                                decoration: BoxDecoration(
                                  color: state.pressed
                                      ? c.pressed
                                      : state.hovered || state.focused
                                      ? c.hover
                                      : Colors.transparent,
                                  border: Border(
                                    left: BorderSide(
                                      color: selected || state.focused ? c.accent : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: numberWidth,
                                      child: Text(
                                        '${index + 1}',
                                        style: context.mmText.callout.copyWith(
                                          height: 1.45,
                                          color: selected ? c.accent : c.secondaryLabel,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        section.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: context.mmText.callout.copyWith(
                                          height: 1.45,
                                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                                          color: selected ? c.accent : c.secondaryLabel,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
