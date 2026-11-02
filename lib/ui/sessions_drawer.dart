import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:simple_icons/simple_icons.dart';

import '../agent/agent_controller.dart';
import '../agent/integrations.dart';
import '../agent/models.dart';
import 'accounts_screen.dart';
import 'chat_screen.dart';
import 'delete_flows.dart';
import 'folder_picker.dart';
import 'i18n.dart';
import 'kit.dart';
import 'new_chat_sheet.dart';
import 'repos_screen.dart';
import 'settings_hub.dart';
import 'theme.dart';

/// The chat list as a drawer over the home shell: brand row, new chat and clone,
/// search, the projects, then the chats grouped by age. Opened from the home
/// header's brand (and by the edge swipe the shell's drawer gives every tab).
class SessionsDrawer extends StatefulWidget {
  const SessionsDrawer({super.key, required this.agent});
  final AgentController agent;

  @override
  State<SessionsDrawer> createState() => _SessionsDrawerState();
}

class _SessionsDrawerState extends State<SessionsDrawer> {
  late Future<List<SessionSummary>> sessions = widget.agent.listSessions();
  String query = '';
  bool allProjects = false;

  AgentController get agent => widget.agent;

  @override
  void initState() {
    super.initState();
    agent.integrations.refreshProjects().catchError((_) {});
  }

  void _reload() => setState(() {
    sessions = agent.listSessions();
  });

  /// Closes the drawer, then opens [screen] over the shell.
  void _push(Widget screen) {
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _newChat() async {
    final before = agent.sessionId;
    final nav = Navigator.of(context);
    nav.pop();
    await showNewChatSheet(nav.context, agent);
    if (agent.sessionId != before) {
      nav.push(MaterialPageRoute(builder: (_) => ChatScreen(agent: agent)));
    }
  }

  /// Resumes the project's latest session, or starts one there, and opens the chat.
  Future<void> _openProject(ProjectInfo project, List<SessionSummary> all) async {
    final nav = Navigator.of(context);
    nav.pop();
    final latest = all.where((s) => s.cwd == project.path && s.messageCount > 0).firstOrNull;
    if (latest != null) {
      if (latest.id != agent.sessionId && !await agent.openSession(latest.path)) return;
    } else {
      if (!await agent.newSession(dir: project.path)) return;
    }
    nav.push(MaterialPageRoute(builder: (_) => ChatScreen(agent: agent)));
  }

  Future<void> _openSession(SessionSummary s) async {
    final nav = Navigator.of(context);
    nav.pop();
    if (s.id != agent.sessionId && !await agent.openSession(s.path)) return;
    nav.push(MaterialPageRoute(builder: (_) => ChatScreen(agent: agent)));
  }

  Future<void> _sessionMenu(SessionSummary s) async {
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
                child: Text(
                  s.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              SettingsGroup(
                children: [
                  SettingsRow(
                    icon: LucideIcons.pencil,
                    color: context.palette.accentAlt,
                    title: tr('Rename'),
                    onTap: () => Navigator.pop(context, 'rename'),
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
    } else if (action == 'delete') {
      await deleteChats(context, agent, [s]);
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;

    return Drawer(
      width: MediaQuery.sizeOf(context).width * 0.86,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([agent, agent.integrations]),
          builder: (context, _) => FutureBuilder<List<SessionSummary>>(
            future: sessions,
            builder: (context, snap) {
              final all = (snap.data ?? const <SessionSummary>[]).where((s) => s.messageCount > 0).toList();
              final q = query.toLowerCase();
              final matches = q.isEmpty
                  ? all
                  : all.where((s) => s.title.toLowerCase().contains(q) || s.cwd.toLowerCase().contains(q)).toList();
              final projects = agent.integrations.projects
                  .where((pr) => q.isEmpty || pr.name.toLowerCase().contains(q))
                  .toList();
              final shownProjects = allProjects ? projects : projects.take(4).toList();

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                          child: Row(
                            children: [
                              const LogoMark(size: 30, glow: false),
                              const SizedBox(width: 10),
                              Text(tr('Rynex'), style: text.titleLarge),
                              const Spacer(),
                              IconButton(
                                tooltip: tr('Accounts & servers'),
                                icon: const Icon(LucideIcons.circleUser),
                                onPressed: () => _push(AccountsScreen(agent: agent)),
                              ),
                              IconButton(
                                tooltip: tr('Settings'),
                                icon: const Icon(LucideIcons.settings2),
                                onPressed: () => _push(SettingsHub(agent: agent)),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: PrimaryButton(
                                  onPressed: _newChat,
                                  icon: LucideIcons.plus,
                                  label: tr('New chat'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _push(ReposScreen(agent: agent)),
                                  icon: const Icon(SimpleIcons.github, size: 16),
                                  label: Text(tr('Clone repo')),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: TextField(
                            onChanged: (v) => setState(() => query = v),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: tr('Search chats and projects'),
                              prefixIcon: const Icon(LucideIcons.search, size: 18),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (projects.isNotEmpty) ...[
                    _SectionLabel(
                      tr('Projects'),
                      trailing: projects.length > 4
                          ? TextButton(
                              onPressed: () => setState(() => allProjects = !allProjects),
                              child: Text(allProjects ? tr('Less') : '${tr('All')} ${projects.length}'),
                            )
                          : null,
                    ),
                    SliverList.builder(
                      itemCount: shownProjects.length,
                      itemBuilder: (context, i) => _ProjectTile(
                        project: shownProjects[i],
                        active: shownProjects[i].path == agent.cwd,
                        onTap: () => _openProject(shownProjects[i], all),
                      ),
                    ),
                  ],
                  if (!snap.hasData)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: BusySpinner(size: 20)),
                    )
                  else if (matches.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          q.isEmpty
                              ? tr('Chats you start appear here.')
                              : tr('No chats match "{q}".').replaceAll('{q}', query),
                          style: text.bodySmall,
                        ),
                      ),
                    )
                  else
                    for (final group in _group(matches)) ...[
                      _SectionLabel(tr(group.$1)),
                      SliverList.builder(
                        itemCount: group.$2.length,
                        itemBuilder: (context, i) {
                          final s = group.$2[i];
                          final active = s.id == agent.sessionId;
                          final working = active && agent.busy;
                          final project = _project(s.cwd);
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: ListTile(
                              dense: true,
                              selected: active,
                              selectedTileColor: p.raised,
                              selectedColor: p.text,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                              title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
                              subtitle: working
                                  ? Row(
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(color: p.warning, shape: BoxShape.circle),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          tr('Working'),
                                          style: text.bodySmall?.copyWith(color: p.warning),
                                        ),
                                      ],
                                    )
                                  : Text(
                                      [?project, formatAgo(s.modified)].join('  ·  '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: text.bodySmall?.copyWith(color: p.faint),
                                    ),
                              trailing: agent.switchingTo == s.path ? const BusySpinner(size: 14) : null,
                              onLongPress: () => _sessionMenu(s),
                              onTap: () => _openSession(s),
                            ),
                          );
                        },
                      ),
                    ],
                  const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// The project folder name for sessions started inside one.
  String? _project(String cwd) {
    return sessionFolder(cwd, agent.info['workspace'] as String? ?? '');
  }

  static List<(String, List<SessionSummary>)> _group(List<SessionSummary> list) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    String bucket(DateTime t) {
      final day = DateTime(t.year, t.month, t.day);
      final days = today.difference(day).inDays;
      if (days <= 0) return 'Today';
      if (days == 1) return 'Yesterday';
      if (days < 7) return 'Previous 7 days';
      if (days < 30) return 'Previous 30 days';
      return 'Older';
    }

    final groups = <String, List<SessionSummary>>{};
    for (final s in list) {
      groups.putIfAbsent(bucket(s.modified), () => []).add(s);
    }
    return [for (final e in groups.entries) (e.key, e.value)];
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 12, trailing == null ? 6 : 0),
      child: Row(
        children: [
          Expanded(child: Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall)),
          ?trailing,
        ],
      ),
    ),
  );
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.project, required this.active, required this.onTap});
  final ProjectInfo project;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListTile(
        dense: true,
        selected: active,
        selectedTileColor: p.raised,
        selectedColor: p.text,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: IconTile(
          icon: project.isGit ? LucideIcons.folderGit2 : LucideIcons.folder,
          color: project.isGit ? p.accent : p.muted,
          size: 30,
        ),
        minLeadingWidth: 30,
        title: Text(project.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
        subtitle: project.isGit
            ? Text(
                [project.githubSlug ?? tr('local folder'), if (project.branch != null) project.branch!].join('  ·  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: mono, fontSize: 11, color: p.faint),
              )
            : null,
        trailing: project.dirty
            ? Tooltip(
                message: tr('Uncommitted changes'),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: p.muted, shape: BoxShape.circle),
                ),
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}
