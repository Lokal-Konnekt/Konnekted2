import 'dart:async';

import 'package:flick/core/theme/lokal_tokens.dart';
import 'package:flick/features/konnekted/library/lokal_library_kit.dart';
import 'package:flick/providers/opt_in_source_provider.dart';
import 'package:flick/widgets/lokal/lokal_opt_in_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'radio_catalog.dart';
import 'radio_providers.dart';

/// Desktop's Online Radio: the catalogue's stations with a search, genre
/// chips and favourites first. Off until internet radio is turned on.
class InternetRadioPage extends ConsumerStatefulWidget {
  const InternetRadioPage({super.key});

  @override
  ConsumerState<InternetRadioPage> createState() => _InternetRadioPageState();
}

class _InternetRadioPageState extends ConsumerState<InternetRadioPage> {
  final _search = TextEditingController();
  String _query = '';
  String? _genre;
  bool _favoritesOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(internetRadioEnabledProvider);
    if (!enabled) {
      return LokalLibraryPage(
        title: 'Radio',
        slivers: [
          SliverToBoxAdapter(
            child: LokalOptInCard(
              icon: Icons.radio_rounded,
              title: 'Turn on internet radio',
              message:
                  'Listen to live stations from a station list online. '
                  'Lokal downloads the list from GitHub and plays each '
                  'station’s stream from its broadcaster.',
              actionLabel: 'Turn on internet radio',
              onTurnOn: () =>
                  ref.read(internetRadioEnabledProvider.notifier).set(true),
            ),
          ),
        ],
      );
    }
    final catalog = ref.watch(radioCatalogProvider);
    final favorites = ref.watch(radioFavoritesProvider);
    final stations = catalog.value?.stations ?? const <RadioStation>[];
    final filtered = filterStations(
      stations,
      query: _query,
      genre: _genre,
    ).where((s) => !_favoritesOnly || favorites.contains(s.id)).toList();
    // Favourites first, then the catalogue's order.
    filtered.sort(
      (a, b) =>
          (favorites.contains(b.id) ? 1 : 0) -
          (favorites.contains(a.id) ? 1 : 0),
    );
    final genres = catalog.value?.genres ?? const <String>[];
    final title = catalog.value?.title;
    return LokalLibraryPage(
      title: 'Radio',
      subtitle: title == null || title.isEmpty ? null : title,
      actions: [
        LokalRoundAction(
          icon: Icons.refresh_rounded,
          label: 'Reload the station list',
          onPressed: () => ref.invalidate(radioCatalogProvider),
        ),
      ],
      slivers: [
        const SliverToBoxAdapter(child: _NowPlayingStation()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: LokalSearchField(
              controller: _search,
              hint: 'Search stations',
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _Chip(
                  label: 'Favourites',
                  icon: Icons.favorite_rounded,
                  selected: _favoritesOnly,
                  onTap: () => setState(() => _favoritesOnly = !_favoritesOnly),
                ),
                for (final genre in genres)
                  _Chip(
                    label: genre,
                    selected: _genre == genre,
                    onTap: () =>
                        setState(() => _genre = _genre == genre ? null : genre),
                  ),
              ],
            ),
          ),
        ),
        if (catalog.isLoading && stations.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (catalog.hasError && stations.isEmpty)
          SliverToBoxAdapter(
            child: LokalEmptyState(
              icon: Icons.wifi_off_rounded,
              title: 'No stations',
              message: '${catalog.error}',
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(radioCatalogProvider),
            ),
          )
        else if (filtered.isEmpty)
          SliverToBoxAdapter(
            child: LokalEmptyState(
              icon: Icons.radio_rounded,
              title: _favoritesOnly ? 'No favourites yet' : 'No stations found',
              message: _favoritesOnly
                  ? 'Tap the heart on a station to keep it here.'
                  : 'Try another search or genre.',
            ),
          )
        else
          SliverList.builder(
            itemCount: filtered.length,
            itemBuilder: (context, i) => _StationRow(
              station: filtered[i],
              favorite: favorites.contains(filtered[i].id),
            ),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
      child: Material(
        color: selected ? t.accent : t.surface2,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: selected ? t.bg : t.accent),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? t.bg : t.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StationIcon extends StatelessWidget {
  const _StationIcon({required this.station, this.size = 52});

  final RadioStation station;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.lokal;
    final fallback = ColoredBox(
      color: t.surface2,
      child: Icon(Icons.radio_rounded, color: t.muted, size: size * .5),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox.square(
        dimension: size,
        child: station.icon == null
            ? fallback
            : Image.network(
                station.icon!,
                fit: BoxFit.cover,
                cacheWidth: (size * 3).round(),
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class _StationRow extends ConsumerWidget {
  const _StationRow({required this.station, required this.favorite});

  final RadioStation station;
  final bool favorite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.lokal;
    final playback = ref.watch(radioPlayerProvider);
    final current = playback.station?.id == station.id;
    final detail = [
      if (station.genre != null) station.genre!,
      if (station.description != null) station.description!,
    ].join(' · ');
    return InkWell(
      onTap: () => current
          ? ref.read(radioPlayerProvider.notifier).toggle()
          : ref.read(radioPlayerProvider.notifier).play(station),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
        child: Row(
          children: [
            _StationIcon(station: station),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    station.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: current ? t.accent : t.text,
                    ),
                  ),
                  if (detail.isNotEmpty)
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.muted, fontSize: 13),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: favorite
                  ? 'Remove from favourites'
                  : 'Add to favourites',
              onPressed: () =>
                  ref.read(radioFavoritesProvider.notifier).toggle(station.id),
              icon: Icon(
                favorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: favorite ? t.accent : t.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The station playing now, with play/pause and stop.
class _NowPlayingStation extends ConsumerWidget {
  const _NowPlayingStation();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.lokal;
    final playback = ref.watch(radioPlayerProvider);
    final station = playback.station;
    if (station == null) return const SizedBox.shrink();
    final notifier = ref.read(radioPlayerProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.border),
        ),
        child: Row(
          children: [
            _StationIcon(station: station, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    station.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                  Text(
                    playback.error ??
                        (playback.loading
                            ? 'Tuning in…'
                            : playback.playing
                            ? 'Live'
                            : 'Paused'),
                    style: TextStyle(
                      color: playback.error != null ? t.red : t.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (playback.loading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                tooltip: playback.playing ? 'Pause' : 'Play',
                onPressed: () => unawaited(notifier.toggle()),
                icon: Icon(
                  playback.playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: t.accent,
                  size: 30,
                ),
              ),
            IconButton(
              tooltip: 'Stop',
              onPressed: () => unawaited(notifier.stop()),
              icon: Icon(Icons.stop_rounded, color: t.muted),
            ),
          ],
        ),
      ),
    );
  }
}
