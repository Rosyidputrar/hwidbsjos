import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:simple_icons/simple_icons.dart';

import '../agent/agent_controller.dart';
import '../agent/integrations.dart';
import '../agent/models.dart';
import 'i18n.dart';
import 'accounts_screen.dart';
import 'chat_extras.dart';
import 'chat_screen.dart';
import 'folder_picker.dart';
import 'kit.dart';
import 'mesh.dart';
import 'model_sheet.dart';
import 'new_chat_sheet.dart';
import 'repos_screen.dart';
import 'settings_hub.dart';
import 'settings_screen.dart';
import 'skills_screen.dart';
import 'tasks_screen.dart';
import 'terminal_screen.dart';
import 'theme.dart';

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

/// The app's home: four tabs and a docked navigation bar with a create button.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.agent});
  final AgentController agent;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int tab = 0;
  final subs = <StreamSubscription<Object?>>[];
  AppLifecycleState lifecycle = AppLifecycleState.resumed;
  int approvalsSeen = 0;

  AgentController get agent => widget.agent;
  bool get _inBackground => lifecycle != AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final f = agent.features;
    subs
      ..add(agent.client.records.where((r) => r['type'] == 'launch').listen((_) => _takeLaunch()))
      ..add(
        f.done.stream.listen((preview) {
          // Id 1 belongs to the foreground service notification, which is removed when the agent stops.
          if (_inBackground) agent.client.notify(11, 'pi is done', preview.isEmpty ? 'Tap to see the result' : preview);
        }),
      )
      ..add(
        f.runFinished.stream.listen((run) {
          final ok = run.status == 'done';
          agent.client.notify(
            2000 + run.id.hashCode % 1000,
            ok ? 'Task done: ${run.title}' : 'Task ${run.status}: ${run.title}',
            run.summary ?? '',
          );
        }),
      );
    f.addListener(_onFeatures);
    f.refreshRuns().catchError((_) {});
    agent.client.requestNotifications().catchError((_) {});
    // The app may have been opened by a share, the widget or the tile.
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeLaunch());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    agent.features.removeListener(_onFeatures);
    for (final s in subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => lifecycle = state;

  /// Approvals that arrive while the app is in the background become notifications.
  void _onFeatures() {
    final pending = agent.features.approvals;
    if (pending.length > approvalsSeen && _inBackground) {
      agent.client.notify(3, 'pi needs your approval', '${pending.last.toolName}: ${pending.last.summary}');
    }
    approvalsSeen = pending.length;
  }

  Future<void> _takeLaunch() async {
    final launch = await agent.client.takeLaunch();
    if (launch == null || !mounted) return;
    // Close any sheet or page so the new chat opens on top of home.
    Navigator.of(context).popUntil((r) => r.isFirst);
    switch (launch['action']) {
      case 'new_chat':
        await _newChat();
      case 'voice':
        await _voiceChat();
      case 'share':
        final files = [
          for (final f in (launch['files'] as List? ?? const []).cast<Map>())
            Attachment(f['path'] as String, f['name'] as String, mime: f['mime'] as String?),
        ];
        await agent.newSession();
        if (mounted) await openChat(context, agent, prompt: launch['text'] as String?, attachments: files);
    }
  }

  Future<void> _newChat() async {
    final before = agent.sessionId;
    await showNewChatSheet(context, agent);
    if (mounted && agent.sessionId != before) await openChat(context, agent);
  }

  Future<void> _voiceChat() async {
    await agent.newSession();
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
      _ChatsTab(agent: agent, onNewChat: _newChat),
      _ProjectsTab(agent: agent),
      SettingsHub(agent: agent, embedded: true),
    ];
    return PopScope(
      // Back on another tab returns to Home before leaving the app.
      canPop: tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => tab = 0);
      },
      child: Scaffold(
        // Every tab stays built (scroll positions survive); the active one fades
        // and drifts in, the others fade out and stop ticking.
        body: Stack(
          children: [
            for (var i = 0; i < tabs.length; i++) _TabLayer(active: i == tab, forward: i >= tab, child: tabs[i]),
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
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            onEnd: () {
              if (!widget.active && mounted) setState(() => hidden = true);
            },
            child: AnimatedSlide(
              offset: active ? Offset.zero : Offset(widget.forward ? 0.03 : -0.03, 0),
              duration: const Duration(milliseconds: 280),
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
// Navigation bar

/// Docked bar: Home, Chats, the create button, Projects, Settings.
class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.onTap, required this.onCreate, this.settingsDot = false});
  final int index;
  final ValueChanged<int> onTap;
  final VoidCallback onCreate;
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
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dot = false,
  });
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
              duration: const Duration(milliseconds: 220),
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
                      child: StatusDot(color: p.warning, size: 7),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? p.text : p.muted,
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
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutBack,
          child: Container(
            width: 52,
            height: 42,
            decoration: BoxDecoration(
              color: p.accent,
              borderRadius: BorderRadius.circular(Radii.md),
              boxShadow: [
                BoxShadow(
                  color: p.accent.withValues(alpha: 0.25),
                  blurRadius: 12,
                  spreadRadius: -2,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: AnimatedRotation(
              turns: turns,
              duration: const Duration(milliseconds: 420),
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
  const _Quick(this.title, this.subtitle, this.icon, this.color, this.category, {this.prompt});
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String category;

  /// Null starts an empty chat through the new-chat sheet.
  final String? prompt;
}

const _quick = [
  _Quick(
    'Build a web app',
    'A polished page you can preview',
    LucideIcons.layoutTemplate,
    Color(0xFFF97316),
    'Build',
    prompt: 'Build me a polished, mobile-first web app: ',
  ),
  _Quick(
    'Design a modern UI',
    'With the ui-designer skill',
    LucideIcons.palette,
    Color(0xFF14B8A6),
    'Build',
    prompt: 'Using the ui-designer skill, design and build a modern screen for: ',
  ),
  _Quick('Chat with the smartest agent', 'Ask anything, no template', LucideIcons.sparkles, Color(0xFF8B5CF6), 'Code'),
  _Quick(
    'Fix a bug',
    'Find the cause and patch it',
    LucideIcons.bug,
    Color(0xFFEF4444),
    'Code',
    prompt: 'Help me find and fix this bug: ',
  ),
  _Quick(
    'Python in Linux',
    'Scripts in the container',
    SimpleIcons.python,
    Color(0xFF3B82F6),
    'Ops',
    prompt: 'Set up a Python project in the Linux container and write a script that ',
  ),
  _Quick(
    'Deploy a site',
    'Get a live URL',
    LucideIcons.rocket,
    Color(0xFFEC4899),
    'Ops',
    prompt: 'Deploy this project and give me the live URL. Project: ',
  ),
  _Quick(
    'Automate a task',
    'A script that does it for you',
    LucideIcons.zap,
    Color(0xFFEAB308),
    'Ops',
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

class _HomeTabState extends State<_HomeTab> {
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
    if (q.prompt == null) {
      widget.onNewChat();
      return;
    }
    // Each quick start gets its own project folder.
    final ws = agent.info['workspace'] as String? ?? '';
    final slug = q.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    final n = DateTime.now();
    final dir = Directory('$ws/$slug-${n.month}${n.day}-${n.hour}${n.minute.toString().padLeft(2, '0')}')
      ..createSync(recursive: true);
    await agent.newSession(dir: dir.path);
    if (mounted) await openChat(context, agent, prompt: q.prompt);
    _refresh();
  }

  Future<void> _openFolder() async {
    final dir = await FolderPicker.pick(context, agent);
    if (dir == null) return;
    await agent.newSession(dir: dir);
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
              padding: const EdgeInsets.fromLTRB(Space.page, Space.md, Space.page, Space.xxl),
              children: [
                // Brand, status and the two personal shortcuts.
                Row(
                  children: [
                    const LogoMark(size: 30),
                    const SizedBox(width: Space.sm),
                    Text('Rynex', style: text.titleMedium),
                    const SizedBox(width: Space.sm),
                    Pill(
                      agent.busy ? tr('Working') : tr('Ready'),
                      color: agent.busy ? p.warning : p.success,
                      dot: true,
                    ),
                    const Spacer(),
                    AppIconButton(
                      icon: LucideIcons.listTodo,
                      label: tr('Tasks'),
                      badge: running,
                      onTap: () => _push(TasksScreen(agent: agent)),
                    ),
                    const SizedBox(width: Space.sm),
                    Semantics(
                      button: true,
                      label: tr('Accounts & servers'),
                      child: GestureDetector(
                        onTap: () => _push(AccountsScreen(agent: agent)),
                        child: Avatar(name: gh?.name ?? gh?.login ?? 'Rynex', url: gh?.avatarUrl, size: 40),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.xxl),
                Text(
                  name.isEmpty ? tr('What should we build today?') : '${tr('Hello,')} $name',
                  style: text.headlineSmall,
                ),
                if (name.isNotEmpty) ...[
                  const SizedBox(height: Space.xs),
                  Text(tr('What should we build today?'), style: text.bodyMedium?.copyWith(color: p.muted)),
                ],
                const SizedBox(height: Space.lg),
                if (agent.hasModel)
                  _PromptCard(agent: agent, onStart: widget.onNewChat, onVoice: widget.onVoice)
                else
                  _ConnectCard(agent: agent),
                if (running > 0) ...[
                  const SizedBox(height: Space.md),
                  InlineBanner(
                    tone: p.accent,
                    icon: LucideIcons.loaderCircle,
                    onTap: () => _push(TasksScreen(agent: agent)),
                    trailing: Icon(LucideIcons.chevronRight, size: 18, color: p.faint),
                    padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.md),
                    child: Text(
                      '$running ${tr(running == 1 ? 'background task running' : 'background tasks running')}',
                      style: text.titleSmall,
                    ),
                  ),
                ],
                // Shortcuts to the places people go most.
                const SizedBox(height: Space.xl),
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
                SectionHeader(tr('Start something')),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  child: Row(
                    children: [
                      for (final c in const ['All', 'Build', 'Code', 'Ops'])
                        Padding(
                          padding: const EdgeInsets.only(right: Space.sm),
                          child: AppChip(
                            label: tr(c == 'All' ? 'All types' : c),
                            selected: category == c,
                            onTap: () => setState(() => category = c),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.md),
                LayoutBuilder(
                  builder: (context, box) {
                    final width = (box.maxWidth - Space.md) / 2;
                    return Wrap(
                      spacing: Space.md,
                      runSpacing: Space.md,
                      children: [
                        for (final q in quick)
                          SizedBox(
                            width: width,
                            child: _QuickCard(q: q, onTap: () => _run(q)),
                          ),
                      ],
                    );
                  },
                ),
                SectionHeader(tr('Recent'), action: tr('See all'), onAction: widget.onSeeAll),
                FutureBuilder<List<SessionSummary>>(
                  future: recent,
                  builder: (context, snap) {
                    final list = (snap.data ?? const <SessionSummary>[])
                        .where((s) => s.messageCount > 0)
                        .take(5)
                        .toList();
                    if (!snap.hasData) return const SizedBox(height: 60);
                    if (list.isEmpty) {
                      return SurfaceCard(
                        child: Row(
                          children: [
                            GlyphTile(icon: LucideIcons.messageSquareDashed, color: p.muted),
                            const SizedBox(width: Space.md),
                            Expanded(child: Text(tr('Your chats will show up here.'), style: text.bodySmall)),
                          ],
                        ),
                      );
                    }
                    return SettingsGroup(
                      children: [
                        for (final s in list)
                          SessionRow(
                            session: s,
                            workspace: agent.info['workspace'] as String? ?? '',
                            working: agent.busy && s.id == agent.sessionId,
                            onTap: () async {
                              if (s.id != agent.sessionId) await agent.openSession(s.path);
                              if (context.mounted) await openChat(context, agent);
                              _refresh();
                            },
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: Space.md),
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
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.md, Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('Ask pi to build, fix or deploy…'),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: p.faint),
          ),
          const SizedBox(height: Space.xl),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AppChip(
                    leading: agent.model == null ? null : BrandTile(id: agent.model!.provider, size: 22),
                    label: agent.model?.name ?? tr('Choose model'),
                    trailingIcon: LucideIcons.chevronsUpDown,
                    onTap: () => showModelSheet(context, agent),
                  ),
                ),
              ),
              const SizedBox(width: Space.sm),
              AppIconButton(icon: LucideIcons.mic, label: tr('Voice'), size: 38, onTap: onVoice),
              const SizedBox(width: Space.sm),
              AppIconButton(icon: LucideIcons.arrowUp, label: tr('New chat'), size: 38, filled: true, onTap: onStart),
            ],
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
          IconTile(icon: LucideIcons.plugZap, color: p.accent, size: 40),
          const SizedBox(height: Space.md),
          Text(tr('Connect a model'), style: text.titleMedium),
          const SizedBox(height: Space.xs),
          Text(
            tr('Sign in to a provider or add an API key: Anthropic, OpenAI, Gemini, OpenRouter and more.'),
            style: text.bodySmall,
          ),
          const SizedBox(height: Space.lg),
          PrimaryButton(
            compact: true,
            icon: LucideIcons.sparkles,
            label: tr('Choose a model'),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(agent: agent))),
          ),
        ],
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
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
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

class _QuickCard extends StatelessWidget {
  const _QuickCard({required this.q, required this.onTap});
  final _Quick q;
  final VoidCallback onTap;

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
                Text(tr(q.category).toUpperCase(), style: text.labelSmall),
              ],
            ),
            const Spacer(),
            Text(tr(q.title), maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleSmall),
            const SizedBox(height: 2),
            Text(
              tr(q.subtitle),
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

/// One chat in a list: tinted icon, title, folder, age, and an optional menu.
class SessionRow extends StatelessWidget {
  const SessionRow({
    super.key,
    required this.session,
    required this.workspace,
    required this.onTap,
    this.onMenu,
    this.working = false,
  });
  final SessionSummary session;
  final String workspace;
  final VoidCallback onTap;
  final VoidCallback? onMenu;
  final bool working;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final folder = sessionFolder(session.cwd, workspace);
    final tone = MeshArt.tone(folder ?? session.id);
    return InkWell(
      onTap: onTap,
      onLongPress: onMenu,
      child: Padding(
        padding: EdgeInsets.fromLTRB(Space.md, Space.md, onMenu != null ? Space.xs : Space.md, Space.md),
        child: Row(
          children: [
            IconTile(icon: folder != null ? LucideIcons.folderGit2 : LucideIcons.messageSquare, color: tone, size: 38),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(session.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (working) ...[StatusDot(color: p.warning, size: 6, pulse: true), const SizedBox(width: 6)],
                      Flexible(
                        child: Text(
                          working ? tr('Working') : (folder ?? tr('Quick chat')),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: folder != null && !working ? mono : null,
                            fontSize: 12,
                            color: working ? p.warning : p.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.sm),
            Text(_ago(session.modified), style: TextStyle(fontSize: 11.5, color: p.faint)),
            if (onMenu != null)
              IconButton(
                tooltip: tr('More'),
                visualDensity: VisualDensity.compact,
                icon: Icon(LucideIcons.ellipsisVertical, size: 18, color: p.faint),
                onPressed: onMenu,
              ),
          ],
        ),
      ),
    );
  }
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  final id = Appearance.instance.language == 'id';
  if (d.inMinutes < 1) return id ? 'baru saja' : 'now';
  if (d.inHours < 1) return id ? '${d.inMinutes} mnt lalu' : '${d.inMinutes}m ago';
  if (d.inDays < 1) return id ? '${d.inHours} jam lalu' : '${d.inHours}h ago';
  if (d.inDays < 7) return id ? '${d.inDays} hr lalu' : '${d.inDays}d ago';
  return '${t.day}/${t.month}';
}

// ---------------------------------------------------------------------------
// Chats

class _ChatsTab extends StatefulWidget {
  const _ChatsTab({required this.agent, required this.onNewChat});
  final AgentController agent;
  final VoidCallback onNewChat;

  @override
  State<_ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<_ChatsTab> {
  late Future<List<SessionSummary>> sessions = widget.agent.listSessions();
  String query = '';

  AgentController get agent => widget.agent;

  void _reload() => setState(() {
    sessions = agent.listSessions();
  });

  Future<void> _menu(SessionSummary s) async {
    final active = s.id == agent.sessionId;
    final action = await showActionSheet<String>(
      context,
      title: s.title,
      actions: [
        (
          icon: LucideIcons.pencil,
          title: tr('Rename'),
          subtitle: null,
          value: 'rename',
          destructive: false,
          enabled: true,
        ),
        (
          icon: LucideIcons.trash2,
          title: tr('Delete'),
          subtitle: active ? tr('Open another chat first') : null,
          value: 'delete',
          destructive: true,
          enabled: !active,
        ),
      ],
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
    } else if (action == 'delete') {
      await agent.deleteSession(s.path);
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final ws = agent.info['workspace'] as String? ?? '';
    return SafeArea(
      bottom: false,
      child: FutureBuilder<List<SessionSummary>>(
        future: sessions,
        builder: (context, snap) {
          final q = query.toLowerCase();
          final withMessages = (snap.data ?? const <SessionSummary>[]).where((s) => s.messageCount > 0).toList();
          final all = withMessages
              .where((s) => q.isEmpty || s.title.toLowerCase().contains(q) || s.cwd.toLowerCase().contains(q))
              .toList();
          final groups = <String, List<SessionSummary>>{};
          for (final s in all) {
            groups.putIfAbsent(_bucket(s.modified), () => []).add(s);
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListenableBuilder(
              listenable: agent,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(Space.page, Space.md, Space.page, Space.xxl),
                children: [
                  PageHeader(
                    tr('Chats'),
                    subtitle: snap.hasData ? '${withMessages.length} ${tr('conversations')}' : null,
                    actions: [
                      AppIconButton(icon: LucideIcons.squarePen, label: tr('New chat'), onTap: widget.onNewChat),
                    ],
                  ),
                  TextField(
                    onChanged: (v) => setState(() {
                      query = v;
                    }),
                    decoration: InputDecoration(
                      hintText: tr('Search anything'),
                      prefixIcon: const Icon(LucideIcons.search, size: 18),
                    ),
                  ),
                  if (!snap.hasData)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else if (all.isEmpty)
                    EmptyState(
                      icon: q.isEmpty ? LucideIcons.messagesSquare : LucideIcons.searchX,
                      title: q.isEmpty ? tr('No chats yet') : tr('Nothing matches.'),
                      message: q.isEmpty ? tr('Start one and it will be listed here.') : null,
                      action: q.isEmpty
                          ? PrimaryButton(
                              compact: true,
                              icon: LucideIcons.plus,
                              label: tr('New chat'),
                              onPressed: widget.onNewChat,
                            )
                          : null,
                    ),
                  for (final e in groups.entries) ...[
                    SectionLabel(tr(e.key), padding: const EdgeInsets.fromLTRB(4, Space.xl, 4, Space.sm)),
                    SettingsGroup(
                      children: [
                        for (final s in e.value)
                          SessionRow(
                            session: s,
                            workspace: ws,
                            working: agent.busy && s.id == agent.sessionId,
                            onMenu: () => _menu(s),
                            onTap: () async {
                              if (s.id != agent.sessionId) await agent.openSession(s.path);
                              if (context.mounted) await openChat(context, agent);
                              _reload();
                            },
                          ),
                      ],
                    ),
                  ],
                ],
              ),
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

  Future<void> _open(ProjectInfo project) async {
    final sessions = await agent.listSessions();
    final latest = sessions.where((s) => s.cwd == project.path && s.messageCount > 0).firstOrNull;
    if (latest != null) {
      if (latest.id != agent.sessionId) await agent.openSession(latest.path);
    } else {
      await agent.newSession(dir: project.path);
    }
    if (mounted) await openChat(context, agent);
  }

  Future<void> _clone() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReposScreen(agent: agent)));
    it.refreshProjects();
  }

  Future<void> _openFolder() async {
    final dir = await FolderPicker.pick(context, agent);
    if (dir == null) return;
    await agent.newSession(dir: dir);
    if (mounted) await openChat(context, agent);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: it,
      builder: (context, _) {
        final projects = it.projects.where((x) => query.isEmpty || x.name.toLowerCase().contains(query)).toList();
        return SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: it.refreshProjects,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(Space.page, Space.md, Space.page, 0),
                  sliver: SliverList.list(
                    children: [
                      PageHeader(
                        tr('Projects'),
                        subtitle: '${it.projects.length} ${tr('folders in the workspace')}',
                        actions: [
                          AppIconButton(icon: SimpleIcons.github, label: tr('Clone repo'), onTap: _clone),
                          AppIconButton(icon: LucideIcons.folderOpen, label: tr('Open folder'), onTap: _openFolder),
                        ],
                      ),
                      TextField(
                        onChanged: (v) => setState(() {
                          query = v.toLowerCase();
                        }),
                        decoration: InputDecoration(
                          hintText: tr('Search projects'),
                          prefixIcon: const Icon(LucideIcons.search, size: 18),
                        ),
                      ),
                      const SizedBox(height: Space.lg),
                    ],
                  ),
                ),
                if (projects.isEmpty)
                  SliverToBoxAdapter(
                    child: EmptyState(
                      icon: LucideIcons.folderPlus,
                      title: query.isEmpty ? tr('No projects yet') : tr('Nothing matches.'),
                      message: query.isEmpty ? tr('Projects you create or clone appear here.') : null,
                      action: query.isEmpty
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _clone,
                                  icon: const Icon(SimpleIcons.github, size: 16),
                                  label: Text(tr('Clone repo')),
                                ),
                                const SizedBox(width: Space.sm),
                                OutlinedButton.icon(
                                  onPressed: _openFolder,
                                  icon: const Icon(LucideIcons.folderOpen, size: 16),
                                  label: Text(tr('Open folder')),
                                ),
                              ],
                            )
                          : null,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.xxl),
                    sliver: SliverGrid.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: Space.md,
                        crossAxisSpacing: Space.md,
                        mainAxisExtent: 138,
                      ),
                      itemCount: projects.length,
                      itemBuilder: (context, i) => _ProjectCard(project: projects[i], onTap: () => _open(projects[i])),
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

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onTap});
  final ProjectInfo project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final pr = project;
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(
                icon: pr.isGit ? LucideIcons.folderGit2 : LucideIcons.folder,
                color: MeshArt.tone(pr.name),
                size: 38,
              ),
              const Spacer(),
              if (pr.dirty)
                Tooltip(
                  message: tr('Uncommitted changes'),
                  child: StatusDot(color: p.warning),
                ),
            ],
          ),
          const Spacer(),
          Text(pr.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
          const SizedBox(height: 2),
          Text(
            pr.githubSlug ?? (pr.dirty ? tr('uncommitted changes') : tr('local folder')),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: p.muted),
          ),
          if (pr.isGit) ...[
            const SizedBox(height: Space.sm),
            Row(
              children: [
                Icon(LucideIcons.gitBranch, size: 12, color: p.faint),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    pr.branch ?? 'git',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: mono, fontSize: 11, color: p.faint),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
