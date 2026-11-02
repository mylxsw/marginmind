import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../shared/l10n.dart';
import '../../shared/phone_form.dart';
import '../../shared/pdf_drop.dart';
import '../../shared/pdf_picker.dart';
import '../workspace/widgets/notices.dart';
import '../workspace/workspace_browser.dart';
import 'library_controller.dart';

enum _Source { blank, document, web }

typedef _Creation = ({String title, List<DroppedFile> files, Uri? url});

/// All library buttons and the New Study Set command share this entry point.
Future<void> showNewStudySet(BuildContext context, WidgetRef ref) async {
  final container = ProviderScope.containerOf(context);
  final controller = ref.read(libraryViewProvider.notifier);
  final picker = ref.read(pdfPickerProvider);
  final request = usesNativePhonePresentation(context)
      ? await _nativeCreation(context, picker)
      : await showMMSheet<_Creation>(
          context: context,
          width: 500,
          builder: (_) => _NewStudySetSheet(picker: picker),
        );
  if (request == null || !context.mounted) return;
  final failureMessage = context.l10n.somethingWentWrong;
  try {
    if (request.files.isNotEmpty) {
      final notice = await controller.createFromFiles(request.files, title: request.title);
      if (context.mounted) showNotice(context, notice, rootTitle: '');
    } else {
      final created = await controller.createBlank(request.title);
      if (request.url case final url?) {
        // Bridge the auto-disposed browser until the workspace subscribes.
        // The library itself may already be unmounted after open().
        final browser = workspaceBrowserProvider(created.id);
        final lease = container.listen(browser, (_, _) {});
        try {
          container.read(browser.notifier).open(url);
          await WidgetsBinding.instance.endOfFrame;
        } finally {
          lease.close();
        }
      }
    }
  } catch (error, stack) {
    debugPrint('Could not create study set: $error\n$stack');
    if (context.mounted) MMHud.show(context, failureMessage);
  }
}

Future<_Creation?> _nativeCreation(BuildContext context, PdfPicker picker) async {
  final l = context.l10n;
  final source = await MMNativePresentation.confirm(
    dark: Theme.of(context).brightness == Brightness.dark,
    title: l.newStudySet,
    cancel: l.cancel,
    actions: [
      MMNativeAction('blank', l.newStudySetBlank),
      MMNativeAction('document', l.newStudySetDocument),
      if (MMPlatformCapabilities.current.webBrowser) MMNativeAction('web', l.newStudySetWeb),
    ],
  );
  if (source == null || !context.mounted) return null;
  var files = <DroppedFile>[];
  if (source == 'document') {
    try {
      files = await picker(l.documentFiles);
    } catch (_) {
      if (context.mounted) MMHud.show(context, l.somethingWentWrong);
      return null;
    }
    if (files.isEmpty || !context.mounted) return null;
  }
  final values = await showPhoneForm(
    context,
    title: l.newStudySet,
    submit: l.create,
    message: source == 'blank'
        ? l.newStudySetBlankHint
        : source == 'document'
        ? l.newStudySetDocumentHint
        : l.newStudySetWebHint,
    fields: [
      MMNativeField(id: 'title', label: l.sheetName, placeholder: l.newStudySetDefaultName),
      if (source == 'web')
        const MMNativeField(id: 'url', label: 'URL', keyboard: 'url', placeholder: 'https://example.com'),
    ],
    validate: (values) {
      if (source != 'web') return null;
      try {
        BrowserPolicy.normalize(values['url']!);
        return null;
      } on BrowserUrlException catch (error) {
        return browserUrlError(context, error.code);
      }
    },
  );
  if (values == null) return null;
  final url = source == 'web' ? BrowserPolicy.normalize(values['url']!) : null;
  final fallback =
      url?.host ?? (files.isEmpty ? l.newStudySetDefaultName : files.first.name.replaceFirst(RegExp(r'\.[^.]+$'), ''));
  return (title: values['title']!.trim().isEmpty ? fallback : values['title']!.trim(), files: files, url: url);
}

class _NewStudySetSheet extends StatefulWidget {
  const _NewStudySetSheet({required this.picker});
  final PdfPicker picker;

  @override
  State<_NewStudySetSheet> createState() => _NewStudySetSheetState();
}

class _NewStudySetSheetState extends State<_NewStudySetSheet> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  _Source _source = _Source.blank;
  List<DroppedFile> _files = const [];
  BrowserUrlError? _error;
  bool _picking = false;
  bool _submitted = false;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() => _picking = true);
    try {
      final files = await widget.picker(context.l10n.documentFiles);
      if (mounted && files.isNotEmpty) setState(() => _files = files);
    } catch (_) {
      if (mounted) MMHud.show(context, context.l10n.somethingWentWrong);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _create() {
    if (_submitted || _picking || (_source == _Source.document && _files.isEmpty)) return;
    Uri? url;
    if (_source == _Source.web) {
      try {
        url = BrowserPolicy.normalize(_url.text);
      } on BrowserUrlException catch (error) {
        setState(() => _error = error.code);
        return;
      }
    }
    final files = _source == _Source.document ? _files : const <DroppedFile>[];
    final fallback =
        url?.host ??
        (files.isEmpty ? context.l10n.newStudySetDefaultName : files.first.name.replaceFirst(RegExp(r'\.[^.]+$'), ''));
    _submitted = true;
    Navigator.of(context)
        .pop<_Creation>((title: _name.text.trim().isEmpty ? fallback : _name.text.trim(), files: files, url: url));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final create = MMButton(
      label: l.create,
      variant: MMButtonVariant.primary,
      onPressed: _picking || (_source == _Source.document && _files.isEmpty) ? null : _create,
    );
    return PopScope(
      canPop: !_picking,
      child: MMSheet(
        title: l.newStudySet,
        titleTrailing: MMBottomSheet.contains(context) ? create : null,
        actions: [
          MMButton(label: l.cancel, onPressed: _picking ? null : () => Navigator.of(context).pop()),
          if (!MMBottomSheet.contains(context)) create,
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MMSegmentedControl<_Source>(
              expand: true,
              value: _source,
              onChanged: _picking ? null : (value) => setState(() => _source = value),
              segments: [
                MMSegment(value: _Source.blank, label: l.newStudySetBlank),
                MMSegment(value: _Source.document, label: l.newStudySetDocument),
                if (MMPlatformCapabilities.current.webBrowser) MMSegment(value: _Source.web, label: l.newStudySetWeb),
              ],
            ),
            const SizedBox(height: MMSpacing.m),
            Text(switch (_source) {
              _Source.blank => l.newStudySetBlankHint,
              _Source.document => l.newStudySetDocumentHint,
              _Source.web => l.newStudySetWebHint,
            }, style: context.mmText.callout.copyWith(color: context.mmColors.secondaryLabel)),
            const SizedBox(height: MMSpacing.m),
            MMTextField(
              controller: _name,
              semanticLabel: l.newStudySetName,
              placeholder: l.newStudySetName,
              autofocus: true,
              enabled: !_picking,
              onSubmitted: (_) => _create(),
            ),
            if (_source == _Source.document) ...[
              const SizedBox(height: MMSpacing.m),
              MMButton(label: l.newStudySetChooseDocuments, onPressed: _picking ? null : _pick),
              for (final file in _files)
                Padding(
                  padding: const EdgeInsets.only(top: MMSpacing.xs),
                  child: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.mmText.callout),
                ),
            ],
            if (_source == _Source.web) ...[
              const SizedBox(height: MMSpacing.m),
              MMTextField(
                controller: _url,
                semanticLabel: l.webUrlLabel,
                placeholder: 'https://',
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _create(),
              ),
              if (_error != null)
                Text(
                  browserUrlError(context, _error!),
                  style: context.mmText.footnote.copyWith(color: context.mmColors.critical),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
