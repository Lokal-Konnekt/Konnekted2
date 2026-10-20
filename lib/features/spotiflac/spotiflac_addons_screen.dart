import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:flick/core/constants/app_constants.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/settings/widgets/settings_widgets.dart';

import 'spotiflac_auth_sheet.dart';
import 'spotiflac_packages.dart';
import 'spotiflac_service.dart';

/// SpotiFLAC add-ons, as desktop's Settings › Add-ons: repositories to browse,
/// packages to install, and each installed add-on's switch, settings and
/// access. Installed add-ons become places Discovery plays songs from.
class SpotiflacAddonsScreen extends StatefulWidget {
  const SpotiflacAddonsScreen({super.key, this.service});

  final SpotiflacService? service;

  @override
  State<SpotiflacAddonsScreen> createState() => _SpotiflacAddonsScreenState();
}

class _SpotiflacAddonsScreenState extends State<SpotiflacAddonsScreen> {
  SpotiflacService get _service => widget.service ?? SpotiflacService.instance;
  SpotiflacPackages? _packages;
  Object? _loadError;
  bool _busy = false;
  final _repoUrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _service.addListener(_refresh);
    unawaited(_load());
  }

  @override
  void dispose() {
    _service.removeListener(_refresh);
    _repoUrl.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final packages = await _service.packages;
      if (!mounted) return;
      setState(() => _packages = packages);
      await packages.refreshDue();
      _service.changed();
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  void _say(String message) =>
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(message)));

  /// Runs [work] with the screen busy; its error, if any, as a message.
  Future<T?> _run<T>(Future<T> Function() work, {String? done}) async {
    if (_busy) return null;
    setState(() => _busy = true);
    try {
      final result = await work();
      if (done != null) _say(done);
      return result;
    } catch (error) {
      _say('$error');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
      _service.changed();
    }
  }

  Future<void> _addRepo(SpotiflacPackages packages) async {
    final url = _repoUrl.text.trim();
    if (url.isEmpty) return;
    final repo = await _run(() => packages.addRepo(url));
    if (repo != null) _repoUrl.clear();
  }

  Future<void> _installFile(SpotiflacPackages packages) async {
    final file = await FilePicker.pickFile(type: FileType.any);
    if (file == null) return;
    if (!RegExp(
      r'\.(sflx|spotiflac-ext)$',
      caseSensitive: false,
    ).hasMatch(file.name)) {
      _say('Choose a .sflx or .spotiflac-ext package');
      return;
    }
    final addon = await _run(
      () async => packages.install(bytes: await file.readAsBytes()),
    );
    if (addon != null) _installed(addon);
  }

  void _installed(SpotiflacAddon addon) => _say(
    '${addon.displayName} installed. Discovery can now play songs from it.',
  );

  @override
  Widget build(BuildContext context) {
    final packages = _packages;
    return SettingsScaffold(
      title: 'Add-ons',
      body: packages == null
          ? Padding(
              padding: const EdgeInsets.only(top: 48),
              child: Center(
                child: _loadError == null
                    ? const CircularProgressIndicator()
                    : Text(
                        'Add-ons couldn’t be opened: $_loadError',
                        style: TextStyle(color: context.lokal.muted),
                      ),
              ),
            )
          : _body(packages),
    );
  }

  Widget _body(SpotiflacPackages packages) {
    final tokens = context.lokal;
    final addons = packages.addons;
    final catalogue = packages.catalogue();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Notice(
          'Add-ons are made and run by third parties. Lokal doesn’t host, '
          'check or vouch for any of them, and you’re responsible for the '
          'ones you add. Only add add-ons you trust and are allowed to use '
          'where you live.',
        ),
        const SizedBox(height: AppConstants.spacingLg),
        const SettingsSectionHeader('Installed'),
        if (addons.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacingSm,
            ),
            child: Text(
              'No add-ons yet. Install one from a repository below. '
              'Installed add-ons play songs Discovery finds that aren’t '
              'in your library.',
              style: TextStyle(color: tokens.muted, fontSize: 13),
            ),
          ),
        for (final addon in addons)
          Padding(
            padding: const EdgeInsets.only(bottom: AppConstants.spacingSm),
            child: _AddonCard(
              key: ValueKey(addon.key),
              packages: packages,
              addon: addon,
              onChanged: _service.changed,
            ),
          ),
        const SizedBox(height: AppConstants.spacingLg),
        const SettingsSectionHeader('Repositories'),
        SettingsCard(
          children: [
            for (final repo in packages.repositories) ...[
              ListTile(
                title: Text(
                  repo.official ? 'SpotiFLAC official' : repo.name,
                  style: TextStyle(color: tokens.text),
                ),
                subtitle: Text(
                  repo.error ??
                      (repo.refreshedAt == null
                          ? 'Not refreshed'
                          : '${repo.entries.length} sources'),
                  style: TextStyle(
                    color: repo.error == null ? tokens.muted : tokens.red,
                    fontSize: 12,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Refresh repository',
                      onPressed: _busy
                          ? null
                          : () => _run(() => packages.refreshRepo(repo.id)),
                      icon: Icon(Icons.refresh_rounded, color: tokens.muted),
                    ),
                    if (!repo.official)
                      IconButton(
                        tooltip: 'Remove repository',
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                packages.removeRepo(repo.id);
                              }),
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: tokens.muted,
                        ),
                      ),
                  ],
                ),
              ),
              const SettingsDivider(),
            ],
            Padding(
              padding: const EdgeInsets.all(AppConstants.spacingMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _repoUrl,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          style: TextStyle(color: tokens.text, fontSize: 13),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'https://…/registry.json',
                          ),
                          onSubmitted: (_) => _addRepo(packages),
                        ),
                      ),
                      const SizedBox(width: AppConstants.spacingSm),
                      FilledButton.tonal(
                        onPressed: _busy ? null : () => _addRepo(packages),
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppConstants.spacingSm),
                  TextButton.icon(
                    onPressed: _busy ? null : () => _installFile(packages),
                    icon: const Icon(Icons.file_open_outlined, size: 18),
                    label: const Text('Install package file'),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_busy)
          Padding(
            padding: const EdgeInsets.only(top: AppConstants.spacingSm),
            child: LinearProgressIndicator(color: tokens.accent),
          ),
        if (catalogue.isNotEmpty) ...[
          const SizedBox(height: AppConstants.spacingLg),
          const SettingsSectionHeader('Available'),
          SettingsCard(
            children: [
              for (final (i, entry) in catalogue.indexed) ...[
                if (i > 0) const SettingsDivider(),
                ListTile(
                  title: Text(
                    '${entry.name}  v${entry.version}',
                    style: TextStyle(color: tokens.text),
                  ),
                  subtitle: Text(
                    !entry.compatible
                        ? 'Needs a newer SpotiFLAC version'
                        : entry.category == 'integration'
                        ? 'Reads playlist links'
                        : entry.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tokens.muted, fontSize: 12),
                  ),
                  trailing: FilledButton.tonal(
                    onPressed:
                        _busy ||
                            !entry.compatible ||
                            (entry.installed != null && !entry.updateAvailable)
                        ? null
                        : () async {
                            final addon = await _run(
                              () => packages.install(
                                repositoryId: entry.repositoryId,
                                id: entry.id,
                              ),
                            );
                            if (addon != null) _installed(addon);
                          },
                    child: Text(
                      entry.updateAvailable
                          ? 'Update'
                          : entry.installed != null
                          ? 'Installed'
                          : 'Install',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: AppConstants.navBarHeight + 40),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.lokal;
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: tokens.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: tokens.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: tokens.orange),
          const SizedBox(width: AppConstants.spacingSm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: tokens.text, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// One installed add-on: its switch, then (opened) settings and access.
class _AddonCard extends StatefulWidget {
  const _AddonCard({
    super.key,
    required this.packages,
    required this.addon,
    required this.onChanged,
  });

  final SpotiflacPackages packages;
  final SpotiflacAddon addon;
  final VoidCallback onChanged;

  @override
  State<_AddonCard> createState() => _AddonCardState();
}

class _AddonCardState extends State<_AddonCard> {
  bool _open = false;
  bool _busy = false;
  bool _confirmRemove = false;
  String? _message;
  late Map<String, Object?> _values = widget.packages.settings(widget.addon);
  Map<String, Object?>? _form;
  final _formInput = <String, Object?>{};

  SpotiflacPackages get _packages => widget.packages;
  SpotiflacAddon get _addon => widget.addon;

  Future<T?> _run<T>(Future<T> Function() work) async {
    if (_busy) return null;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      return await work();
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
      widget.onChanged();
    }
  }

  /// Opens [url] in the login sheet, then checks access again.
  Future<void> _openAuth(String url) async {
    if (Uri.tryParse(url)?.scheme != 'https') {
      setState(() => _message = 'The add-on gave a page that isn’t secure.');
      return;
    }
    await SpotiflacAuthSheet.show(
      context,
      packages: _packages,
      addon: _addon,
      url: url,
    );
    final status = await _run(() => _packages.authStatus(_addon.key));
    if (!mounted || status == null) return;
    setState(
      () => _message = status['authenticated'] == true
          ? 'Access verified. This add-on can now play and download.'
          : 'Verification wasn’t completed. Try again when you’re ready.',
    );
  }

  Future<void> _verify() async {
    final url = await _run(() => _packages.verify(_addon.key));
    if (!mounted) return;
    if (url == null) {
      if (_message == null) setState(() => _message = 'Access verified.');
      return;
    }
    await _openAuth(url);
  }

  Future<void> _action(String id, {Object? input, String? token}) async {
    final result = await _run(
      () => _packages.invokeAction(_addon.key, id, input: input, token: token),
    );
    if (!mounted || result == null) return;
    final schema = result['action_form'] ?? result['byoa_form'];
    setState(() {
      _form = schema is Map
          ? {...schema.cast<String, Object?>(), 'token': result['formToken']}
          : null;
      _formInput.clear();
      if (result['message'] != null) _message = '${result['message']}';
      if (result['success'] == false) {
        _message = '${result['error'] ?? 'The add-on action failed.'}';
      }
    });
    final auth = '${result['open_auth_url'] ?? ''}';
    if (auth.isNotEmpty) await _openAuth(auth);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.lokal;
    final access = _packages.access(_addon);
    final needsSetup = _addon.enabled && !access.ready;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: needsSetup
              ? tokens.orange.withValues(alpha: 0.4)
              : tokens.border,
        ),
      ),
      child: Opacity(
        opacity: _addon.enabled ? 1 : 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Icon(Icons.extension_rounded, color: tokens.accent),
              title: Text(
                _addon.displayName,
                style: TextStyle(color: tokens.text),
              ),
              subtitle: Text(
                needsSetup
                    ? access.missing.isNotEmpty
                          ? 'Needs ${access.missing.join(', ')}'
                          : access.kind == 'login'
                          ? 'Needs login'
                          : 'Needs verification'
                    : 'v${_addon.version}',
                style: TextStyle(
                  color: needsSetup ? tokens.orange : tokens.muted,
                  fontSize: 12,
                ),
              ),
              trailing: Switch(
                value: _addon.enabled,
                onChanged: _busy
                    ? null
                    : (on) => _run(() async {
                        _packages.setEnabled(_addon.key, on);
                      }),
              ),
              onTap: () => setState(() => _open = !_open),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _open
                  ? _details(access)
                  : const SizedBox(width: double.infinity),
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  _message!,
                  style: TextStyle(color: tokens.muted, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _details(SpotiflacAccess access) {
    final tokens = context.lokal;
    final quality = _addon.qualityOptions.whereType<Map>().toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_addon.description.isNotEmpty) ...[
            Text(
              _addon.description,
              style: TextStyle(color: tokens.muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
          ],
          for (final field in _addon.settingsSchema.whereType<Map>())
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SettingField(
                field: field,
                value: _values['${field['key']}'],
                onChanged: (value) =>
                    setState(() => _values['${field['key']}'] = value),
                onAction: (action) => _action(action),
              ),
            ),
          if (quality.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SettingField(
                field: {
                  'key': 'downloadQuality',
                  'label': 'Quality',
                  'type': 'select',
                  'options': [
                    for (final q in quality)
                      {'value': q['id'], 'label': q['label'] ?? q['id']},
                  ],
                },
                value: _values['downloadQuality'] ?? quality.first['id'],
                onChanged: (value) =>
                    setState(() => _values['downloadQuality'] = value),
              ),
            ),
          if (_addon.settingsSchema.isNotEmpty || quality.length > 1)
            FilledButton.tonal(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      _packages.setSettings(_addon.key, _values);
                      _values = _packages.settings(_addon);
                      if (mounted) setState(() => _message = 'Settings saved');
                    }),
              child: const Text('Save settings'),
            ),
          for (final action in _addon.globalActions.whereType<Map>())
            TextButton(
              onPressed: _busy ? null : () => _action('${action['action']}'),
              child: Text('${action['label'] ?? action['action']}'),
            ),
          if (access.kind == 'verification' || access.kind == 'login') ...[
            const SizedBox(height: 8),
            Text(
              access.verified
                  ? 'Access is active.'
                  : access.kind == 'verification'
                  ? 'This add-on needs a one-time verification before it can '
                        'play or download. A page opens; it closes by itself '
                        'when access is confirmed.'
                  : 'Log in with the button above to play and download from '
                        'this add-on.',
              style: TextStyle(color: tokens.muted, fontSize: 12),
            ),
            Row(
              children: [
                if (access.kind == 'verification' && !access.verified)
                  FilledButton.tonal(
                    onPressed: _busy || !_addon.enabled ? null : _verify,
                    child: const Text('Verify access'),
                  ),
                if (access.verified)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() => _packages.logout(_addon.key)),
                    child: const Text('Disconnect'),
                  ),
              ],
            ),
          ],
          if (_form case final form?) _accountForm(form),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: _confirmRemove
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _confirmRemove = false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() => _packages.remove(_addon.key)),
                        style: TextButton.styleFrom(
                          foregroundColor: tokens.red,
                        ),
                        child: const Text('Remove'),
                      ),
                    ],
                  )
                : TextButton.icon(
                    onPressed: () => setState(() => _confirmRemove = true),
                    style: TextButton.styleFrom(foregroundColor: tokens.muted),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Remove add-on'),
                  ),
          ),
        ],
      ),
    );
  }

  /// A login form the add-on asked for (desktop's "action form").
  Widget _accountForm(Map<String, Object?> form) {
    final tokens = context.lokal;
    final fields = (form['fields'] as List? ?? const []).whereType<Map>();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${form['title'] ?? 'Account details'}',
            style: TextStyle(color: tokens.text, fontWeight: FontWeight.w600),
          ),
          if (form['description'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${form['description']}',
                style: TextStyle(color: tokens.muted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          for (final field in fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SettingField(
                field: {
                  ...field,
                  'secret': const {'password', 'otp'}.contains(field['type']),
                  if (field['options'] is List)
                    'options': [
                      for (final o in field['options'] as List)
                        {'value': o, 'label': o},
                    ],
                },
                value: _formInput['${field['key']}'] ?? field['default'],
                onChanged: (value) =>
                    setState(() => _formInput['${field['key']}'] = value),
              ),
            ),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: _busy
                    ? null
                    : () => _action(
                        '${form['submit_action']}',
                        input: Map.of(_formInput),
                        token: form['token'] as String?,
                      ),
                child: const Text('Continue'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _form = null;
                  _formInput.clear();
                }),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One field from an add-on's manifest `settings`, as desktop draws it.
class _SettingField extends StatelessWidget {
  const _SettingField({
    required this.field,
    required this.value,
    required this.onChanged,
    this.onAction,
  });

  final Map field;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final ValueChanged<String>? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = context.lokal;
    final label = '${field['label'] ?? field['key']}';
    final help = field['description'] ?? field['help'];
    final helpText = help == null
        ? null
        : Text('$help', style: TextStyle(color: tokens.muted, fontSize: 11));
    final current = value ?? field['default'];
    switch (field['type']) {
      case 'button':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton(
              onPressed: () => onAction?.call('${field['action']}'),
              child: Text(label),
            ),
            ?helpText,
          ],
        );
      case 'boolean':
      case 'toggle':
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: current == true || current == 'true',
          onChanged: onChanged,
          title: Text(
            label,
            style: TextStyle(color: tokens.text, fontSize: 14),
          ),
          subtitle: helpText,
        );
      case 'select':
        final options = [
          for (final o in field['options'] as List? ?? const [])
            o is Map ? o : {'value': o, 'label': o},
        ];
        final selected = options.any((o) => o['value'] == current)
            ? current
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<Object?>(
              initialValue: selected,
              isExpanded: true,
              decoration: InputDecoration(labelText: label, isDense: true),
              items: [
                for (final o in options)
                  DropdownMenuItem(
                    value: o['value'],
                    child: Text('${o['label'] ?? o['value']}'),
                  ),
              ],
              onChanged: onChanged,
            ),
            ?helpText,
          ],
        );
      default:
        final secret = field['secret'] == true || field['type'] == 'password';
        final number = field['type'] == 'number';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              initialValue: secret ? '' : '${current ?? ''}',
              obscureText: secret,
              autocorrect: false,
              keyboardType: number ? TextInputType.number : TextInputType.text,
              style: TextStyle(color: tokens.text, fontSize: 13),
              decoration: InputDecoration(
                labelText: label,
                isDense: true,
                hintText: secret
                    ? 'Leave empty to keep the saved value'
                    : field['placeholder'] as String?,
              ),
              onChanged: onChanged,
            ),
            ?helpText,
          ],
        );
    }
  }
}
