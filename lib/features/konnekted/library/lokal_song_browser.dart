import 'dart:async';

import 'package:flick/l10n/l10n.dart';
import 'package:flick/widgets/lokal/lokal_choice_sheet.dart';
import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/konnekted_data.dart';
import 'package:flick/models/song.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'lokal_library_kit.dart';
import 'lokal_song_filter.dart';

import 'package:flick/widgets/lokal/lokal_quality.dart';

final DateTime _epochDate = DateTime.fromMillisecondsSinceEpoch(0);

/// Desktop's Simple view sorts.
enum LokalSongSort {
  /// The list's own order (a playlist, or history newest first).
  original('Default order'),
  recentlyAdded('Recently added'),
  title('Title'),
  artist('Artist'),
  mostPlayed('Most played'),
  longest('Longest');

  const LokalSongSort(this.label);

  final String label;
}

/// A song list as slivers: a search field and sort that stay pinned while
/// the list scrolls, the Play and Shuffle pills, and the songs.
class LokalSongBrowser extends ConsumerStatefulWidget {
  const LokalSongBrowser({
    super.key,
    required this.songs,
    this.initialSort = LokalSongSort.recentlyAdded,
    this.originalLabel,
    this.searchHint = 'Search songs',
    this.onRemove,
    this.subtitleOf,
  });

  final List<Song> songs;
  final LokalSongSort initialSort;

  /// Offers [LokalSongSort.original] under this name, e.g. "Playlist order".
  final String? originalLabel;
  final String searchHint;

  /// Offered in each song's actions, e.g. remove from this playlist.
  final void Function(Song song)? onRemove;
  final String Function(Song song)? subtitleOf;

  @override
  ConsumerState<LokalSongBrowser> createState() => _LokalSongBrowserState();
}

class _LokalSongBrowserState extends ConsumerState<LokalSongBrowser> {
  final _search = TextEditingController();
  late LokalSongSort _sort = widget.initialSort;
  late bool _descending = _defaultDescending(widget.initialSort);
  Timer? _queryTimer;
  String _query = '';

  static bool _defaultDescending(LokalSongSort sort) =>
      sort == LokalSongSort.recentlyAdded ||
      sort == LokalSongSort.mostPlayed ||
      sort == LokalSongSort.longest;

  void _onSearchChanged(String value) {
    _queryTimer?.cancel();
    if (value.isEmpty) {
      setState(() => _query = '');
      return;
    }
    // Typing should stay responsive with tens of thousands of entries.
    _queryTimer = Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => _query = value);
    });
  }
  LokalSongLocation _location = LokalSongLocation.all;
  String _audioFilter = 'all';
  LokalSongLocation? _inputLocation;
  String? _inputAudioFilter;
  List<Song>? _visibleCache;
  List<Song>? _inputSongs;
  Map<String, int>? _inputCounts;
  String? _inputQuery;
  LokalSongSort? _inputSort;
  bool? _inputDescending;
  List<Song>? _formatInput;
  List<String> _cachedFormats = const [];

  List<String> _formats() {
    if (!identical(_formatInput, widget.songs)) {
      _formatInput = widget.songs;
      _cachedFormats = libraryAudioFormats(widget.songs);
    }
    return _cachedFormats;
  }

  @override
  void dispose() {
    _queryTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  List<Song> _visible(Map<String, int> counts) {
    final query = _query.trim().toLowerCase();
    if (identical(_inputSongs, widget.songs) &&
        identical(_inputCounts, counts) &&
        _inputQuery == query &&
        _inputSort == _sort &&
        _inputDescending == _descending &&
        _inputLocation == _location &&
        _inputAudioFilter == _audioFilter &&
        _visibleCache != null) {
      return _visibleCache!;
    }
    final songs = [
      for (final song in widget.songs)
        if (matchesLibraryFilters(song, _location, _audioFilter) &&
            (query.isEmpty ||
                '${song.title}\n${song.artist}\n${song.album ?? ''}'
                    .toLowerCase()
                    .contains(query)))
          song,
    ];
    // Lowercasing inside the sort comparator repeatedly allocates strings.
    // Precompute the sort keys once per filter/sort change.
    final titleKeys = <String, String>{
      for (final song in songs) song.id: song.title.toLowerCase(),
    };
    int byTitle(Song a, Song b) =>
        titleKeys[a.id]!.compareTo(titleKeys[b.id]!);
    switch (_sort) {
      case LokalSongSort.original:
        break;
      case LokalSongSort.recentlyAdded:
        songs.sort((a, b) {
          final c = (a.dateAdded ?? _epochDate).compareTo(
            b.dateAdded ?? _epochDate,
          );
          return c != 0 ? c : byTitle(a, b);
        });
      case LokalSongSort.title:
        songs.sort(byTitle);
      case LokalSongSort.artist:
        final artistKeys = <String, String>{
          for (final song in songs) song.id: song.artist.toLowerCase(),
        };
        songs.sort((a, b) {
          final c = artistKeys[a.id]!.compareTo(artistKeys[b.id]!);
          return c != 0 ? c : byTitle(a, b);
        });
      case LokalSongSort.mostPlayed:
        songs.sort((a, b) {
          final c = (counts[a.id] ?? 0).compareTo(counts[b.id] ?? 0);
          return c != 0 ? c : byTitle(a, b);
        });
      case LokalSongSort.longest:
        songs.sort((a, b) => a.duration.compareTo(b.duration));
    }
    if (_descending) {
      // Reversal is view-only. Saved playlist order is edited separately.
      songs.setAll(0, songs.reversed.toList(growable: false));
    }
    _inputSongs = widget.songs;
    _inputCounts = counts;
    _inputQuery = query;
    _inputSort = _sort;
    _inputDescending = _descending;
    _inputLocation = _location;
    _inputAudioFilter = _audioFilter;
    return _visibleCache = songs;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final counts = _sort == LokalSongSort.mostPlayed
        ? ref.watch(lokalPlayCountsProvider).value ?? const <String, int>{}
        : const <String, int>{};
    final songs = _visible(counts);
    final sorts = [
      if (widget.originalLabel != null) LokalSongSort.original,
      for (final sort in LokalSongSort.values)
        if (sort != LokalSongSort.original) sort,
    ];
    String label(LokalSongSort sort) => sort == LokalSongSort.original
        ? widget.originalLabel ?? sort.label
        : sort.label;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    return SliverMainAxisGroup(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: LokalPinnedHeader(
            height: 60 * scale,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: LokalSearchField(
                      controller: _search,
                      hint: widget.searchHint,
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                  PopupMenuButton<LokalSongSort>(
                    tooltip: lokalText(
                      "Sort: {arg0}",
                      args: {'arg0': label(_sort)},
                    ),
                    icon: Icon(Icons.swap_vert_rounded, color: t.accent),
                    color: t.surface2,
                    initialValue: _sort,
                    onSelected: (sort) => setState(() => _sort = sort),
                    itemBuilder: (_) => [
                      for (final sort in sorts)
                        CheckedPopupMenuItem(
                          value: sort,
                          checked: sort == _sort,
                          child: Text(label(sort)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                PopupMenuButton<LokalSongLocation>(
                  tooltip: lokalText('Filter by location'),
                  initialValue: _location,
                  onSelected: (value) => setState(() => _location = value),
                  itemBuilder: (_) => [
                    for (final value in LokalSongLocation.values)
                      CheckedPopupMenuItem(
                        value: value,
                        checked: value == _location,
                        child: Text(lokalText(value.label)),
                      ),
                  ],
                  child: Chip(
                    avatar: Icon(
                      Icons.folder_outlined,
                      size: 18,
                      color: t.accent,
                    ),
                    label: Text(lokalText(_location.label)),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: lokalText('Filter by format and quality'),
                  initialValue: _audioFilter,
                  onSelected: (value) => setState(() => _audioFilter = value),
                  itemBuilder: (_) => [
                    CheckedPopupMenuItem(
                      value: 'all',
                      checked: _audioFilter == 'all',
                      child: Text(lokalText('All formats and qualities')),
                    ),
                    PopupMenuItem(
                      enabled: false,
                      child: Text(lokalText('Quality')),
                    ),
                    for (final value in LokalQualityTier.values)
                      CheckedPopupMenuItem(
                        value: 'quality:${value.name}',
                        checked: _audioFilter == 'quality:${value.name}',
                        child: Text(lokalText(value.label)),
                      ),
                    if (libraryAudioFormats(widget.songs).isNotEmpty) ...[
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        enabled: false,
                        child: Text(lokalText('Format')),
                      ),
                      for (final value in libraryAudioFormats(widget.songs))
                        CheckedPopupMenuItem(
                          value: value,
                          checked: _audioFilter == value,
                          child: Text(libraryAudioFilterLabel(value)),
                        ),
                    ],
                  ],
                  child: Chip(
                    avatar: Icon(
                      Icons.equalizer_rounded,
                      size: 18,
                      color: t.accent,
                    ),
                    label: Text(
                      lokalText(libraryAudioFilterLabel(_audioFilter)),
                    ),
                  ),
                ),
                if (_location != LokalSongLocation.all ||
                    _audioFilter != 'all') ...[
                  Text(
                    lokalSongCount(songs.length),
                    style: TextStyle(color: t.muted, fontSize: 12),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _location = LokalSongLocation.all;
                      _audioFilter = 'all';
                    }),
                    child: Text(lokalText('Clear filters')),
                  ),
                ],
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(child: LokalPlayShufflePills(songs: songs)),
        if (songs.isEmpty)
          SliverToBoxAdapter(
            child: LokalEmptyState(
              icon: Icons.search_off_rounded,
              title: lokalText('No matching songs'),
              message: lokalText(
                'Try another search, location or audio filter.',
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              return LokalTrackRow(
                song: song,
                subtitle: widget.subtitleOf?.call(song),
                onTap: () => lokalPlay(context, ref, songs, start: song),
                onRemove: widget.onRemove == null
                    ? null
                    : () => widget.onRemove!(song),
              );
            },
          ),
      ],
    );
  }
}

/// A page with a song list: Songs, Liked, Downloads, a genre.
class LokalSongListPage extends ConsumerWidget {
  const LokalSongListPage({
    super.key,
    required this.title,
    required this.source,
    this.initialSort = LokalSongSort.recentlyAdded,
    this.originalLabel,
    this.emptyIcon = Icons.music_note_rounded,
    this.emptyTitle = 'No songs yet',
    this.emptyMessage = 'Songs show up here once they’re in your library.',
    this.subtitleOf,
  });

  final String title;
  final AsyncValue<List<Song>> Function(WidgetRef ref) source;
  final LokalSongSort initialSort;
  final String? originalLabel;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;
  final String Function(Song song)? subtitleOf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = source(ref);
    final list = songs.value;
    return LokalLibraryPage(
      title: title,
      subtitle: list == null ? null : lokalSongCount(list.length),
      slivers: [
        if (list != null && list.isNotEmpty)
          LokalSongBrowser(
            songs: list,
            initialSort: initialSort,
            originalLabel: originalLabel,
            subtitleOf: subtitleOf,
          )
        else
          SliverToBoxAdapter(
            child: songs.hasError
                ? LokalEmptyState(
                    icon: Icons.error_outline_rounded,
                    title: lokalText('Couldn’t load these songs'),
                    message: lokalText('Try again in a moment.'),
                    actionLabel: 'Try again',
                    onAction: () => ref.invalidate(konnektedLibraryProvider),
                  )
                : list == null
                ? const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : LokalEmptyState(
                    icon: emptyIcon,
                    title: emptyTitle,
                    message: emptyMessage,
                  ),
          ),
      ],
    );
  }
}
