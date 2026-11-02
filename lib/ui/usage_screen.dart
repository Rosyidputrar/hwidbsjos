import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../agent/agent_controller.dart';
import '../agent/clock.dart';
import '../agent/features.dart';
import '../agent/integrations.dart' show AppSettings;
import '../agent/pricing.dart';
import 'errors.dart';
import 'kit.dart';
import 'i18n.dart';
import 'theme.dart';

String _money(num v) {
  if (v == 0) return r'$0.00';
  return v < 0.01 ? '\$${v.toStringAsFixed(4)}' : '\$${v.toStringAsFixed(2)}';
}

String _compact(num n) {
  String trim(double v) => v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
  if (n >= 1e9) return localNumber('${trim(n / 1e9)}B');
  if (n >= 1e6) return localNumber('${trim(n / 1e6)}M');
  if (n >= 1e3) return localNumber('${trim(n / 1e3)}k');
  return localNumber('${n.round()}');
}

num _num(Object? o) => o is num ? o : 0;

/// Numbers line up and share the body font (the mono face made a few figures look like code).
const _figures = [FontFeature.tabularFigures()];

/// Usage and limits. Every figure is pi's own accounting from this
/// device's chats: per-day and per-model cost and tokens, the open chat's
/// context, the daily budget and the summary limit.
class UsageScreen extends StatefulWidget {
  const UsageScreen({super.key, required this.agent});
  final AgentController agent;

  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends State<UsageScreen> {
  int _days = 7;

  /// The rows of the period [_days] names; null while that period is being read. Rows of another period are never
  /// shown under its tab.
  List<UsageRow>? _rows;
  Map<String, dynamic>? _session;
  Object? _error;

  /// Counts reads of the rows, so one that comes back after a newer one (the same period asked twice: a pull to refresh
  /// over a slow first read) cannot overwrite it. The period check alone only guards against another period's tab.
  int _reading = 0;

  AgentController get agent => widget.agent;

  @override
  void initState() {
    super.initState();
    _load();
    agent.features.sessionStats().then((s) {
      if (mounted) setState(() => _session = s);
    }, onError: (_) {});
    agent.integrations.refreshSettings().then((_) {
      if (mounted) setState(() {});
    }, onError: (_) {});
  }

  Future<void> _load() async {
    final days = _days;
    final reading = ++_reading;
    setState(() => _error = null);
    try {
      final rows = await agent.features.usage(days: days);
      // A newer read (another period, or the same one asked again) is on its way or done: this one is stale.
      if (mounted && reading == _reading) setState(() => _rows = rows);
    } catch (e) {
      if (mounted && reading == _reading) setState(() => _error = e);
    }
  }

  void _setDays(int days) {
    if (days == _days) return;
    setState(() {
      _days = days;
      _rows = null;
    });
    _load();
  }

  num get _budget => _num(agent.integrations.settings?.json['dailyBudget']);

  /// The fixed limits offered (tokens); of those past the open model's window only the first is kept, as "anything
  /// the model allows" (the host never summarizes past the window anyway).
  static const compactLadder = [100000, 200000, 300000, 500000, 700000, 1000000, 1500000, 2000000];

  /// The open chat's context window, told by the host with the session's stats; null before that or with no chat.
  int? get _window {
    final ctx = _session?['context'];
    return ctx is Map && ctx['contextWindow'] is num ? (ctx['contextWindow'] as num).toInt() : null;
  }

  /// The choices: the default (null, follows the model), the ladder up to the window, and 0 (the model's own limit).
  List<int?> get compactChoices {
    final w = _window;
    final within = [
      for (final v in compactLadder)
        if (w == null ? v <= 500000 : v < w) v,
    ];
    return [null, ...within, 0];
  }

  /// The limit being saved: shown at once, with a spinner, until the host has it. [_savingDefault] tells a null that
  /// means "saving the default" apart from one that means "nothing is being saved".
  int? _compactSaving;
  bool _savingDefault = false;

  String _compactText(int? v) {
    if (v == null) {
      final share = agent.integrations.settings?.compactAtShare;
      if (share == null) return _compactText(AppSettings.compactAtDefault);
      final inForce = agent.integrations.settings?.compactLimit(_window);
      return tr('{p}% of the model\'s window')
              .replaceAll('{p}', (share * 100).round().toString()) +
          (inForce != null && _window != null ? ' (${localNumber(formatTokens(inForce))})' : '');
    }
    return v == 0
        ? tr('At the model\'s limit')
        : tr('{n} tokens').replaceAll('{n}', localNumber(formatTokens(v)));
  }

  Future<void> _editCompactAt() async {
    if (_savingDefault || _compactSaving != null) return;
    final current = agent.integrations.settings?.compactAt;
    // null is the dialog's "dismissed"; the default choice comes back as -1.
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(tr('Summarize the chat at')),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              tr(
                'Every request sends the whole chat, so a long chat costs more with every message. Past this size the older turns become a summary. Large models would otherwise wait until close to their own limit.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (final v in compactChoices)
            ListTile(
              title: Text(_compactText(v)),
              subtitle: v == null ? Text(tr('Recommended')) : null,
              trailing: v == current ? const Icon(LucideIcons.check, size: 18) : null,
              onTap: () => Navigator.pop(context, v ?? -1),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final value = picked == -1 ? null : picked;
    if (value == current) return;
    setState(() {
      _compactSaving = value;
      _savingDefault = value == null;
    });
    try {
      // null clears the setting on the host: the default (the share of the model's window) is in force again.
      await agent.integrations.updateSettings({'compactAt': value});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) {
        setState(() {
          _compactSaving = null;
          _savingDefault = false;
        });
      }
    }
  }

  Future<void> _editBudget() async {
    final value = await showDialog<double>(context: context, builder: (_) => _BudgetDialog(current: _budget));
    if (value == null) return;
    try {
      await agent.integrations.updateSettings({'dailyBudget': value < 0 ? 0 : value});
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Usage')),
        actions: [
          IconButton(
            tooltip: tr('Refresh'),
            onPressed: _load,
            icon: const Icon(LucideIcons.refreshCw),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            SectionLabel(tr('This phone'), padding: const EdgeInsets.fromLTRB(4, 8, 4, 10)),
            Wrap(
              spacing: 8,
              children: [
                for (final d in const [7, 30])
                  ChoiceChip(
                    label: Text('$d ${tr('days')}'),
                    selected: _days == d,
                    onSelected: (_) => _setDays(d),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_error != null)
              SurfaceCard(child: ErrorNotice(error: _error, onRetry: _load))
            else if (rows == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: BusySpinner.page()))
            else
              ..._summary(context, rows),
            SectionLabel(tr('This chat')),
            _sessionCard(context),
            SectionLabel(tr('Limits')),
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: LucideIcons.wallet,
                  color: p.warning,
                  title: tr('Daily budget'),
                  subtitle: _budget == 0
                      ? tr('No limit')
                      : tr('{n} per day').replaceAll('{n}', formatUsd(_budget)),
                  onTap: _editBudget,
                ),
                SettingsRow(
                  icon: LucideIcons.layers,
                  color: p.accentAlt,
                  title: tr('Summarize the chat at'),
                  subtitle: _compactText(
                    _savingDefault ? null : (_compactSaving ?? agent.integrations.settings?.compactAt),
                  ),
                  trailing: _savingDefault || _compactSaving != null ? const BusySpinner() : null,
                  onTap: _savingDefault || _compactSaving != null ? null : _editCompactAt,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                tr('The budget counts what the agent spent today (WIB) at each model\'s own prices, plus work still running.'),
                style: text.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _summary(BuildContext context, List<UsageRow> rows) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    // Cost is pi's own, summed from the chat files. When no model in the
    // period carries pricing, the chart falls back to tokens.
    final piCost = rows.fold<double>(0, (a, r) => a + r.cost);
    final hasCost = piCost > 0;

    final tokens = rows.fold<int>(0, (a, r) => a + r.tokens);
    final cached = rows.fold<int>(0, (a, r) => a + r.cacheRead + r.cacheWrite);
    final requests = rows.fold<int>(0, (a, r) => a + r.requests);

    final today = clock();
    final days = [
      for (var i = _days - 1; i >= 0; i--)
        DateTime(today.year, today.month, today.day - i).toIso8601String().substring(0, 10),
    ];
    final perDay = {for (final d in days) d: 0.0};
    for (final r in rows) {
      if (perDay.containsKey(r.day)) {
        final v = hasCost ? r.cost : r.tokens.toDouble();
        perDay[r.day] = perDay[r.day]! + v;
      }
    }

    final byModel = <String, ({String provider, String model, int tokens, double cost})>{};
    for (final r in rows) {
      final k = '${r.provider}/${r.model}';
      final prev = byModel[k];
      byModel[k] = (
        provider: r.provider,
        model: r.model,
        tokens: (prev?.tokens ?? 0) + r.tokens,
        cost: (prev?.cost ?? 0) + r.cost,
      );
    }
    final models = byModel.values.toList()
      ..sort((a, b) => hasCost ? b.cost.compareTo(a.cost) : b.tokens.compareTo(a.tokens));

    return [
      Row(
        children: [
          Expanded(
            child: _StatCard(
              icon: LucideIcons.coins,
              color: p.accent,
              label: tr('Cost'),
              value: hasCost ? _money(piCost) : '—',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(icon: LucideIcons.activity, color: p.accentAlt, label: tr('Requests'), value: _compact(requests)),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _StatCard(icon: LucideIcons.layers, color: p.success, label: tr('Tokens billed'), value: _compact(tokens)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              icon: LucideIcons.databaseZap,
              color: p.warning,
              label: tr('From cache'),
              value: tokens == 0 ? '—' : '${(cached / tokens * 100).round()}%',
            ),
          ),
        ],
      ),
      SectionLabel(tr(hasCost ? 'Cost per day' : 'Tokens per day')),
      SurfaceCard(
        child: _BarChart(
          values: [for (final d in days) perDay[d]!],
          labels: days,
          format: hasCost ? _money : _compact,
        ),
      ),
      SectionLabel(tr('By model')),
      if (models.isEmpty)
        SurfaceCard(child: Text(tr('No requests in this period.'), style: text.bodySmall))
      else
        SettingsGroup(
          children: [
            for (final m in models)
              SettingsRow(
                leading: BrandTile(id: m.provider, size: 30),
                title: m.model.isEmpty ? 'unknown' : m.model,
                subtitle: '${m.provider} · ${_compact(m.tokens)} ${tr('tokens')}',
                trailing: Text(
                  hasCost ? _money(m.cost) : '—',
                  style: text.titleSmall?.copyWith(fontFeatures: _figures),
                ),
              ),
          ],
        ),
    ];
  }

  Widget _sessionCard(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final s = _session;
    if (s == null) {
      return SurfaceCard(child: Text(tr('No active chat.'), style: text.bodySmall));
    }
    final tokens = s['tokens'];
    final total = tokens is Map ? _num(tokens['total']) : _num(tokens);
    final cost = _num(s['cost']);
    final ctx = s['context'] is Map ? (s['context'] as Map).cast<String, dynamic>() : null;
    final ctxTokens = ctx?['tokens'] is num ? ctx!['tokens'] as num : null;
    final window = ctx?['contextWindow'] is num ? ctx!['contextWindow'] as num : null;
    var percent = ctx?['percent'] is num ? (ctx!['percent'] as num).toDouble() : null;
    if (percent == null && ctxTokens != null && window != null && window > 0) percent = ctxTokens / window * 100;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconTile(icon: LucideIcons.messageSquare, color: p.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_compact(total)} ${tr('tokens')}', style: text.titleMedium),
                    if (cost > 0) Text(_money(cost), style: text.bodySmall?.copyWith(fontFeatures: _figures)),
                  ],
                ),
              ),
            ],
          ),
          if (percent != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Text(tr('Context window'), style: text.bodySmall)),
                Text(
                  [
                    if (ctxTokens != null && window != null) '${_compact(ctxTokens)} / ${_compact(window)}',
                    '${percent.toStringAsFixed(0)}%',
                  ].join(' · '),
                  style: text.bodySmall?.copyWith(fontFeatures: _figures),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.pill),
              child: LinearProgressIndicator(
                value: (percent / 100).clamp(0, 1).toDouble(),
                minHeight: 8,
                backgroundColor: p.border,
                color: percent > 85 ? p.danger : (percent > 60 ? p.warning : p.accent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.color, required this.label, required this.value});
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon: icon, color: color, size: 30),
          const SizedBox(height: 12),
          Text(value, style: text.titleLarge?.copyWith(fontFeatures: _figures)),
          const SizedBox(height: 2),
          Text(label, style: text.bodySmall),
        ],
      ),
    );
  }
}

/// Flat bars, one per day; the tallest is labelled.
class _BarChart extends StatelessWidget {
  const _BarChart({required this.values, required this.labels, required this.format});
  final List<double> values;
  final List<String> labels;
  final String Function(num) format;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final max = values.fold<double>(0, (a, v) => v > a ? v : a);
    final gap = values.length > 14 ? 3.0 : 8.0;
    String short(String d) => d.length >= 10 ? d.substring(5) : d;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          max == 0 ? tr('Nothing yet') : '${tr('Peak')} ${format(max)}',
          style: text.bodySmall?.copyWith(fontFeatures: _figures),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < values.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(
                  child: Tooltip(
                    message: '${labels[i]}: ${format(values[i])}',
                    child: Container(
                      height: max == 0 ? 3 : (values[i] / max * 116).clamp(3, 116).toDouble(),
                      decoration: BoxDecoration(
                        color: values[i] == 0 ? p.border : p.accent,
                        borderRadius: BorderRadius.circular(Radii.xs),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(short(labels.first), style: text.labelSmall),
            const Spacer(),
            Text(short(labels.last), style: text.labelSmall),
          ],
        ),
      ],
    );
  }
}

/// The daily budget editor. It owns its text controller, so the field is not
/// disposed while the dialog is still animating out.
class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({required this.current});
  final num current;

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  late final _ctrl = TextEditingController(
    text: widget.current == 0
        ? ''
        : localNumber(widget.current.toString().replaceAll(RegExp(r'\.0+$'), '')),
  );
  String? _problem;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final text = _ctrl.text.trim();
    // Empty is "no limit"; anything else must read as a number, or a typo would
    // silently clear the limit (it used to save 0, and "1,5" used to become 15).
    if (text.isEmpty) return Navigator.pop(context, 0.0);
    final v = parseLocalNumber(text);
    if (v == null || v < 0) return setState(() => _problem = tr('Enter a number, like 2 or 1.5'));
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Daily budget')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              'The agent stops starting new requests once today\'s spend reaches this, in USD. Leave empty for no limit.',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(prefixText: r'$ ', hintText: tr('No limit'), errorText: _problem),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
        TextButton(onPressed: _save, child: Text(tr('Save'))),
      ],
    );
  }
}
