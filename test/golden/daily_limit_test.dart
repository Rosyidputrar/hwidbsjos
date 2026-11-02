// UX-08: spending had no limit until one was set, and nothing said so: a new connection started with none, the
// subagent card did not say what a subagent may spend, and the Usage row read the same either way. A first
// connection now offers a daily limit, and the limits say what they are (in USD, at each model's own prices).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rynex/agent/integrations.dart';
import 'package:rynex/ui/daily_limit_offer.dart';
import 'package:rynex/ui/settings_screen.dart';
import 'package:rynex/ui/settings_hub.dart';
import 'package:rynex/ui/subagent_settings_screen.dart';

import 'harness.dart';

Future<void> frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    applyLook(const Look());
    layoutErrors.clear();
  });

  group('the offer', () {
    Future<(FakeHost, Future<double?> Function())> open(WidgetTester tester, {Look look = const Look(), double budget = 0}) async {
      final host = FakeHost();
      host.stored['dailyBudget'] = budget;
      final agent = newAgent();
      double? result;
      var done = false;
      await pumpLook(
        tester,
        look,
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await offerDailyLimit(context, agent);
                  done = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
        height: 900,
      );
      await tester.tap(find.text('open'));
      await frames(tester);
      return (host, () async {
        await frames(tester);
        expect(done, isTrue);
        return result;
      });
    }

    testWidgets('says there is no limit and what each choice costs', (tester) async {
      await open(tester);
      expect(find.text('Set a daily limit?'), findsOneWidget);
      expect(find.text('\$1 a day'), findsOneWidget);
      expect(find.text('\$2.5 a day'), findsOneWidget);
      expect(find.text('\$5 a day'), findsOneWidget);
      expect(find.text('\$10 a day'), findsOneWidget);
      expect(find.text('No limit'), findsOneWidget);
    });

    testWidgets('a choice is saved as the daily budget', (tester) async {
      final (host, result) = await open(tester);
      await tester.tap(find.text('\$2.5 a day'));
      expect(await result(), 2.5);
      expect(host.sent('settings_set').single['settings'], {'dailyBudget': 2.5});
    });

    testWidgets('No limit leaves things as they were, and saves nothing', (tester) async {
      final (host, result) = await open(tester);
      await tester.tap(find.text('No limit'));
      expect(await result(), isNull);
      expect(host.sent('settings_set'), isEmpty);
    });

    testWidgets('dismissed, nothing is saved either', (tester) async {
      final (host, result) = await open(tester);
      await tester.tapAt(const Offset(200, 40));
      expect(await result(), isNull);
      expect(host.sent('settings_set'), isEmpty);
    });

    testWidgets('a limit that is already set is not asked about again', (tester) async {
      final (host, result) = await open(tester, budget: 40);
      expect(find.text('Set a daily limit?'), findsNothing);
      expect(await result(), isNull);
      expect(host.sent('settings_set'), isEmpty);
    });

    for (final look in [const Look(), const Look(dark: true, language: 'id'), const Look(language: 'id', textScale: 1.6, width: 320)]) {
      testWidgets('looks right, ${look.name}', (tester) async {
        await open(tester, look: look);
        collectLayoutErrors(tester, look.name);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile(golden('daily_limit_${look.name}')));
      });
    }
  });

  group('after the first connection', () {
    Future<FakeHost> save(WidgetTester tester, {required bool hadProvider, double budget = 0}) async {
      final host = FakeHost();
      host.stored['dailyBudget'] = budget;
      host.answers['custom_providers'] = (_) => hadProvider
          ? [
              {'id': 'test', 'name': 'Test', 'baseUrl': 'https://x.test/v1', 'api': 'openai-completions', 'hasKey': true, 'models': <Object>[]},
            ]
          : <Object>[];
      host.answers['custom_provider_save'] = (_) => null;
      host.answers['providers'] = (_) => <Object>[];
      host.answers['models'] = (_) => <Object>[];
      host.answers['state'] = (_) => <String, dynamic>{};
      await pumpLook(tester, const Look(), SettingsScreen(agent: newAgent()), height: 1200);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Add'));
      await frames(tester);
      // The providers screen has a search field of its own behind the sheet; scope to the sheet.
      final fields = find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField));
      await tester.enterText(fields.at(0), 'Test');
      await tester.enterText(fields.at(1), 'https://x.test/v1');
      await tester.enterText(fields.at(3), 'm1');
      await tester.tap(find.widgetWithText(FilledButton, 'Add endpoint'));
      await frames(tester, 14);
      return host;
    }

    testWidgets('saving a first endpoint offers a daily limit', (tester) async {
      await save(tester, hadProvider: false);
      expect(find.text('Set a daily limit?'), findsOneWidget);
    });

    testWidgets('connecting when one was already there does not ask again', (tester) async {
      await save(tester, hadProvider: true);
      expect(find.text('Set a daily limit?'), findsNothing);
    });

    testWidgets('a first connection with a limit already set does not ask either', (tester) async {
      await save(tester, hadProvider: false, budget: 20);
      expect(find.text('Set a daily limit?'), findsNothing);
    });
  });

  group('the limits say what they are', () {
    test('a subagent: its ceiling, and three at once', () {
      expect(subagentSpendNote(AppSettings(const {'subagentCostLimit': 5})), 'Each subagent can spend up to \$5, and up to 3 run at once. Costs are estimates.');
      expect(subagentSpendNote(AppSettings(const {'subagentCostLimit': 0})), startsWith('No cost limit: a subagent keeps spending'));
      expect(subagentSpendNote(null), contains('\$5'), reason: 'the default, before settings load');
    });

    test('the Usage row says when there is no daily limit', () {
      expect(budgetSubtitle(AppSettings(const {'dailyBudget': 0})), 'No daily limit: tap to set one');
      expect(budgetSubtitle(null), 'No daily limit: tap to set one');
      expect(budgetSubtitle(AppSettings(const {'dailyBudget': 40})), '\$40 per day');
    });

    test('in Indonesian', () {
      applyLook(const Look(language: 'id'));
      expect(budgetSubtitle(AppSettings(const {'dailyBudget': 0})), 'Tanpa batas harian: ketuk untuk mengatur');
      expect(subagentSpendNote(AppSettings(const {'subagentCostLimit': 5})), contains('maksimal 3 berjalan bersamaan'));
    });

    testWidgets('the subagent screen shows it', (tester) async {
      final host = FakeHost();
      host.stored['subagentCostLimit'] = 5;
      await pumpLook(tester, const Look(), SubagentSettingsScreen(agent: newAgent()), height: 1400);
      await frames(tester);
      expect(find.textContaining('Each subagent can spend up to \$5'), findsOneWidget);
      expect(host, isNotNull);
    });
  });
}
