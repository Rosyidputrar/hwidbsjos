import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../agent/agent_controller.dart';
import '../agent/models.dart';
import '../agent/features.dart';
import 'i18n.dart';
import 'chat_extras.dart';
import 'message_views.dart';

import 'package:simple_icons/simple_icons.dart';

import 'repos_screen.dart';
import 'kit.dart';
import 'model_sheet.dart';
import 'tasks_screen.dart';
import 'settings_screen.dart';
import 'folder_picker.dart';
import 'theme.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.agent,
    this.initialPrompt,
    this.initialAttachments = const [],
    this.listenOnOpen = false,
  });
  final AgentController agent;

  /// Pre-filled into the composer (quick starts, shares), for the user to finish.
  final String? initialPrompt;
  final List<Attachment> initialAttachments;

  /// Start voice input right away (the widget's Voice button).
  final bool listenOnOpen;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final scroll = ScrollController();
  final input = TextEditingController();
  final focus = FocusNode();
  bool followBottom = true;

  /// The user's finger is on the list (or it is still flinging from it);
  /// auto-follow must not fight them.
  bool dragging = false;
  int lastCount = 0;
  final attachments = <Attachment>[];
  List<SlashCommand>? slash;

  AgentController get agent => widget.agent;

  /// "/par" while typing a command name; null otherwise.
  String? get _slashQuery {
    final t = input.text;
    if (!t.startsWith('/') || t.contains(' ') || t.contains('\n')) return null;
    return t.substring(1);
  }

  @override
  void initState() {
    super.initState();
    agent.addListener(_onAgentChanged);
    final prompt = widget.initialPrompt;
    if (prompt != null) {
      input.text = prompt;
      input.selection = TextSelection.collapsed(offset: prompt.length);
      WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
    }
    scroll.addListener(() {
      if (!scroll.hasClients || dragging) return;
      if (_atBottom != followBottom) setState(() => followBottom = _atBottom);
    });
    input.addListener(() {
      if (_slashQuery != null && slash == null) _loadSlash();
      setState(() {});
    });
    attachments.addAll(widget.initialAttachments);
    if (widget.listenOnOpen) WidgetsBinding.instance.addPostFrameCallback((_) => _voice());
    // History may have loaded before this screen existed.
    lastCount = agent.entries.length;
    _jumpToBottom();
  }

  @override
  void dispose() {
    agent.removeListener(_onAgentChanged);
    scroll.dispose();
    input.dispose();
    focus.dispose();
    super.dispose();
  }

  bool get _atBottom => scroll.position.pixels >= scroll.position.maxScrollExtent - 80;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is ScrollStartNotification && n.dragDetails != null) {
      dragging = true;
      if (followBottom) setState(() => followBottom = false);
    } else if (n is ScrollEndNotification && dragging) {
      dragging = false;
      // Landing back at the bottom re-arms following.
      if (scroll.hasClients && _atBottom != followBottom) setState(() => followBottom = _atBottom);
    }
    return false;
  }

  void _onAgentChanged() {
    final grew = agent.entries.length != lastCount;
    lastCount = agent.entries.length;
    if (followBottom || grew && agent.entries.lastOrNull is UserEntry) _jumpToBottom();
  }

  void _jumpToBottom({bool animate = false, int passes = 4}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients || dragging) return;
      final target = scroll.position.maxScrollExtent;
      if (animate) {
        scroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        return;
      }
      scroll.jumpTo(target);
      // A lazy list only estimates its extent until the tail is laid out;
      // settle again next frame if landing there revealed more.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (passes > 1 && scroll.hasClients && scroll.position.maxScrollExtent > target + 1) {
          _jumpToBottom(passes: passes - 1);
        }
      });
    });
  }

  Future<void> _loadSlash() async {
    slash = const [];
    try {
      final list = await agent.features.slashCommands();
      if (mounted) setState(() => slash = list);
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = input.text;
    if (text.trim().isEmpty && attachments.isEmpty) return;
    if (!agent.hasModel) {
      await _connectProvider();
      return;
    }
    final files = List<Attachment>.of(attachments);
    input.clear();
    setState(() => attachments.clear());
    followBottom = true;
    if (files.isEmpty) {
      await agent.send(text);
    } else {
      final prompt = await preparePrompt(text, files, agent.cwd);
      await agent.sendWith(prompt.text, images: prompt.images);
    }
  }

  /// Long-press on send: hand the task to a background agent instead.
  Future<void> _queue() async {
    final text = input.text.trim();
    if (text.isEmpty) return;
    input.clear();
    await agent.features.enqueue(text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('Queued as a background task')),
          action: SnackBarAction(
            label: tr('View'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TasksScreen(agent: agent))),
          ),
        ),
      );
    }
  }

  Future<void> _attach() async {
    final picked = await pickAttachments(context);
    if (picked.isNotEmpty) setState(() => attachments.addAll(picked));
  }

  Future<void> _voice() async {
    try {
      final heard = await agent.client.listen();
      if (heard == null || heard.trim().isEmpty) return;
      final current = input.text.trim();
      input.text = current.isEmpty ? heard : '$current $heard';
      input.selection = TextSelection.collapsed(offset: input.text.length);
      focus.requestFocus();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Voice input: $e')));
    }
  }

  void _prefill(String text) {
    input.text = text;
    input.selection = TextSelection.collapsed(offset: text.length);
    focus.requestFocus();
  }

  /// Long-press on one of your messages: edit & resend, fork, copy.
  Future<void> _userMenu(UserEntry entry, int userIndex) async {
    final action = await showActionSheet<String>(
      context,
      actions: [
        (
          icon: LucideIcons.pencil,
          title: tr('Edit & resend'),
          subtitle: tr('Rewind to this message and change it'),
          value: 'edit',
          destructive: false,
          enabled: true,
        ),
        (
          icon: LucideIcons.gitFork,
          title: tr('Fork from here'),
          subtitle: tr('A new chat that branches off before this message'),
          value: 'fork',
          destructive: false,
          enabled: true,
        ),
        (icon: LucideIcons.copy, title: tr('Copy'), subtitle: null, value: 'copy', destructive: false, enabled: true),
      ],
    );
    if (action == null || !mounted) return;
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: entry.text));
      return;
    }
    if (agent.busy) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Wait for pi to finish first'))));
      return;
    }
    try {
      final points = await agent.features.forkPoints();
      if (userIndex >= points.length) throw 'This message cannot be edited';
      final entryId = points[userIndex].entryId;
      final text = action == 'edit' ? await agent.editMessage(entryId) : await agent.forkAt(entryId);
      _prefill(text.isEmpty ? entry.text : text);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _connectProvider() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(agent: agent)));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListenableBuilder(
      listenable: agent,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          leading: Navigator.of(context).canPop()
              ? IconButton(
                  tooltip: tr('Back'),
                  icon: const Icon(LucideIcons.chevronLeft, size: 24),
                  onPressed: () => Navigator.of(context).pop(),
                )
              : null,
          title: _Title(agent: agent),
          actions: [
            AppIconButton(
              icon: LucideIcons.layoutGrid,
              label: tr('Workspace'),
              size: 38,
              onTap: () => showProjectTools(context, agent, onPrompt: _prefill),
            ),
            const SizedBox(width: Space.md),
          ],
          // A thin running bar while pi works; a hairline otherwise.
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: agent.busy
                ? LinearProgressIndicator(minHeight: 2, backgroundColor: p.border)
                : Divider(height: 2, thickness: 1, color: p.border),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  agent.entries.isEmpty
                      ? _EmptyState(
                          agent: agent,
                          onConnect: _connectProvider,
                          onPrompt: _prefill,
                          onClone: () =>
                              Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReposScreen(agent: agent))),
                        )
                      : NotificationListener<TranscriptGrew>(
                          onNotification: (_) {
                            if (followBottom) _jumpToBottom();
                            return true;
                          },
                          // Content can also shrink or reflow on its own (a live
                          // code panel folding away when a tool call lands);
                          // stay pinned to the bottom through that too.
                          child: NotificationListener<ScrollMetricsNotification>(
                            onNotification: (n) {
                              if (followBottom && !dragging && n.metrics.pixels != n.metrics.maxScrollExtent) {
                                _jumpToBottom();
                              }
                              return false;
                            },
                            child: NotificationListener<ScrollNotification>(
                              onNotification: _onScroll,
                              child: _transcript(),
                            ),
                          ),
                        ),
                  if (!followBottom)
                    Positioned(
                      right: Space.lg,
                      bottom: Space.md,
                      child: AppIconButton(
                        icon: LucideIcons.arrowDown,
                        label: tr('Scroll to bottom'),
                        size: 38,
                        onTap: () => _jumpToBottom(animate: true),
                      ),
                    ),
                ],
              ),
            ),
            DevServerBanner(agent: agent),
            ApprovalCards(features: agent.features),
            PlanBar(agent: agent),
            if (_slashQuery != null && slash != null)
              SlashMenu(commands: slash!, query: _slashQuery!, onPick: (c) => _prefill('/${c.name} ')),
            if (agent.billingNotice != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.lg, 0),
                child: Text(
                  agent.billingNotice!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.muted),
                ),
              ),
            _Composer(
              controller: input,
              focus: focus,
              agent: agent,
              onSend: _send,
              onQueue: _queue,
              onAttach: _attach,
              onVoice: _voice,
              attachments: attachments,
              onRemoveAttachment: (a) => setState(() => attachments.remove(a)),
              onPickModel: () => showModelSheet(context, agent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _transcript() {
    final entries = agent.entries;
    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.xl),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        // pi's replies get a small byline at the start of each turn.
        final turnStart = i == 0 || entries[i - 1] is UserEntry;
        final child = switch (e) {
          UserEntry() => UserMessageView(
            e,
            onLongPress: () => _userMenu(e, entries.take(i).whereType<UserEntry>().length),
          ),
          AssistantEntry() => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (turnStart) const _Byline(),
              AssistantMessageView(e, tools: agent.tools, cwd: agent.cwd, live: agent),
            ],
          ),
          NoticeEntry() => NoticeView(e),
        };
        final gap = i == 0 ? 0.0 : (e is UserEntry ? 28.0 : 14.0);
        return Padding(
          padding: EdgeInsets.only(top: gap),
          child: child,
        );
      },
    );
  }
}

/// "pi" with the logo, above the first reply of a turn.
class _Byline extends StatelessWidget {
  const _Byline();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(
        children: [
          const LogoMark(size: 20),
          const SizedBox(width: 6),
          Text(
            'pi',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text),
          ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.agent});
  final AgentController agent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final name = agent.sessionName?.trim();
    final firstUser = agent.entries.whereType<UserEntry>().firstOrNull?.text.split('\n').first;
    final title = (name != null && name.isNotEmpty) ? name : (firstUser ?? tr('New chat'));
    // Sessions inside a project folder show which one.
    final project = sessionFolder(agent.cwd, agent.info['workspace'] as String? ?? '');
    final sub = TextStyle(fontSize: 11.5, color: p.muted, fontWeight: FontWeight.w500);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (agent.busy) ...[
              StatusDot(color: p.warning, size: 6, pulse: true),
              const SizedBox(width: 5),
              Text(tr('Working'), style: sub.copyWith(color: p.warning)),
              const SizedBox(width: 6),
            ],
            if (project != null) ...[
              Icon(LucideIcons.folderGit2, size: 12, color: p.accent),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  project,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sub.copyWith(fontFamily: mono, fontWeight: FontWeight.w400),
                ),
              ),
            ] else if (agent.model != null)
              Flexible(
                child: Text(
                  agent.model!.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sub.copyWith(color: p.faint),
                ),
              )
            else if (!agent.busy)
              Text(tr('Quick chat'), style: sub.copyWith(color: p.faint)),
          ],
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.agent, required this.onConnect, required this.onPrompt, required this.onClone});
  final AgentController agent;
  final VoidCallback onConnect;
  final void Function(String prompt) onPrompt;
  final VoidCallback onClone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final ready = agent.hasModel;
    final suggestions = [
      (
        LucideIcons.layoutTemplate,
        const Color(0xFFF97316),
        'Build a web app',
        'A polished single-page app I can preview',
        'Build me a polished, mobile-first web app: ',
      ),
      (SimpleIcons.github, p.text, 'Clone a repo', 'Pick one of your GitHub repositories', null),
      (
        SimpleIcons.python,
        const Color(0xFF3B82F6),
        'Set up Python',
        'Install Python and packages in Linux',
        'Set up a Python environment in the Linux container with requests and rich, then write a hello script.',
      ),
      (
        LucideIcons.folderSearch,
        const Color(0xFF14B8A6),
        'Explore workspace',
        'Summarize what is on this device',
        'Look around the workspace and give me a short tour of what is there.',
      ),
    ];
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.page, Space.xl, Space.page, Space.lg),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight - 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  padding: const EdgeInsets.all(Space.md),
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(Radii.lg),
                    border: Border.all(color: p.border),
                  ),
                  child: const LogoMark(size: 48),
                ),
              ),
              const SizedBox(height: Space.xl),
              Text(
                ready ? tr('What should we build?') : tr('Connect a model to begin'),
                style: text.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.sm),
              Text(
                ready
                    ? tr('pi codes, runs commands, installs packages and deploys, right here on your phone.')
                    : tr('The agent runs on your phone. Sign in to a provider or add an API key to choose its model.'),
                style: text.bodyMedium?.copyWith(color: p.muted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Space.xxl),
              if (!ready)
                Center(
                  child: SizedBox(
                    width: 260,
                    child: PrimaryButton(
                      label: tr('Connect a model'),
                      icon: LucideIcons.sparkles,
                      onPressed: onConnect,
                    ),
                  ),
                )
              else ...[
                SectionLabel(tr('Try one of these'), padding: const EdgeInsets.fromLTRB(4, 0, 4, Space.sm)),
                SettingsGroup(
                  children: [
                    for (final (icon, color, title, blurb, prompt) in suggestions)
                      SettingsRow(
                        leading: IconTile(icon: icon, color: color, size: 34),
                        title: tr(title),
                        subtitle: tr(blurb),
                        trailing: Icon(
                          prompt == null ? LucideIcons.arrowUpRight : LucideIcons.cornerDownLeft,
                          size: 16,
                          color: p.faint,
                        ),
                        onTap: prompt == null ? onClone : () => onPrompt(prompt),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focus,
    required this.agent,
    required this.onSend,
    required this.onQueue,
    required this.onAttach,
    required this.onVoice,
    required this.attachments,
    required this.onRemoveAttachment,
    required this.onPickModel,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final AgentController agent;
  final VoidCallback onSend;
  final VoidCallback onQueue;
  final VoidCallback onAttach;
  final VoidCallback onVoice;
  final List<Attachment> attachments;
  final void Function(Attachment) onRemoveAttachment;
  final VoidCallback onPickModel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hasText = controller.text.trim().isNotEmpty || attachments.isNotEmpty;
    final busy = agent.busy;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.md),
        child: ListenableBuilder(
          listenable: focus,
          builder: (context, child) => AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(
                color: focus.hasFocus ? p.accent.withValues(alpha: 0.7) : p.border,
                width: focus.hasFocus ? 1.4 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: (focus.hasFocus ? p.accent : Colors.black).withValues(alpha: focus.hasFocus ? 0.14 : 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                  spreadRadius: -6,
                ),
              ],
            ),
            child: child,
          ),
          child: Column(
            children: [
              if (attachments.isNotEmpty) AttachmentStrip(items: attachments, onRemove: onRemoveAttachment),
              TextField(
                controller: controller,
                focusNode: focus,
                minLines: 1,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                style: Theme.of(context).textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: busy ? tr('Queue a follow-up…') : tr('Ask pi to build, fix or deploy…'),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.fromLTRB(Space.lg, 14, Space.lg, 6),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.sm, 0, Space.sm, Space.sm),
                child: Row(
                  children: [
                    // The options scroll sideways on narrow phones instead of squeezing the model name;
                    // the right edge fades so it reads as scrollable.
                    Expanded(
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (r) => const LinearGradient(
                          colors: [Colors.white, Colors.white, Colors.transparent],
                          stops: [0, 0.88, 1],
                        ).createShader(r),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.only(right: Space.lg),
                          child: Row(
                            children: [
                              AppIconButton(icon: LucideIcons.plus, label: tr('Attach'), size: 34, onTap: onAttach),
                              const SizedBox(width: 6),
                              AppChip(
                                leading: agent.model == null ? null : BrandTile(id: agent.model!.provider, size: 22),
                                label: agent.model?.name ?? tr('Choose model'),
                                trailingIcon: LucideIcons.chevronsUpDown,
                                maxWidth: 110,
                                onTap: onPickModel,
                              ),
                              if (agent.thinkingLevels.length > 1) ...[
                                const SizedBox(width: 6),
                                _ThinkingChip(agent: agent),
                              ],
                              const SizedBox(width: 6),
                              AppChip(
                                icon: LucideIcons.listChecks,
                                label: tr('Plan'),
                                selected: agent.planMode,
                                onTap: () => agent.setPlanMode(!agent.planMode),
                              ),
                              const SizedBox(width: 6),
                              _ApprovalChip(agent: agent),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    if (busy && !hasText)
                      AppIconButton(
                        icon: LucideIcons.square,
                        label: tr('Stop'),
                        size: 38,
                        filled: true,
                        onTap: agent.abort,
                      )
                    else if (!hasText)
                      AppIconButton(icon: LucideIcons.mic, label: tr('Voice'), size: 38, onTap: onVoice)
                    else
                      AppIconButton(
                        icon: LucideIcons.arrowUp,
                        label: tr('Send'),
                        size: 38,
                        filled: true,
                        onTap: onSend,
                        // Hold to hand the message to a background agent instead.
                        onLongPress: onQueue,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThinkingChip extends StatelessWidget {
  const _ThinkingChip({required this.agent});
  final AgentController agent;

  @override
  Widget build(BuildContext context) {
    final on = agent.thinkingLevel != 'off';
    return PopupMenuButton<String>(
      tooltip: tr('Thinking level'),
      initialValue: agent.thinkingLevel,
      onSelected: agent.setThinking,
      position: PopupMenuPosition.over,
      itemBuilder: (_) => [
        for (final level in agent.thinkingLevels)
          PopupMenuItem(value: level, height: 40, child: Text(_levelLabel(level))),
      ],
      child: IgnorePointer(
        child: AppChip(icon: LucideIcons.brain, label: _levelLabel(agent.thinkingLevel), selected: on, onTap: () {}),
      ),
    );
  }

  static String _levelLabel(String level) => switch (level) {
    'off' => tr('Off'),
    'minimal' => tr('Minimal'),
    'low' => tr('Low'),
    'medium' => tr('Medium'),
    'high' => tr('High'),
    'xhigh' => tr('Max'),
    _ => level,
  };
}

/// The approval mode, visible and switchable right in the composer.
class _ApprovalChip extends StatelessWidget {
  const _ApprovalChip({required this.agent});
  final AgentController agent;

  static const _modes = ['ask_all', 'ask_risky', 'auto'];

  static String _label(String mode) => switch (mode) {
    'ask_all' => tr('Ask all'),
    'auto' => tr('Bypass all'),
    _ => tr('Risky only'),
  };

  static IconData _icon(String mode) => switch (mode) {
    'ask_all' => LucideIcons.shieldCheck,
    'auto' => LucideIcons.shieldOff,
    _ => LucideIcons.shield,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final it = agent.integrations;
    return ListenableBuilder(
      listenable: it,
      builder: (context, _) {
        final mode = it.settings?.approvalMode ?? agent.approvalMode;
        return PopupMenuButton<String>(
          tooltip: tr('Approvals'),
          initialValue: mode,
          position: PopupMenuPosition.over,
          onSelected: (v) async {
            if (v == mode) return;
            if (v == 'auto' && !await confirmBypass(context)) return;
            await it.updateSettings({'approvalMode': v});
            agent.approvalMode = v;
          },
          itemBuilder: (_) => [
            for (final m in _modes)
              PopupMenuItem(
                value: m,
                height: 44,
                child: Row(
                  children: [
                    Icon(_icon(m), size: 16, color: m == 'auto' ? p.warning : p.muted),
                    const SizedBox(width: Space.sm),
                    Text(_label(m)),
                  ],
                ),
              ),
          ],
          child: IgnorePointer(
            child: AppChip(
              icon: _icon(mode),
              label: _label(mode),
              selected: mode == 'auto',
              color: p.warning,
              onTap: () {},
            ),
          ),
        );
      },
    );
  }
}
