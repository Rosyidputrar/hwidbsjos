// UX-03: a mistyped or half-pasted API key, the commonest first-run failure, showed the provider's raw HTTP reply in
// English. These pin what a first-time user reads, in both languages, and that a failure that is not the host's still
// says something.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rynex/agent/agent_client.dart';
import 'package:rynex/ui/errors.dart';
import 'package:rynex/ui/settings_screen.dart';

import 'golden/harness.dart';

void main() {
  setUpAll(loadAppFonts);
  setUp(() => applyLook(const Look()));

  group('what a key problem reads like', () {
    test('a rejected key', () {
      for (final raw in [
        '401 Unauthorized: {"error":{"message":"Invalid API key","type":"invalid_request_error"}}',
        '403 Forbidden: {"error":"no"}',
        'Invalid API key',
      ]) {
        expect(keyProblem(AgentError(raw)), 'The key was not accepted. Check that you copied all of it, with no spaces.', reason: raw);
      }
    });

    test('a provider that does not answer', () {
      for (final raw in ['fetch failed', 'The operation was aborted due to timeout', 'request timed out']) {
        expect(keyProblem(AgentError(raw)), 'The provider did not answer. Check your connection and try again.', reason: raw);
      }
    });

    test('another status is not shown as a number and a JSON body', () {
      final said = keyProblem(AgentError('502 Bad Gateway: <html>...</html>'));
      expect(said, 'The provider answered with an error. Try again in a moment.');
      expect(said, isNot(contains('502')));
    });

    test('a failure that is not the host\'s (a platform error) still says something', () {
      expect(keyProblem(Exception('boom')), isNotEmpty);
      expect(keyProblem(StateError('')), isNotEmpty);
    });

    test('in Indonesian', () {
      applyLook(const Look(language: 'id'));
      expect(keyProblem(AgentError('401 Unauthorized: {}')), 'Key ditolak. Pastikan tersalin utuh, tanpa spasi.');
      expect(keyProblem(AgentError('fetch failed')), 'Provider tidak menjawab. Periksa koneksi lalu coba lagi.');
    });
  });

  testWidgets('the endpoint sheet shows it under the form, instead of the raw reply', (tester) async {
    final host = FakeHost();
    host.answers['custom_provider_fetch_models'] = (_) => const HostError('401 Unauthorized: {"error":{"message":"Invalid API key"}}');
    host.answers['custom_providers'] = (_) => <Object>[];
    host.answers['providers'] = (_) => <Object>[];
    host.answers['models'] = (_) => <Object>[];
    host.answers['state'] = (_) => <String, dynamic>{};
    await pumpLook(tester, const Look(), SettingsScreen(agent: newAgent()));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Add'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // The providers screen has a search field of its own behind the sheet; scope to the sheet.
    final fields = find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField));
    await tester.enterText(fields.at(1), 'https://x.test/v1');
    await tester.tap(find.text('Fetch models from the server'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('The key was not accepted. Check that you copied all of it, with no spaces.'), findsOneWidget);
    expect(find.textContaining('Invalid API key'), findsNothing);
    expect(find.textContaining('401'), findsNothing);
  });
}
