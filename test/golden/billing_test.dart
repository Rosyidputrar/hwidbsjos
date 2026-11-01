// The subagent cost panel (model, thinking level, live cost in USD at the
// model's own prices). Data comes from the fixtures shape the host sends.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rynex/agent/subagents.dart';
import 'package:rynex/ui/subagent_card.dart';

import 'harness.dart';

int _ms(Duration ago) => goldenNow.subtract(ago).millisecondsSinceEpoch;

SubagentState subagent({String status = 'running'}) {
  final store = SubagentStore();
  store.applyRecord({
    'type': 'subagent_started',
    'subagent': {
      'id': 's1',
      'parentSessionFile': 'chat.jsonl',
      'brief': 'Audit billing',
      'profile': 'read',
      'status': status,
      'createdAt': _ms(const Duration(minutes: 2)),
      'startedAt': _ms(const Duration(minutes: 2)),
      'currentTool': 'read',
      'currentArgs': 'agent/src/host.ts',
      'toolCalls': [],
      'queue': [],
      'inputTokens': 2400,
      'outputTokens': 6100,
      'cacheReadTokens': 164000,
      'cacheWriteTokens': 900,
      'cost': 1.27,
      'requests': 9,
      'model': 'claude-opus-5.5',
      'modelName': 'Claude Opus 5.5',
      'thinkingLevel': 'high',
    },
  });
  return store['s1']!;
}

Future<void> frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    layoutErrors.clear();
    pinClock();
  });

  for (final look in const [Look(), Look(dark: true, language: 'id'), Look(language: 'id', textScale: 1.3, width: 320)]) {
    testWidgets('golden: subagent card + cost panel ${look.name}', (tester) async {
      FakeHost();
      final agent = newAgent();
      final s = subagent();
      await pumpLook(
        tester,
        look,
        Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [SubagentCard(state: s, agent: agent), const SizedBox(height: 16), SubagentCostPanel(state: s)],
          ),
        ),
        height: 900,
      );
      await frames(tester);
      expect(layoutErrors, isEmpty);
      expect(find.textContaining('Claude Opus 5.5'), findsWidgets);
      await expectLater(find.byType(Scaffold), matchesGoldenFile(golden('subagent_cost_${look.name}')));
    });
  }

  test('subagent status updates keep model, reasoning and cost, and add up', () {
    applyLook(const Look());
    final s = subagent();
    s.applyStatus({'status': 'running', 'cost': 1.5, 'requests': 10, 'thinkingLevel': 'high'});
    expect(s.cost, 1.5);
    expect(s.requests, 10);
    expect(s.modelName, 'Claude Opus 5.5');
    expect(s.totalTokens, 2400 + 6100 + 164000 + 900);
    expect(subagentModelLine(s), 'Claude Opus 5.5 · High');
  });
}
