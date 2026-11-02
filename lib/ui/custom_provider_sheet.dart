import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../agent/agent_controller.dart';
import '../agent/models.dart';
import 'errors.dart';
import 'i18n.dart';
import 'kit.dart';
import 'theme.dart';

/// The API shapes the host can speak to a custom endpoint (agent/src/providers.ts APIS).
const _apis = <(String, String)>[
  ('openai-completions', 'OpenAI-compatible (Chat Completions)'),
  ('openai-responses', 'OpenAI Responses'),
  ('anthropic-messages', 'Anthropic Messages'),
  ('google-generative-ai', 'Google Generative AI'),
];

String _slug(String name) => name
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9-_]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

/// Adds or edits one custom endpoint: any server speaking an API the agent
/// already implements, e.g. an OpenAI-compatible one on the local network.
/// Resolves true once the endpoint was saved or removed.
Future<bool?> showCustomProviderSheet(BuildContext context, AgentController agent, {CustomProvider? provider}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _CustomProviderSheet(agent: agent, provider: provider),
    ),
  );
}

class _CustomProviderSheet extends StatefulWidget {
  const _CustomProviderSheet({required this.agent, required this.provider});
  final AgentController agent;
  final CustomProvider? provider;

  @override
  State<_CustomProviderSheet> createState() => _CustomProviderSheetState();
}

class _CustomProviderSheetState extends State<_CustomProviderSheet> {
  final name = TextEditingController();
  final baseUrl = TextEditingController();
  final apiKey = TextEditingController();
  final models = TextEditingController();
  final contextWindow = TextEditingController();
  final maxTokens = TextEditingController();
  final priceIn = TextEditingController();
  final priceOut = TextEditingController();

  /// The prices the sheet opened with, to tell "cleared" from "never set".
  String _priceInStart = '';
  String _priceOutStart = '';

  String api = 'openai-completions';
  bool images = false;
  bool obscure = true;
  bool busy = false;
  bool fetching = false;
  String? error;

  /// Full model entries by id, from the saved provider or the last fetch, so
  /// saving keeps what the endpoint reported (context, reasoning, prices)
  /// instead of flattening every model to a bare id.
  final _known = <String, Map<String, dynamic>>{};

  @override
  void initState() {
    super.initState();
    final provider = widget.provider;
    if (provider != null) {
      api = provider.api;
      name.text = provider.name;
      baseUrl.text = provider.baseUrl;
      for (final m in provider.models) {
        _known[m.id] = m.json;
      }
      models.text = [
        for (final m in provider.models) (m.name == null || m.name == m.id) ? m.id : '${m.id} | ${m.name}',
      ].join('\n');
      images = provider.models.any((m) => m.vision);
      // One price for the whole endpoint: the first model that has one shows it.
      for (final m in provider.models) {
        final cost = m.json['cost'];
        if (cost is Map) {
          priceIn.text = _plain(cost['input']);
          priceOut.text = _plain(cost['output']);
          break;
        }
      }
      _priceInStart = priceIn.text;
      _priceOutStart = priceOut.text;
    }
  }

  /// 3 -> "3", 0.15 -> "0.15"; empty for nothing or zero.
  static String _plain(Object? v) {
    final n = v is num ? v.toDouble() : 0.0;
    if (n <= 0) return '';
    return n == n.roundToDouble() ? n.round().toString() : n.toString();
  }

  static double _price(String text) => double.tryParse(text.trim().replaceAll(',', '.')) ?? 0;

  @override
  void dispose() {
    for (final c in [name, baseUrl, apiKey, models, contextWindow, maxTokens, priceIn, priceOut]) {
      c.dispose();
    }
    super.dispose();
  }

  List<({String id, String? label})> _parsedModels() {
    final out = <({String id, String? label})>[];
    final seen = <String>{};
    for (final line in models.text.split(RegExp(r'[\n,]+'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split('|');
      final id = parts.first.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      final label = parts.length > 1 ? parts.sublist(1).join('|').trim() : '';
      out.add((id: id, label: label.isEmpty ? null : label));
    }
    return out;
  }

  Future<void> _save() async {
    final parsed = _parsedModels();
    if (name.text.trim().isEmpty || baseUrl.text.trim().isEmpty || parsed.isEmpty) {
      setState(() => error = tr('Name, base URL and at least one model are required.'));
      return;
    }
    final editing = widget.provider;
    final id = editing?.id ?? _slug(name.text);
    if (id.isEmpty) {
      setState(() => error = tr('Give the provider a name with letters or numbers.'));
      return;
    }
    final window = int.tryParse(contextWindow.text.trim());
    final output = int.tryParse(maxTokens.text.trim());
    // Prices apply to every model of the endpoint. Filled in: they replace what the models carried. Emptied after
    // having been set: the prices go. Untouched and empty: a fetched catalog's own prices stay.
    final pIn = _price(priceIn.text), pOut = _price(priceOut.text);
    final hasPrice = pIn > 0 || pOut > 0;
    final clearPrice = !hasPrice && (_priceInStart.isNotEmpty || _priceOutStart.isNotEmpty);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.agent.saveCustomProvider({
        'id': id,
        if (editing != null) 'previousId': editing.id,
        'name': name.text.trim(),
        'baseUrl': baseUrl.text.trim(),
        'api': api,
        'apiKey': apiKey.text.trim(),
        'models': [
          for (final m in parsed)
            {
              ...?_known[m.id],
              'id': m.id,
              if (m.label != null) 'name': m.label,
              // The two numbers are defaults for models that do not carry their own.
              if (_known[m.id]?['contextWindow'] == null && window != null && window > 0) 'contextWindow': window,
              if (_known[m.id]?['maxTokens'] == null && output != null && output > 0) 'maxTokens': output,
              'input': images ? ['text', 'image'] : ['text'],
              if (hasPrice) 'cost': {'input': pIn, 'output': pOut, 'cacheRead': 0, 'cacheWrite': 0},
              if (clearPrice) 'cost': null,
            },
        ],
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => error = keyProblem(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _remove() async {
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('Remove {name}?').replaceAll('{name}', widget.provider!.name),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                tr('Only this endpoint is deleted; its models disappear from the model list. Nothing else on the device changes.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: context.palette.danger),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(tr('Remove endpoint')),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.agent.deleteCustomProvider(widget.provider!.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => error = keyProblem(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _fetch() async {
    final url = baseUrl.text.trim();
    if (url.isEmpty) {
      setState(() => error = tr('Enter the base URL first.'));
      return;
    }
    setState(() {
      fetching = true;
      error = null;
    });
    try {
      final found = await widget.agent.fetchProviderModels(
        api: api,
        baseUrl: url,
        apiKey: apiKey.text.trim(),
        providerId: widget.provider?.id,
      );
      for (final m in found) {
        _known[m.id] = m.json;
      }
      if (!mounted) return;
      setState(() {
        models.text = [
          for (final m in found) (m.name == null || m.name == m.id) ? m.id : '${m.id} | ${m.name}',
        ].join('\n');
        // A fetched catalog that says which models see images sets the switch.
        if (found.any((m) => m.vision)) images = true;
      });
      if (found.isEmpty) setState(() => error = tr('The server listed no models.'));
    } catch (e) {
      if (mounted) setState(() => error = keyProblem(e));
    } finally {
      if (mounted) setState(() => fetching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final editing = widget.provider != null;
    Widget field(
      TextEditingController c,
      String label, {
      String? hint,
      int lines = 1,
      bool simple = false,
      bool secret = false,
      TextInputType? type,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: lines,
        minLines: lines,
        keyboardType: type,
        autocorrect: false,
        enableSuggestions: false,
        obscureText: secret && obscure,
        style: simple ? const TextStyle(fontFamily: mono, fontSize: 13.5) : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixIcon: secret
              ? IconButton(
                  icon: Icon(obscure ? LucideIcons.eye : LucideIcons.eyeOff, size: 18),
                  onPressed: () => setState(() => obscure = !obscure),
                )
              : null,
        ),
      ),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(editing ? tr('Edit endpoint') : tr('Add endpoint'), style: text.titleLarge),
              const SizedBox(height: 4),
              Text(
                tr('Any server speaking one of these APIs: Ollama, LM Studio, vLLM, a proxy or your own gateway.'),
                style: text.bodySmall,
              ),
              const SizedBox(height: 16),
              field(name, tr('Name'), hint: tr('Home Ollama')),
              field(baseUrl, tr('Base URL'), hint: 'http://192.168.1.20:11434/v1', simple: true, type: TextInputType.url),
              DropdownButtonFormField<String>(
                initialValue: api,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Protocol')),
                items: [
                  for (final a in _apis)
                    DropdownMenuItem(value: a.$1, child: Text(a.$2, maxLines: 2, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => api = v ?? api),
              ),
              const SizedBox(height: 12),
              field(
                apiKey,
                tr('API key'),
                hint: editing && widget.provider?.hasKey == true
                    ? tr('Key saved earlier — leave empty to keep it')
                    : tr('Leave empty for a server that needs none'),
                secret: true,
                simple: true,
              ),
              const SizedBox(height: 6),
              Text(tr('Stored on this device only, and never included in backups.'), style: text.bodySmall),
              const SizedBox(height: 16),
              field(
                models,
                tr('Models (one per line: id or id | name)'),
                hint: 'qwen2.5-coder:7b | Qwen Coder\nllama3.1:8b',
                lines: 4,
                simple: true,
                type: TextInputType.multiline,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: fetching ? null : _fetch,
                  icon: fetching ? const BusySpinner(size: 14) : const Icon(LucideIcons.download, size: 16),
                  label: Text(fetching ? tr('Asking the server…') : tr('Fetch models from the server')),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: field(contextWindow, tr('Context window'), hint: '128000', simple: true, type: TextInputType.number)),
                  const SizedBox(width: 10),
                  Expanded(child: field(maxTokens, tr('Max output'), hint: '16384', simple: true, type: TextInputType.number)),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: field(priceIn, tr('Input price (\$ / 1M tokens)'), hint: '0.15', simple: true, type: const TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(width: 10),
                  Expanded(child: field(priceOut, tr('Output price (\$ / 1M tokens)'), hint: '0.60', simple: true, type: const TextInputType.numberWithOptions(decimal: true))),
                ],
              ),
              Text(
                tr('Optional. With prices, chats show what they cost and the daily limit can stop spending. Without them the cost is unknown.'),
                style: text.bodySmall,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Image input'), style: text.titleSmall),
                subtitle: Text(tr('Let attachments and screenshots reach this endpoint'), style: text.bodySmall),
                value: images,
                onChanged: (v) => setState(() => images = v),
              ),
              if (error != null) ...[
                const SizedBox(height: 4),
                Text(error!, style: text.bodySmall?.copyWith(color: p.danger)),
              ],
              const SizedBox(height: 14),
              FilledButton(
                onPressed: busy ? null : _save,
                child: busy ? const _Busy() : Text(editing ? tr('Save') : tr('Add endpoint')),
              ),
              if (editing) ...[
                const SizedBox(height: 8),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: p.danger),
                  onPressed: busy ? null : _remove,
                  child: Text(tr('Remove endpoint')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy();

  @override
  Widget build(BuildContext context) => const BusySpinner(size: 16);
}
