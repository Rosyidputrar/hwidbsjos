import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:simple_icons/simple_icons.dart';

import '../agent/agent_controller.dart';
import 'accounts_screen.dart';
import 'backup_screen.dart';
import 'chat_extras.dart';
import 'container_screen.dart';
import 'kit.dart';
import 'i18n.dart';
import 'illustration.dart';
import 'mcp_screen.dart';
import 'network_screen.dart';
import 'settings_screen.dart';
import 'skills_screen.dart';
import 'tasks_screen.dart';
import 'templates_screen.dart';
import 'theme.dart';
import 'usage_screen.dart';

/// The settings home: everything the agent can use, grouped.
class SettingsHub extends StatefulWidget {
  const SettingsHub({super.key, required this.agent, this.embedded = false});
  final AgentController agent;

  /// Shown as a tab of the home shell: no app bar, a large title instead.
  final bool embedded;

  @override
  State<SettingsHub> createState() => _SettingsHubState();
}

class _SettingsHubState extends State<SettingsHub> {
  int? skillCount;

  AgentController get agent => widget.agent;

  @override
  void initState() {
    super.initState();
    final it = agent.integrations;
    it.refresh().catchError((_) {});
    it.refreshContainer().catchError((_) => it.container!);
    it.refreshSettings().catchError((_) => it.settings!);
    it.skills().then((s) {
      if (mounted) setState(() => skillCount = s.length);
    }, onError: (_) {});
  }

  void _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (!mounted) return;
    agent.integrations.skills().then((s) {
      if (mounted) setState(() => skillCount = s.length);
    }, onError: (_) {});
  }

  Future<void> _setAppLock(bool on) async {
    if (on) {
      // Confirm the phone can unlock before turning it on, so nobody locks themselves out.
      try {
        final auth = LocalAuthentication();
        if (!await auth.isDeviceSupported()) throw tr('No screen lock is set on this phone.');
        if (!await auth.authenticate(localizedReason: tr('Unlock Rynex'))) return;
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        return;
      }
    }
    Appearance.instance.update(appLock: on);
  }

  Future<void> _pickFallbacks() async {
    final it = agent.integrations;
    final chosen = [
      for (final m in it.settings?.fallbackModels ?? const <Map<String, dynamic>>[]) '${m['provider']}/${m['model']}',
    ];
    final models = agent.models;
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          builder: (context, scroll) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
                child: Row(
                  children: [
                    Expanded(child: Text(tr('Fallback models'), style: Theme.of(context).textTheme.titleLarge)),
                    TextButton(onPressed: () => Navigator.pop(context, chosen), child: Text(tr('Save'))),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  tr('Used when the current model hits a limit or errors'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scroll,
                  children: [
                    for (final m in models)
                      CheckboxListTile(
                        value: chosen.contains(m.key),
                        title: Text(m.name),
                        subtitle: Text(
                          chosen.contains(m.key) ? '#${chosen.indexOf(m.key) + 1} · ${m.provider}' : m.provider,
                        ),
                        onChanged: (v) => setSheet(() => v == true ? chosen.add(m.key) : chosen.remove(m.key)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null) return;
    await it.updateSettings({
      'fallbackModels': [
        for (final k in result) {'provider': k.substring(0, k.indexOf('/')), 'model': k.substring(k.indexOf('/') + 1)},
      ],
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: Listenable.merge([agent, agent.integrations, agent.features, Appearance.instance]),
      builder: (context, _) {
        final it = agent.integrations;
        final look = Appearance.instance;
        final connected = agent.providers.where((x) => x.configured).toList();
        final c = it.container;
        final approval = it.settings?.approvalMode ?? agent.approvalMode;
        final dnsLabel = switch (it.settings?.dns) {
          'system' => 'System DNS',
          'google' => 'Google DoH',
          'custom' => 'Custom DoH',
          _ => 'Cloudflare DoH',
        };
        final list = ListView(
          padding: EdgeInsets.fromLTRB(Space.page, widget.embedded ? Space.md : Space.xs, Space.page, 40),
          children: [
            if (widget.embedded) PageHeader(tr('Settings')),
            // Runtime status and the current model, at a glance.
            SurfaceCard(
              onTap: () => _open(SettingsScreen(agent: agent)),
              child: Row(
                children: [
                  const LogoMark(size: 44),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Rynex', style: text.titleMedium),
                            const SizedBox(width: Space.sm),
                            Pill(
                              agent.busy ? tr('Working') : tr('Ready'),
                              color: agent.busy ? p.warning : p.success,
                              dot: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          agent.model?.name ?? tr('No model selected'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(color: p.text),
                        ),
                        Text(
                          'pi ${agent.info['version'] ?? ''} · Node ${agent.info['node'] ?? ''}',
                          style: TextStyle(fontFamily: mono, fontSize: 11.5, color: p.faint),
                        ),
                      ],
                    ),
                  ),
                  Icon(LucideIcons.chevronRight, size: 18, color: p.faint),
                ],
              ),
            ),
            SectionLabel(tr('AI & models')),
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: LucideIcons.brain,
                  color: p.accent,
                  title: tr('Models & providers'),
                  subtitle: connected.isEmpty
                      ? tr('Connect a provider to start')
                      : '${connected.map((x) => x.name).join(', ')}${agent.model != null ? ' · ${agent.model!.name}' : ''}',
                  onTap: () => _open(SettingsScreen(agent: agent)),
                ),
                SettingsRow(
                  icon: LucideIcons.lifeBuoy,
                  title: tr('Fallback models'),
                  subtitle: (it.settings?.fallbackModels ?? const []).isEmpty
                      ? tr('Used when the current model hits a limit or errors')
                      : it.settings!.fallbackModels.map((m) => m['model']).join(' → '),
                  onTap: _pickFallbacks,
                ),
                SettingsRow(
                  icon: LucideIcons.puzzle,
                  title: tr('Skills'),
                  subtitle: skillCount == null
                      ? tr('Instructions the agent loads on demand')
                      : '$skillCount ${tr('installed')}',
                  onTap: () => _open(SkillsScreen(agent: agent)),
                ),
                SettingsRow(
                  icon: LucideIcons.chartColumn,
                  title: tr('Usage & budget'),
                  subtitle: (it.settings?.dailyBudget ?? 0) > 0
                      ? '\$${it.settings!.dailyBudget.toStringAsFixed(2)} / ${tr('day')}'
                      : tr('Tokens, cost and a daily limit'),
                  onTap: () => _open(UsageScreen(agent: agent)),
                ),
              ],
            ),
            SectionLabel(tr('Agent behaviour')),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Segmented<String>(
                    label: tr('Approvals'),
                    value: approval,
                    options: {'ask_all': tr('Ask all'), 'ask_risky': tr('Risky only'), 'auto': tr('Bypass all')},
                    onChanged: (v) async {
                      if (v == 'auto' && !await confirmBypass(context)) return;
                      await it.updateSettings({'approvalMode': v});
                      agent.approvalMode = v;
                    },
                  ),
                  const SizedBox(height: Space.sm),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        approval == 'auto' ? LucideIcons.shieldOff : LucideIcons.shieldCheck,
                        size: 14,
                        color: approval == 'auto' ? p.warning : p.muted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(switch (approval) {
                          'auto' => tr('All permissions bypassed: pi never asks before acting.'),
                          'ask_all' => tr('pi asks before every command and file change.'),
                          _ => tr('pi asks only before risky commands, like deleting or pushing.'),
                        }, style: text.bodySmall?.copyWith(color: approval == 'auto' ? p.warning : null)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.md),
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: LucideIcons.listTodo,
                  title: tr('Background tasks'),
                  subtitle: tr('Queue, parallel agents and schedules'),
                  trailing: _count(agent.features.runs.where((r) => r.active).length),
                  onTap: () => _open(TasksScreen(agent: agent)),
                ),
                SettingsRow(
                  icon: LucideIcons.plug,
                  title: tr('MCP servers'),
                  subtitle: agent.features.mcpServers.isEmpty
                      ? tr('Extra tools from Model Context Protocol servers')
                      : '${agent.features.mcpServers.length} server${agent.features.mcpServers.length == 1 ? '' : 's'}',
                  onTap: () => _open(McpScreen(agent: agent)),
                ),
                SettingsRow(
                  icon: LucideIcons.squareSlash,
                  title: tr('Prompt templates'),
                  subtitle: tr('Slash commands like /review and /test'),
                  onTap: () => _open(TemplatesScreen(agent: agent)),
                ),
              ],
            ),
            SectionLabel(tr('Workspace')),
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: c?.distro == 'alpine' ? SimpleIcons.alpinelinux : SimpleIcons.debian,
                  color: c?.distro == 'alpine' ? const Color(0xFF0D597F) : const Color(0xFFD70A53),
                  title: tr('Linux container'),
                  subtitle: c == null
                      ? 'Debian or Alpine with apt / apk'
                      : c.installed
                      ? '${c.image}${c.enabled ? ' · agent shell' : ''}'
                      : 'Not installed · run apt, pip, npm and more',
                  trailing: c?.enabled == true
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Pill(tr('On'), color: p.success, dot: true),
                            const SizedBox(width: Space.xs),
                            Icon(LucideIcons.chevronRight, size: 18, color: p.faint),
                          ],
                        )
                      : null,
                  onTap: () => _open(ContainerScreen(agent: agent)),
                ),
                SettingsRow(
                  icon: LucideIcons.keyRound,
                  title: tr('Accounts & servers'),
                  subtitle: [
                    if (it.github != null) 'GitHub @${it.github!.login}',
                    if (it.vercelUser != null) 'Vercel',
                    if (it.hosts.isNotEmpty) '${it.hosts.length} server${it.hosts.length == 1 ? '' : 's'}',
                  ].join(' · ').ifEmpty(tr('GitHub, Vercel, SSH keys and servers')),
                  onTap: () => _open(AccountsScreen(agent: agent)),
                ),
                SettingsRow(
                  icon: LucideIcons.globe,
                  title: tr('Web & DNS'),
                  subtitle: '$dnsLabel · ${tr('web search for the agent')}',
                  onTap: () => _open(NetworkScreen(agent: agent)),
                ),
              ],
            ),
            SectionLabel(tr('Appearance')),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Segmented<ThemeMode>(
                    label: tr('Theme'),
                    value: look.value,
                    options: {ThemeMode.light: tr('Light'), ThemeMode.dark: tr('Dark'), ThemeMode.system: tr('System')},
                    onChanged: look.set,
                  ),
                  const SizedBox(height: Space.lg),
                  Segmented<double>(
                    label: tr('Text size'),
                    value: look.textScale,
                    options: {0.9: tr('Small'), 1.0: tr('Default'), 1.12: tr('Large'), 1.25: tr('Huge')},
                    onChanged: (v) => look.update(textScale: v),
                  ),
                  const SizedBox(height: Space.lg),
                  Segmented<String>(
                    label: tr('Language'),
                    value: look.language,
                    options: languages,
                    onChanged: (v) => look.update(language: v),
                  ),
                  const SizedBox(height: Space.lg),
                  Text(tr('Accent colour'), style: text.labelMedium),
                  const SizedBox(height: Space.sm),
                  Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    children: [
                      for (var i = 0; i < accentChoices.length; i++)
                        Semantics(
                          button: true,
                          selected: look.accent == i,
                          label: '${tr('Accent colour')} ${i + 1}',
                          child: GestureDetector(
                            onTap: () => look.update(accent: i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 34,
                              height: 34,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: look.accent == i ? p.text : Colors.transparent, width: 2),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Theme.of(context).brightness == Brightness.light
                                      ? accentChoices[i].$1
                                      : accentChoices[i].$2,
                                ),
                                child: look.accent == i
                                    ? const Icon(LucideIcons.check, size: 14, color: Colors.white)
                                    : null,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.md),
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: LucideIcons.rows3,
                  title: tr('Compact layout'),
                  subtitle: tr('Tighter spacing, more on screen'),
                  trailing: Switch(
                    value: look.compact,
                    onChanged: (v) => look.update(compact: v),
                  ),
                  onTap: () => look.update(compact: !look.compact),
                ),
              ],
            ),
            SectionLabel(tr('Privacy & data')),
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: LucideIcons.fingerprint,
                  title: tr('App lock'),
                  subtitle: tr('Fingerprint or screen lock when opening Rynex'),
                  trailing: Switch(value: look.appLock, onChanged: _setAppLock),
                  onTap: () => _setAppLock(!look.appLock),
                ),
                SettingsRow(
                  icon: LucideIcons.archive,
                  title: tr('Backup & restore'),
                  subtitle: tr('Chats, settings, skills and keys in one file'),
                  onTap: () => _open(BackupScreen(agent: agent)),
                ),
              ],
            ),
            SectionLabel(tr('About')),
            SettingsGroup(
              children: [
                _InfoRow(tr('Workspace'), agent.info['workspace']?.toString() ?? '—'),
                _InfoRow(tr('Agent directory'), agent.info['agentDir']?.toString() ?? '—'),
                SettingsRow(
                  icon: LucideIcons.scale,
                  title: tr('Open-source licenses'),
                  subtitle: tr('Rynex and the libraries it is built on'),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Rynex',
                    applicationIcon: const Padding(padding: EdgeInsets.all(Space.sm), child: LogoMark(size: 56)),
                  ),
                ),
                SettingsRow(
                  icon: LucideIcons.rotateCcw,
                  title: tr('Restart agent'),
                  subtitle: tr('Reload the runtime, keeping your chats'),
                  onTap: agent.busy ? null : agent.restart,
                ),
              ],
            ),
            SectionLabel(tr('Made by')),
            const _DeveloperCard(),
            const SizedBox(height: Space.lg),
            Center(child: StorysetCredit(openUrl: agent.client.openUrl)),
          ],
        );
        if (widget.embedded) return SafeArea(bottom: false, child: list);
        return Scaffold(
          appBar: AppBar(title: Text(tr('Settings'))),
          body: list,
        );
      },
    );
  }

  /// A small count badge before the chevron, hidden at zero.
  Widget? _count(int n) {
    if (n == 0) return null;
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Pill('$n', color: p.accent),
        const SizedBox(width: Space.xs),
        Icon(LucideIcons.chevronRight, size: 18, color: p.faint),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 3),
          SelectableText(
            value,
            style: TextStyle(fontFamily: mono, fontSize: 12, height: 1.5, color: p.text),
          ),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// Who builds Rynex.
class _DeveloperCard extends StatelessWidget {
  const _DeveloperCard();

  static const name = 'seseegy';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return SurfaceCard(
      child: Row(
        children: [
          const LogoMark(size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rynex', style: text.titleMedium),
                const SizedBox(height: 2),
                Text('${tr('Made by')} $name', style: text.bodySmall?.copyWith(color: p.muted)),
              ],
            ),
          ),
          Pill('AI agent', color: p.accent),
        ],
      ),
    );
  }
}
