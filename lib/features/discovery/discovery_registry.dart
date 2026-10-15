import 'discovery_http.dart';
import 'discovery_models.dart';
import 'discovery_settings.dart';
import 'discovery_sources.dart';

/// A validated snapshot of the listener's enabled addon configurations.
/// Construction never contacts a server. Order controls search presentation,
/// not automatic substitution: playback stays pinned to the selected source.
class DiscoverySourceRegistry {
  DiscoverySourceRegistry(DiscoveryHttp http, DiscoverySettings settings)
    : addons = List.unmodifiable([
        for (final config in settings.validated().activeAddons)
          DiscoveryAddon(
            http,
            endpoint: config.endpoint,
            token: config.token,
            configId: config.id,
            displayName: config.displayName,
          ),
      ]);

  final List<DiscoveryAddon> addons;

  Future<ResolvedDiscoveryAudio> resolve(
    DiscoveryTrack track, {
    Future<void>? cancel,
  }) async {
    if (track.source == DiscoverySource.addon && track.addonId != null) {
      for (final addon in addons) {
        if (addon.configId == track.addonId) {
          // Also checks endpoint identity before any request: editing a source
          // must not send an old row/inline media URL to a newly selected host.
          return addon.resolve(track, cancel: cancel);
        }
      }
    }
    throw const DiscoveryException(
      'This source is disabled or no longer configured. Search again after enabling it.',
    );
  }
}
