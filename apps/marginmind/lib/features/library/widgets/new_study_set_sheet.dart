import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';

import '../../../app/providers.dart';
import '../../../shared/l10n.dart';
import '../../workspace/widgets/notices.dart';
import '../../workspace/workspace_controller.dart';
import '../library_controller.dart';

Future<void> showNewStudySetSheet(BuildContext context, WidgetRef ref) {
  return showMMSheet<void>(context: context, builder: (_) => const NewStudySetSheet());
}

/// ⌘N: name, location, color, "import after creating". Return creates,
/// Esc cancels.
class NewStudySetSheet extends ConsumerStatefulWidget {
  const NewStudySetSheet({super.key});

  @override
  ConsumerState<NewStudySetSheet> createState() => _NewStudySetSheetState();
}

class _NewStudySetSheetState extends ConsumerState<NewStudySetSheet> {
  final _name = TextEditingController();
  String? _folderId;
  MMAnnotationColor _color = MMAnnotationColor.blue;
  bool _importAfter = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    final filter = ref.read(libraryViewProvider).query.filter;
    if (filter is FolderFilter) _folderId = filter.folderId;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canCreate => _name.text.trim().isNotEmpty && !_busy;

  Future<void> _create() async {
    if (!_canCreate) return;
    setState(() => _busy = true);
    final l = context.l10n;
    var files = const <XFile>[];
    if (_importAfter) {
      try {
        files = await openFiles(
          acceptedTypeGroups: [
            XTypeGroup(label: l.pdfFiles, extensions: const ['pdf'], uniformTypeIdentifiers: const ['com.adobe.pdf']),
          ],
        );
      } catch (_) {
        // No picker available: create the set anyway; import works later.
      }
    }
    final created = await ref
        .read(studySetRepositoryProvider)
        .create(NewStudySet(title: _name.text, colorIndex: _color.index, folderId: _folderId));
    final library = ref.read(libraryViewProvider.notifier)
      ..setFilter(LibraryFilter.all)
      ..select(created.id);
    if (!mounted) return;
    // The sheet is gone after pop(); keep using the app's container.
    final container = ProviderScope.containerOf(context, listen: false);
    final navigator = Navigator.of(context);
    final hudContext = navigator.context;
    navigator.pop();
    if (files.isEmpty) {
      if (hudContext.mounted) MMHud.show(hudContext, l.createdHud(created.title));
      return;
    }
    final notice = await container.read(workspaceProvider(created.id).notifier).importDocuments([
      for (final f in files) (path: f.path, name: f.name),
    ]);
    await library.open(created.id);
    if (hudContext.mounted) showNotice(hudContext, notice, rootTitle: created.title);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final folders = ref.watch(foldersProvider).value ?? const <Folder>[];
    return MMSheet(
      title: l.newStudySet,
      actions: [
        MMButton(label: l.cancel, onPressed: () => Navigator.of(context).pop()),
        MMButton(label: l.create, variant: MMButtonVariant.primary, onPressed: _canCreate ? _create : null),
      ],
      child: Column(
        children: [
          MMFormRow(
            label: l.sheetName,
            child: MMTextField(
              controller: _name,
              autofocus: true,
              placeholder: l.sheetNamePlaceholder,
              semanticLabel: l.sheetName,
              onSubmitted: (_) => _create(),
            ),
          ),
          if (folders.isNotEmpty)
            MMFormRow(
              label: l.sheetLocation,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: MMSegmentedControl<String?>(
                  value: _folderId,
                  onChanged: (v) => setState(() => _folderId = v),
                  segments: [
                    for (final f in folders) MMSegment(value: f.id, label: f.name),
                    MMSegment(value: null, label: l.libraryUnfiled),
                  ],
                ),
              ),
            ),
          MMFormRow(
            label: l.sheetColor,
            child: MMColorPicker(selected: _color, onChanged: (v) => setState(() => _color = v), labelOf: l.colorName),
          ),
          MMFormRow(
            label: '',
            child: _Checkbox(
              value: _importAfter,
              label: l.sheetImportAfterCreate,
              onChanged: (v) => setState(() => _importAfter = v),
            ),
          ),
        ],
      ),
    );
  }
}

class _Checkbox extends StatelessWidget {
  const _Checkbox({required this.value, required this.label, required this.onChanged});

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.mmColors;
    return MergeSemantics(
      child: Semantics(
        checked: value,
        child: MMInteractive(
          onTap: () => onChanged(!value),
          semanticLabel: label,
          builder: (context, s) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: value ? c.accent : c.card,
                  borderRadius: BorderRadius.circular(3.5),
                  border: Border.all(color: value ? c.accent : c.secondaryLabel.withValues(alpha: 0.5), width: 0.5),
                ),
                child: value ? Icon(Icons.check, size: 11, color: c.onAccent) : null,
              ),
              const SizedBox(width: 8),
              Flexible(child: Text(label, style: context.mmText.body)),
            ],
          ),
        ),
      ),
    );
  }
}
