import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../shared/l10n.dart';
import '../../../app/app_commands.dart';
import '../workspace_browser.dart';

class BrowserPane extends ConsumerStatefulWidget {
  const BrowserPane({super.key, required this.studySetId, required this.session, required this.visible});
  final String studySetId;
  final BrowserSession session;
  final bool visible;
  @override
  ConsumerState<BrowserPane> createState() => _BrowserPaneState();
}

class _BrowserPaneState extends ConsumerState<BrowserPane> {
  final _address = TextEditingController();
  final _focus = FocusNode();
  BrowserUrlError? _error;
  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (_focus.hasFocus) {
      final text = widget.session.url.toString();
      _address.value = TextEditingValue(
        text: text,
        selection: TextSelection(baseOffset: 0, extentOffset: text.length),
      );
    }
    setState(() {});
  }

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
    final browser = ref.watch(workspaceBrowserProvider(widget.studySetId));
    final l = context.l10n;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (session.disposed) return const SizedBox.shrink();
        return MMBackHandler(
          onBack: () {
            if (!widget.visible) return false;
            if (session.canGoBack) {
              unawaited(session.back());
            } else {
              owner.close(session.id);
            }
            return true;
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < MMSizes.readerMinWidth;
              if (!_focus.hasFocus) _address.text = compact ? session.url.host : session.url.toString();
              final reason = switch (session.loadError) {
                BrowserLoadError.timeout => l.webErrorTimeout,
                BrowserLoadError.host => l.webErrorHost,
                BrowserLoadError.certificate => l.webErrorCertificate,
                BrowserLoadError.offline => l.webErrorOffline,
                BrowserLoadError.other => null,
              };
              final converter = ref.watch(browserConverterProvider);
              void convert() {
                session.dismissPrompt();
                (converter ?? previewBrowserCapture)(context, widget.studySetId, session);
              }

              final page = browser.page(session.id);
              final updating = page?.replacingDocumentId != null;
              final nativeWindows = defaultTargetPlatform == TargetPlatform.windows;
              final commands = browserCommands(
                l,
                session,
                close: () => owner.close(session.id),
                convert: convert,
                converting: browser.converting,
                updating: updating,
              );
              final reload = MMIconButton(
                icon: session.loading ? MMIcons.stop : MMIcons.regenerate,
                tooltip: session.loading ? l.browserStop : l.browserReload,
                onPressed: commands[session.loading ? BrowserCommand.stop : BrowserCommand.reload]!.onInvoke,
              );
              final convertButton = MMIconButton(
                key: const ValueKey('browser-convert'),
                icon: MMIcons.webConvert,
                tooltip: updating ? l.browserUpdate : l.browserConvert,
                onPressed: browser.converting ? null : commands[BrowserCommand.convert]!.onInvoke,
              );
              final prompt = Container(
                key: const ValueKey('browser-ready-prompt'),
                width: (constraints.maxWidth - 24).clamp(0.0, 330.0),
                padding: const EdgeInsets.all(MMSpacing.m),
                decoration: BoxDecoration(
                  color: context.mmColors.surface,
                  borderRadius: BorderRadius.circular(MMRadii.dropdown),
                  border: Border.all(color: context.mmColors.border, width: .5),
                  boxShadow: context.mmColors.glassShadow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(MMIcons.webConvert, size: 20, color: context.mmColors.accent),
                        const SizedBox(width: MMSpacing.s),
                        Expanded(
                          child: Text(
                            updating ? l.browserUpdate : l.webSaveDocumentTitle,
                            style: context.mmText.headline,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: MMSpacing.s),
                    Text(
                      session.phase == BrowserPhase.slow
                          ? l.webStillLoading
                          : updating
                          ? l.webUpdatePrompt
                          : l.webReadyPrompt,
                      style: context.mmText.bodySecondary,
                    ),
                    const SizedBox(height: MMSpacing.m),
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: MMSpacing.s,
                        runSpacing: MMSpacing.s,
                        children: [
                          MMButton(
                            label: updating ? l.webUpdateAction : l.browserConvert,
                            variant: MMButtonVariant.primary,
                            onPressed: browser.converting ? null : convert,
                          ),
                          MMButton(
                            label: session.phase == BrowserPhase.slow ? l.webKeepWaiting : l.webLater,
                            variant: MMButtonVariant.plain,
                            onPressed: session.dismissPrompt,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(MMSpacing.s),
                    child: Row(
                      children: [
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
                        if (!compact) reload,
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(MMRadii.capsule),
                            child: Container(
                              height: MMInput.of(context).touchPlatform
                                  ? MMSizes.browserAddressTouch
                                  : MMSizes.browserAddress,
                              color: context.mmColors.quaternaryFill,
                              child: Stack(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: MMSpacing.s),
                                    child: Row(
                                      children: [
                                        Icon(
                                          session.phase == BrowserPhase.failed ? MMIcons.warning : MMIcons.lock,
                                          size: MMSizes.dropdownIcon,
                                          color: context.mmColors.secondaryLabel,
                                        ),
                                        const SizedBox(width: MMSpacing.s),
                                        Expanded(
                                          child: MMTextField(
                                            controller: _address,
                                            focusNode: _focus,
                                            plain: true,
                                            semanticLabel: l.webUrlPlaceholder,
                                            onSubmitted: _navigate,
                                          ),
                                        ),
                                        if (compact) reload,
                                      ],
                                    ),
                                  ),
                                  if (session.loading)
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      child: LinearProgressIndicator(
                                        key: const ValueKey('browser-load-progress'),
                                        minHeight: MMSizes.browserProgressTrack,
                                        color: context.mmColors.accent,
                                        backgroundColor: context.mmColors.quaternaryFill,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: MMSpacing.s),
                        convertButton,
                      ],
                    ),
                  ),
                  if (_error != null)
                    Text(
                      browserUrlError(context, _error!),
                      style: context.mmText.footnote.copyWith(color: context.mmColors.critical),
                    ),
                  if (session.prompt && nativeWindows)
                    // WebView2 child HWNDs cannot sit beneath Flutter overlays.
                    // Reserve a short row on Windows; other hosts float the prompt.
                    Align(alignment: Alignment.centerRight, child: prompt),
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
                                    Text(l.webErrorTitle, style: context.mmText.headline),
                                    if (reason != null) ...[
                                      const SizedBox(height: MMSpacing.s),
                                      Text(reason, style: context.mmText.bodySecondary),
                                    ],
                                    const SizedBox(height: MMSpacing.m),
                                    MMButton(label: l.webRetry, onPressed: session.reload),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (widget.visible && session.prompt && !nativeWindows)
                          Positioned(top: 8, right: 12, child: prompt),
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
