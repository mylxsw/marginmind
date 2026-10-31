import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mm_core/mm_core.dart';
import 'package:mm_design/mm_design.dart';
import 'package:mm_platform/mm_platform.dart';

import '../../../shared/l10n.dart';
import '../translation_task_summary.dart';
import 'full_translation_panel.dart';

bool _defaultIsWindowForeground() {
  final state = WidgetsBinding.instance.lifecycleState;
  return state == null || state == AppLifecycleState.resumed;
}

/// Owned by the workspace, so completion remains visible after compare closes.
void listenFullTranslationNotifications(
  BuildContext context,
  WidgetRef ref,
  String setId,
  Iterable<String> documents, {
  String Function(String documentId)? documentTitleOf,
  bool Function()? isWindowForeground,
}) {
  final checkForeground = isWindowForeground ?? _defaultIsWindowForeground;
  for (final documentId in documents) {
    ref.listen(translationTaskSummaryProvider((setId, documentId)), (before, next) {
      final old = before?.value;
      final current = next.value;
      if (old == null || current == null || old.job.id != current.job.id) return;
      final l = context.l10n;
      final job = current.job;
      if (old.job.state == TranslationJobState.offline && job.state == TranslationJobState.running) {
        MMHud.show(context, l.fullTranslationHudNetworkRestored);
        return;
      }
      String? message;
      if (old.job.state != job.state) {
        if (job.state == TranslationJobState.done) {
          if (!checkForeground()) {
            final docTitle = documentTitleOf?.call(documentId) ?? documentId;
            final body = job.failures.isEmpty
                ? docTitle
                : l.fullTranslationNotificationBodyFailed(docTitle, job.failures.length);
            unawaited(MMSystemNotification.show(title: l.fullTranslationHudDone, body: body));
          }
          message = job.failures.isEmpty
              ? l.fullTranslationHudDone
              : l.fullTranslationHudDoneFailed(job.failures.length);
        } else if (job.state == TranslationJobState.stopped) {
          message = l.fullTranslationHudStopped;
        }
      }
      if (message != null) {
        MMHud.show(
          context,
          message,
          action: (
            l.fullTranslationHudView,
            () {
              if (!context.mounted) return;
              showFullTranslationPanel(context, studySetId: setId, documentId: documentId, targetLang: job.targetLang);
            },
          ),
        );
      } else if (old.job.mode == TranslationMode.batch && job.mode == TranslationMode.all) {
        MMHud.show(context, l.fullTranslationHudRestAll);
      }
    });
  }
}
