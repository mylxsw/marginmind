import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

/// Shared compact navigation for PDF and reflow reader sidebars.
class ReaderSidebarTabBar extends StatelessWidget {
  const ReaderSidebarTabBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (MMInput.of(context).phone) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: MMReaderNavigationLayout.inset),
        child: LayoutBuilder(
          builder: (context, bounds) {
            var slot = bounds.maxWidth / children.length;
            for (final tab in children.whereType<ReaderSidebarTab>()) {
              final painter = TextPainter(
                text: TextSpan(
                  text: tab.label,
                  style: context.mmText.body.copyWith(fontWeight: FontWeight.w600),
                ),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout();
              final required = painter.width + MMSpacing.m * 2;
              if (required > slot) slot = required;
              painter.dispose();
            }
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: slot * children.length,
                child: Row(children: [for (final child in children) Expanded(child: child)]),
              ),
            );
          },
        ),
      );
    }
    return MMCompactToolbarScope(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: LayoutBuilder(
          builder: (context, bounds) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: bounds.maxWidth),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Phone section navigation uses text and an underline on the panel surface.
class ReaderSidebarTab extends StatelessWidget {
  const ReaderSidebarTab({super.key, required this.label, required this.selected, required this.onPressed});
  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => MMInteractive(
    semanticLabel: label,
    selected: selected,
    onTap: onPressed,
    builder: (context, state) => Container(
      constraints: const BoxConstraints(minHeight: MMReaderNavigationLayout.tabHeight),
      color: state.pressed ? context.mmColors.pressed : null,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MMSpacing.m, vertical: 10),
            child: Text(
              label,
              maxLines: 1,
              style: context.mmText.body.copyWith(
                color: selected ? context.mmColors.label : context.mmColors.secondaryLabel,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (selected)
            Positioned(
              bottom: 0,
              width: MMReaderNavigationLayout.underlineWidth,
              height: MMSpacing.xxs,
              child: ColoredBox(color: context.mmColors.label),
            ),
        ],
      ),
    ),
  );
}

/// Phone navigation covers the reader without disposing its viewport.
class PhoneReaderNavigationFrame extends StatefulWidget {
  const PhoneReaderNavigationFrame({
    super.key,
    required this.title,
    required this.onClose,
    required this.child,
    this.open = true,
    this.nativePresentation,
  });
  final bool open;
  final Future<bool> Function()? nativePresentation;
  final String title;
  final VoidCallback onClose;
  final Widget child;
  @override
  State<PhoneReaderNavigationFrame> createState() => _PhoneReaderNavigationFrameState();
}

class _PhoneReaderNavigationFrameState extends State<PhoneReaderNavigationFrame> {
  bool _showing = false;
  bool _managing = false;
  @override
  void didUpdateWidget(PhoneReaderNavigationFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.open) _managing = false;
  }

  @override
  Widget build(BuildContext context) {
    if (MMNativePresentation.available && widget.nativePresentation != null && !_managing) {
      if (widget.open && !_showing) {
        _showing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted || !widget.open) {
            _showing = false;
            return;
          }
          try {
            final manage = await widget.nativePresentation!();
            if (!mounted) return;
            setState(() {
              _showing = false;
              _managing = manage;
            });
            if (!manage) widget.onClose();
          } catch (error, stack) {
            debugPrint('Native reader navigation failed: $error\n$stack');
            if (mounted) {
              setState(() {
                _showing = false;
                _managing = true;
              });
            }
          }
        });
      }
      return const SizedBox.shrink();
    }
    return MMBottomSheet(
      expand: true,
      initialFraction: MMSizes.phoneSheetExpanded,
      scrim: true,
      onDismiss: widget.onClose,
      child: Material(
        key: const ValueKey('phone-document-navigation'),
        type: MaterialType.transparency,
        child: SafeArea(
          top: false,
          child: Semantics(label: widget.title, container: true, explicitChildNodes: true, child: widget.child),
        ),
      ),
    );
  }
}
