/// Normal Morneye playback must never inherit a native Atmos-only download
/// preference. Only an explicit Play/Download Atmos request may ask an add-on
/// for `DOLBY_ATMOS`. Keep the other configured quality tiers unchanged.
bool isMorneyeAtmosQuality(String? value) =>
    RegExp(r'^(?:DOLBY[_ -]?ATMOS|ATMOS)$', caseSensitive: false)
        .hasMatch(value?.trim() ?? '');

String chooseMorneyeDownloadQuality({
  required String? requested,
  required String? configured,
  required List<dynamic> options,
  required String provider,
}) {
  if (requested != null && requested.isNotEmpty) return requested;
  if (configured != null && configured.isNotEmpty &&
      !isMorneyeAtmosQuality(configured)) return configured;

  final candidates = <String>[];
  for (final option in options) {
    if (option is! Map) continue;
    final id = option['id']?.toString() ?? '';
    if (id.isEmpty || isMorneyeAtmosQuality(id) ||
        isMorneyeAtmosQuality(option['kind']?.toString()) ||
        isMorneyeAtmosQuality(option['name']?.toString()) ||
        isMorneyeAtmosQuality(option['label']?.toString())) continue;
    candidates.add(id);
  }
  if (isMorneyeAtmosQuality(configured)) {
    for (final tier in ['HI_RES_LOSSLESS', 'LOSSLESS', 'HIGH']) {
      for (final id in candidates) {
        if (id.toUpperCase() == tier) return id;
      }
    }
    if (candidates.isNotEmpty) return candidates.first;
    // Tidal normally supports HI_RES_LOSSLESS; do not substitute Atmos
    // merely because an extension did not publish qualityOptions.
    return provider.toLowerCase().startsWith('tidal')
        ? 'HI_RES_LOSSLESS'
        : 'default';
  }
  for (final option in options) {
    if (option is! Map) continue;
    if (option['kind'] == 'lossless') {
      final id = option['id']?.toString() ?? '';
      if (id.isNotEmpty && !isMorneyeAtmosQuality(id)) return id;
    }
  }
  return candidates.isNotEmpty ? candidates.first : 'default';
}

/// Saving a file may intentionally use the configured Atmos tier; playback
/// must not inherit it. Keeping this distinction explicit also prevents
/// quality leakage to another track from the same add-on.
String resolveMorneyeRequestQuality({
  required bool forPlayback,
  required String? requested,
  required String? configured,
  required List<dynamic> options,
  required String provider,
}) {
  if (!forPlayback && requested == null &&
      configured != null && configured.isNotEmpty) {
    return configured;
  }
  return chooseMorneyeDownloadQuality(
    requested: requested, configured: configured,
    options: options, provider: provider,
  );
}

/// Requesting the best catalogue edition because Atmos happens to be
/// advertised overrides the user's HIGH/LOW setting. Only an explicit Atmos
/// play command may force a tier. Normal playback passes null so the addon
/// receives its configured downloadQuality.
String? explicitMorneyePlaybackTier({required bool atmosRequested}) =>
    atmosRequested ? 'DOLBY_ATMOS' : null;
