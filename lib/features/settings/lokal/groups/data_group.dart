import 'package:flick/l10n/l10n.dart';

import 'dart:async';

import '../../../link/lokal_desktop_link_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flick/core/theme/lokal_theme.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/services/alac_converter_service.dart';
import 'package:flick/services/album_art_service.dart';
import 'package:flick/services/playback_cache_preferences_service.dart';
import 'package:flick/widgets/lokal/settings/lokal_settings_kit.dart';

/// Bumped after a cache changes, so the sizes shown measure again.
final _cacheChanged = ValueNotifier<int>(0);

String _bytes(int bytes) {
  if (bytes <= 0) return '0 MB';
  const units = ['B', 'KB', 'MB', 'GB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(size >= 100 || unit == 0 ? 0 : 1)} ${units[unit]}';
}

void _say(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.removeCurrentSnackBar();
  messenger?.showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool destructive = false,
}) async {
  return showLokalConfirmSheet(
    context: context,
    title: title,
    message: message,
    confirmLabel: action,
    destructive: destructive,
  );
}

Future<void> _clear(
  BuildContext context, {
  required String what,
  required Future<void> Function() clear,
}) async {
  final ok = await _confirm(
    context,
    title: lokalText("Clear {arg0}?", args: {'arg0': what}),
    message: lokalText('It fills up again as you listen.'),
    action: 'Clear',
  );
  if (!ok || !context.mounted) return;
  try {
    await clear();
    if (context.mounted) _say(context, 'Cleared.');
  } catch (error) {
    if (context.mounted) _say(context, 'Couldn’t clear it ($error).');
  } finally {
    _cacheChanged.value++;
  }
}

/// Data: caches, and clearing the library.
List<LokalSettingsSection> dataSettings(BuildContext context, WidgetRef ref) =>
    [
      LokalSettingsSection(
        title: lokalText('Desktop link'),
        children: [
          LokalSettingLink(
            label: lokalText('Desktop link'),
            description: lokalText(
              'Pair, merge libraries and copy music files over Wi-Fi.',
            ),
            onTap: () => unawaited(
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LokalDesktopLinkScreen(),
                ),
              ),
            ),
          ),
        ],
      ),
      LokalSettingsSection(
        title: lokalText('Cache'),
        children: [
          LokalSettingRow(
            label: lokalText('Artwork cache'),
            description: lokalText(
              'Album covers kept on the phone so they open at once.',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CacheSize(AlbumArtService.instance.getCacheSize),
                const SizedBox(width: 10),
                LokalSettingButton(
                  label: lokalText('Clear'),
                  onPressed: () => _clear(
                    context,
                    what: 'the artwork cache',
                    clear: AlbumArtService.instance.clearCache,
                  ),
                ),
              ],
            ),
          ),
          LokalSettingRow(
            label: lokalText('Converted songs'),
            description: lokalText(
              'Playable copies of songs the phone can’t play as they are, like Apple Lossless.',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _CacheSize(AlacConverterService.getCacheSize),
                const SizedBox(width: 10),
                LokalSettingButton(
                  label: lokalText('Clear'),
                  onPressed: () => _clear(
                    context,
                    what: 'converted songs',
                    clear: AlacConverterService.clearCache,
                  ),
                ),
              ],
            ),
          ),
          const _CacheLimit(),
        ],
      ),
      LokalSettingsSection(
        title: lokalText('Danger zone'),
        children: [
          LokalSettingRow(
            label: lokalText('Clear library'),
            description: lokalText(
              'Remove every song from Lokal. Your music files aren’t touched; rescan to bring them back.',
            ),
            trailing: LokalSettingButton(
              label: lokalText('Clear'),
              destructive: true,
              onPressed: () async {
                final ok = await _confirm(
                  context,
                  title: lokalText('Clear your library?'),
                  message: lokalText(
                    'Every song is removed from Lokal. Files on your phone stay where they are.',
                  ),
                  action: 'Clear library',
                  destructive: true,
                );
                if (!ok || !context.mounted) return;
                try {
                  await SongRepository().deleteAllSongs();
                  if (context.mounted) _say(context, 'Library cleared.');
                } catch (error) {
                  if (context.mounted) {
                    _say(context, 'Couldn’t clear the library ($error).');
                  }
                }
              },
            ),
          ),
        ],
      ),
    ];

/// A cache's size in DM Mono, measured again after a clear.
class _CacheSize extends StatefulWidget {
  const _CacheSize(this.measure);

  final Future<int> Function() measure;

  @override
  State<_CacheSize> createState() => _CacheSizeState();
}

class _CacheSizeState extends State<_CacheSize> {
  int? _size;

  @override
  void initState() {
    super.initState();
    _cacheChanged.addListener(_measure);
    _measure();
  }

  @override
  void dispose() {
    _cacheChanged.removeListener(_measure);
    super.dispose();
  }

  void _measure() {
    unawaited(
      widget.measure().then(
        (bytes) {
          if (mounted) setState(() => _size = bytes);
        },
        onError: (Object _) {
          if (mounted) setState(() => _size = 0);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = _size;
    return Text(
      size == null || size < 0 ? '…' : _bytes(size),
      style: LokalTheme.label(context.lokal, size: 12),
    );
  }
}

/// How big the converted-songs cache may grow.
class _CacheLimit extends StatefulWidget implements LokalSearchable {
  const _CacheLimit();

  static const _label = 'Cache size limit';
  static const _description =
      'Past this size, the oldest converted songs are removed.';

  @override
  String get searchText => '$_label $_description';

  @override
  State<_CacheLimit> createState() => _CacheLimitState();
}

class _CacheLimitState extends State<_CacheLimit> {
  final _service = PlaybackCachePreferencesService();
  int? _cap;

  @override
  void initState() {
    super.initState();
    unawaited(
      _service.getMaxCacheBytes().then((cap) {
        if (mounted) setState(() => _cap = cap);
      }),
    );
  }

  Future<void> _set(int bytes) async {
    setState(() => _cap = bytes);
    await _service.setMaxCacheBytes(bytes);
    // A smaller limit removes the oldest copies straight away.
    await AlacConverterService.enforceCacheCap(bytes);
    _cacheChanged.value++;
  }

  @override
  Widget build(BuildContext context) {
    final options = [
      for (final (label, bytes) in kPlaybackCacheCapPresets)
        LokalSegment(bytes, label),
    ];
    final cap = _cap;
    return LokalSettingChoice<int>(
      label: _CacheLimit._label,
      description: _CacheLimit._description,
      options: [
        ...options,
        if (cap != null && !options.any((o) => o.value == cap))
          LokalSegment(cap, _bytes(cap)),
      ],
      value: cap ?? kPlaybackCacheDefaultMaxBytes,
      enabled: cap != null,
      onChanged: _set,
    );
  }
}
