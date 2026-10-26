import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final imagePickerProvider = Provider<Future<List<String>> Function(String)>(
  (ref) =>
      (label) async => [
        for (final file in await openFiles(
          acceptedTypeGroups: [
            XTypeGroup(
              label: label,
              extensions: const ['png', 'jpg', 'jpeg'],
              uniformTypeIdentifiers: const ['public.png', 'public.jpeg'],
            ),
          ],
        ))
          file.path,
      ],
);
