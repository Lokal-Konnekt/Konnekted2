import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:flick/features/discovery/discovery_http.dart';
import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/features/discovery/discovery_settings.dart';
import 'package:flick/features/discovery/discovery_sources.dart';

class HttpAddonsSettingsScreen extends StatefulWidget {
  const HttpAddonsSettingsScreen({
    super.key,
    this.initial,
    this.store,
    this.client,
  });
  final DiscoverySettings? initial;
  final DiscoverySettingsStore? store;

  /// An injected client is owned by the caller and is never closed here.
  final http.Client? client;

  @override
  State<HttpAddonsSettingsScreen> createState() =>
      _HttpAddonsSettingsScreenState();
}

class _HttpAddonsSettingsScreenState extends State<HttpAddonsSettingsScreen> {
  late final http.Client _client;
  late final DiscoverySettingsStore _store;
  final _addons = <DiscoveryAddonConfig>[];
  bool _youtube = false;
  bool _loading = true;
  bool _saving = false;
  bool _saved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? DiscoverySettingsStore();
    _client = widget.client ?? http.Client();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = widget.initial ?? await _store.load();
      if (!mounted) return;
      _addons.addAll(settings.addons);
      _youtube = settings.youtubeEnabled;
    } catch (_) {
      if (!mounted) return;
      _error = 'Saved source settings could not be loaded securely. Reconfigure sources to continue.';
    }
    if (mounted) setState(() => _loading = false);
  }

  DiscoverySettings _draft([List<DiscoveryAddonConfig>? addons]) =>
      DiscoverySettings(
        youtubeEnabled: _youtube,
        addons: List.unmodifiable(addons ?? _addons),
      ).validated();

  void _editDraft(VoidCallback change) {
    if (_saving) return;
    setState(() {
      change();
      _error = null;
    });
  }

  Future<void> _editAddon([int? index]) async {
    if (_saving ||
        (index == null && _addons.length >= DiscoverySettings.maxAddons)) {
      return;
    }
    final original = index == null
        ? DiscoveryAddonConfig(
            id: DiscoveryAddonConfig.createId(),
            endpoint: '',
          )
        : _addons[index];
    final result = await Navigator.of(context).push<DiscoveryAddonConfig>(
      MaterialPageRoute(
        builder: (_) => _AddonEditor(
          initial: original,
          isNew: index == null,
          client: _client,
          validate: (addon) {
            final next = [..._addons];
            if (index == null) {
              next.add(addon);
            } else {
              next[index] = addon;
            }
            _draft(next);
          },
        ),
      ),
    );
    if (!mounted || result == null) return;
    _editDraft(() {
      if (index == null) {
        _addons.add(result);
      } else {
        _addons[index] = result;
      }
    });
  }

  void _move(int index, int offset) => _editDraft(() {
    final addon = _addons.removeAt(index);
    _addons.insert(index + offset, addon);
  });

  Future<void> _save() async {
    if (_saving || _loading) return;
    final DiscoverySettings settings;
    try {
      settings = _draft();
    } catch (error) {
      setState(() => _error = discoveryError(error));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _store.save(settings);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Source settings could not be saved securely. Try again.';
        });
      }
      return;
    }
    if (!mounted) return;
    // Rebuild PopScope before popping, keeping all draft controls locked until
    // the successfully persisted snapshot has been returned to discovery.
    setState(() => _saved = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, settings);
  }

  @override
  void dispose() {
    if (widget.client == null) _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<DiscoverySettings>(
    canPop: !_saving || _saved,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('HTTP music add-ons'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: _saving ? null : () => Navigator.maybePop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    'Choose where discovery connects',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'All sources are off by default. Enabled sources receive the search terms you enter. No account sign-in is required or offered here. Changes apply only after Save sources succeeds.',
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile.adaptive(
                    key: const ValueKey('youtube-enabled'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('YouTube Music catalog'),
                    subtitle: const Text(
                      'Guest public song search. Results open in YouTube Music; this adapter does not extract YouTube audio.',
                    ),
                    value: _youtube,
                    onChanged: _saving
                        ? null
                        : (value) => _editDraft(() => _youtube = value),
                  ),
                  const Divider(height: 32),
                  Text(
                    'Your HTTPS music addons',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Search and play recordings your sources are authorized to serve. Addons are used in the order shown. Disabled addons stay available to edit.',
                  ),
                  const SizedBox(height: 12),
                  if (_addons.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No music addons added. Add your own HTTPS endpoint, then enable it when you are ready. No provider is preconfigured.',
                      ),
                    ),
                  for (var index = 0; index < _addons.length; index++)
                    _addonCard(index),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('add-addon'),
                    onPressed:
                        _saving || _addons.length >= DiscoverySettings.maxAddons
                        ? null
                        : () => _editAddon(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add music addon'),
                  ),
                  Text(
                    _addons.length >= DiscoverySettings.maxAddons
                        ? 'Maximum of ${DiscoverySettings.maxAddons} addons. Remove one to add another.'
                        : '${_addons.length} of ${DiscoverySettings.maxAddons} addons',
                  ),
                  const Divider(height: 32),
                  const Text(
                    'Addon playback downloads a progressive audio file to the app cache (128 MiB per file, 384 MiB total) and probes it with the native engine. HLS, DASH, DRM and custom media headers are unsupported. The addon must permit caching. Quality is determined from the file, not the provider label.',
                  ),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) _ErrorMessage(_error!),
            Row(
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.maybePop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('save-sources'),
                    onPressed: _saving || _loading ? null : _save,
                    child: Text(_saving ? 'Saving securely…' : 'Save sources'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _addonCard(int index) {
    final addon = _addons[index];
    final name = addon.displayName;
    return Card(
      key: ValueKey('addon-${addon.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            key: ValueKey('enabled-addon-${addon.id}'),
            title: Text(name),
            subtitle: Text(addon.enabled ? 'Enabled' : 'Disabled'),
            value: addon.enabled,
            onChanged: _saving
                ? null
                : (enabled) => _editDraft(() {
                    _addons[index] = DiscoveryAddonConfig(
                      id: addon.id,
                      endpoint: addon.endpoint,
                      label: addon.label,
                      token: addon.token,
                      enabled: enabled,
                    );
                  }),
          ),
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              IconButton(
                key: ValueKey('move-up-addon-${addon.id}'),
                tooltip: 'Move $name up',
                onPressed: _saving || index == 0
                    ? null
                    : () => _move(index, -1),
                icon: const Icon(Icons.arrow_upward),
              ),
              IconButton(
                key: ValueKey('move-down-addon-${addon.id}'),
                tooltip: 'Move $name down',
                onPressed: _saving || index == _addons.length - 1
                    ? null
                    : () => _move(index, 1),
                icon: const Icon(Icons.arrow_downward),
              ),
              IconButton(
                key: ValueKey('edit-addon-${addon.id}'),
                tooltip: 'Edit $name',
                onPressed: _saving ? null : () => _editAddon(index),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                key: ValueKey('remove-addon-${addon.id}'),
                tooltip: 'Remove $name',
                onPressed: _saving
                    ? null
                    : () => _editDraft(() => _addons.removeAt(index)),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddonEditor extends StatefulWidget {
  const _AddonEditor({
    required this.initial,
    required this.isNew,
    required this.client,
    required this.validate,
  });

  final DiscoveryAddonConfig initial;
  final bool isNew;
  final http.Client client;
  final void Function(DiscoveryAddonConfig) validate;

  @override
  State<_AddonEditor> createState() => _AddonEditorState();
}

class _AddonEditorState extends State<_AddonEditor> {
  late final _label = TextEditingController(text: widget.initial.label);
  late final _endpoint = TextEditingController(text: widget.initial.endpoint);
  late final _token = TextEditingController(text: widget.initial.token);
  Completer<void>? _cancelCheck;
  bool _checking = false;
  int _revision = 0;
  String? _status;
  String? _error;

  void _edited() {
    _cancelCheck?.complete();
    _cancelCheck = null;
    setState(() {
      _revision++;
      _checking = false;
      _status = null;
      _error = null;
    });
  }

  DiscoveryAddonConfig _draft() => DiscoveryAddonConfig(
    id: widget.initial.id,
    label: _label.text,
    endpoint: _endpoint.text,
    token: _token.text,
    enabled: widget.initial.enabled,
  ).validated();

  Future<void> _check() async {
    if (_checking) return;
    final revision = _revision;
    final cancel = Completer<void>();
    _cancelCheck = cancel;
    setState(() {
      _checking = true;
      _status = null;
      _error = null;
    });
    try {
      final addon = DiscoveryAddon(
        DiscoveryHttp(widget.client),
        endpoint: _endpoint.text,
        token: _token.text,
      );
      final health = await addon.health(cancel: cancel.future);
      if (!mounted || revision != _revision) return;
      setState(() {
        // A remote manifest name can itself contain a URL or credential.
        _status = health.cacheAllowed
            ? 'Manifest reachable; search and stream declared. Playback is verified when you select a result.'
            : 'The addon is reachable, but disallows downloads. This player requires temporary caching.';
      });
    } catch (error) {
      if (mounted && revision == _revision) {
        setState(() => _error = discoveryError(error));
      }
    } finally {
      if (mounted && revision == _revision) {
        _cancelCheck = null;
        setState(() => _checking = false);
      }
    }
  }

  void _apply() {
    if (_checking) return;
    try {
      final addon = _draft();
      widget.validate(addon);
      Navigator.pop(context, addon);
    } catch (error) {
      setState(() => _error = discoveryError(error));
    }
  }

  @override
  void dispose() {
    _cancelCheck?.complete();
    _label.dispose();
    _endpoint.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.isNew ? 'Add music addon' : 'Edit music addon'),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Use a name you recognize. Endpoint and token are shown only in this editor. Adding or editing an addon does not contact it; Test endpoint explicitly contacts this server.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('addon-label'),
            controller: _label,
            decoration: const InputDecoration(
              labelText: 'Addon name (optional)',
              hintText: 'Music addon',
              helperText: 'Shown in your source list. Do not include secrets.',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _edited(),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('addon-endpoint'),
            controller: _endpoint,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Addon HTTPS base URL',
              hintText: 'https://your-server.example/music',
              helperText: 'Base URL or /manifest.json.',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) {
              _token.clear();
              _edited();
            },
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('addon-token'),
            controller: _token,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Addon bearer token (optional)',
              helperText: 'Stored securely. Sent only to this addon API, never to media hosts. Cleared when the endpoint is edited.',
              helperMaxLines: 3,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _edited(),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('test-endpoint'),
              onPressed: _checking ? null : _check,
              icon: _checking
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check),
              label: Text(_checking ? 'Checking manifest…' : 'Test endpoint'),
            ),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_status!),
            ),
        ],
      ),
    ),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) _ErrorMessage(_error!),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('apply-addon'),
                  onPressed: _checking ? null : _apply,
                  child: Text(
                    widget.isNew ? 'Add to sources' : 'Apply changes',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    ),
  );
}
