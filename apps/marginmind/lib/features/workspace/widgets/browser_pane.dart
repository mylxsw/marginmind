import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../shared/l10n.dart';
import '../../../app/app_commands.dart';
import '../workspace_browser.dart';

class BrowserPane extends ConsumerStatefulWidget {
  const BrowserPane({
    super.key,
    required this.studySetId,
    required this.session,
    required this.visible,
    required this.documentSwitcher,
  });
  final String studySetId;
  final BrowserSession session;
  final bool visible;
  final Widget documentSwitcher;
  @override
  ConsumerState<BrowserPane> createState() => _BrowserPaneState();
}

class _BrowserPaneState extends ConsumerState<BrowserPane> {
  final _address = TextEditingController();
  final _focus = FocusNode();
  BrowserUrlError? _error;
  @override
  void dispose() {
    _address.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _navigate(String value) {
    try {
      final uri = BrowserPolicy.normalize(value);
      setState(() => _error = null);
      unawaited(widget.session.navigate(uri));
      _focus.unfocus();
    } on BrowserUrlException catch (error) {
      setState(() => _error = error.code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final owner = ref.read(workspaceBrowserProvider(widget.studySetId).notifier);
    final l = context.l10n;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (session.disposed) return const SizedBox.shrink();
        if (!_focus.hasFocus) _address.text = session.url.toString();
        return PopScope(
          canPop: !widget.visible,
          onPopInvokedWithResult: (popped, _) {
            if (!popped) {
              if (session.canGoBack) {
                session.back();
              } else {
                owner.close();
              }
            }
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < MMSizes.readerMinWidth;
              final converter = ref.watch(browserConverterProvider);
              void convert() {
                session.dismissPrompt();
                (converter ?? previewBrowserCapture)(context, widget.studySetId, session);
              }

              final commands = browserCommands(l, session, close: owner.close, convert: convert);
              final convertButton = MMButton(
                key: const ValueKey('browser-convert'),
                label: compact ? l.browserConvertShort : l.browserConvert,
                variant: session.canCapture ? MMButtonVariant.primary : MMButtonVariant.secondary,
                // The GUL-577 converter is a separate staged task. Keep the browser
                // command available for its consumer without pretending to save data.
                onPressed: commands[BrowserCommand.convert]!.onInvoke,
              );
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(MMSpacing.s),
                    child: Row(
                      children: [
                        if (compact) MMIconButton(icon: MMIcons.close, tooltip: l.browserClose, onPressed: owner.close),
                        if (!compact) ...[
                          MMIconButton(
                            icon: MMIcons.chevronLeft,
                            tooltip: l.browserBack,
                            onPressed: commands[BrowserCommand.back]!.onInvoke,
                          ),
                          MMIconButton(
                            icon: MMIcons.chevronRight,
                            tooltip: l.browserForward,
                            onPressed: commands[BrowserCommand.forward]!.onInvoke,
                          ),
                        ],
                        MMIconButton(
                          icon: session.loading ? MMIcons.close : MMIcons.history,
                          tooltip: session.loading ? l.browserStop : l.browserReload,
                          onPressed: commands[session.loading ? BrowserCommand.stop : BrowserCommand.reload]!.onInvoke,
                        ),
                        Expanded(
                          child: MMTextField(
                            controller: _address,
                            focusNode: _focus,
                            semanticLabel: l.browserAddress,
                            onSubmitted: _navigate,
                          ),
                        ),
                        const SizedBox(width: MMSpacing.s),
                        convertButton,
                        if (!compact) ...[
                          MMIconButton(icon: MMIcons.close, tooltip: l.browserClose, onPressed: owner.close),
                          widget.documentSwitcher,
                        ],
                      ],
                    ),
                  ),
                  if (_error != null)
                    Text(
                      browserUrlError(context, _error!),
                      style: context.mmText.footnote.copyWith(color: context.mmColors.critical),
                    ),
                  if (session.prompt)
                    // Keep the nonmodal prompt above the native surface: child HWNDs
                    // cannot be composited under a Flutter overlay on Windows.
                    Container(
                      key: const ValueKey('browser-ready-prompt'),
                      padding: const EdgeInsets.all(MMSpacing.m),
                      decoration: BoxDecoration(
                        color: context.mmColors.fill,
                        borderRadius: BorderRadius.circular(MMRadii.dropdown),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              session.phase == BrowserPhase.slow ? l.browserStillLoading : l.browserReady,
                              style: context.mmText.headline,
                            ),
                          ),
                          MMButton(label: l.browserLater, onPressed: session.dismissPrompt),
                          const SizedBox(width: MMSpacing.s),
                          MMButton(label: l.browserConvertShort, variant: MMButtonVariant.primary, onPressed: convert),
                        ],
                      ),
                    ),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: MMBrowserView(
                            session: session,
                            visible: widget.visible && session.phase != BrowserPhase.failed,
                          ),
                        ),
                        if (session.phase == BrowserPhase.failed)
                          Positioned.fill(
                            child: ColoredBox(
                              color: context.mmColors.windowBackground,
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(MMIcons.web, color: context.mmColors.secondaryLabel),
                                    const SizedBox(height: MMSpacing.m),
                                    Text(l.browserFailed, style: context.mmText.headline),
                                    const SizedBox(height: MMSpacing.m),
                                    MMButton(label: l.browserRetry, onPressed: session.reload),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
