import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../agent/agent_controller.dart';
import '../agent/models.dart';
import 'custom_provider_sheet.dart';
import 'daily_limit_offer.dart';
import 'i18n.dart';
import 'kit.dart';
import 'login_flow.dart';
import 'theme.dart';

/// Models & providers: every provider the agent knows (built into pi, plus
/// the user's own endpoints). Nothing is locked to one service — connect with
/// an account, an API key, or a custom base URL.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.agent});
  final AgentController agent;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String query = '';
  List<CustomProvider> _custom = const [];
  bool _loadingCustom = false;

  @override
  void initState() {
    super.initState();
    widget.agent.refreshProviders();
    _loadCustom();
    widget.agent.addListener(_onAgentChanged);
  }

  @override
  void dispose() {
    widget.agent.removeListener(_onAgentChanged);
    super.dispose();
  }

  void _onAgentChanged() {
    // Saving or removing an endpoint makes the host re-report providers;
    // keep the custom list in step without a manual refresh.
    _loadCustom();
  }

  Future<void> _loadCustom() async {
    if (_loadingCustom) return;
    _loadingCustom = true;
    try {
      final list = await widget.agent.customProviders();
      if (mounted) setState(() => _custom = list);
    } catch (_) {
      // The sections below still work from the provider list alone.
    } finally {
      _loadingCustom = false;
    }
  }

  bool get _anyConnected => widget.agent.providers.any((x) => x.configured) || _custom.isNotEmpty;

  Future<void> _afterConnect(bool wasConnected) async {
    if (!mounted || wasConnected) return;
    await offerDailyLimit(context, widget.agent);
  }

  Future<void> _addEndpoint(BuildContext context) async {
    final wasConnected = _anyConnected;
    final saved = await showCustomProviderSheet(context, widget.agent);
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Endpoint saved'))));
      await _afterConnect(wasConnected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: widget.agent,
      builder: (context, _) {
        final agent = widget.agent;
        final q = query.toLowerCase();
        final connected = agent.providers.where((x) => x.configured).toList();
        final others = agent.providers
            .where((x) => !x.configured && (q.isEmpty || x.name.toLowerCase().contains(q) || x.id.contains(q)))
            .toList();

        return Scaffold(
          appBar: AppBar(
            title: Text(tr('Models & providers')),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Divider(height: 1, color: p.border),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _Header(tr('Connected')),
              if (connected.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(tr('No providers yet. Pick one below.'), style: text.bodySmall),
                ),
              for (final pr in connected)
                _ProviderTile(provider: pr, agent: agent, custom: _custom, afterConnect: _afterConnect),
              _Header(tr('Add provider')),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: TextField(
                  onChanged: (v) => setState(() => query = v),
                  decoration: InputDecoration(
                    hintText: tr('Search providers'),
                    prefixIcon: const Icon(LucideIcons.search, size: 18),
                  ),
                ),
              ),
              for (final pr in others)
                _ProviderTile(provider: pr, agent: agent, custom: _custom, afterConnect: _afterConnect),
              _Header(
                tr('Custom endpoints'),
                trailing: TextButton.icon(
                  onPressed: () => _addEndpoint(context),
                  icon: const Icon(LucideIcons.plus, size: 18),
                  label: Text(tr('Add')),
                ),
              ),
              if (_custom.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    tr('Point the app at any server that speaks an OpenAI-compatible API: Ollama, LM Studio, vLLM, a proxy or your own gateway.'),
                    style: text.bodySmall,
                  ),
                ),
              for (final c in _custom) _CustomTile(endpoint: c, agent: agent, afterConnect: _afterConnect),
              _Header(tr('Environment')),
              _InfoRow(tr('Agent engine (pi)'), agent.info['version']?.toString() ?? '—'),
              _InfoRow('Node.js', agent.info['node']?.toString() ?? '—'),
              _InfoRow('Workspace', agent.info['workspace']?.toString() ?? '—', monospace: true),
              _InfoRow('Agent directory', agent.info['agentDir']?.toString() ?? '—', monospace: true),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: OutlinedButton(onPressed: agent.busy ? null : agent.restart, child: Text(tr('Restart agent'))),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One endpoint defined by the user: edit it or remove it.
class _CustomTile extends StatelessWidget {
  const _CustomTile({required this.endpoint, required this.agent, required this.afterConnect});
  final CustomProvider endpoint;
  final AgentController agent;
  final Future<void> Function(bool wasConnected) afterConnect;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: BrandTile(id: endpoint.id, size: 38),
      title: Text(endpoint.name, style: Theme.of(context).textTheme.titleSmall),
      subtitle: Text(
        tr('{n} models · {api}').replaceAll('{n}', '${endpoint.models.length}').replaceAll('{api}', endpoint.api),
      ),
      trailing: Icon(LucideIcons.chevronRight, size: 18, color: p.faint),
      onTap: () async {
        final changed = await showCustomProviderSheet(context, agent, provider: endpoint);
        if (changed == true && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Endpoint updated'))));
        }
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.label, {this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 24, 20, trailing == null ? 8 : 0),
    child: Row(
      children: [
        Expanded(child: Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall)),
        ?trailing,
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, {this.monospace = false});
  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.labelMedium),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: monospace
                ? TextStyle(fontFamily: mono, fontSize: 12.5, color: p.text, height: 1.5)
                : text.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({required this.provider, required this.agent, required this.custom, required this.afterConnect});
  final ProviderInfo provider;
  final AgentController agent;
  final List<CustomProvider> custom;
  final Future<void> Function(bool wasConnected) afterConnect;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final subtitle = provider.configured
        ? (provider.oauth ? tr('Signed in') : tr('API key'))
        : tr('{n} models').replaceAll('{n}', '${provider.modelCount}');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: BrandTile(id: provider.id, size: 38),
      title: Text(provider.name, style: Theme.of(context).textTheme.titleSmall),
      subtitle: Text(subtitle),
      trailing: provider.configured
          ? Pill(tr('Connected'), color: p.success, dot: true)
          : Icon(LucideIcons.chevronRight, size: 18, color: p.faint),
      onTap: () => _open(context),
    );
  }

  Future<void> _open(BuildContext context) async {
    final methods = provider.methods;
    // Our own endpoint is edited (or removed) in its own sheet, not disconnected.
    if (provider.custom) {
      CustomProvider? endpoint;
      for (final c in custom) {
        if (c.id == provider.id) endpoint = c;
      }
      if (endpoint == null) {
        // Not loaded yet (or added elsewhere): fetch the list, then match.
        try {
          for (final c in await agent.customProviders()) {
            if (c.id == provider.id) endpoint = c;
          }
        } catch (_) {}
      }
      endpoint ??= CustomProvider({
        'id': provider.id,
        'name': provider.name,
        'baseUrl': '',
        'api': 'openai-completions',
        'models': const [],
      });
      if (!context.mounted) return;
      await showCustomProviderSheet(context, agent, provider: endpoint);
      return;
    }
    if (provider.configured) {
      final disconnect = await showModalBottomSheet<bool>(
        context: context,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(provider.name, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(tr('Remove the stored credential from this device.'), style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: context.palette.danger),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(tr('Disconnect')),
                ),
              ],
            ),
          ),
        ),
      );
      if (disconnect == true) await agent.logout(provider.id);
      return;
    }
    if (methods.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('{name} uses ambient credentials and cannot be set up here.').replaceAll('{name}', provider.name))),
      );
      return;
    }
    var method = methods.first;
    if (methods.length > 1) {
      final picked = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(tr('Sign in with account')),
                subtitle: Text(tr('Use your subscription through the browser')),
                onTap: () => Navigator.of(context).pop('oauth'),
              ),
              ListTile(
                title: Text(tr('Use an API key')),
                subtitle: Text(tr('Paste a key from the provider console')),
                onTap: () => Navigator.of(context).pop('api_key'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (picked == null) return;
      method = picked;
    }
    if (!context.mounted) return;
    final wasConnected = agent.providers.any((x) => x.configured);
    final ok = await showLoginSheet(context, agent, provider, method);
    if (ok == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('{name} connected').replaceAll('{name}', provider.name))),
      );
      await afterConnect(wasConnected);
    }
  }
}
