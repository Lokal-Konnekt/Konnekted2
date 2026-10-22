import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/data/entities/folder_entity.dart';
import 'package:flick/data/repositories/folder_repository.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/features/settings/library_scan/library_scan_flow.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/providers/library_scan_preferences_provider.dart';
import 'package:flick/services/library_scanner_service.dart' show ScanMode;
import 'package:flick/services/music_folder_service.dart';
import 'package:flick/services/permission_service.dart';
import 'package:flick/services/scan_session_controller.dart';
import 'package:flick/widgets/lokal/settings/lokal_settings_kit.dart';

/// Settings › Library › Folders: the music folders, one prominent Add folder,
/// full library access and Rescan (quick, full or deep).
///
/// Scan filters live in Settings › Library and caches in Settings › Data; this
/// page only manages folders and runs scans, through [LibraryScanFlow].
class LibrarySettingsScreen extends ConsumerStatefulWidget {
  const LibrarySettingsScreen({super.key});

  @override
  ConsumerState<LibrarySettingsScreen> createState() =>
      _LibrarySettingsScreenState();
}

enum _Rescan { quick, full, deep }

enum _FolderAction { rescan, deepScan, remove }

class _LibrarySettingsScreenState extends ConsumerState<LibrarySettingsScreen>
    with WidgetsBindingObserver {
  final MusicFolderService _folderService = MusicFolderService();
  final SongRepository _songRepository = SongRepository();
  final ScanSessionController _session = ScanSessionController.instance;

  List<MusicFolder> _folders = [];
  final Map<String, FolderEntity> _folderEntities = {};
  int _songCount = 0;
  bool _loaded = false;
  bool _allFilesAccessGranted = false;
  bool _allFilesAccessSupported = false;

  bool get _isAndroid => Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session.status.addListener(_onSessionStatus);
    unawaited(_syncFoldersToDatabase().then((_) => _loadLibraryData()));
    unawaited(_loadAndroidState());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // All Files Access is granted in system settings; refresh on return.
    if (state == AppLifecycleState.resumed) unawaited(_loadAndroidState());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.status.removeListener(_onSessionStatus);
    super.dispose();
  }

  void _onSessionStatus() {
    if (_session.status.value != ScanSessionStatus.running) {
      unawaited(_loadLibraryData());
    }
  }

  Future<void> _syncFoldersToDatabase() async {
    final folders = await _folderService.getSavedFolders();
    final repository = FolderRepository();
    for (final folder in folders) {
      final existing = await repository.getFolderByUri(folder.uri);
      final entity = FolderEntity()
        ..uri = folder.uri
        ..displayName = folder.displayName
        ..dateAdded = folder.dateAdded
        ..songCount = existing?.songCount ?? 0
        ..useDeepScan = existing?.useDeepScan;
      await repository.upsertFolder(entity);
    }
  }

  Future<void> _loadLibraryData() async {
    final folders = await _folderService.getSavedFolders();
    final count = await _songRepository.getSongCount();
    final repo = FolderRepository();
    final entities = <String, FolderEntity>{};
    for (final folder in folders) {
      final entity = await repo.getFolderByUri(folder.uri);
      if (entity != null) entities[folder.uri] = entity;
    }
    if (!mounted) return;
    setState(() {
      _folders = folders;
      _folderEntities
        ..clear()
        ..addAll(entities);
      _songCount = count;
      _loaded = true;
    });
  }

  Future<void> _loadAndroidState() async {
    if (!_isAndroid) return;
    final permissions = PermissionService();
    try {
      final results = await Future.wait<dynamic>([
        permissions.hasAllFilesAccess(),
        permissions.isAllFilesAccessSupported(),
      ]);
      if (!mounted) return;
      setState(() {
        _allFilesAccessGranted = results[0] as bool;
        _allFilesAccessSupported = results[1] as bool;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _allFilesAccessSupported = false;
      });
    }
  }

  void _say(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _openAllFilesAccessSettings() async {
    try {
      final launched = await PermissionService().openAllFilesAccessSettings();
      if (!launched && mounted) _say('Couldn’t open the access settings.');
    } catch (e) {
      if (mounted) _say('Couldn’t open the access settings ($e).');
    }
  }

  Future<void> _addFolder() async {
    final folder = await LibraryScanFlow.addFolder(context);
    if (folder != null) await _loadLibraryData();
  }

  Future<void> _rescan(_Rescan mode) => LibraryScanFlow.rescanAll(
    context,
    mode: mode == _Rescan.quick ? ScanMode.quick : ScanMode.full,
    deep: mode == _Rescan.deep,
  );

  Future<void> _confirmRemoveFolder(MusicFolder folder) async {
    final t = context.lokal;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: t.surface,
        title: Text('Remove ${folder.displayName}?'),
        content: const Text(
          'Its songs leave your library. The files stay on your phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: t.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _folderService.removeFolder(folder.uri);
      await _loadLibraryData();
    } catch (e) {
      if (mounted) _say('Couldn’t remove the folder ($e).');
    }
  }

  Future<void> _setFolderDeepScan(MusicFolder folder, bool value) async {
    final repo = FolderRepository();
    final entity =
        _folderEntities[folder.uri] ??
        (FolderEntity()
          ..uri = folder.uri
          ..displayName = folder.displayName
          ..dateAdded = folder.dateAdded
          ..songCount = 0);
    entity.useDeepScan = value;
    await repo.upsertFolder(entity);
    if (mounted) setState(() => _folderEntities[folder.uri] = entity);
  }

  Future<void> _onFolderAction(
    MusicFolder folder,
    _FolderAction action,
    bool deepScan,
  ) async {
    switch (action) {
      case _FolderAction.rescan:
        await LibraryScanFlow.scanFolder(context, folder);
      case _FolderAction.deepScan:
        await _setFolderDeepScan(folder, !deepScan);
      case _FolderAction.remove:
        await _confirmRemoveFolder(folder);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
        child: ValueListenableBuilder<ScanSession?>(
          valueListenable: _session.session,
          builder: (context, session, _) {
            final scanning = session != null;
            return ListView(
              padding: EdgeInsets.only(
                bottom: 40 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                LokalSettingsHeader(
                  title: 'Folders',
                  subtitle: _loaded
                      ? l10n.songsIn(_songCount, _folders.length)
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                  child: FilledButton.icon(
                    key: const ValueKey('folders-add'),
                    onPressed: scanning ? null : _addFolder,
                    icon: const Icon(Icons.create_new_folder_rounded),
                    label: const Text('Add folder'),
                    style: FilledButton.styleFrom(
                      backgroundColor: t.accent,
                      foregroundColor: t.onAccent,
                      disabledBackgroundColor: t.surface3,
                      minimumSize: const Size.fromHeight(52),
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(
                        fontFamily: LokalTheme.sans,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                _folderSection(scanning),
                if (_folders.isNotEmpty || _allFilesAccessSupported)
                  _scanSection(scanning),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _folderSection(bool scanning) {
    final t = context.lokal;
    if (_loaded && _folders.isEmpty) {
      return LokalSettingsSection(
        title: 'Music folders',
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              'No folders yet. Add the folder your music is in and Lokal '
              'scans it straight away.',
              style: TextStyle(fontSize: 13.5, height: 1.4, color: t.muted),
            ),
          ),
        ],
      );
    }
    final globalDeepScan = ref
        .watch(libraryScanPreferencesProvider)
        .useDeepScan;
    return LokalSettingsSection(
      title: 'Music folders',
      children: [
        for (final folder in _folders)
          _folderRow(
            folder,
            deepScan:
                _folderEntities[folder.uri]?.useDeepScan ?? globalDeepScan,
            scanning: scanning,
          ),
      ],
    );
  }

  Widget _folderRow(
    MusicFolder folder, {
    required bool deepScan,
    required bool scanning,
  }) {
    final t = context.lokal;
    final removable = folder.isRemovable == true;
    final offline =
        removable &&
        folder.volumeState != null &&
        folder.volumeState != 'mounted';
    final songs = _folderEntities[folder.uri]?.songCount ?? 0;
    final details = [
      l10n.songsCount(songs),
      if (_isAndroid) deepScan ? 'Deep scan' : 'Media index',
      if (removable) offline ? 'USB not connected' : 'External',
    ].join(' · ');
    return LokalSettingRow(
      icon: removable ? Icons.usb_rounded : Icons.folder_rounded,
      label: folder.displayName,
      description: details,
      trailing: PopupMenuButton<_FolderAction>(
        tooltip: 'Folder options',
        color: t.surface2,
        icon: Icon(Icons.more_horiz_rounded, color: t.muted),
        onSelected: (action) => _onFolderAction(folder, action, deepScan),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: _FolderAction.rescan,
            enabled: !scanning,
            child: const Text('Rescan this folder'),
          ),
          if (_isAndroid)
            CheckedPopupMenuItem(
              value: _FolderAction.deepScan,
              checked: deepScan,
              child: const Text('Deep scan'),
            ),
          PopupMenuItem(
            value: _FolderAction.remove,
            enabled: !scanning,
            child: Text('Remove', style: TextStyle(color: t.red)),
          ),
        ],
      ),
    );
  }

  Widget _scanSection(bool scanning) {
    final t = context.lokal;
    return LokalSettingsSection(
      title: 'Scanning',
      children: [
        if (_folders.isNotEmpty)
          LokalSettingRow(
            icon: Icons.refresh_rounded,
            label: 'Rescan',
            description: _isAndroid
                ? 'Quick rereads changed files, full rereads every file, deep '
                      'also reads folders straight from storage.'
                : 'Quick rereads changed files, full rereads every file.',
            enabled: !scanning,
            trailing: PopupMenuButton<_Rescan>(
              key: const ValueKey('folders-rescan'),
              tooltip: 'Rescan',
              enabled: !scanning,
              color: t.surface2,
              onSelected: _rescan,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _Rescan.quick,
                  child: _MenuChoice('Quick', 'Only new and changed files'),
                ),
                const PopupMenuItem(
                  value: _Rescan.full,
                  child: _MenuChoice('Full', 'Reread every file'),
                ),
                if (_isAndroid)
                  const PopupMenuItem(
                    value: _Rescan.deep,
                    child: _MenuChoice(
                      'Deep',
                      'Full, read straight from storage',
                    ),
                  ),
              ],
              child: const _Capsule('Rescan'),
            ),
          ),
        if (_isAndroid && _allFilesAccessSupported)
          LokalSettingRow(
            icon: _allFilesAccessGranted
                ? Icons.verified_user_rounded
                : Icons.folder_open_rounded,
            label: 'Full library access',
            description: _allFilesAccessGranted
                ? 'On. Scans read every volume directly, formats Android '
                      'skips included.'
                : 'Off. Allow it so scans find everything, including DSD and '
                      'WavPack files Android’s index skips.',
            onTap: _openAllFilesAccessSettings,
            trailing: _allFilesAccessGranted
                ? Text('ON', style: LokalTheme.label(t, color: t.accent))
                : LokalSettingButton(
                    label: 'Allow',
                    onPressed: _openAllFilesAccessSettings,
                  ),
          ),
      ],
    );
  }
}

/// A capsule that looks like [LokalSettingButton] without its own tap, for a
/// menu button's face.
class _Capsule extends StatelessWidget {
  const _Capsule(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: t.surface3,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.border2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(), style: LokalTheme.label(t, color: t.text)),
          const SizedBox(width: 4),
          Icon(Icons.expand_more_rounded, size: 16, color: t.muted),
        ],
      ),
    );
  }
}

class _MenuChoice extends StatelessWidget {
  const _MenuChoice(this.title, this.subtitle);

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: LokalTheme.sans,
            fontWeight: FontWeight.w600,
            color: t.text,
          ),
        ),
        Text(subtitle, style: TextStyle(fontSize: 12, color: t.muted)),
      ],
    );
  }
}
