import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:simple_icons/simple_icons.dart';

import '../agent/agent_controller.dart';
import '../agent/agent_fs.dart';
import '../agent/integrations.dart';
import '../agent/models.dart';
import '../agent/updater.dart';
import 'i18n.dart';
import 'accounts_screen.dart';
import 'chat_extras.dart';
import 'chat_screen.dart';
import 'delete_flows.dart';
import 'errors.dart';
import 'folder_picker.dart';
import 'kit.dart';
import 'illustration.dart';
import 'mesh.dart';
import 'model_sheet.dart';
import 'new_chat_sheet.dart';
import 'repos_screen.dart';
import 'sessions_drawer.dart';
import 'settings_hub.dart';
import 'settings_screen.dart';
import 'skills_screen.dart';
import 'tasks_screen.dart';
import 'terminal_screen.dart';
import 'sync_screen.dart';
import 'auto_backup.dart' show offerServerRestore;
import 'theme.dart';
import 'update_sheet.dart';

/// Opens the chat for the agent's current session.
Future<void> openChat(
  BuildContext context,
  AgentController agent, {
  String? prompt,
  List<Attachment> attachments = const [],
  bool listen = false,
}) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) =>
        ChatScreen(agent: agent, initialPrompt: prompt, initialAttachments: attachments, listenOnOpen: listen),
  ),
);

/// The app's home: tabs plus a floating navigation bar.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.agent});
  final AgentController agent;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int tab = 0;

  /// The Chats tab is picking chats: Back leaves that first, and only then the tab.
  final _chatsSelecting = ValueNotifier(false);
  final subs = <StreamSubscription<Object?>>[];
  AppLifecycleState lifecycle = AppLifecycleState.resumed;
  int approvalsSeen = 0;

  AgentController get agent => widget.agent;
  bool get _inBackground => lifecycle != AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Just switched back to the phone's agent with a server backup here: offer it (auto_backup.dart).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && agent.remote.takeRestoreOffer()) offerServerRestore(context, agent);
    });
    final f = agent.features;
    subs
      ..add(agent.client.records.where((r) => r['type'] == 'launch').listen((_) => _takeLaunch()))
      ..add(f.done.stream.listen(_notifyDone))
      ..add(
        f.runFinished.stream.listen((run) {
          final title = switch (run.status) {
            'done' => tr('Task done'),
            'cancelled' => tr('Task cancelled'),
            _ => tr('Task failed'),
          };
          agent.client.notify(
            2000 + run.id.hashCode % 1000,
            '$title: ${run.title}',
            run.summary ?? '',
            channel: 'tasks',
            launch: run.sessionFile != null
                ? {'action': 'open_chat', 'path': run.sessionFile}
                : {'action': 'open_tasks'},
          );
        }),
      );
    f.addListener(_onFeatures);
    agent.addListener(_onAgent);
    // Switching chats mid-turn would drop the reply: ask first (see AgentController.readyToSwitch).
    agent.confirmStopToSwitch = () => confirmStopToSwitch(context);
    agent.integrations.addListener(_onSync);
    f.refreshRuns().catchError((_) {});
    agent.integrations.refreshSync().catchError((_) {});
    agent.client.requestNotifications().catchError((_) {});
    // The app may have been opened by a share, the widget or the tile.
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeLaunch());
    subs.add(
      Updater.instance.readyToInstall.stream.listen((_) {
        if (!_inBackground && mounted) showUpdateSheet(context, agent);
      }),
    );
    _startUpdates();
  }

  /// Picks up an update download from an earlier run, then checks GitHub now and then.
  Future<void> _startUpdates() async {
    final updater = Updater.instance;
    final justUpdated = await updater.init();
    if (!mounted || !updater.supported) return;
    final messenger = ScaffoldMessenger.of(context);
    if (justUpdated != null) {
      messenger.showSnackBar(SnackBar(content: Text('${tr('Updated to')} $justUpdated')));
    }
    switch (updater.phase) {
      case UpdatePhase.ready:
        await showUpdateSheet(context, agent);
        return;
      case UpdatePhase.downloading || UpdatePhase.failed:
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              tr(
                updater.phase == UpdatePhase.failed ? 'The update download failed' : 'The update is still downloading',
              ),
            ),
            action: SnackBarAction(label: tr('View'), onPressed: () => showUpdateSheet(context, agent)),
          ),
        );
        return;
      default:
    }
    if (!updater.dueForAutoCheck) return;
    // Let the app settle (and the agent boot) before going to the network.
    await Future<void>.delayed(const Duration(seconds: 4));
    await updater.check();
    if (mounted && !_inBackground && updater.shouldPrompt) await showUpdateSheet(context, agent);
  }

  @override
  void dispose() {
    _chatsSelecting.dispose();
    agent.confirmStopToSwitch = null;
    WidgetsBinding.instance.removeObserver(this);
    agent.features.removeListener(_onFeatures);
    agent.removeListener(_onAgent);
    agent.integrations.removeListener(_onSync);
    for (final s in subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    lifecycle = state;
    // Subagent notifications cover the open chat too while nothing is on screen
    // (not for "inactive": the shade pulled down still shows the app).
    agent.inBackground = state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    if (state == AppLifecycleState.resumed) {
      Updater.instance.onResume().catchError((_) {});
      // Back in the app: "pi is done" has served its purpose.
      agent.client.cancelNotification(_doneId).catchError((_) {});
    }
    // Leaving the app: sync shortly, before Android may stop it.
    if (state == AppLifecycleState.paused && agent.integrations.sync?.enabled == true) {
      agent.integrations.syncNow(soon: true).catchError((_) {});
    }
  }

  // Notification ids. 1 is the agent's ongoing notification (AgentService).
  static const _doneId = 11;
  static const _approvalId = 3;
  static const _syncId = 40;

  /// The open chat finished while the app was in the background: say whether it worked, and open that chat on tap.
  void _notifyDone(String preview) {
    if (!_inBackground) return;
    final open = {'action': 'open_chat', 'path': agent.sessionFile};
    final error = agent.lastTurnError;
    if (error != null) {
      agent.client.notify(
        _doneId,
        tr('The agent stopped with an error'),
        error,
        launch: open,
        actions: [
          (label: tr('Try again'), launch: {'action': 'retry', 'path': agent.sessionFile}),
        ],
      );
    } else {
      agent.client.notify(
        _doneId,
        '${tr('The agent is done')}: ${agent.chatTitle}',
        preview.isEmpty ? tr('Tap to see the result') : preview,
        launch: open,
      );
    }
  }

  /// Approvals that arrive while the app is in the background become notifications, gone once answered.
  void _onFeatures() {
    final pending = agent.features.approvals;
    if (pending.length > approvalsSeen && _inBackground) {
      agent.client.notify(
        _approvalId,
        tr('The agent needs your approval'),
        '${pending.last.toolName}: ${pending.last.summary}',
        channel: 'approvals',
        launch: {'action': 'open_chat'},
      );
    }
    if (pending.isEmpty && approvalsSeen > 0) agent.client.cancelNotification(_approvalId).catchError((_) {});
    approvalsSeen = pending.length;
  }

  String? _busyLine;

  /// Keeps the ongoing notification on what the agent is doing (chat and tool).
  void _onAgent() {
    if (!agent.busy) {
      _busyLine = null;
      return;
    }
    final tool = agent.runningTool;
    // With a plan, the step it is on says more than the tool it is running.
    // Only a plan from this turn: an older one may be about something else.
    final todo = agent.todo;
    final plan = todo != null && todo.currentTurn ? todo.plan : null;
    final step = plan == null || plan.finished
        ? null
        : tr('Step {n}/{total}: {step}')
              .replaceAll('{n}', '${plan.currentNumber}')
              .replaceAll('{total}', '${plan.total}')
              .replaceAll('{step}', plan.current?.label ?? '');
    final text = step ?? (tool == null ? tr('Agent is working') : '${tr('Running')} $tool');
    final line = '${agent.chatTitle}|$text';
    if (line == _busyLine) return;
    _busyLine = line;
    agent.client.busyText(title: agent.chatTitle, text: text).catchError((_) {});
  }

  bool _syncWarned = false;

  /// Sync failing again and again (an expired token, a full disk) shouldn't go unnoticed.
  void _onSync() {
    final s = agent.integrations.sync;
    if (s == null) return;
    if (s.failures >= 3 && !_syncWarned) {
      _syncWarned = true;
      agent.client.notify(
        _syncId,
        tr('GitHub sync is failing'),
        tr(s.lastError ?? 'Sync failed; tap for details'),
        channel: 'sync',
        launch: {'action': 'open_sync'},
      );
    } else if (s.failures == 0 && _syncWarned) {
      _syncWarned = false;
      agent.client.cancelNotification(_syncId).catchError((_) {});
    }
  }

  /// Opens the chat a notification points at (the open one when [path] is null).
  Future<void> _openChatAt(String? path) async {
    if (path != null && path != agent.sessionFile) {
      final known = (await agent.listSessions()).any((s) => s.path == path);
      if (known && !await agent.openSession(path)) return;
    }
    if (mounted) await openChat(context, agent);
  }

  Future<void> _takeLaunch() async {
    final launch = await agent.client.takeLaunch();
    if (launch == null || !mounted) return;
    // Close sheets and pages so the new chat opens on top of home — but
    // never force past a route that refuses to pop. popUntil ignores
    // PopScope vetoes (it would loop on the editor's save prompt), so pop
    // one by one and stop at the first refusal: the editor stays intact
    // underneath, and the new chat simply opens on top of it.
    while (mounted && Navigator.of(context).canPop()) {
      if (!await Navigator.of(context).maybePop()) break;
    }
    switch (launch['action']) {
      case 'new_chat':
        await _newChat();
      case 'update':
        if (mounted) await showUpdateSheet(context, agent);
      case 'open_chat':
        await _openChatAt(launch['path'] as String?);
      case 'retry':
        final path = launch['path'] as String?;
        if (path != null && path != agent.sessionFile && !await agent.openSession(path)) return;
        await agent.retry();
        if (mounted) await openChat(context, agent);
      case 'open_tasks':
        if (mounted) await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TasksScreen(agent: agent)));
      case 'open_sync':
        if (mounted) await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SyncScreen(agent: agent)));
      case 'voice':
        if (!await agent.newSession()) return;
        if (mounted) await openChat(context, agent, listen: true);
      case 'share':
        final files = [
          for (final f in (launch['files'] as List? ?? const []).cast<Map>())
            Attachment(f['path'] as String, f['name'] as String, mime: f['mime'] as String?),
        ];
        if (!await agent.newSession()) return;
        if (mounted) await openChat(context, agent, prompt: launch['text'] as String?, attachments: files);
    }
  }

  Future<void> _newChat() async {
    final before = agent.sessionId;
    await showNewChatSheet(context, agent);
    if (mounted && agent.sessionId != before) await openChat(context, agent);
  }

  Future<void> _voiceChat() async {
    if (!await agent.newSession()) return;
    if (mounted) await openChat(context, agent, listen: true);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      _HomeTab(
        agent: agent,
        onSeeAll: () => setState(() => tab = 1),
        onNewChat: _newChat,
        onVoice: _voiceChat,
        onProjects: () => setState(() => tab = 2),
      ),
      _ChatsTab(agent: agent, selecting: _chatsSelecting),
      _ProjectsTab(agent: agent),
      SettingsHub(agent: agent, embedded: true),
    ];
    // Back from Chats, Projects or Settings goes to Home, as in other apps; only Back from Home leaves the app.
    return PopScope(
      canPop: tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_chatsSelecting.value) setState(() => tab = 0);
      },
      child: Scaffold(
        drawer: SessionsDrawer(agent: agent),
        // Every tab stays built (scroll positions survive); the active one fades
        // and drifts in, the others fade out and stop ticking.
        body: Stack(
          children: [
            for (var i = 0; i < tabs.length; i++)
              _TabLayer(active: i == tab, forward: i >= tab, child: ContentWidth(child: tabs[i])),
          ],
        ),
        bottomNavigationBar: ListenableBuilder(
          listenable: agent.features,
          builder: (context, _) => _NavBar(
            index: tab,
            onTap: (i) => setState(() => tab = i),
            onCreate: _newChat,
            settingsDot: agent.features.approvals.isNotEmpty,
          ),
        ),
      ),
    );
  }
}

class _TabLayer extends StatefulWidget {
  const _TabLayer({required this.active, required this.forward, required this.child});
  final bool active;
  final bool forward;
  final Widget child;

  @override
  State<_TabLayer> createState() => _TabLayerState();
}

class _TabLayerState extends State<_TabLayer> {
  /// True once an inactive tab has finished fading out; only then is it
  /// taken offstage (and its tickers paused), so the fade itself can run.
  late bool hidden = !widget.active;

  @override
  void didUpdateWidget(_TabLayer old) {
    super.didUpdateWidget(old);
    if (widget.active && hidden) setState(() => hidden = false);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    return Offstage(
      offstage: hidden && !active,
      child: TickerMode(
        enabled: active || !hidden,
        child: IgnorePointer(
          ignoring: !active,
          child: AnimatedOpacity(
            opacity: active ? 1 : 0,
            duration: Motion.of(context, const Duration(milliseconds: 240)),
            curve: Curves.easeOutCubic,
            onEnd: () {
              if (!widget.active && mounted) setState(() => hidden = true);
            },
            child: AnimatedSlide(
              offset: active ? Offset.zero : Offset(widget.forward ? 0.04 : -0.04, 0),
              duration: Motion.of(context, const Duration(milliseconds: 300)),
              curve: Curves.easeOutCubic,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Navigation bar: Home, Chats, the create button, Projects, Settings (docked).

class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.onTap, required this.onCreate, this.settingsDot = false});
  final int index;
  final ValueChanged<int> onTap;
  final VoidCallback onCreate;

  /// A dot on Settings: approvals are waiting there.
  final bool settingsDot;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget item(int i, IconData icon, String label, {bool dot = false}) => Expanded(
      child: _NavItem(icon: icon, label: tr(label), selected: i == index, dot: dot, onTap: () => onTap(i)),
    );
    return Container(
      decoration: BoxDecoration(
        color: p.nav,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(
            children: [
              item(0, LucideIcons.house, 'Home'),
              item(1, LucideIcons.messagesSquare, 'Chats'),
              Expanded(
                child: Center(child: _CreateButton(onTap: onCreate)),
              ),
              item(2, LucideIcons.folderGit2, 'Projects'),
              item(3, LucideIcons.settings2, 'Settings', dot: settingsDot),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tab: icon in a pill indicator that fills in when selected, label below.
class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap, this.dot = false});
  final IconData icon;
  final String label;
  final bool selected;
  final bool dot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = selected ? p.accent : p.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        customBorder: const StadiumBorder(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: Motion.of(context, const Duration(milliseconds: 220)),
              curve: Curves.easeOutCubic,
              width: selected ? 52 : 36,
              height: 30,
              decoration: BoxDecoration(
                color: selected ? p.accent.withValues(alpha: 0.14) : Colors.transparent,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 20, color: color),
                  if (dot)
                    Positioned(
                      right: selected ? 12 : 4,
                      top: 4,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(color: p.warning, shape: BoxShape.circle),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            // The item's own Semantics above already names it: the visible label would merge into
            // the same node and double the name ("Settings Settings").
            ExcludeSemantics(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? p.text : p.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The accent "new chat" button in the middle of the bar.
class _CreateButton extends StatefulWidget {
  const _CreateButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_CreateButton> createState() => _CreateButtonState();
}

class _CreateButtonState extends State<_CreateButton> {
  bool pressed = false;
  double turns = 0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: tr('New chat'),
      child: GestureDetector(
        onTapDown: (_) => setState(() => pressed = true),
        onTapCancel: () => setState(() => pressed = false),
        onTapUp: (_) {
          HapticFeedback.mediumImpact();
          setState(() {
            pressed = false;
            turns += 0.25;
          });
          widget.onTap();
        },
        child: AnimatedScale(
          scale: pressed ? 0.9 : 1,
          duration: Motion.of(context, const Duration(milliseconds: 160)),
          curve: Curves.easeOutBack,
          child: Container(
            width: 52,
            height: 42,
            decoration: BoxDecoration(
              color: p.accent,
              borderRadius: BorderRadius.circular(Radii.md),
              boxShadow: [
                BoxShadow(color: p.accent.withValues(alpha: 0.25), blurRadius: 12, spreadRadius: -2, offset: const Offset(0, 3)),
              ],
            ),
            child: AnimatedRotation(
              turns: turns,
              duration: Motion.of(context, const Duration(milliseconds: 420)),
              curve: Curves.easeOutBack,
              child: Icon(LucideIcons.plus, size: 22, color: p.onAccent),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Home

class _Quick {
  const _Quick(
    this.title,
    this.blurb,
    this.icon,
    this.color,
    this.category,
    this.art, {
    this.prompt,
  });
  final String title;

  /// One line under the title: what you get.
  final String blurb;

  /// Storyset illustration shown on the card.
  final String art;
  final IconData icon;
  final Color color;
  final String category;
  final String? prompt;
}

/// Category chips over the quick starts: id -> label.
const _categories = {'All': 'All types', 'Build': 'Build', 'Code': 'Code', 'Ops': 'Ops'};

const _quick = [
  _Quick(
    'Build a web app',
    'A site or app, ready to deploy',
    LucideIcons.layoutTemplate,
    Color(0xFFFF7A1A),
    'Build',
    'projects',
    prompt: 'Build me a polished, mobile-first web app: ',
  ),
  _Quick(
    'Design a modern UI',
    'A polished screen from a description',
    LucideIcons.palette,
    Color(0xFF14B8A6),
    'Build',
    'design',
    prompt: 'Using the ui-designer skill, design and build a modern screen for: ',
  ),
  _Quick(
    'Chat with the smartest agent',
    'Ask, plan or brainstorm',
    LucideIcons.sparkles,
    Color(0xFF7C5CFC),
    'Code',
    'chat',
  ),
  _Quick(
    'Fix a bug',
    'Find the cause and patch it',
    LucideIcons.bug,
    Color(0xFFEF4444),
    'Code',
    'bug',
    prompt: 'Help me find and fix this bug: ',
  ),
  _Quick(
    'Python in Linux',
    'Scripts in a real Linux container',
    SimpleIcons.python,
    Color(0xFF3B82F6),
    'Code',
    'python',
    prompt: 'Set up a Python project in the Linux container and write a script that ',
  ),
  _Quick(
    'Deploy a site',
    'Get a live URL in minutes',
    LucideIcons.rocket,
    Color(0xFF0EA5E9),
    'Ops',
    'launch',
    prompt: 'Deploy this project and give me the live URL. Project: ',
  ),
  _Quick(
    'Automate a task',
    'A script that does it for you',
    LucideIcons.zap,
    Color(0xFFF59E0B),
    'Ops',
    'automate',
    prompt: 'Write a script that automates: ',
  ),
];

class _HomeTab extends StatefulWidget {
  const _HomeTab({
    required this.agent,
    required this.onSeeAll,
    required this.onNewChat,
    required this.onVoice,
    required this.onProjects,
  });
  final AgentController agent;
  final VoidCallback onSeeAll;
  final VoidCallback onNewChat;
  final VoidCallback onVoice;
  final VoidCallback onProjects;

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> with BusyActions {
  String category = 'All';
  late Future<List<SessionSummary>> recent = widget.agent.listSessions();

  AgentController get agent => widget.agent;

  void _refresh() => setState(() {
    recent = agent.listSessions();
  });

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _refresh();
  }

  Future<void> _run(_Quick q) async {
    if (busy()) return;
    if (q.prompt != null) return _startQuick(q);
    widget.onNewChat();
  }

  /// A quick start: its own project folder and a chat in it, with a spinner on the card until the chat opens.
  Future<void> _startQuick(_Quick q) async {
    final opened = await runBusy(q.title, () async {
      try {
        return await _prepareQuick(q);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
        return null;
      }
    });
    if (opened == null || !mounted) return;
    final fs = agent.fs;
    await openChat(context, agent, prompt: tr(q.prompt!));
    // Backed out without sending anything: don't leave an empty project behind.
    if (agent.cwd == opened &&
        agent.entries.isEmpty &&
        await fs.exists(opened).catchError((_) => false) &&
        (await fs.list(opened).catchError((_) => <FsEntry>[])).isEmpty) {
      await fs.delete(opened).catchError((_) {});
      try {
        await agent.newSession();
      } catch (_) {}
    }
    _refresh();
  }

  /// Makes the quick start's folder and its chat; the folder, or null when no chat came of it.
  Future<String?> _prepareQuick(_Quick q) async {
    // Each quick start gets its own project folder.
    final ws = agent.info['workspace'] as String? ?? '';
    final slug = q.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    final n = DateTime.now();
    // This phone's workspace, or the server's (server_agent.md, phase 5).
    final fs = agent.fs;
    final dir = joinPath(ws, '$slug-${n.month}${n.day}-${n.hour}${n.minute.toString().padLeft(2, '0')}');
    await fs.mkdir(dir);
    if (!await agent.newSession(dir: dir)) {
      await fs.delete(dir).catchError((_) {});
      return null;
    }
    return dir;
  }

  Future<void> _openFolder() async {
    final dir = await FolderPicker.pick(context, agent);
    if (dir == null) return;
    if (!await agent.newSession(dir: dir)) return;
    if (mounted) await openChat(context, agent);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: Listenable.merge([agent, agent.integrations, agent.features]),
      builder: (context, _) {
        final gh = agent.integrations.github;
        final running = agent.features.runs.where((r) => r.active).length;
        final name = (gh?.name ?? gh?.login ?? '').split(' ').first;
        final quick = _quick.where((q) => category == 'All' || q.category == category).toList();
        return SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                // Brand (opens the sessions drawer), status and the two personal shortcuts.
                Row(
                  children: [
                    Semantics(
                      button: true,
                      label: tr('Menu'),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Scaffold.of(context).openDrawer(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const LogoMark(size: 30),
                              const SizedBox(width: 8),
                              Text(tr('Rynex'), style: text.titleMedium),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Pill(agent.busy ? tr('Working') : tr('Ready'), color: agent.busy ? p.warning : p.success, dot: true),
                    const Spacer(),
                    Badge(
                      isLabelVisible: running > 0,
                      label: Text('$running'),
                      backgroundColor: p.accent,
                      child: _CircleButton(
                        icon: LucideIcons.listTodo,
                        label: tr('Tasks'),
                        onTap: () => _push(TasksScreen(agent: agent)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Signed out: a person icon, not initials made from the app name ("GA").
                    if (gh == null)
                      _CircleButton(
                        icon: LucideIcons.userRound,
                        label: tr('Accounts & servers'),
                        onTap: () => _push(AccountsScreen(agent: agent)),
                      )
                    else
                      Semantics(
                        button: true,
                        label: tr('Accounts & servers'),
                        child: TapTarget(
                          onTap: () => _push(AccountsScreen(agent: agent)),
                          child: Avatar(name: gh.name ?? gh.login, url: gh.avatarUrl, size: 40),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 28),
                if (name.isNotEmpty) ...[
                  Text('${tr('Hello,')} $name', style: text.headlineSmall),
                  const SizedBox(height: 4),
                  Text(tr('What should we build today?'), style: text.bodyMedium?.copyWith(color: p.muted)),
                ] else
                  Text(tr('What should we build today?'), style: text.headlineSmall),
                const SizedBox(height: 20),
                if (agent.hasModel)
                  _PromptCard(agent: agent, onStart: widget.onNewChat, onVoice: widget.onVoice)
                else
                  _ConnectCard(agent: agent),
                if (running > 0) ...[
                  const SizedBox(height: 12),
                  SurfaceCard(
                    onTap: () => _push(TasksScreen(agent: agent)),
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                    child: Row(
                      children: [
                        const BusySpinner(size: 18),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '$running ${tr(running == 1 ? 'background task running' : 'background tasks running')}',
                            style: text.titleSmall,
                          ),
                        ),
                        Icon(LucideIcons.chevronRight, size: 18, color: p.faint),
                      ],
                    ),
                  ),
                ],
                // Shortcuts to the places people go most.
                const SizedBox(height: 24),
                Row(
                  children: [
                    _Shortcut(
                      icon: SimpleIcons.github,
                      label: tr('Clone repo'),
                      onTap: () async {
                        await _push(ReposScreen(agent: agent));
                        agent.integrations.refreshProjects().catchError((_) {});
                      },
                    ),
                    _Shortcut(icon: LucideIcons.folderOpen, label: tr('Open folder'), onTap: _openFolder),
                    _Shortcut(
                      icon: LucideIcons.squareTerminal,
                      label: tr('Terminal'),
                      onTap: () => _push(TerminalScreen(agent: agent)),
                    ),
                    _Shortcut(
                      icon: LucideIcons.puzzle,
                      label: tr('Skills'),
                      onTap: () => _push(SkillsScreen(agent: agent)),
                    ),
                  ],
                ),
                _SectionHeader(tr('Start something')),
                // Sized by its chips (a fixed height clipped them at larger text sizes).
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  child: Row(
                    children: [
                      for (final MapEntry(key: c, value: label) in _categories.entries)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _PillChip(
                            label: tr(label),
                            selected: category == c,
                            onTap: () => setState(() => category = c),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, box) {
                    final width = (box.maxWidth - 12) / 2;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final q in quick)
                          SizedBox(
                            width: width,
                            child: _TemplateCard(q: q, busy: busy(q.title), onTap: () => _run(q)),
                          ),
                      ],
                    );
                  },
                ),
                _SectionHeader(tr('Recent'), action: tr('See all'), onAction: widget.onSeeAll),
                FutureBuilder<List<SessionSummary>>(
                  future: recent,
                  builder: (context, snap) {
                    final list = (snap.data ?? const <SessionSummary>[])
                        .where((s) => s.messageCount > 0)
                        .take(5)
                        .toList();
                    // A list that could not be read says so, with a retry (it stayed blank).
                    if (snap.hasError) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: ErrorNotice(error: snap.error, onRetry: _refresh),
                      );
                    }
                    if (!snap.hasData) return const SizedBox(height: 60);
                    if (list.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(tr('Your chats will show up here.'), style: text.bodySmall),
                      );
                    }
                    return Column(
                      children: [
                        for (final s in list)
                          _SessionRow(
                            session: s,
                            workspace: agent.info['workspace'] as String? ?? '',
                            busy: agent.switchingTo == s.path,
                            onTap: () async {
                              if (s.id != agent.sessionId && !await agent.openSession(s.path)) return;
                              if (context.mounted) await openChat(context, agent);
                              _refresh();
                            },
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton.icon(
                    onPressed: widget.onProjects,
                    icon: const Icon(LucideIcons.folderGit2, size: 16),
                    label: Text(tr('Browse projects')),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Looks like the chat composer; tapping it starts a new chat.
class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.agent, required this.onStart, required this.onVoice});
  final AgentController agent;
  final VoidCallback onStart;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SurfaceCard(
      onTap: onStart,
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('Ask pi to build, fix or deploy…'),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: p.faint),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _ModelChip(agent: agent),
                ),
              ),
              const SizedBox(width: 8),
              _CircleButton(icon: LucideIcons.mic, label: tr('Voice'), onTap: onVoice),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: tr('New chat'),
                child: TapTarget(
                  onTap: onStart,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
                    child: Icon(LucideIcons.arrowUp, size: 20, color: p.onAccent),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The current model in the prompt card, opening the model sheet.
class _ModelChip extends StatelessWidget {
  const _ModelChip({required this.agent});
  final AgentController agent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: tr('Choose model'),
      child: Material(
        color: p.raised,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => showModelSheet(context, agent),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (agent.model != null) ...[
                  BrandTile(id: agent.model!.provider, size: 22),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    agent.model?.name ?? tr('Choose model'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(LucideIcons.chevronsUpDown, size: 14, color: p.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(Radii.lg),
                  border: Border.all(color: p.border),
                ),
                child: Icon(icon, size: 21, color: p.text),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: p.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A home section's title, with an optional action on the right.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 28, 0, 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: context.palette.accentText,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                // From the theme, not a bare TextStyle: a button's own textStyle replaces the theme's whole style,
                // family included, and the label fell back to the platform font.
                textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 13),
              ),
              child: Text(action!),
            ),
        ],
      ),
    );
  }
}

/// Shown until a model provider is connected.
class _ConnectCard extends StatelessWidget {
  const _ConnectCard({required this.agent});
  final AgentController agent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return SurfaceCard(
      highlight: true,
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconTile(icon: LucideIcons.plugZap, color: p.accent, size: 40),
              const Spacer(),
              // In its own tile, like the quick-start cards, so it never sits on the text.
              const SizedBox.square(
                dimension: 72,
                child: MeshArt(
                  seed: 'connect',
                  radius: Radii.md,
                  child: Padding(padding: EdgeInsets.all(6), child: Illustration('connect', height: 60)),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Text(tr('Connect a provider'), style: text.titleMedium),
          const SizedBox(height: Space.xs),
          Text(
            tr('Sign in with an account, add an API key, or point Rynex at your own endpoint \u2014 Claude, GPT, Gemini, DeepSeek and more, through any provider you choose.'),
            style: text.bodySmall,
          ),
          const SizedBox(height: Space.lg),
          PrimaryButton(
            compact: true,
            icon: LucideIcons.sparkles,
            label: tr('Connect a provider'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(agent: agent))),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap, required this.label});
  final IconData icon;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: label,
      child: TapTarget(
        onTap: onTap,
        child: Material(
          color: p.surface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(dimension: 44, child: Icon(icon, size: 20, color: p.text)),
          ),
        ),
      ),
    );
  }
}

class _PillChip extends StatelessWidget {
  const _PillChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // A 48 dp touch box around the 38 dp pill it draws.
    return Semantics(
      button: true,
      selected: selected,
      child: TapTarget(
        onTap: onTap,
        child: Material(
          color: selected ? p.text : Colors.transparent,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Text(
                label,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: selected ? p.inverse : p.muted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.q, required this.onTap, this.busy = false});
  final _Quick q;
  final VoidCallback onTap;

  /// Its folder and chat are being made.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: SizedBox(
        height: 96,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconTile(icon: q.icon, color: q.color, size: 34),
                const Spacer(),
                if (busy)
                  const BusySpinner(size: 16)
                else
                  Text(tr(q.category).toUpperCase(), style: text.labelSmall),
              ],
            ),
            const Spacer(),
            Text(tr(q.title), maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleSmall),
            const SizedBox(height: 2),
            Text(
              tr(q.blurb),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: p.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.session,
    required this.workspace,
    required this.onTap,
    this.onLongPress,
    this.selected,
    this.busy = false,
  });
  final SessionSummary session;
  final String workspace;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// This chat is being opened (the app waits on the host): a spinner instead of its time.
  final bool busy;

  /// Non-null in selection mode: whether this chat is picked.
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final folder = sessionFolder(session.cwd, workspace);
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.lg),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 52,
              child: MeshArt(
                seed: session.id,
                radius: 16,
                child: Center(
                  child: Icon(
                    folder != null ? LucideIcons.folderGit2 : LucideIcons.messageSquare,
                    size: 20,
                    color: MeshArt.inkFor(session.id),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(session.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                  const SizedBox(height: 3),
                  Text(
                    folder ?? tr('Quick chat'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: folder != null ? mono : null, fontSize: 12, color: p.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (busy)
              const BusySpinner()
            else if (selected != null)
              Icon(
                selected! ? LucideIcons.circleCheck : LucideIcons.circle,
                size: 22,
                color: selected! ? p.danger : p.faint,
              )
            else
              Text(formatAgo(session.modified), style: TextStyle(fontSize: 11.5, color: p.faint)),
          ],
        ),
      ),
    );
  }
}

/// (Relative times now come from the shared formatAgo in i18n.dart.)

// ---------------------------------------------------------------------------
// Chats

class _ChatsTab extends StatefulWidget {
  const _ChatsTab({required this.agent, this.selecting});
  final AgentController agent;

  /// Told whether chats are being picked, so Home's Back leaves that first.
  final ValueNotifier<bool>? selecting;

  @override
  State<_ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<_ChatsTab> {
  late Future<List<SessionSummary>> sessions = widget.agent.listSessions();
  String query = '';

  /// Kept by the tab: the list builds its rows lazily, and a search field rebuilt from nothing would lose its text.
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Paths of chats picked for deleting; selection mode is on while it is not empty.
  final _selected = <String>{};

  AgentController get agent => widget.agent;

  void _reload() => setState(() {
    sessions = agent.listSessions();
  });

  Future<void> _menu(SessionSummary s) async {
    final action = await showAppSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SettingsGroup(
            children: [
              SettingsRow(
                icon: LucideIcons.pencil,
                color: context.palette.accentAlt,
                title: tr('Rename'),
                onTap: () => Navigator.pop(context, 'rename'),
              ),
              SettingsRow(
                icon: LucideIcons.squareCheck,
                color: context.palette.muted,
                title: tr('Select'),
                subtitle: tr('Pick several chats to delete at once'),
                onTap: () => Navigator.pop(context, 'select'),
              ),
              SettingsRow(
                icon: LucideIcons.trash2,
                color: context.palette.danger,
                title: tr('Delete'),
                destructive: true,
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'rename') {
      final controller = TextEditingController(text: s.name ?? s.title);
      final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('Rename chat')),
          content: TextField(controller: controller, autofocus: true, onSubmitted: (v) => Navigator.pop(context, v)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(tr('Save'))),
          ],
        ),
      );
      controller.dispose();
      if (name != null && name.trim().isNotEmpty) await agent.renameSession(s.path, name.trim());
    } else if (action == 'select') {
      setState(() => _selected.add(s.path));
      return;
    } else if (action == 'delete') {
      if (!await deleteChats(context, agent, [s])) return;
    }
    _reload();
  }

  void _toggle(SessionSummary s) =>
      setState(() => _selected.contains(s.path) ? _selected.remove(s.path) : _selected.add(s.path));

  Future<void> _deleteSelected(List<SessionSummary> visible) async {
    final chosen = visible.where((s) => _selected.contains(s.path)).toList();
    if (!await deleteChats(context, agent, chosen)) return;
    setState(_selected.clear);
    _reload();
  }

  Widget _selectionBar(List<SessionSummary> visible) {
    final p = context.palette;
    final count = visible.where((s) => _selected.contains(s.path)).length;
    final allChosen = count == visible.length;
    return Row(
      children: [
        IconButton(
          tooltip: tr('Cancel'),
          onPressed: () => setState(_selected.clear),
          icon: const Icon(LucideIcons.x, size: 20),
        ),
        Expanded(child: Text('$count ${tr('selected')}', style: Theme.of(context).textTheme.titleMedium)),
        TextButton(
          onPressed: () => setState(() => allChosen ? _selected.clear() : _selected.addAll(visible.map((s) => s.path))),
          child: Text(allChosen ? tr('Select none') : tr('Select all')),
        ),
        IconButton(
          tooltip: tr('Delete'),
          onPressed: count == 0 ? null : () => _deleteSelected(visible),
          icon: Icon(LucideIcons.trash2, size: 20, color: count == 0 ? p.faint : p.danger),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final ws = agent.info['workspace'] as String? ?? '';
    return SafeArea(
      bottom: false,
      child: FutureBuilder<List<SessionSummary>>(
        future: sessions,
        builder: (context, snap) {
          final q = query.toLowerCase();
          final all = (snap.data ?? const <SessionSummary>[])
              .where((s) => s.messageCount > 0)
              .where((s) => q.isEmpty || s.title.toLowerCase().contains(q) || s.cwd.toLowerCase().contains(q))
              .toList();
          final groups = <String, List<SessionSummary>>{};
          for (final s in all) {
            groups.putIfAbsent(_bucket(s.modified), () => []).add(s);
          }
          final selecting = _selected.isNotEmpty;
          final told = widget.selecting;
          if (told != null && told.value != selecting) WidgetsBinding.instance.addPostFrameCallback((_) => told.value = selecting);
          return PopScope(
            // Back leaves selection mode first.
            canPop: !selecting,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) setState(_selected.clear);
            },
            // Only what is on screen is built, and the rows are not rebuilt every time the agent reports (about 30 times
            // a second while it streams): the list listens for the one thing a row shows from it, the chat being opened.
            child: _OnSwitching(
              agent: agent,
              builder: (context, switchingTo) {
                final rows = <Widget Function(BuildContext)>[
                  (_) => selecting
                      // At least the title's height (no jump between the two), and room for 48 dp buttons at any text size.
                      ? ConstrainedBox(
                          constraints: BoxConstraints(minHeight: text.displaySmall!.fontSize! * 1.25),
                          child: _selectionBar(all),
                        )
                      : Text(tr('Chats'), style: text.displaySmall),
                  (_) => const SizedBox(height: 16),
                  (_) => TextField(
                    controller: _query,
                    onChanged: (v) => setState(() {
                      query = v;
                    }),
                    decoration: InputDecoration(
                      hintText: tr('Search anything'),
                      prefixIcon: const Icon(LucideIcons.search, size: 18),
                    ),
                  ),
                  // A list that could not be read says so, with a retry (it spun forever).
                  if (snap.hasError)
                    (_) => Padding(
                      padding: const EdgeInsets.all(24),
                      child: ErrorNotice(error: snap.error, onRetry: _reload, center: true),
                    )
                  else if (!snap.hasData)
                    (_) => const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: BusySpinner.page()),
                    )
                  else if (all.isEmpty)
                    (_) => Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Column(
                        children: [
                          if (q.isEmpty) const Illustration('chat', height: 200),
                          const SizedBox(height: 12),
                          Text(
                            tr(q.isEmpty ? 'No chats yet. Tap + to start one.' : 'Nothing matches.'),
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  for (final e in groups.entries) ...[
                    (_) => SectionLabel(tr(e.key), padding: const EdgeInsets.fromLTRB(2, 22, 2, 4)),
                    for (final s in e.value)
                      (context) => _SessionRow(
                        session: s,
                        workspace: ws,
                        selected: selecting ? _selected.contains(s.path) : null,
                        busy: switchingTo == s.path,
                        onLongPress: () => selecting ? _toggle(s) : _menu(s),
                        onTap: () async {
                          if (selecting) return _toggle(s);
                          if (s.id != agent.sessionId && !await agent.openSession(s.path)) return;
                          if (context.mounted) await openChat(context, agent);
                          _reload();
                        },
                      ),
                  ],
                ];
                return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    itemCount: rows.length,
                    itemBuilder: (context, i) => rows[i](context),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  static String _bucket(DateTime t) {
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(t.year, t.month, t.day)).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 7) return 'This week';
    if (days < 30) return 'This month';
    return 'Older';
  }
}

// ---------------------------------------------------------------------------
// Projects

class _ProjectsTab extends StatefulWidget {
  const _ProjectsTab({required this.agent});
  final AgentController agent;

  @override
  State<_ProjectsTab> createState() => _ProjectsTabState();
}

class _ProjectsTabState extends State<_ProjectsTab> {
  String query = '';

  AgentController get agent => widget.agent;
  Integrations get it => agent.integrations;

  @override
  void initState() {
    super.initState();
    it.refreshProjects().catchError((_) {});
  }

  /// The project being opened, from the tap until its chat is on screen (finding its latest chat is a round trip too).
  String? _opening;

  Future<void> _open(ProjectInfo project) async {
    if (_opening != null || agent.switchingTo != null) return;
    setState(() => _opening = project.path);
    try {
      final sessions = await agent.listSessions();
      final latest = sessions.where((s) => s.cwd == project.path && s.messageCount > 0).firstOrNull;
      if (latest != null) {
        if (latest.id != agent.sessionId && !await agent.openSession(latest.path)) return;
      } else {
        if (!await agent.newSession(dir: project.path)) return;
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      return;
    } finally {
      if (mounted) setState(() => _opening = null);
    }
    if (mounted) await openChat(context, agent);
  }

  Future<void> _projectMenu(ProjectInfo project) async {
    final action = await showAppSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(project.name, style: Theme.of(context).textTheme.titleMedium),
              ),
              SettingsGroup(
                children: [
                  SettingsRow(
                    icon: LucideIcons.messageSquare,
                    color: context.palette.accentAlt,
                    title: tr('Open'),
                    onTap: () => Navigator.pop(context, 'open'),
                  ),
                  SettingsRow(
                    icon: LucideIcons.trash2,
                    color: context.palette.danger,
                    title: tr('Delete project'),
                    subtitle: tr('Removes the folder from this phone'),
                    destructive: true,
                    onTap: () => Navigator.pop(context, 'delete'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'open') await _open(project);
    if (action == 'delete' && mounted) await deleteProjectFlow(context, agent, project);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: Listenable.merge([it, agent]),
      builder: (context, _) {
        final projects = it.projects.where((x) => query.isEmpty || x.name.toLowerCase().contains(query)).toList();
        return SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: it.refreshProjects,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  sliver: SliverList.list(
                    children: [
                      Text(tr('Projects'), style: text.displaySmall),
                      const SizedBox(height: 16),
                      TextField(
                        onChanged: (v) => setState(() {
                          query = v.toLowerCase();
                        }),
                        decoration: InputDecoration(
                          hintText: tr('Search projects'),
                          prefixIcon: const Icon(LucideIcons.search, size: 18),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await Navigator.of(context)
                                    .push(MaterialPageRoute(builder: (_) => ReposScreen(agent: agent)));
                                it.refreshProjects();
                              },
                              icon: const Icon(SimpleIcons.github, size: 16),
                              label: Text(tr('Clone repo')),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final dir = await FolderPicker.pick(context, agent);
                                if (dir == null) return;
                                if (!await agent.newSession(dir: dir)) return;
                                if (context.mounted) await openChat(context, agent);
                              },
                              icon: const Icon(LucideIcons.folderOpen, size: 16),
                              label: Text(tr('Open folder')),
                            ),
                          ),
                        ],
                      ),
                      if (projects.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            tr('Long-press a project to open or delete it.'),
                            style: text.bodySmall?.copyWith(color: p.muted),
                          ),
                        ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
                if (projects.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        children: [
                          const Illustration('projects', height: 200),
                          const SizedBox(height: 12),
                          Text(tr('Projects you create or clone appear here.'), style: text.bodySmall),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    sliver: SliverGrid.builder(
                      // Two tiles across on a phone, more on a wider screen, instead of two huge ones.
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 230,
                        mainAxisSpacing: 18,
                        crossAxisSpacing: 14,
                        childAspectRatio: 0.82,
                      ),
                      itemCount: projects.length,
                      itemBuilder: (context, i) {
                        final pr = projects[i];
                        return GestureDetector(
                          onTap: () => _open(pr),
                          onLongPress: () => _projectMenu(pr),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: MeshArt(
                                  seed: pr.name,
                                  radius: 22,
                                  child: Stack(
                                    children: [
                                      Center(
                                        child: _opening == pr.path
                                            ? BusySpinner(size: 28, color: MeshArt.inkFor(pr.name))
                                            : Icon(
                                                pr.isGit ? LucideIcons.folderGit2 : LucideIcons.folder,
                                                size: 44,
                                                color: MeshArt.inkFor(pr.name),
                                              ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Align(
                                          alignment: Alignment.topRight,
                                          child: pr.isGit
                                              ? Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white.withValues(alpha: 0.85),
                                                    borderRadius: BorderRadius.circular(Radii.pill),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(
                                                        LucideIcons.gitBranch,
                                                        size: 11,
                                                        color: Color(0xFF111113),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        pr.branch ?? 'git',
                                                        style: const TextStyle(
                                                          fontSize: 10.5,
                                                          fontWeight: FontWeight.w600,
                                                          color: Color(0xFF111113),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                )
                                              : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(pr.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                              const SizedBox(height: 2),
                              Text(
                                pr.githubSlug ?? tr(pr.dirty ? 'uncommitted changes' : 'local folder'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: p.muted),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Rebuilds [builder] when the chat being opened changes, and not on the agent's other reports.
class _OnSwitching extends StatefulWidget {
  const _OnSwitching({required this.agent, required this.builder});
  final AgentController agent;
  final Widget Function(BuildContext context, String? switchingTo) builder;

  @override
  State<_OnSwitching> createState() => _OnSwitchingState();
}

class _OnSwitchingState extends State<_OnSwitching> {
  late String? _switching = widget.agent.switchingTo;

  void _changed() {
    if (widget.agent.switchingTo != _switching) setState(() => _switching = widget.agent.switchingTo);
  }

  @override
  void initState() {
    super.initState();
    widget.agent.addListener(_changed);
  }

  @override
  void dispose() {
    widget.agent.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _switching);
}
