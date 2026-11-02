import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../agent/agent_controller.dart';
import '../agent/drafts.dart';
import '../agent/models.dart';
import '../agent/features.dart';
import 'i18n.dart';
import 'chat_extras.dart';
import 'errors.dart';
import 'rewind_confirm.dart';
import 'message_menu.dart';
import 'message_views.dart';

import 'package:simple_icons/simple_icons.dart';

import 'repos_screen.dart';
import 'kit.dart';
import 'live_clock.dart';
import 'model_sheet.dart';
import 'review_screen.dart';
import 'tasks_screen.dart';
import 'server_screen.dart';
import 'settings_screen.dart';
import 'folder_picker.dart';
import 'subagent_card.dart';
import 'summarized_turns_screen.dart';
import 'theme.dart';
import 'usage_screen.dart';
import 'transfer_dialog.dart';
import 'todo_views.dart';

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

  /// Uncommitted files after the agent's last turn here (the review banner), and whether it was closed.
  int _changedFiles = 0;
  bool _reviewClosed = false;
  bool _wasBusy = false;

  /// The @ list: files matching what is typed after the @ at the cursor, and the query they answer.
  List<String> mentionFiles = const [];
  String? mentionQuery;
  Timer? _mentionTimer;
  int _mentionAsk = 0;

  /// The chat whose draft the input holds.
  String? draftChat;

  /// The clipboard holds a picture: the field's menu offers "Paste image". Checked when the field gains focus and when
  /// the app comes back (the user copied it in another app).
  bool _clipboardImage = false;
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(onResume: _checkClipboard);

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
    _lifecycle;
    focus.addListener(() {
      if (focus.hasFocus) _checkClipboard();
    });
    agent.addListener(_onAgentChanged);
    draftChat = agent.sessionId;
    final prompt = widget.initialPrompt ?? Drafts.instance.get(draftChat);
    if (prompt.isNotEmpty) {
      input.text = prompt;
      input.selection = TextSelection.collapsed(offset: prompt.length);
      WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
    }
    scroll.addListener(() {
      if (!scroll.hasClients || dragging) return;
      if (_atBottom != followBottom) setState(() => followBottom = _atBottom);
    });
    input.addListener(() {
      Drafts.instance.set(draftChat, input.text);
      if (_slashQuery != null && slash == null) _loadSlash();
      _findMention();
      setState(() {});
    });
    if (widget.initialAttachments.isNotEmpty) {
      attachments.addAll(widget.initialAttachments);
      _saveFiles();
    } else {
      attachments.addAll(_draftFiles());
    }
    if (widget.listenOnOpen) WidgetsBinding.instance.addPostFrameCallback((_) => _voice());
    // History may have loaded before this screen existed.
    lastCount = agent.entries.length;
    _jumpToBottom();
  }

  @override
  void dispose() {
    agent.removeListener(_onAgentChanged);
    _mentionTimer?.cancel();
    _lifecycle.dispose();
    Drafts.instance.flush();
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
    // Another chat opened under this screen (new chat, fork, the open one deleted): bring its draft along.
    if (agent.sessionId != draftChat) {
      draftChat = agent.sessionId;
      final draft = Drafts.instance.get(draftChat);
      input.value = TextEditingValue(
        text: draft,
        selection: TextSelection.collapsed(offset: draft.length),
      );
      setState(() {
        attachments
          ..clear()
          ..addAll(_draftFiles());
      });
    }
    // A turn just ended: did it leave changes to commit?
    if (_wasBusy && !agent.busy) {
      _reviewClosed = false;
      unawaited(_checkChanges());
    }
    _wasBusy = agent.busy;
    final grew = agent.entries.length != lastCount;
    lastCount = agent.entries.length;
    if (followBottom || grew && agent.entries.lastOrNull is UserEntry) _jumpToBottom();
  }

  /// Takes a waiting message back: it no longer goes, and its text returns to an empty composer so it isn't lost.
  void _dropOffline(String id) {
    final p = agent.dropOffline(id);
    if (p != null && input.text.trim().isEmpty) _prefill(p.text);
  }

  /// How many files the project has to commit; none when it isn't a repository or the host can't say.
  Future<void> _checkChanges() async {
    var n = 0;
    try {
      final st = await agent.features.gitStatus();
      n = st.isRepo ? st.files.length : 0;
    } catch (_) {}
    if (mounted && n != _changedFiles) setState(() => _changedFiles = n);
  }

  Future<void> _openReview() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReviewScreen(agent: agent)));
    if (mounted) await _checkChanges();
  }

  /// The open chat's saved attachments, still on disk.
  List<Attachment> _draftFiles() => [
    for (final f in Drafts.instance.files(draftChat)) Attachment(f.path, f.name, mime: f.mime),
  ];

  /// Keeps the attachments with the draft (copied into app storage, so they survive the picker's cache).
  void _saveFiles() {
    Drafts.instance.setFiles(draftChat, [for (final a in attachments) (path: a.path, name: a.name, mime: a.mime)]);
  }

  void _jumpToBottom({bool animate = false, int passes = 4}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients || dragging) return;
      final target = scroll.position.maxScrollExtent;
      if (animate) {
        if (Motion.reduced(context)) {
          scroll.jumpTo(target);
        } else {
          scroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
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

  ({int start, String query})? get _mention =>
      input.selection.isCollapsed ? mentionAt(input.text, input.selection.baseOffset) : null;

  /// Asks the host for files matching the @ being typed, a moment after the typing stops; an answer for an older query
  /// is dropped. No @ at the cursor (or no project): no list.
  void _findMention() {
    final m = _mention;
    if (m == null) {
      _mentionTimer?.cancel();
      mentionQuery = null;
      mentionFiles = const [];
      return;
    }
    if (m.query == mentionQuery) return;
    mentionQuery = m.query;
    _mentionTimer?.cancel();
    _mentionTimer = Timer(const Duration(milliseconds: 120), () async {
      final ask = ++_mentionAsk;
      List<String> files;
      try {
        files = await agent.features.findFiles(m.query);
      } catch (_) {
        files = const [];
      }
      if (mounted && ask == _mentionAsk && mentionQuery == m.query) setState(() => mentionFiles = files);
    });
  }

  void _pickMention(String path) {
    final m = _mention;
    if (m == null) return;
    final r = insertMention(input.text, m.start, input.selection.baseOffset, path);
    input.value = TextEditingValue(text: r.text, selection: TextSelection.collapsed(offset: r.cursor));
    focus.requestFocus();
  }

  Future<void> _loadSlash() async {
    slash = const [];
    try {
      final list = await agent.features.slashCommands();
      if (mounted) setState(() => slash = list);
    } catch (_) {}
  }

  /// A message is on its way to the host: Send shows a spinner and a second tap does nothing, so the same text is
  /// never sent twice.
  bool _sending = false;

  Future<void> _send() async {
    if (_sending) return;
    final text = input.text;
    if (text.trim().isEmpty && attachments.isEmpty) return;
    if (!agent.hasModel) {
      await _connectProvider();
      return;
    }
    setState(() => _sending = true);
    try {
      await _sendNow(text);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendNow(String text) async {
    final files = List<Attachment>.of(attachments);
    // Clear only on success: a refused message (budget, host error) never
    // reaches the transcript, so clearing first would lose it.
    final bool ok;
    if (files.isEmpty) {
      ok = await agent.send(text);
    } else {
      // Files go to the server first when the agent is there; that can take a while, and it can fail (the message
      // and its files then stay where they are, to try again).
      final prompt = await runTransfer(
        context,
        connection: widget.agent.client.connection,
        title: tr('Sending files'),
        show: !agent.fs.isLocal,
        task: (h) => preparePrompt(
          text,
          files,
          agent.cwd,
          agent.fs,
          onProgress: h.onProgress,
          cancel: h.cancel,
          onFile: (l) => h.label = l,
        ),
      );
      if (prompt == null) return;
      // The controller queues the files before the call (the host may echo the
      // message before it returns) and drops them on refusal or cancel.
      ok = await agent.sendWith(prompt.text, images: prompt.images, attachments: prompt.files);
    }
    if (!mounted || !ok) return;
    input.clear();
    setState(() => attachments.clear());
    _saveFiles();
    followBottom = true;
  }

  /// Cancels a waiting follow-up; "Edit" puts its text back in the composer.
  Future<void> _cancelQueued(QueuedPrompt q) async {
    HapticFeedback.selectionClick();
    final text = await agent.cancelQueued(q.id);
    if (text == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr('Message cancelled')),
        action: SnackBarAction(
          label: tr('Edit'),
          onPressed: () {
            if (input.text.trim().isEmpty) {
              input.text = text;
              input.selection = TextSelection.collapsed(offset: text.length);
            } else {
              _insert('\n$text');
            }
            focus.requestFocus();
          },
        ),
      ),
    );
  }

  /// Long-press on send: hand the task to a background agent instead.
  Future<void> _queue() async {
    final text = input.text.trim();
    if (text.isEmpty) return;
    try {
      await agent.features.enqueue(text);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      return;
    }
    input.clear();
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

  /// A long paste lands as a "Pasted content" attachment; tapping it offers to put it in the field instead.
  void _pasted(String text) {
    final Attachment a;
    try {
      a = pastedAttachment(text);
    } catch (_) {
      // No temp storage: keep the paste as text rather than losing it.
      _insert(text);
      return;
    }
    setState(() => attachments.add(a));
    _saveFiles();
  }

  Future<void> _checkClipboard() async {
    final has = await agent.client.clipboardHasImage();
    if (mounted && has != _clipboardImage) setState(() => _clipboardImage = has);
  }

  /// "Paste image" from the field's menu: the clipboard's picture becomes an attachment.
  Future<void> _pasteImage() async {
    final image = await agent.client.clipboardImage();
    if (!mounted) return;
    if (image == null) {
      setState(() => _clipboardImage = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('The clipboard has no picture to paste'))));
      return;
    }
    setState(() => attachments.add(Attachment(image['path']!, image['name']!, mime: image['mime'])));
    _saveFiles();
  }

  /// A picture the keyboard pasted (Gboard's clipboard, a screenshot, a sticker): attached, never typed as text.
  void _insertedContent(KeyboardInsertedContent content) {
    final bytes = content.data;
    if (bytes == null || bytes.isEmpty || !content.mimeType.startsWith('image/')) return;
    final Attachment a;
    try {
      a = pastedImageAttachment(bytes, content.mimeType);
    } catch (_) {
      return;
    }
    setState(() => attachments.add(a));
    _saveFiles();
  }

  Future<void> _openPasted(Attachment a) async {
    final String text;
    try {
      text = File(a.path).readAsStringSync();
    } catch (_) {
      return;
    }
    final asText = await showPastedSheet(context, text);
    if (asText != true || !mounted || !attachments.remove(a)) return;
    setState(() {});
    _saveFiles();
    _insert(text);
  }

  /// Puts [text] at the cursor (replacing a selection), as a paste would.
  void _insert(String text) {
    final v = input.value;
    final sel = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: v.text.length);
    input.value = TextEditingValue(
      text: v.text.replaceRange(sel.start, sel.end, text),
      selection: TextSelection.collapsed(offset: sel.start + text.length),
    );
  }

  Future<void> _attach() async {
    final picked = await pickAttachments(context, client: agent.client);
    if (picked.isNotEmpty) {
      setState(() => attachments.addAll(picked));
      _saveFiles();
    }
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('Voice input')}: ${friendlyError(e)}')));
    }
  }

  void _prefill(String text) {
    input.text = text;
    input.selection = TextSelection.collapsed(offset: text.length);
    focus.requestFocus();
  }

  /// Long-press on one of your messages: edit & resend, fork, copy.
  Future<void> _userMenu(BuildContext bubbleContext, UserEntry entry, int userIndex) async {
    final action = await showMessageMenu(
      bubbleContext,
      bubble: UserBubble(entry.text),
      actions: [
        MessageAction('copy', tr('Copy'), LucideIcons.copy),
        MessageAction('select', tr('Select text'), LucideIcons.textCursorInput),
        MessageAction('edit', tr('Edit & resend'), LucideIcons.pencil),
        MessageAction('fork', tr('Fork from here'), LucideIcons.gitFork),
      ],
    );
    if (action == null || !mounted) return;
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: entry.text));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Copied'))));
      return;
    }
    if (action == 'select') {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: SingleChildScrollView(child: SelectableText(entry.text, style: Theme.of(context).textTheme.bodyLarge)),
        ),
      );
      return;
    }
    if (agent.busy) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Wait for the agent to finish first'))));
      return;
    }
    if (_rewinding != null) return;
    var how = action;
    if (action == 'edit') {
      // Going back takes the rest of the chat out, and the files stay as they are: asked first, with Fork on offer.
      final choice = await confirmRewind(context, messages: messagesAfter(agent.entries, entry));
      if (choice == null || !mounted) return;
      how = choice == RewindChoice.fork ? 'fork' : 'edit';
      if (agent.busy) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Wait for the agent to finish first'))));
        return;
      }
    }
    setState(() => _rewinding = (entry: entry, label: tr(how == 'edit' ? 'Rewinding…' : 'Forking…')));
    try {
      final points = await agent.features.forkPoints();
      if (userIndex >= points.length) throw tr('This message cannot be edited');
      final entryId = points[userIndex].entryId;
      final text = how == 'edit' ? await agent.editMessage(entryId) : await agent.forkAt(entryId);
      _prefill(text.isEmpty ? entry.text : text);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _rewinding = null);
    }
  }

  /// The message an edit or fork is working on, from the tap until the chat has reloaded.
  ({UserEntry entry, String label})? _rewinding;

  Future<void> _connectProvider() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(agent: agent)));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListenableBuilder(
      listenable: Listenable.merge([agent, agent.remote]),
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
            // Phone or server, and whether the server can be reached; only once a server is set up.
            ConnectionChip(agent: agent),
            // Everything that acts on the chat's folder lives behind this one button (the project tools sheet);
            // the bar keeps the title's room however narrow the phone.
            Tooltip(
              message: tr('Project tools'),
              child: AppIconButton(
                icon: LucideIcons.layoutGrid,
                label: tr('Project tools'),
                size: 38,
                onTap: () => showProjectTools(context, agent, onPrompt: _prefill),
              ),
            ),
            const SizedBox(width: 12),
          ],
          // A thin running bar while the agent works; a hairline otherwise.
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: agent.busy ? const BusyBar(busy: true) : Divider(height: 2, thickness: 1, color: p.border),
          ),
        ),
        // A readable column on a wide screen; the bar above stays full width.
        body: ContentWidth(
          max: 760,
          child: Column(
          children: [
            ConnectionBanner(agent: agent),
            ServerUpdateBanner(agent: agent),
            Expanded(
              child: Stack(
                children: [
                  // A first message still waiting for the server is the chat's start: show it, not the welcome.
                  agent.entries.isEmpty && agent.offlineForCurrent.isEmpty
                      ? _EmptyState(
                          agent: agent,
                          onConnect: _connectProvider,
                          onPrompt: (prompt) {
                            input.text = prompt;
                            input.selection = TextSelection.collapsed(offset: prompt.length);
                            focus.requestFocus();
                          },
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
                      right: 16,
                      bottom: 12,
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
            ApprovalCards(features: agent.features, agent: agent),
            BypassBar(agent: agent),
            if (_changedFiles > 0 && !_reviewClosed && !agent.busy)
              ReviewBanner(
                files: _changedFiles,
                onReview: _openReview,
                onClose: () => setState(() => _reviewClosed = true),
              ),
            PlanBar(agent: agent),
            // The agent's todo list for the task at hand (todo_write).
            if (agent.todo != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: TodoProgressBar(agent: agent),
              ),
            if (_slashQuery != null && slash != null)
              SlashMenu(commands: slash!, query: _slashQuery!, onPick: (c) => _prefill('/${c.name} '))
            else if (mentionQuery != null && _mention != null && mentionFiles.isNotEmpty)
              MentionMenu(files: mentionFiles, onPick: _pickMention),
            if (agent.billingNotice != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  agent.billingNotice!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.muted),
                ),
              ),
            CrossChatBanner(agent: agent),
            _Composer(
              controller: input,
              focus: focus,
              agent: agent,
              onSend: _send,
              sending: _sending,
              onQueue: _queue,
              onAttach: _attach,
              onPaste: _pasted,
              canPasteImage: _clipboardImage,
              onPasteImage: _pasteImage,
              onInsertedContent: _insertedContent,
              onVoice: _voice,
              attachments: attachments,
              onOpenAttachment: (a) => a.isPasted ? _openPasted(a) : null,
              onRemoveAttachment: (a) {
                setState(() => attachments.remove(a));
                _saveFiles();
              },
              onPickModel: () => showModelSheet(context, agent),
            ),
          ],
        ),
        ),
      ),
    );
  }

  /// The line under the transcript while the agent works, or null when something on screen
  /// already shows it: the first-token dots, text typing in, thinking streaming, an approval card.
  String? _activity() {
    if (!agent.busy || agent.features.approvals.isNotEmpty) return null;
    final last = agent.entries.lastOrNull;
    if (last is AssistantEntry) {
      final blocks = last.orderedBlocks;
      if (last.streaming && (blocks.isEmpty || blocks.last.kind != BlockKind.toolCall)) return null;
      for (final b in blocks.reversed) {
        if (b.kind != BlockKind.toolCall) continue;
        final run = agent.tools[b.toolCallId];
        // Arguments still streaming: the tool row says "preparing…" itself.
        if (run == null && last.streaming) return null;
        // A running subagent shows its own progress on its card.
        if (run?.status == ToolStatus.running && b.toolName == 'subagent') return null;
        if (run?.status == ToolStatus.running) {
          return tr('Running {tool}…').replaceAll('{tool}', b.toolName ?? 'tool');
        }
        break;
      }
    }
    // Between steps: a tool finished, the model hasn't answered yet.
    return tr('Thinking…');
  }

  Widget _transcript() {
    final entries = agent.entries;
    final placed = placeSubagents(agent);
    final footers = turnFooters(entries, busy: agent.busy);
    final subs = placed.trailing;
    final retry = agent.endsInError;
    final activity = _activity();
    // While the agent works: what it does, and how long the turn has taken (item under the transcript).
    final status = agent.busy && (activity != null || agent.turnStartedAt != null);
    final queued = agent.queuedPrompts;
    final offline = agent.offlineForCurrent;
    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: entries.length + subs.length + (status ? 1 : 0) + queued.length + offline.length + (retry ? 1 : 0),
      itemBuilder: (context, i) {
        if (i < entries.length) {
          final e = entries[i];
          // The agent's replies get a small byline at the start of each turn.
          final turnStart = i == 0 || entries[i - 1] is UserEntry;
          final child = switch (e) {
            UserEntry() => UserMessageView(
              e,
              onLongPress: _rewinding != null
                  ? null
                  : (bubble) => _userMenu(bubble, e, entries.take(i).whereType<UserEntry>().length),
              fs: agent.fs,
              working: identical(_rewinding?.entry, e) ? _rewinding!.label : null,
            ),
            AssistantEntry() => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (turnStart) const _Byline(),
                AssistantMessageView(
                  e,
                  tools: agent.tools,
                  cwd: agent.cwd,
                  agent: agent,
                  live: agent,
                  modelLabel: agent.modelLabel,
                  subagentCard: placed.cardFor,
                  subagentCost: (id) => switch (agent.subagentStore.all.where((s) => s.toolCallId == id).firstOrNull) {
                    final s? => (cost: s.cost),
                    null => null,
                  },
                  footer: footers[i],
                ),
              ],
            ),
            NoticeEntry() => NoticeView(
              e,
              onRaiseBudget: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => UsageScreen(agent: agent))),
            ),
            JobEntry() => JobNoticeView(e),
            CompactionEntry() => CompactionView(
              e,
              onShowEarlier: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => SummarizedTurnsScreen(agent: agent))),
            ),
          };
          final gap = i == 0 ? 0.0 : (e is UserEntry ? 28.0 : 14.0);
          return Padding(
            padding: EdgeInsets.only(top: gap),
            child: child,
          );
        }
        final si = i - entries.length;
        if (si < subs.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 14),
            child: SubagentCard(key: ValueKey(subs[si].id), state: subs[si], agent: agent),
          );
        }
        if (status && si == subs.length) {
          final tokens = turnTokensSoFar(entries);
          return Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (activity != null) ...[AgentActivity(label: activity), const SizedBox(height: 8)],
                // The turn's live clock, with the tokens it has used so far.
                LiveClock(
                  label: tr('Working'),
                  startedAt: agent.turnStartedAt,
                  detail: tokens > 0 ? tr('{n} tokens').replaceAll('{n}', localNumber(formatTokens(tokens))) : null,
                ),
              ],
            ),
          );
        }
        // Follow-ups waiting for the current turn to end, oldest first.
        final qi = si - subs.length - (status ? 1 : 0);
        if (qi < queued.length) {
          return Padding(
            padding: EdgeInsets.only(top: qi == 0 ? 28 : 10),
            child: QueuedMessageView(
              key: ValueKey('queued-${queued[qi].id}'),
              prompt: queued[qi],
              onCancel: () => _cancelQueued(queued[qi]),
            ),
          );
        }
        // Typed while the server was out of reach: they go once it is back.
        final oi = qi - queued.length;
        if (oi < offline.length) {
          final o = offline[oi];
          return Padding(
            padding: EdgeInsets.only(top: oi == 0 && queued.isEmpty ? 28 : 10),
            child: QueuedMessageView(
              key: ValueKey('offline-${o.id}'),
              prompt: QueuedPrompt({'id': o.id, 'text': o.text, 'images': o.images.length}),
              status: tr('Waiting for the connection'),
              statusIcon: LucideIcons.wifiOff,
              error: o.error == null ? null : tr(o.error!),
              onRetry: o.error == null ? null : () => agent.retryOffline(o.id),
              onCancel: () => _dropOffline(o.id),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: _RetryBar(onRetry: agent.retry, onPickModel: () => showModelSheet(context, agent)),
        );
      },
    );
  }
}

/// Shown under a failed turn: try again, or switch model first.
class _RetryBar extends StatelessWidget {
  const _RetryBar({required this.onRetry, required this.onPickModel});
  final VoidCallback onRetry;
  final VoidCallback onPickModel;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.tonalIcon(
          onPressed: onRetry,
          icon: const Icon(LucideIcons.rotateCcw, size: 16),
          label: Text(tr('Try again')),
        ),
        OutlinedButton.icon(
          onPressed: onPickModel,
          icon: const Icon(LucideIcons.sparkles, size: 16),
          label: Text(tr('Switch model')),
        ),
      ],
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
                child: Text(agent.model!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: sub.copyWith(color: p.faint)),
              )
            else if (!agent.busy)
              Text(tr('Quick chat'), style: sub.copyWith(color: p.faint)),
          ],
        ),
      ],
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const LogoMark(size: 20),
          const SizedBox(width: 6),
          Text('pi', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text)),
        ],
      ),
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
      // Same names, blurbs and colours as the quick starts on Home.
      (
        LucideIcons.layoutTemplate,
        const Color(0xFFFF7A1A),
        'Build a web app',
        'A site or app, ready to deploy',
        'Build me a polished, mobile-first web app: ',
      ),
      // p.text, not Home's slate: this soft tile tints the icon with its own colour.
      (SimpleIcons.github, p.text, 'Clone a GitHub repo', 'Pick up an existing project', null),
      (
        SimpleIcons.python,
        const Color(0xFF3B82F6),
        'Python in Linux',
        'Scripts in a real Linux container',
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
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
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
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(Radii.lg),
                    border: Border.all(color: p.border),
                  ),
                  child: const LogoMark(size: 48),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                tr(ready ? 'What should we build?' : 'Connect a model to begin'),
                style: text.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                ready
                    ? tr('The agent codes, runs commands, installs packages and deploys, right here on your phone.')
                    : tr('The agent runs on your phone. Sign in to a provider or add an API key to choose its model.'),
                style: text.bodyMedium?.copyWith(color: p.muted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              if (!ready)
                Center(
                  child: SizedBox(
                    width: 260,
                    child: PrimaryButton(label: tr('Connect a model'), icon: LucideIcons.sparkles, onPressed: onConnect),
                  ),
                )
              else ...[
                SectionLabel(tr('Try one of these'), padding: const EdgeInsets.fromLTRB(4, 0, 4, 8)),
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
                        onTap: prompt == null ? onClone : () => onPrompt(tr(prompt)),
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

/// Runs what a control does and says so when it fails (the link is down, the host refused). A failure nobody caught
/// used to end as an unhandled async error and a tap that looked like it did nothing.
Future<void> tellFailure(BuildContext context, Future<void> Function() call, {String? done}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await call();
    if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focus,
    required this.agent,
    required this.onSend,
    this.sending = false,
    required this.onQueue,
    required this.onAttach,
    required this.onPaste,
    this.canPasteImage = false,
    this.onPasteImage,
    this.onInsertedContent,
    required this.onVoice,
    required this.attachments,
    required this.onOpenAttachment,
    required this.onRemoveAttachment,
    required this.onPickModel,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final AgentController agent;
  final VoidCallback onSend;

  /// The last message is still on its way: Send spins and is off.
  final bool sending;
  final VoidCallback onQueue;
  final VoidCallback onAttach;

  /// Called instead of inserting a long paste (see LongPasteFormatter).
  final void Function(String text) onPaste;

  /// The clipboard holds a picture: the field's menu offers [onPasteImage].
  final bool canPasteImage;
  final VoidCallback? onPasteImage;

  /// A picture the keyboard pasted.
  final void Function(KeyboardInsertedContent content)? onInsertedContent;
  final VoidCallback onVoice;
  final List<Attachment> attachments;
  final void Function(Attachment) onOpenAttachment;
  final void Function(Attachment) onRemoveAttachment;
  final VoidCallback onPickModel;

  /// Stop. With a server agent and the link down it cannot reach the host: it says so instead of looking like it worked.
  Future<void> _stop(BuildContext context) {
    if (!agent.client.connection.value.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr("Offline: can't stop it from here. It stops by itself when it finishes; reconnect to stop it now."))),
      );
      return Future.value();
    }
    return tellFailure(context, agent.abort, done: tr('Stopping…'));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hasText = controller.text.trim().isNotEmpty || attachments.isNotEmpty;
    final busy = agent.busy;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: ListenableBuilder(
          listenable: focus,
          builder: (context, child) => AnimatedContainer(
            duration: Motion.of(context, const Duration(milliseconds: 180)),
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
              if (attachments.isNotEmpty)
                AttachmentStrip(items: attachments, onOpen: onOpenAttachment, onRemove: onRemoveAttachment),
              TextField(
                controller: controller,
                focusNode: focus,
                inputFormatters: [LongPasteFormatter(onPaste)],
                contentInsertionConfiguration: onInsertedContent == null
                    ? null
                    : ContentInsertionConfiguration(
                        allowedMimeTypes: pasteImageTypes,
                        onContentInserted: onInsertedContent!,
                      ),
                contextMenuBuilder: (context, editable) => AdaptiveTextSelectionToolbar.buttonItems(
                  anchors: editable.contextMenuAnchors,
                  buttonItems: [
                    ...editable.contextMenuButtonItems,
                    if (canPasteImage && onPasteImage != null)
                      ContextMenuButtonItem(
                        label: tr('Paste image'),
                        onPressed: () {
                          editable.hideToolbar();
                          onPasteImage!();
                        },
                      ),
                  ],
                ),
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
                  contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
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
                          padding: const EdgeInsets.only(right: 16),
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
                              Tooltip(
                                message: tr(agent.planMode ? 'Plan mode on' : 'Plan mode'),
                                child: AppChip(
                                  icon: LucideIcons.listChecks,
                                  label: tr('Plan'),
                                  semanticsLabel: tr(agent.planMode ? 'Plan mode on' : 'Plan mode'),
                                  selected: agent.planMode,
                                  onTap: () => tellFailure(context, () => agent.setPlanMode(!agent.planMode)),
                                ),
                              ),
                              const SizedBox(width: 6),
                              _ApprovalChip(agent: agent),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // While the agent works, Stop stays reachable; typed text adds Send (queues a follow-up).
                    if (busy)
                      AppIconButton(
                        icon: LucideIcons.square,
                        label: tr('Stop'),
                        size: 38,
                        filled: !hasText,
                        onTap: () => _stop(context),
                      ),
                    if (hasText || sending) ...[
                      if (busy) const SizedBox(width: 6),
                      if (sending)
                        // A tap here is swallowed: the message is already on its way. The button's own label says so.
                        Semantics(
                          button: true,
                          label: tr('Sending…'),
                          child: TapTarget(
                            onTap: () {},
                            child: const SizedBox.square(dimension: 38, child: Center(child: BusySpinner(size: 18, semanticsLabel: ''))),
                          ),
                        )
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
                    ] else if (!busy)
                      AppIconButton(icon: LucideIcons.mic, label: tr('Voice'), size: 38, onTap: onVoice),
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
      onSelected: (level) => tellFailure(context, () => agent.setThinking(level)),
      position: PopupMenuPosition.over,
      elevation: 0,
      itemBuilder: (context) => [
        // "Medium" alone doesn't say what it sets.
        PopupMenuItem(
          enabled: false,
          height: 32,
          child: Text(tr('Thinking level'), style: Theme.of(context).textTheme.labelSmall),
        ),
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
    final mode = agent.approvalMode;
    return PopupMenuButton<String>(
      tooltip: tr('Approvals'),
      initialValue: mode,
      position: PopupMenuPosition.over,
      elevation: 0,
      onSelected: (v) async {
        if (v == mode) return;
        if (v == 'auto' && !await confirmBypass(context)) return;
        if (!context.mounted) return;
        await tellFailure(context, () => agent.setApprovalMode(v));
      },
      itemBuilder: (context) => [
        for (final m in _modes)
          PopupMenuItem(
            value: m,
            height: 44,
            child: Row(
              children: [
                Icon(_icon(m), size: 16, color: m == 'auto' ? p.warning : p.muted),
                const SizedBox(width: 8),
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
  }
}
