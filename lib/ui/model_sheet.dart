import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../agent/agent_controller.dart';
import '../agent/models.dart';
import 'i18n.dart';
import 'kit.dart';
import 'settings_screen.dart';
import 'theme.dart';

Future<void> showModelSheet(BuildContext context, AgentController agent) {
  agent.refreshProviders();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ModelSheet(agent: agent),
  );
}

class _ModelSheet extends StatefulWidget {
  const _ModelSheet({required this.agent});
  final AgentController agent;

  @override
  State<_ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends State<_ModelSheet> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: widget.agent,
      builder: (context, _) {
        final agent = widget.agent;
        final q = query.toLowerCase();
        final filtered = agent.models
            .where((m) => q.isEmpty || m.name.toLowerCase().contains(q) || m.key.toLowerCase().contains(q))
            .toList();
        final byProvider = <String, List<ModelInfo>>{};
        for (final m in filtered) {
          byProvider.putIfAbsent(m.provider, () => []).add(m);
        }
        final names = {for (final pr in agent.providers) pr.id: pr.name};

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (context, scroll) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    Expanded(child: Text(tr('Model'), style: text.titleLarge)),
                    TextButton.icon(
                      onPressed: () {
                        final nav = Navigator.of(context)..pop();
                        nav.push(MaterialPageRoute(builder: (_) => SettingsScreen(agent: agent)));
                      },
                      icon: const Icon(LucideIcons.plugZap, size: 16),
                      label: Text(tr('Providers')),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: TextField(
                  onChanged: (v) => setState(() => query = v),
                  decoration: InputDecoration(
                    hintText: tr('Search models'),
                    prefixIcon: const Icon(LucideIcons.search, size: 18),
                  ),
                ),
              ),
              Expanded(
                child: agent.models.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            tr('No models yet. Connect a provider to see its models here.'),
                            style: text.bodyMedium?.copyWith(color: p.muted),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView(
                        controller: scroll,
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          for (final entry in byProvider.entries) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                              child: Row(
                                children: [
                                  BrandTile(id: entry.key, size: 20),
                                  const SizedBox(width: 8),
                                  Text((names[entry.key] ?? entry.key).toUpperCase(), style: text.labelSmall),
                                ],
                              ),
                            ),
                            for (final m in entry.value) _ModelTile(model: m, agent: agent),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({required this.model, required this.agent});
  final ModelInfo model;
  final AgentController agent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final selected = agent.model?.key == model.key;
    final details = [
      if (model.contextWindow != null && model.contextWindow! > 0) '${(model.contextWindow! / 1000).round()}k context',
      if (model.reasoning) 'reasoning',
      if (model.acceptsImages) 'vision',
    ].join('  ·  ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListTile(
        selected: selected,
        onTap: () async {
          Navigator.of(context).pop();
          await agent.setModel(model);
        },
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Text(
          model.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: p.text),
        ),
        subtitle: details.isEmpty ? null : Text(details),
        trailing: selected ? Icon(LucideIcons.circleCheck, size: 20, color: p.accent) : null,
      ),
    );
  }
}
