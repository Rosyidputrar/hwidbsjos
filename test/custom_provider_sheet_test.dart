// The endpoint sheet: what it sends the host when saving, prices included. A price is what lets a chat show its cost and
// the daily limit stop spending on an endpoint of one's own, so it has to reach the host exactly and be removable.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rynex/agent/agent_controller.dart';
import 'package:rynex/agent/models.dart';
import 'package:rynex/ui/custom_provider_sheet.dart';

import 'golden/harness.dart';

Future<void> open(WidgetTester tester, AgentController agent, {CustomProvider? provider}) async {
  await pumpLook(
    tester,
    const Look(),
    Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(onPressed: () => showCustomProviderSheet(context, agent, provider: provider), child: const Text('open')),
        ),
      ),
    ),
    height: 1600,
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Map<String, dynamic> saved(FakeHost host) => (host.commands.lastWhere((c) => c['type'] == 'custom_provider_save')['provider'] as Map).cast<String, dynamic>();

void main() {
  setUpAll(loadAppFonts);

  setUp(() => applyLook(const Look()));

  Future<FakeHost> hostFor() async {
    final host = FakeHost();
    for (final t in ['custom_provider_save', 'providers', 'models', 'custom_providers', 'state']) {
      host.answers[t] = (_) => t == 'state' ? <String, dynamic>{} : <Object>[];
    }
    return host;
  }

  testWidgets('prices typed in reach every model, as dollars per million tokens', (tester) async {
    final host = await hostFor();
    await open(tester, newAgent());
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'My server');
    await tester.enterText(fields.at(1), 'http://192.168.1.20:11434/v1');
    await tester.enterText(fields.at(3), 'a-model\nb-model | B');
    await tester.enterText(find.widgetWithText(TextField, 'Input price (\$ / 1M tokens)'), '0,15');
    await tester.enterText(find.widgetWithText(TextField, 'Output price (\$ / 1M tokens)'), '0.6');
    await tester.ensureVisible(find.text('Add endpoint').last);
    await tester.tap(find.text('Add endpoint').last);
    await tester.pumpAndSettle();
    final models = (saved(host)['models'] as List).cast<Map>();
    expect(models.map((m) => m['id']), ['a-model', 'b-model']);
    for (final m in models) {
      expect(m['cost'], {'input': 0.15, 'output': 0.6, 'cacheRead': 0, 'cacheWrite': 0}, reason: '${m['id']} (a comma decimal counts)');
    }
  });

  testWidgets('no prices typed: no cost is sent, so the cost stays unknown instead of free', (tester) async {
    final host = await hostFor();
    await open(tester, newAgent());
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Plain');
    await tester.enterText(fields.at(1), 'https://api.example.com/v1');
    await tester.enterText(fields.at(3), 'm1');
    await tester.ensureVisible(find.text('Add endpoint').last);
    await tester.tap(find.text('Add endpoint').last);
    await tester.pumpAndSettle();
    expect((saved(host)['models'] as List).single, isNot(contains('cost')));
  });

  CustomProvider priced() => CustomProvider({
    'id': 'custom-a',
    'name': 'A',
    'baseUrl': 'https://a.example/v1',
    'api': 'openai-completions',
    'hasKey': true,
    'models': [
      {'id': 'm1', 'cost': {'input': 3, 'output': 15, 'cacheRead': 0, 'cacheWrite': 0}},
      {'id': 'm2'},
    ],
  });

  testWidgets('editing shows the saved prices; changing them replaces them on every model', (tester) async {
    final host = await hostFor();
    await open(tester, newAgent(), provider: priced());
    expect(find.widgetWithText(TextField, '3'), findsOneWidget);
    expect(find.widgetWithText(TextField, '15'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '15'), '10');
    await tester.ensureVisible(find.text('Save').last);
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    for (final m in (saved(host)['models'] as List).cast<Map>()) {
      expect((m['cost'] as Map)['input'], 3, reason: m['id'] as String);
      expect((m['cost'] as Map)['output'], 10, reason: m['id'] as String);
    }
  });

  testWidgets('clearing both prices removes them', (tester) async {
    final host = await hostFor();
    await open(tester, newAgent(), provider: priced());
    await tester.enterText(find.widgetWithText(TextField, '3'), '');
    await tester.enterText(find.widgetWithText(TextField, '15'), '');
    await tester.ensureVisible(find.text('Save').last);
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    for (final m in (saved(host)['models'] as List).cast<Map>()) {
      expect(m['cost'], isNull, reason: '${m['id']} sends null, which the host reads as no price');
    }
  });
}
