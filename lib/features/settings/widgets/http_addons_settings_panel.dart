import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:flick/features/discovery/discovery_http.dart';
import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/features/discovery/discovery_settings.dart';
import 'package:flick/features/discovery/discovery_sources.dart';

/// Inline HTTP catalogue setup for Settings › Online sources.
/// A manifest is checked before the source is stored or enabled.
class HttpAddonsSettingsPanel extends StatefulWidget {
  const HttpAddonsSettingsPanel({
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
  State<HttpAddonsSettingsPanel> createState() => _HttpAddonsSettingsPanelState();
}

class _HttpAddonsSettingsPanelState extends State<HttpAddonsSettingsPanel> {
  late final DiscoverySettingsStore _store;
  late final http.Client _client;
  final _url = TextEditingController();
  DiscoverySettings? _settings;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _message;

  List<DiscoveryAddonConfig> get _addons =>
      _settings?.addons ?? const <DiscoveryAddonConfig>[];

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
      setState(() {
        _settings = settings;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Saved sources could not be loaded. Try again.';
        _loading = false;
      });
    }
  }

  DiscoverySettings _withAddons(List<DiscoveryAddonConfig> addons) =>
      DiscoverySettings(
        youtubeEnabled: _settings!.youtubeEnabled,
        addons: List.unmodifiable(addons),
      ).validated();

  Future<void> _add() async {
    final current = _settings;
    final raw = _url.text.trim();
    if (_busy || _loading || current == null || raw.isEmpty) return;
    if (current.addons.length >= DiscoverySettings.maxAddons) {
      setState(() => _error = 'Remove a source before adding another.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final endpoint = normalizeAddonEndpoint(raw).toString();
      if (current.addons.any((addon) => addon.endpoint == endpoint)) {
        throw const DiscoveryException('This source is already added.');
      }

      final health = await DiscoveryAddon(
        DiscoveryHttp(_client),
        endpoint: endpoint,
      ).health();
      if (!health.cacheAllowed) {
        throw const DiscoveryException(
          'This source disallows downloads required for playback.',
        );
      }

      final host = Uri.parse(endpoint).host.toLowerCase().replaceFirst(
        RegExp(r'^www\\.'),
        '',
      );
      final baseLabel = host.isEmpty ? 'Music source' : host;
      var label = baseLabel;
      var suffix = 2;
      while (current.addons.any(
        (addon) => addon.label.toLowerCase() == label.toLowerCase(),
      )) {
        label = '$baseLabel ($suffix)';
        suffix++;
      }
      final addon = DiscoveryAddonConfig(
        id: DiscoveryAddonConfig.createId(),
        endpoint: endpoint,
        // Keep path tokens and remote manifest fields out of the UI label.
        label: label,
        enabled: true,
      ).validated();
      final next = _withAddons([...current.addons, addon]);
      await _store.save(next);
      if (!mounted) return;
      _url.clear();
      setState(() {
        _settings = next;
        _message = 'Source added and enabled.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = discoveryError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _persist(DiscoverySettings next, String message) async {
    if (_busy || _loading || _settings == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await _store.save(next);
      if (!mounted) return;
      setState(() {
        _settings = next;
        _message = message;
      });
    } catch (error) {
      if (mounted) setState(() => _error = discoveryError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setYoutubeCatalogEnabled(bool enabled) async {
    final current = _settings;
    if (current == null) return;
    await _persist(
      DiscoverySettings(youtubeEnabled: enabled, addons: current.addons).validated(),
      'Source updated.',
    );
  }

  Future<void> _setEnabled(int index, bool enabled) async {
    final current = _settings;
    if (current == null || index < 0 || index >= current.addons.length) return;
    final old = current.addons[index];
    final updated = DiscoveryAddonConfig(
      id: old.id,
      endpoint: old.endpoint,
      label: old.label,
      token: old.token,
      enabled: enabled,
    );
    final addons = [...current.addons];
    addons[index] = updated;
    await _persist(_withAddons(addons), 'Source updated.');
  }

  Future<void> _remove(int index) async {
    final current = _settings;
    if (current == null || index < 0 || index >= current.addons.length) return;
    final addons = [...current.addons]..removeAt(index);
    await _persist(_withAddons(addons), 'Source removed.');
  }

  @override
  void dispose() {
    _url.dispose();
    if (widget.client == null) _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final addons = _addons;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            key: const ValueKey('youtube-catalog-enabled'),
            contentPadding: EdgeInsets.zero,
            title: const Text('YouTube Music catalog'),
            subtitle: const Text('Guest public song search in Discovery.'),
            value: _settings?.youtubeEnabled ?? false,
            onChanged: _busy || _settings == null
                ? null
                : _setYoutubeCatalogEnabled,
          ),
          const Divider(height: 20),
          const Text(
            'HTTP music add-ons',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Paste an HTTPS manifest.json link. It is checked before being added.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('http-addon-manifest-url'),
                  controller: _url,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  enabled: !_loading &&
                      !_busy &&
                      addons.length < DiscoverySettings.maxAddons,
                  onSubmitted: (_) => _add(),
                  decoration: const InputDecoration(
                    hintText: 'https://example.com/manifest.json',
                    prefixIcon: Icon(Icons.link_rounded),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                key: const ValueKey('http-addon-add'),
                tooltip: 'Add source',
                onPressed: _loading ||
                        _busy ||
                        _settings == null ||
                        addons.length >= DiscoverySettings.maxAddons
                    ? null
                    : _add,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_rounded),
              ),
            ],
          ),
          if (_loading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              key: const ValueKey('http-addon-error'),
              style: TextStyle(color: colors.error),
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(
              _message!,
              key: const ValueKey('http-addon-message'),
              style: TextStyle(color: colors.primary),
            ),
          ],
          if (addons.isNotEmpty) ...[
            const Divider(height: 24),
            for (var index = 0; index < addons.length; index++)
              ListTile(
                key: ValueKey('http-addon-${addons[index].id}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.extension_rounded),
                title: Text(addons[index].displayName),
                subtitle: Text(addons[index].enabled ? 'Enabled' : 'Disabled'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      key: ValueKey('http-addon-enabled-${addons[index].id}'),
                      value: addons[index].enabled,
                      onChanged: _busy
                          ? null
                          : (enabled) => _setEnabled(index, enabled),
                    ),
                    IconButton(
                      tooltip: 'Remove ${addons[index].displayName}',
                      onPressed: _busy ? null : () => _remove(index),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
              ),
          ],
          if (!_loading && addons.isEmpty && _error == null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'No HTTP add-ons yet.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (addons.length >= DiscoverySettings.maxAddons)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Maximum of ${DiscoverySettings.maxAddons} sources reached.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
