import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/discovery/discovery_models.dart';
import 'package:flick/features/konnekted/konnekted_discovery.dart';
import 'package:flick/features/settings/lokal/lokal_settings_group.dart';
import 'package:flick/features/settings/lokal/lokal_settings_page.dart';
import 'package:flick/features/spotiflac/spotiflac_service.dart';
import 'package:flick/providers/providers.dart';

/// Songs you don't have, under your library's results: desktop's Search
/// "online" block. One source at a time (YouTube Music or an add-on you
/// installed), switched with chips; a tap finds the song and plays it.
class OnlineSearchSection extends ConsumerStatefulWidget {
  const OnlineSearchSection({super.key, required this.query, this.sources});

  final String query;

  /// Loads the sources; replaced in tests.
  final Future<List<OnlineSource>> Function(
    http.Client client,
    void Function(String status) onStatus,
  )?
  sources;

  @override
  ConsumerState<OnlineSearchSection> createState() =>
      _OnlineSearchSectionState();
}

class _OnlineSearchSectionState extends ConsumerState<OnlineSearchSection> {
  static String? _remembered; // The chosen source, for the app's lifetime.

  final _client = http.Client();
  List<OnlineSource>? _sources;
  String? _chosen;
  Future<List<OnlineResult>>? _results;
  String? _searched;
  String? _busy;
  int _inactiveAddons = 0;

  @override
  void initState() {
    super.initState();
    SpotiflacService.instance.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    SpotiflacService.instance.removeListener(_load);
    _client.close();
    super.dispose();
  }

  Future<void> _load() async {
    final load =
        widget.sources ??
        (client, onStatus) => onlineSources(client, onStatus: onStatus);
    List<OnlineSource> sources;
    try {
      sources = await load(_client, _status);
    } catch (_) {
      sources = const [];
    }
    if (!mounted) return;
    setState(() {
      _sources = sources;
      _searched = null; // Search again: the add-ons may have changed.
    });
    if (widget.sources != null) return; // Tests give their own sources.
    try {
      final packages = await SpotiflacService.instance.packages;
      final playable = await SpotiflacService.instance.playable();
      final inactive =
          packages.addons.where((a) => a.enabled && a.searches).length -
          playable.length;
      if (mounted) setState(() => _inactiveAddons = inactive);
    } catch (_) {}
  }

  OnlineSource? get _source {
    final sources = _sources;
    if (sources == null || sources.isEmpty) return null;
    final wanted = _chosen ?? _remembered;
    return sources.where((s) => s.id == wanted).firstOrNull ?? sources.first;
  }

  void _choose(OnlineSource source) {
    HapticFeedback.selectionClick();
    setState(() {
      _chosen = _remembered = source.id;
      _searched = null;
    });
  }

  void _status(String message) => _say(message);

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _play(OnlineSource source, OnlineResult result) async {
    if (_busy != null) return;
    final track = result.track;
    setState(() => _busy = '${source.id}:${track.id}');
    _say('Getting ${track.title} from ${source.name}…');
    try {
      final song = await source.play(track);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
      await ref.read(playerProvider.notifier).play(song, playlist: [song]);
    } catch (error) {
      _say(discoveryError(error));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _openAddons() =>
      unawaited(openLokalSettings(context, group: LokalSettingsGroup.addons));

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final source = _source;
    final query = widget.query.trim();
    if (source != null && query.isNotEmpty) {
      final key = '${source.id}\n$query';
      if (_searched != key) {
        _searched = key;
        _results = source.results(query);
      }
    }
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Not in your library',
              style: TextStyle(
                color: t.text,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              source == null
                  ? 'Looking for places to search…'
                  : source.addon
                  ? 'From an add-on you installed'
                  : 'Streams from YouTube Music',
              style: TextStyle(color: t.muted, fontSize: 12),
            ),
            if (_sources case final sources? when sources.length > 1) ...[
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final s in sources)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _SourceChip(
                          label: s.name,
                          selected: s.id == source?.id,
                          onTap: () => _choose(s),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (_inactiveAddons > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: InkWell(
                  onTap: _openAddons,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      _inactiveAddons == 1
                          ? 'One add-on needs setting up before it can search. '
                                'Open add-ons'
                          : '$_inactiveAddons add-ons need setting up before '
                                'they can search. Open add-ons',
                      style: TextStyle(color: t.accent, fontSize: 12),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            if (source != null)
              FutureBuilder<List<OnlineResult>>(
                future: _results,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: t.muted,
                          ),
                        ),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return _Note(
                      '${source.name} couldn’t search right now. '
                      '${discoveryError(snapshot.error!)}',
                    );
                  }
                  final results = snapshot.data ?? const [];
                  if (results.isEmpty) {
                    return _Note('No songs found on ${source.name}.');
                  }
                  return Column(
                    children: [
                      for (final result in results.take(15))
                        _OnlineTile(
                          result: result,
                          busy: _busy == '${source.id}:${result.track.id}',
                          onTap: () => _play(source, result),
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? t.accent.withValues(alpha: .2)
                : t.surface2.withValues(alpha: .6),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? t.accent : t.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? t.accent : t.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      text,
      style: TextStyle(color: context.lokal.muted, fontSize: 13),
    ),
  );
}

class _OnlineTile extends StatelessWidget {
  const _OnlineTile({
    required this.result,
    required this.busy,
    required this.onTap,
  });

  final OnlineResult result;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final track = result.track;
    final placeholder = ColoredBox(
      color: t.surface2,
      child: Icon(Icons.music_note_rounded, color: t.muted, size: 20),
    );
    final artwork = result.artwork;
    final duration = track.duration;
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox.square(
                dimension: 48,
                child:
                    artwork == null || Uri.tryParse(artwork)?.scheme != 'https'
                    ? placeholder
                    : Image.network(
                        artwork,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => placeholder,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    [
                      track.artist,
                      if (track.album case final album? when album.isNotEmpty)
                        album,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (busy)
              SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: t.accent,
                ),
              )
            else if (duration != null)
              Text(
                '${duration.inMinutes}:'
                '${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
                style: TextStyle(color: t.muted2, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}
