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
class PhoneReaderNavigationFrame extends StatelessWidget {
  const PhoneReaderNavigationFrame({super.key, required this.title, required this.onClose, required this.child});
  final String title;
  final VoidCallback onClose;
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('phone-document-navigation'),
    color: context.mmColors.windowBackground,
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
                  child: Text(title, style: context.mmText.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                MMIconButton(
                  key: const ValueKey('phone-document-navigation-close'),
                  icon: MMIcons.close,
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    ),
  );
}
