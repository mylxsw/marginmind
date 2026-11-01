import 'dart:convert';

import 'package:mm_core/mm_core.dart';

import 'assistant_tasks.dart';

/// A unit is an immutable, host-read source fragment, never a search snippet.
class SummaryUnit {
  const SummaryUnit(this.id, this.text);
  final String id, text;
  Map<String, dynamic> toJson() => {'id': id, 'text': text};
}

typedef SummaryStage = Future<RunResult<String>> Function(List<SummaryUnit> units, int stage);

/// Bounds both leaf requests and every merge request. A merge must reduce the
/// number of groups; an oversized response fails rather than looping forever.
Future<AssistantSummary> summarizeAssistantUnits({
  required List<SummaryUnit> units,
  required int requestCharacters,
  required SummaryStage execute,
  required CancellationToken cancel,
}) async {
  if (units.isEmpty || requestCharacters < 2048) throw const ConfigurationFailure('emptySummaryRange');
  if (units.map((u) => u.id).toSet().length != units.length) throw const ConfigurationFailure('duplicateSummaryRange');
  final fragments = <SummaryUnit>[];
  for (final unit in units) {
    if (unit.text.trim().isEmpty) throw const ConfigurationFailure('unreadSummaryRange');
    var start = 0, part = 0;
    while (start < unit.text.length) {
      var low = start, high = unit.text.length;
      final id = '${unit.id}/$part';
      while (low < high) {
        final mid = (low + high + 1) ~/ 2;
        if (jsonEncode(SummaryUnit(id, unit.text.substring(start, mid)).toJson()).length <= requestCharacters ~/ 2) {
          low = mid;
        } else {
          high = mid - 1;
        }
      }
      if (low > start &&
          low < unit.text.length &&
          unit.text.codeUnitAt(low - 1) >= 0xd800 &&
          unit.text.codeUnitAt(low - 1) <= 0xdbff) {
        low--;
      }
      if (low == start) throw const ConfigurationFailure('summaryFragmentTooLarge');
      fragments.add(SummaryUnit(id, unit.text.substring(start, low)));
      start = low;
      part++;
    }
  }
  var stage = 0;
  Future<AssistantSummary> run(List<SummaryUnit> group) async {
    cancel.check();
    final result = await execute(group, stage++);
    cancel.check();
    if (result.status != RunStatus.completed || result.value == null) {
      throw const ConfigurationFailure('partialSummary');
    }
    final summary = AssistantSummary.parse(result.value!);
    final ids = {for (final unit in group) unit.id};
    if (ids.length != summary.coveredIds.length || !summary.coveredIds.toSet().containsAll(ids)) {
      throw const ConfigurationFailure('summaryCoverageMismatch');
    }
    return summary;
  }

  List<List<SummaryUnit>> groups(List<SummaryUnit> values) {
    final output = <List<SummaryUnit>>[];
    var current = <SummaryUnit>[];
    for (final unit in values) {
      if (jsonEncode([unit.toJson()]).length > requestCharacters) {
        throw const ConfigurationFailure('summaryOutputTooLarge');
      }
      if (jsonEncode([...current, unit].map((u) => u.toJson()).toList()).length > requestCharacters) {
        output.add(current);
        current = [];
      }
      current.add(unit);
    }
    if (current.isNotEmpty) output.add(current);
    return output;
  }

  var work = fragments;
  final allIds = fragments.map((u) => u.id).toList();
  // Each intermediate summary carries its complete descendant coverage outside
  // model prose. The model can neither add nor drop a source in that ledger.
  var ledger = {
    for (final u in fragments) u.id: [u.id],
  };
  while (true) {
    final batches = groups(work);
    if (batches.length == 1) {
      final finalSummary = await run(batches.single);
      return AssistantSummary(
        finalSummary.text,
        allIds,
        finalSummary.decisions,
        finalSummary.suggestions,
        finalSummary.unresolved,
      );
    }
    final next = <SummaryUnit>[];
    final nextLedger = <String, List<String>>{};
    for (final batch in batches) {
      final summary = await run(batch);
      final id = 'merge-$stage';
      nextLedger[id] = [for (final u in batch) ...ledger[u.id]!];
      next.add(
        SummaryUnit(
          id,
          jsonEncode(
            AssistantSummary(
              summary.text,
              nextLedger[id]!,
              summary.decisions,
              summary.suggestions,
              summary.unresolved,
            ).toJson(),
          ),
        ),
      );
    }
    if (next.length >= work.length) throw const ConfigurationFailure('summaryCannotReduce');
    work = next;
    ledger = nextLedger;
  }
}
