@TestOn('vm')
@Tags(['network'])
library;

import 'dart:convert';

import 'package:mm_core/mm_core.dart';
import 'package:mm_research/mm_research.dart';
import 'package:test/test.dart';

void main() {
  test('public OpenAlex HTTPS works through production transport without API key', () async {
    final bytes = await ResearchHttp()
        .send(
          Uri.parse('https://api.openalex.org/works?per-page=1'),
          cancellation: CancellationToken(),
          headers: {'accept': 'application/json'},
          budget: const ResearchBudget(duration: Duration(seconds: 30)),
        )
        .expand((b) => b)
        .toList();
    expect((jsonDecode(utf8.decode(bytes)) as Map)['results'], isNotEmpty);
  });
}
