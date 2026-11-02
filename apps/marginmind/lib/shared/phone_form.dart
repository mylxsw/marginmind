import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mm_design/mm_design.dart';

import 'l10n.dart';

Future<Map<String, String>?> showPhoneForm(
  BuildContext context, {
  required String title,
  required String submit,
  required List<MMNativeField> fields,
  String? message,
  FutureOr<String?> Function(Map<String, String>)? validate,
}) {
  final l = context.l10n;
  return MMNativePresentation.form(
    title: title.replaceFirst(RegExp(r'(…|\.\.\.)$'), ''),
    dark: Theme.of(context).brightness == Brightness.dark,
    cancel: l.cancel,
    submit: submit,
    fields: fields,
    message: message,
    discard: l.phoneDiscardChanges,
    keepEditing: l.phoneKeepEditing,
    discardTitle: l.phoneDiscardChangesTitle,
    validate: validate,
  );
}

bool usesNativePhonePresentation(BuildContext context) => MMNativePresentation.available && MMInput.of(context).phone;
