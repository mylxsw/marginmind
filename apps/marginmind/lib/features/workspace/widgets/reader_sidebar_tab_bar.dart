import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

/// Shared compact navigation for PDF and reflow reader sidebars.
class ReaderSidebarTabBar extends StatelessWidget {
  const ReaderSidebarTabBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => MMCompactToolbarScope(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: LayoutBuilder(
        builder: (context, bounds) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: bounds.maxWidth),
            child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: children),
          ),
        ),
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
    return MMNativeGlassScope(
      enabled: true,
      child: MMBottomSheet(
        expand: true,
        scrim: true,
        onDismiss: widget.onClose,
        child: Material(
          key: const ValueKey('phone-document-navigation'),
          type: MaterialType.transparency,
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: context.mmText.headline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      MMIconButton(
                        key: const ValueKey('phone-document-navigation-close'),
                        icon: MMIcons.close,
                        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),
                ),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
