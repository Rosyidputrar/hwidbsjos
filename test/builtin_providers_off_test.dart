// Built-in providers are turned off for now: the host says so in its hello (`builtinProviders: false`) and the app shows
// only the endpoints the person adds. If the host ever turns them back on, the catalogue is back with no other change.
import 'package:flutter_test/flutter_test.dart';
import 'package:rynex/ui/settings_screen.dart';

import 'golden/harness.dart';

void main() {
  setUpAll(loadAppFonts);
  setUp(() => applyLook(const Look()));

  Future<void> open(WidgetTester tester, {required bool builtin}) async {
    final host = FakeHost();
    host.answers['providers'] = (_) => [
      {'id': 'anthropic', 'name': 'Anthropic', 'configured': true, 'oauth': false, 'methods': ['api_key', 'oauth'], 'models': 5, 'custom': false},
      {'id': 'openai', 'name': 'OpenAI', 'configured': false, 'oauth': false, 'methods': ['api_key'], 'models': 9, 'custom': false},
    ];
    host.answers['custom_providers'] = (_) => [
      {'id': 'custom-ollama', 'name': 'Ollama on the LAN', 'api': 'openai-completions', 'baseUrl': 'http://192.168.1.20:11434/v1', 'hasKey': false, 'models': [{'id': 'qwen2.5-coder'}]},
    ];
    host.answers['models'] = (_) => <Object>[];
    final agent = newAgent();
    agent.info = {'builtinProviders': builtin};
    await pumpLook(tester, const Look(), SettingsScreen(agent: agent), height: 1800);
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('off: no catalogue, no sign-in, no search; only the endpoints, with the reason', (tester) async {
    await open(tester, builtin: false);
    expect(find.text('Anthropic'), findsNothing);
    expect(find.text('OpenAI'), findsNothing);
    expect(find.text('ADD PROVIDER'), findsNothing);
    expect(find.text('Search providers'), findsNothing);
    expect(find.text('CONNECTED'), findsNothing);
    expect(find.textContaining('Built-in providers are turned off'), findsOneWidget);
    expect(find.text('CUSTOM ENDPOINTS'), findsOneWidget);
    expect(find.text('Ollama on the LAN'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget, reason: 'the way to add an endpoint is there');
  });

  testWidgets('on (a host that offers them): the catalogue is back, and the notice is gone', (tester) async {
    await open(tester, builtin: true);
    expect(find.text('Anthropic'), findsOneWidget);
    expect(find.text('ADD PROVIDER'), findsOneWidget);
    expect(find.textContaining('Built-in providers are turned off'), findsNothing);
    expect(find.text('Ollama on the LAN'), findsOneWidget);
  });
}
