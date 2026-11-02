// UI-05: with a server set up, the chat's bar holds the back button, the title and the connection badge; the tools
// (terminal, deploy, files, git, …) used to crowd the bar as separate buttons or a "More" menu and squeeze the title
// to "N…" on a narrow phone. They now live behind the one Workspace button, in the project tools sheet's grid.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rynex/agent/agent_client.dart';
import 'package:rynex/agent/agent_controller.dart';
import 'package:rynex/agent/remote_profile.dart';
import 'package:rynex/ui/chat_screen.dart';

import '../support/fake_backend.dart';
import 'harness.dart';

const _hostKey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIABn0o4m7AzJb8wgXq1z+8+KtuqK5nyX6AX9nOQI2zVG';

String _code() =>
    'rynex1:${base64.encode(utf8.encode(jsonEncode({'v': 1, 'host': 'agentai.example.com', 'port': 22, 'user': 'rynex', 'hostKey': _hostKey})))}';

void main() {
  setUpAll(loadAppFonts);
  late Directory tmp;
  late AgentController agent;

  setUp(() {
    applyLook(const Look());
    layoutErrors.clear();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('rynex/agent'), (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(const MethodChannel('rynex/agent'), null));
    tmp = Directory.systemTemp.createTempSync('gh-title-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    agent = AgentController(AgentClient(backend: FakeBackend())..backoff = ((_) => const Duration(minutes: 1)));
    final store = RemoteProfileStore(File('${tmp.path}/home/.rynex/remote.json'));
    store.save(RemoteProfile.fromSetupCode(SetupCode.parse(_code())).copyWith(active: true));
    agent.remote.configure(setup: RemoteSetup(home: '${tmp.path}/home'), store: store, hostDir: '${tmp.path}/host');
    agent.sessionName = 'Nota penjualan toko';
  });

  /// The chat pushed over another page, as it is opened from Home (so it has a back button).
  Future<void> open(WidgetTester tester, Look look) async {
    await pumpLook(
      tester,
      look,
      Builder(
        builder: (c) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => ChatScreen(agent: agent))),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  double titleWidth(WidgetTester tester) => tester.getSize(find.text('Nota penjualan toko')).width;

  for (final look in const [
    Look(width: 320),
    Look(width: 320, textScale: 1.3),
    Look(width: 320, textScale: 2.0),
    Look(width: 360, textScale: 1.3),
    Look(width: 411, textScale: 2.0),
    Look(language: 'id', width: 320, textScale: 1.3),
  ]) {
    testWidgets('the title keeps room, and the tools are one tap away ${look.name}', (tester) async {
      await open(tester, look);
      expect(titleWidth(tester), greaterThanOrEqualTo(90), reason: 'the chat is named in the bar');
      expect(find.byTooltip(look.language == 'id' ? 'Lainnya' : 'More'), findsNothing);
      await tester.tap(find.byTooltip(look.language == 'id' ? 'Alat proyek' : 'Project tools'));
      await tester.pumpAndSettle();
      expect(find.text('Terminal'), findsOneWidget);
      expect(find.text('Deploy'), findsOneWidget);
    });
  }

  testWidgets('a wide phone has the same one Workspace button', (tester) async {
    await open(tester, const Look(width: 480));
    expect(find.byTooltip('More'), findsNothing);
    expect(find.byTooltip('Project tools'), findsOneWidget);
  });

  testWidgets('without a server the bar keeps the Workspace button', (tester) async {
    agent = AgentController(AgentClient(backend: FakeBackend()))..sessionName = 'Nota penjualan toko';
    await open(tester, const Look(width: 320));
    expect(find.byTooltip('More'), findsNothing);
    expect(find.byTooltip('Project tools'), findsOneWidget);
  });

  testWidgets('UI-14: the connection badge is 48 dp to touch', (tester) async {
    await open(tester, const Look(width: 480));
    final s = tester.getSize(find.ancestor(of: find.text('Server'), matching: find.byType(InkWell)).first);
    expect(s.width >= 48 && s.height >= 48, isTrue, reason: 'the badge is $s');
  });
}
