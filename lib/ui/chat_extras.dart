import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../agent/agent_controller.dart';
import '../agent/features.dart';
import 'i18n.dart';
import 'changes_screen.dart';
import 'deploy_sheet.dart';
import 'editor_screen.dart';
import 'files_screen.dart';
import 'folder_picker.dart';
import 'git_screen.dart';
import 'kit.dart';
import 'preview_screen.dart';
import 'search_screen.dart';
import 'tasks_screen.dart';
import 'terminal_screen.dart';
import 'theme.dart';
import 'usage_screen.dart';

// ---------------------------------------------------------------------------
// Attachments

/// A file or picture attached to the next message.
class Attachment {
  Attachment(this.path, this.name, {this.mime});
  final String path;
  final String name;
  final String? mime;

  static const _imageTypes = {
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'webp': 'image/webp',
    'gif': 'image/gif',
  };

  String get ext => name.contains('.') ? name.split('.').last.toLowerCase() : '';
  String? get imageMime => mime?.startsWith('image/') == true ? mime : _imageTypes[ext];
  bool get isImage => imageMime != null;
}

/// Pictures go to the model as images; other files are copied into the
/// project's `.attachments/` folder and referenced by path in the message.
Future<({String text, List<Map<String, String>> images})> preparePrompt(
  String text,
  List<Attachment> attachments,
  String cwd,
) async {
  final images = <Map<String, String>>[];
  final paths = <String>[];
  for (final a in attachments) {
    final file = File(a.path);
    if (!file.existsSync()) continue;
    if (a.isImage && file.lengthSync() < 8 * 1024 * 1024) {
      images.add({'type': 'image', 'data': base64Encode(await file.readAsBytes()), 'mimeType': a.imageMime!});
    } else {
      final dir = Directory('$cwd/.attachments')..createSync(recursive: true);
      final target = '${dir.path}/${a.name}';
      await file.copy(target);
      paths.add(target);
    }
  }
  final note = paths.isEmpty ? '' : '\n\nAttached files:\n${paths.map((p) => '- $p').join('\n')}';
  return (text: '$text$note'.trim(), images: images);
}

Future<List<Attachment>> pickAttachments(BuildContext context) async {
  final choice = await showActionSheet<String>(
    context,
    title: tr('Attach'),
    actions: [
      (
        icon: LucideIcons.images,
        title: tr('Photos'),
        subtitle: tr('Screenshots, sketches, error photos'),
        value: 'gallery',
        destructive: false,
        enabled: true,
      ),
      (
        icon: LucideIcons.camera,
        title: tr('Camera'),
        subtitle: tr('Take a picture now'),
        value: 'camera',
        destructive: false,
        enabled: true,
      ),
      (
        icon: LucideIcons.paperclip,
        title: tr('Files'),
        subtitle: tr('PDFs, code, data, anything'),
        value: 'files',
        destructive: false,
        enabled: true,
      ),
    ],
  );
  final picker = ImagePicker();
  switch (choice) {
    case 'gallery':
      final images = await picker.pickMultiImage(imageQuality: 85, maxWidth: 2048);
      return [for (final x in images) Attachment(x.path, x.name, mime: x.mimeType)];
    case 'camera':
      final x = await picker.pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2048);
      return x == null ? [] : [Attachment(x.path, x.name, mime: x.mimeType)];
    case 'files':
      final files = await FilePicker.pickFiles();
      return [
        for (final f in files)
          if (f.path != null) Attachment(f.path!, f.name),
      ];
  }
  return const [];
}

/// Thumbnails / chips of what will be sent with the next message.
class AttachmentStrip extends StatelessWidget {
  const AttachmentStrip({super.key, required this.items, required this.onRemove});
  final List<Attachment> items;
  final void Function(Attachment) onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: 68,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final a = items[i];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.sm),
                child: a.isImage
                    ? Image.file(File(a.path), width: 56, height: 56, fit: BoxFit.cover)
                    : Container(
                        width: 120,
                        height: 56,
                        color: p.raised,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Icon(LucideIcons.fileText, size: 16, color: p.muted),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                a.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: p.text),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              Positioned(
                right: -6,
                top: -6,
                child: GestureDetector(
                  onTap: () => onRemove(a),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(color: p.text, shape: BoxShape.circle),
                    child: Icon(LucideIcons.x, size: 12, color: p.inverse),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Approvals

/// Asks once before turning every approval off, since pi can then delete files or push without asking.
Future<bool> confirmBypass(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Bypass all permissions?')),
        content: Text(tr('pi will run every command, edit any file and use every tool without asking.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Bypass'))),
        ],
      ),
    ) ??
    false;

class ApprovalCards extends StatelessWidget {
  const ApprovalCards({super.key, required this.features});
  final Features features;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: features,
      builder: (context, _) {
        if (features.approvals.isEmpty) return const SizedBox.shrink();
        final a = features.approvals.first;
        return Padding(
          padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, 0),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(color: p.warning.withValues(alpha: 0.55), width: 1.2),
              boxShadow: [
                BoxShadow(color: p.warning.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 6)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconTile(icon: toolIcon(a.toolName), color: p.warning, size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${tr('Allow')} ${a.toolName}?', style: text.titleSmall),
                          Text(a.reason, style: text.bodySmall),
                        ],
                      ),
                    ),
                    if (features.approvals.length > 1) Pill('+${features.approvals.length - 1}', color: p.muted),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 110),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: p.raised,
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(color: p.border),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      a.summary,
                      style: TextStyle(fontFamily: mono, fontSize: 12, color: p.text, height: 1.45),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => features.answer(a, allow: false),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42), foregroundColor: p.danger),
                        child: Text(tr('Deny')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => features.answer(a, allow: true, always: true),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                        child: Text(tr('Always')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => features.answer(a, allow: true),
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                        child: Text(tr('Allow')),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () async {
                    if (!await confirmBypass(context)) return;
                    await features.client.call('settings_set', {
                      'settings': {'approvalMode': 'auto'},
                    });
                    for (final pending in [...features.approvals]) {
                      await features.answer(pending, allow: true);
                    }
                  },
                  style: TextButton.styleFrom(foregroundColor: p.muted),
                  icon: const Icon(LucideIcons.shieldOff, size: 16),
                  label: Text(tr('Bypass all permissions')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Plan mode

/// After the agent answers in plan mode: approve and run, or keep planning.
class PlanBar extends StatelessWidget {
  const PlanBar({super.key, required this.agent});
  final AgentController agent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (!agent.planMode || agent.busy || agent.entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, 0),
      child: InlineBanner(
        tone: p.accent,
        icon: LucideIcons.listChecks,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: () => agent.setPlanMode(false), child: Text(tr('Exit'))),
            FilledButton(
              onPressed: agent.approvePlan,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
              child: Text(tr('Approve & run')),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Plan mode'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            Text(tr('Review the plan, then run it'), style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dev servers

/// A server the agent started: preview it, or share a public link.
class DevServerBanner extends StatefulWidget {
  const DevServerBanner({super.key, required this.agent});
  final AgentController agent;

  @override
  State<DevServerBanner> createState() => _DevServerBannerState();
}

class _DevServerBannerState extends State<DevServerBanner> {
  final opening = <int>{};

  Future<void> _share(int port) async {
    final f = widget.agent.features;
    setState(() => opening.add(port));
    try {
      final url = f.tunnels[port] ?? await f.startTunnel(port);
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Public link copied: $url'),
            action: SnackBarAction(label: tr('Open'), onPressed: () => widget.agent.client.openUrl(url)),
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => opening.remove(port));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final f = widget.agent.features;
    return ListenableBuilder(
      listenable: f,
      builder: (context, _) {
        if (f.devServers.isEmpty) return const SizedBox.shrink();
        return Column(
          children: [
            for (final e in f.devServers.entries)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, 0),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                  decoration: BoxDecoration(
                    color: p.success.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(Radii.md),
                    border: Border.all(color: p.success.withValues(alpha: 0.28)),
                  ),
                  child: Row(
                    children: [
                      StatusDot(color: p.success, pulse: true),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          f.tunnels[e.key] ?? 'localhost:${e.key}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: mono, fontSize: 12.5, color: p.text),
                        ),
                      ),
                      TextButton(
                        onPressed: () => HtmlPreviewScreen.openUrl(context, title: 'localhost:${e.key}', url: e.value),
                        child: Text(tr('Preview')),
                      ),
                      opening.contains(e.key)
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : IconButton(
                              tooltip: tr('Share a public link'),
                              icon: const Icon(LucideIcons.share2, size: 18),
                              onPressed: () => _share(e.key),
                            ),
                      IconButton(
                        tooltip: tr('Dismiss'),
                        icon: Icon(LucideIcons.x, size: 16, color: p.muted),
                        onPressed: () {
                          if (f.tunnels.containsKey(e.key)) f.stopTunnel(e.key);
                          f.dismissDevServer(e.key);
                        },
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Slash commands

/// Suggestions while the message starts with "/": templates and skills.
class SlashMenu extends StatelessWidget {
  const SlashMenu({super.key, required this.commands, required this.query, required this.onPick});
  final List<SlashCommand> commands;
  final String query;
  final void Function(SlashCommand) onPick;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final q = query.toLowerCase();
    final matches = commands.where((c) => c.name.toLowerCase().contains(q)).take(8).toList();
    if (matches.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, 0),
      constraints: const BoxConstraints(maxHeight: 260),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: p.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        children: [
          for (final c in matches)
            ListTile(
              dense: true,
              leading: Icon(c.isSkill ? LucideIcons.puzzle : LucideIcons.slash, size: 18, color: p.accent),
              title: Text(
                '/${c.name}${c.hint != null ? '  ${c.hint}' : ''}',
                style: TextStyle(fontFamily: mono, fontSize: 13, color: p.text),
              ),
              subtitle: Text(c.description, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => onPick(c),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Workspace sheet

/// Everything that acts on the chat's folder: files, git, terminal, deploy,
/// history, memory, tasks and usage, as one grid.
Future<void> showProjectTools(
  BuildContext context,
  AgentController agent, {
  required void Function(String prompt) onPrompt,
}) async {
  void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
  final memory = '${agent.cwd}/AGENTS.md';
  final workspace = agent.info['workspace'] as String? ?? '';
  final folder = sessionFolder(agent.cwd, workspace);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) {
      final p = sheet.palette;
      final text = Theme.of(sheet).textTheme;
      void go(Widget w) {
        Navigator.pop(sheet);
        push(w);
      }

      final tiles = <(IconData, String, Color, VoidCallback?)>[
        (LucideIcons.folderOpen, tr('Files'), const Color(0xFFF97316), () => go(FilesScreen(agent: agent))),
        (
          LucideIcons.gitBranch,
          tr('Git'),
          const Color(0xFFEF4444),
          () => go(GitScreen(agent: agent, onWork: onPrompt)),
        ),
        (LucideIcons.squareTerminal, tr('Terminal'), const Color(0xFF64748B), () => go(TerminalScreen(agent: agent))),
        (
          LucideIcons.rocket,
          tr('Deploy'),
          const Color(0xFFEC4899),
          agent.busy
              ? null
              : () {
                  Navigator.pop(sheet);
                  showDeploySheet(context, agent);
                },
        ),
        (LucideIcons.search, tr('Search'), const Color(0xFF3B82F6), () => go(SearchScreen(agent: agent))),
        (LucideIcons.history, tr('Changes'), const Color(0xFF8B5CF6), () => go(ChangesScreen(agent: agent))),
        (
          LucideIcons.brain,
          tr('Memory'),
          const Color(0xFFD946EF),
          () {
            final f = File(memory);
            if (!f.existsSync()) {
              f.writeAsStringSync('# Project notes for pi\n\n- Stack:\n- How to run:\n- Conventions:\n');
            }
            go(EditorScreen(agent: agent, path: memory));
          },
        ),
        (LucideIcons.listTodo, tr('Tasks'), const Color(0xFF14B8A6), () => go(TasksScreen(agent: agent))),
        (LucideIcons.chartColumn, tr('Usage'), const Color(0xFFEAB308), () => go(UsageScreen(agent: agent))),
      ];

      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconTile(icon: folder != null ? LucideIcons.folderGit2 : LucideIcons.messageSquare, size: 40),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(folder ?? tr('Workspace'), style: text.titleMedium),
                        Text(
                          agent.cwd,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: mono, fontSize: 11.5, color: p.faint),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.lg),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: Space.sm,
                crossAxisSpacing: Space.sm,
                childAspectRatio: 1.15,
                children: [
                  for (final (icon, label, color, onTap) in tiles)
                    ActionTile(icon: icon, label: label, color: color, onTap: onTap),
                ],
              ),
              if (agent.busy) ...[
                const SizedBox(height: Space.sm),
                Text(tr('Deploy is available once pi finishes.'), style: text.bodySmall, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      );
    },
  );
}
